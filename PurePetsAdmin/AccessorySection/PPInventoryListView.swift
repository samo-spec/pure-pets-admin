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
import AVFoundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth
import CoreImage

// MARK: - Sendable Conformance

extension PetAccessory: @unchecked Sendable, Identifiable {
    public var id: String { accessoryID }
}

extension PetAccessory {
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
    let gender: PPLivePetUnitGender
    let mediaURLs: [String]
    let quarantineReason: String
    let quarantinedAt: Date?
    let refundedAt: Date?
    let returnCaseId: String
    let activeReturnCaseID: String
    let activeReturnCaseNumber: String
    let returnLifecycleStatus: String
    let healthStatus: String
    let custodyStatus: String
    let version: Int
    let returnReason: String
    let returnTransactionId: String

    var isUnderInspection: Bool {
        if status == "UNDER_INSPECTION" { return true }
        let lifecycle = returnLifecycleStatus.lowercased()
        let activeInspectionStates: Set<String> = [
            "return_requested",
            "return_in_transit",
            "return_received",
            "under_inspection",
            "quarantined",
            "medical_hold"
        ]
        if !activeReturnCaseID.isEmpty && activeInspectionStates.contains(lifecycle) { return true }
        // Backward-compatible fallback for modern records created before the
        // lifecycle projection was added. A legacy financial-return quarantine
        // without an active case must not be presented as a current dossier.
        return !activeReturnCaseID.isEmpty && status == "QUARANTINED" && lifecycle.isEmpty
    }

    var isLegacyReturnedQuarantine: Bool {
        status == "QUARANTINED" &&
            activeReturnCaseID.isEmpty &&
            (quarantineReason == "LIVE_ANIMAL_RETURN" || !returnCaseId.isEmpty || refundedAt != nil)
    }

    var linkedReturnCaseReference: String {
        if !activeReturnCaseNumber.isEmpty { return activeReturnCaseNumber }
        if !activeReturnCaseID.isEmpty { return activeReturnCaseID }
        return returnCaseId
    }

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
        gender = PPLivePetUnitGender.resolved(dictionary["gender"])
        mediaURLs = PPLivePetInventoryService.strings(dictionary["mediaURLs"] ?? dictionary["mediaUrls"])
        quarantineReason = PPLivePetInventoryService.string(dictionary["quarantineReason"])
        quarantinedAt = PPLivePetInventoryService.date(dictionary["quarantinedAt"])
        refundedAt = PPLivePetInventoryService.date(dictionary["refundedAt"])
        returnCaseId = PPLivePetInventoryService.string(dictionary["returnCaseId"])
        activeReturnCaseID = PPLivePetInventoryService.string(dictionary["activeReturnCaseId"])
        activeReturnCaseNumber = PPLivePetInventoryService.string(dictionary["activeReturnCaseNumber"])
        returnLifecycleStatus = PPLivePetInventoryService.string(dictionary["returnLifecycleStatus"]).lowercased()
        healthStatus = PPLivePetInventoryService.string(dictionary["healthStatus"]).lowercased()
        custodyStatus = PPLivePetInventoryService.string(dictionary["custodyStatus"]).lowercased()
        version = max(1, PPLivePetInventoryService.integer(dictionary["version"]))
        returnReason = PPLivePetInventoryService.string(dictionary["returnReason"])
        returnTransactionId = PPLivePetInventoryService.string(dictionary["returnTransactionId"])
    }

    var displayIdentity: String {
        let tag = ringTag.trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? id : tag
    }

    var naturalSortKey: String {
        displayIdentity.normalizedEnglishDigits.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension PPLivePetInventoryUnit: Comparable {
    static func < (lhs: PPLivePetInventoryUnit, rhs: PPLivePetInventoryUnit) -> Bool {
        let primary = lhs.naturalSortKey.compare(rhs.naturalSortKey, options: [.numeric, .caseInsensitive])
        if primary != .orderedSame {
            return primary == .orderedAscending
        }
        let fallbackKeyLhs = lhs.id.normalizedEnglishDigits.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackKeyRhs = rhs.id.normalizedEnglishDigits.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondary = fallbackKeyLhs.compare(fallbackKeyRhs, options: [.numeric, .caseInsensitive])
        if secondary != .orderedSame {
            return secondary == .orderedAscending
        }
        return lhs.id < rhs.id
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
    var localizedName: String { displayName }
    //func localizedName() -> String { displayName }

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

    nonisolated static func integer(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let integer = value as? Int { return integer }
        if let text = value as? String, let integer = Int(text) { return integer }
        return 0
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
        if backendMsg.contains("clearLivePetForResale") || backendMsg.contains("Returned live animals must be released") {
            return Language.get(
                "LivePet_Error_ReturnedAnimalNeedsClearance",
                alter: "الحيوانات المسترجعة تتطلب استكمال الفحص البيطري واعتماد إعادة البيع من خلال ملف الاسترجاع."
            )
        }
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
        expectedRevision: Int? = nil,
        payload: [String: Any]
    ) async throws -> [String: Any] {
        var request: [String: Any] = ["contractVersion": 2, "action": action, "payload": payload]
        if let productID, !productID.isEmpty { request["productId"] = productID }
        if let commandID, !commandID.isEmpty { request["commandId"] = commandID }
        if let expectedRevision { request["expectedRevision"] = expectedRevision }
        let response = try await call("validateInventoryChange", payload: request)
        if let commandID, !commandID.isEmpty,
           string(response["commandId"]) != commandID {
            throw PPLivePetServiceError.invalidResponse
        }
        return response
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
        return result.sorted()
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
        validUntil: Date,
        commandID: String
    ) async throws {
        guard let sellingPrice = unit.sellingPrice, sellingPrice > 0 else {
            throw PPLivePetServiceError.missingSellingPrice
        }
        _ = try await callTransaction([
            "action": "create",
            "commandId": commandID,
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

    static func completeReservation(_ reservation: PPLivePetReservation, cashReceived: Double, commandID: String) async throws {
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
            "commandId": commandID,
            "payload": binding,
        ])
    }

    static func cancelReservation(_ reservation: PPLivePetReservation, commandID: String) async throws {
        _ = try await callTransaction([
            "action": "cancel",
            "transactionId": reservation.id,
            "commandId": commandID,
            "expectedStatus": "pending",
            "reason": "admin_live_pet_reservation_release",
            "currency": reservation.currency,
        ])
    }

    static func updateCatalogPresentation(
        productID: String,
        values: [String: Any],
        commandID: String,
        expectedRevision: Int? = nil
    ) async throws -> [String: Any] {
        // Despite the legacy name, this is now an authoritative catalog command.
        // Only public-safe metadata crosses the client boundary; actor, owner,
        // branch, lifecycle, timestamps, stock, cost, and projection fields are
        // resolved or derived by Infra.
        //
        // The allowlist is the security boundary and is deliberately kept. What
        // changed is the failure mode: an unlisted key used to be dropped
        // silently by a `filter`, so a caller that passed a field this command
        // does not own — a colour-variant identity field, for example — got a
        // successful save that quietly omitted it. An unexpected key is a
        // contract violation in the calling code, so it now fails loudly instead
        // of being discarded.
        let allowedKeys: Set<String> = [
            "name", "nameEn", "desc", "descEn", "sku", "barcode", "category",
            "price", "sellPrice", "finalPrice", "discountPercent", "discountAmount",
            "wholesalePrice", "petMainCategoryID", "petSubCategoryID", "condition",
            // Both spellings are accepted by the backend update allowlist. Added
            // so the accessory category can be updated through the callable
            // instead of the direct merge write it used to need.
            "AccessoryCategoryID", "accessoryCategoryID",
            "weight", "weightUnit", "size", "imageURLsArray", "imageMeta", "isNew",
            "hasOffer", "showInAppMarket", "active", "inventoryTrackingPolicy",
            "expiryDate", "reorderLevel", "keywords", "birdColor", "relatedAccessories",
            "shelfLifeDays", "guaranteedShelfLifeDays", "expiryCutoffDays"
        ]
        let rejectedKeys = values.keys.filter { !allowedKeys.contains($0) }.sorted()
        guard rejectedKeys.isEmpty else {
            throw PPLivePetServiceError.unsupportedCatalogFields(rejectedKeys)
        }
        let sanitizedValues = values
        guard !sanitizedValues.isEmpty else {
            throw PPLivePetServiceError.invalidResponse
        }
        return try await callInventory(
            action: "update",
            productID: productID,
            commandID: commandID,
            expectedRevision: expectedRevision,
            payload: sanitizedValues
        )
    }

    static func readProduct(productID: String, minimumRevision: Int) async throws -> PetAccessory {
        let normalizedProductID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProductID.isEmpty else { throw PPLivePetServiceError.invalidResponse }
        let snapshot = try await Firestore.firestore()
            .collection("petAccessories")
            .document(normalizedProductID)
            .getDocument()
        guard snapshot.exists, let data = snapshot.data() else {
            throw PPLivePetServiceError.invalidResponse
        }
        let revision = integer(data["revision"])
        guard revision >= minimumRevision else {
            throw PPLivePetServiceError.readbackPending
        }
        return PetAccessory(dictionary: data, documentID: normalizedProductID)
    }

    private static func call(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        let boxed = PPSendableDictionary(dict: payload)
        guard let currentUser = Auth.auth().currentUser else {
            throw PPLivePetServiceError.notAuthenticated
        }
        _ = try? await currentUser.getIDToken(forcingRefresh: false)
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
                _ = try? await currentUser.getIDToken(forcingRefresh: true)
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
    case readbackPending
    case truncatedReservations
    case missingSellingPrice
    case notAuthenticated
    /// A caller passed catalog fields this command does not own. Surfaced rather
    /// than silently dropped, so a field can never appear saved when it was not
    /// sent.
    case unsupportedCatalogFields([String])

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return Language.get("LivePet_Error_InvalidResponse", alter: "تعذر تأكيد استجابة الخادم. حدّث البيانات وحاول مرة أخرى.")
        case .readbackPending:
            return Language.get("Inventory_ReadbackPending", alter: "اعتمد الخادم العملية، لكن النسخة المؤكدة لم تصل بعد. أعد المحاولة دون تعديل البيانات.")
        case .truncatedReservations:
            return Language.get("LivePet_Error_ReservationLimit", alter: "تعذر تحميل جميع الحجوزات بأمان. استخدم نقطة البيع لمراجعة القائمة الكاملة.")
        case .missingSellingPrice:
            return Language.get("LivePet_Error_MissingUnitPrice", alter: "حدد سعر بيع صالحاً للحيوان قبل حجزه أو بيعه.")
        case .notAuthenticated:
            return Language.get("LivePet_Error_NotAuthenticated", alter: "يجب تسجيل الدخول بحساب موظف معتمد لإجراء هذه العملية.")
        case .unsupportedCatalogFields(let fields):
            let template = Language.get(
                "Inventory_UnsupportedCatalogFields",
                alter: "هذه الحقول لا تُحدَّث من هذه الشاشة ولم يتم الحفظ: %@."
            )
            return String(format: template, fields.joined(separator: ", "))
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

    @Published var availableSubSubKinds: [AdminSubSubKindItem] = []
    @Published var subSubKindItemsBySubSubID: [Int: [AdminSubKindItemDetail]] = [:]
    @Published var isLoadingSubSubTaxonomy: Bool = false
    var hasSubSubKinds: Bool { !availableSubSubKinds.isEmpty }

    init(item: PetAccessory) {
        self.item = item
        fetchTaxonomy()
    }

    func fetchTaxonomy() {
        guard availableSubSubKinds.isEmpty, !isLoadingSubSubTaxonomy else { return }
        let mainID = item.petMainCategoryID
        let subID = item.petSubCategoryID > 0 ? item.petSubCategoryID : ((item.petSubCategoryIDs as? [NSNumber])?.first?.intValue ?? 0)
        guard mainID > 0 || subID > 0 else { return }

        let cachedKinds = (AppManager.shared().mainKindsArray as? [MainKindsModel]) ?? (MainKindsArrayManager.shared().mainKindsArray as? [MainKindsModel]) ?? []
        let fallbackKind: MainKindsModel? = MainKindsArrayManager.shared().mainKind(forID: mainID)
        var resolvedMainKind = cachedKinds.first(where: { $0.id == mainID }) ?? fallbackKind
        if resolvedMainKind == nil && subID > 0 {
            resolvedMainKind = cachedKinds.first(where: { mk in
                let subs = (mk.subKindsArray as? [SubKindModel]) ?? (MainKindsArrayManager.shared().getSubKindArray(mk.id) as? [SubKindModel]) ?? []
                return subs.contains(where: { $0.id == subID })
            })
        }
        if let mainKind = resolvedMainKind,
           let subKinds = (mainKind.subKindsArray as? [SubKindModel]) ?? (MainKindsArrayManager.shared().getSubKindArray(mainKind.id) as? [SubKindModel]),
           let subKind = subKinds.first(where: { $0.id == subID }) {
            if let arr = subKind.subSubKindArray as? [subSubKindModel], !arr.isEmpty {
                self.availableSubSubKinds = arr.map { m in
                    AdminSubSubKindItem(
                        id: "\(m.id)",
                        numericID: m.id,
                        subKindID: m.subKindID,
                        nameAr: m.nameAr ?? "",
                        nameEn: m.nameEn ?? "",
                        imageUrl: ""
                    )
                }
                for m in arr {
                    if let items = m.subKindItemsArray as? [subKindItemsModel], !items.isEmpty {
                        self.subSubKindItemsBySubSubID[m.id] = items.map { it in
                            AdminSubKindItemDetail(
                                id: "\(it.id)",
                                numericID: it.id,
                                subSubKindID: it.subSubKindID,
                                itemNameAr: it.itemNameAr ?? "",
                                itemNameEn: it.itemNameEn ?? "",
                                male: it.male ?? "",
                                female: it.female ?? "",
                                imageUrl: ""
                            )
                        }
                    }
                }
                if !self.availableSubSubKinds.isEmpty { return }
            }

            let mainDocID = mainKind.documentID.isEmpty ? "\(mainKind.id)" : mainKind.documentID
            let subKindDocID = (subKind.documentID != nil && !subKind.documentID!.isEmpty) ? subKind.documentID! : "\(subKind.id)"
            guard !mainDocID.isEmpty && !subKindDocID.isEmpty else { return }

            isLoadingSubSubTaxonomy = true
            let db = Firestore.firestore()
            let subDocRef = db.collection("MainKinds").document(mainDocID).collection("SubKinds").document(subKindDocID)
            subDocRef.collection("SubSubKinds").order(by: "ID", descending: false).getDocuments { [weak self] (snapshot: QuerySnapshot?, _: Error?) in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isLoadingSubSubTaxonomy = false
                    guard let docs = snapshot?.documents, !docs.isEmpty else { return }
                    let subSubs = docs.compactMap { AdminSubSubKindItem.fromSnapshot($0) }
                    if !subSubs.isEmpty {
                        self.availableSubSubKinds = subSubs
                        for subSub in subSubs {
                            let subSubDocID = subSub.id.isEmpty ? "\(subSub.numericID)" : subSub.id
                            subDocRef.collection("SubSubKinds").document(subSubDocID).collection("Items").order(by: "ID", descending: false).getDocuments { (itemSnap: QuerySnapshot?, _: Error?) in
                                DispatchQueue.main.async {
                                    let items = itemSnap?.documents.compactMap { AdminSubKindItemDetail.fromSnapshot($0) } ?? []
                                    self.subSubKindItemsBySubSubID[subSub.numericID] = items
                                }
                            }
                        }
                    }
                }
            }
        }
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
    var canReleaseQuarantine: Bool { canManageStock && (staff?.hasPermission("stock.quarantine.release") ?? false) }
    var canViewLivePetReturns: Bool {
        (staff?.hasPermission("returns.live_pet.view") ?? false) || (staff?.isAdmin() ?? false)
    }
    var canViewCosts: Bool { (staff?.hasPermission("stock.cost.view") ?? false) || (staff?.isAdmin() ?? false) }

    func reservation(for unit: PPLivePetInventoryUnit) -> PPLivePetReservation? {
        reservations.first { $0.contains(productID: item.accessoryID, unitID: unit.id) }
    }

    @discardableResult
    func load() async -> Bool {
        guard item.isLivePet else { return true }
        isLoading = true
        errorMessage = nil
        var confirmed = true
        do {
            let authoritativeProduct = try await PPLivePetInventoryService.readProduct(
                productID: item.accessoryID,
                minimumRevision: 0
            )
            item.revision = authoritativeProduct.revision
            item.quantity = authoritativeProduct.quantity
            item.reservedQuantity = authoritativeProduct.reservedQuantity
            item.noStock = authoritativeProduct.noStock
            item.isArchived = authoritativeProduct.isArchived
            item.active = authoritativeProduct.active
            item.showInAppMarket = authoritativeProduct.showInAppMarket
            item.inventoryMode = authoritativeProduct.inventoryMode
            item.inventorySchemaVersion = authoritativeProduct.inventorySchemaVersion
            if mode == .individual {
                do {
                    if canManageStock {
                        units = try await PPLivePetInventoryService.listUnits(productID: item.accessoryID).sorted()
                    } else if canSell {
                        // `includeReservations` is a stock.manage-only read in
                        // Infra. POS staff still receive available units here;
                        // their pending reservations are loaded through the
                        // separate reservation projection below.
                        units = try await PPLivePetInventoryService.listUnits(
                            productID: item.accessoryID,
                            includeHistory: false,
                            includeReservations: false
                        ).sorted()
                    } else {
                        units = []
                    }
                } catch {
                    if canManageStock { throw error }
                    confirmed = false
                    errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
                }
            } else {
                units = []
            }
            do {
                branches = scopedBranches(try await PPLivePetInventoryService.listBranches())
            } catch {
                confirmed = false
                errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
            }
            if canViewReservations {
                do {
                    reservations = try await PPLivePetInventoryService.listReservations(productID: item.accessoryID)
                } catch {
                    confirmed = false
                    errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
                }
            } else {
                reservations = []
            }
        } catch {
            confirmed = false
            errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
        }
        isLoading = false
        return confirmed && errorMessage == nil
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
            let confirmed = await load()
            if !confirmed {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                isMutating = false
                return false
            } else {
                successMessage = Language.get(successKey, alter: successFallback)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            isMutating = false
            return true
        } catch {
            errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            isMutating = false
            return false
        }
    }

    func migrate(mode: PPLivePetInventoryMode, units: [PPLivePetUnitDraft], standardSellingPrice: Double, commandID: String) async -> Bool {
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
                commandID: commandID,
                payload: payload
            )
            self.item.inventoryMode = mode.rawValue
            self.item.inventorySchemaVersion = 2
        }, successKey: "LivePet_Migration_Success", successFallback: "تم اعتماد نمط تتبع المخزون الحي.")
    }

    func intake(
        mode: PPLivePetInventoryMode,
        units: [PPLivePetUnitDraft],
        photoDrafts: [String: PPLivePetUnitPhotoDraft] = [:],
        quantity: Int,
        cost: Double?,
        supplier: String,
        notes: String,
        branchID: String? = nil,
        commandID: String
    ) async -> Bool {
        await perform({
            let targetBranch = branchID ?? BranchContextStore.shared.activeBranch?.branchID ?? self.item.storeID ?? ""
            let effectiveQty = mode == .individual ? max(1, units.count) : max(1, quantity)
            var payload: [String: Any] = [
                "quantity": effectiveQty,
                "supplier": supplier,
                "arrivalDate": ISO8601DateFormatter().string(from: units.first?.acquisitionDate ?? Date()),
                "notes": notes,
            ]
            if let cost { payload["costPrice"] = cost }
            if !targetBranch.isEmpty {
                payload["branchId"] = targetBranch
            }
            if mode == .individual {
                var mediaByUnitID: [String: [String]] = [:]
                if !photoDrafts.isEmpty {
                    guard let actorUID = Auth.auth().currentUser?.uid, !actorUID.isEmpty else {
                        throw PPLivePetUnitPhotoStorageService.livePetUnitPhotoError(
                            code: 2,
                            key: "LivePetIntake_UnitPhotoSessionExpired",
                            fallback: "انتهت جلسة الموظف. سجّل الدخول مجدداً قبل رفع صورة الحيوان."
                        )
                    }
                    for u in units {
                        if var photo = photoDrafts[u.id] {
                            let uploadedURL = try await PPLivePetUnitPhotoStorageService.upload(
                                photo: &photo,
                                unitID: u.id,
                                commandID: commandID,
                                actorUID: actorUID
                            )
                            if !uploadedURL.isEmpty {
                                mediaByUnitID[u.id] = [uploadedURL]
                            }
                        }
                    }
                }
                payload["units"] = try self.validatedUnitPayloads(units, mediaURLs: mediaByUnitID)
            }
            _ = try await PPLivePetInventoryService.callInventory(
                action: "intake",
                productID: self.item.accessoryID,
                commandID: commandID,
                payload: payload
            )
        }, successKey: "LivePet_Intake_Success", successFallback: "تمت إضافة المخزون وتأكيد سجل الحركة.")
    }

    func intake(
        mode: PPLivePetInventoryMode,
        unit: PPLivePetUnitDraft,
        photoDraft: PPLivePetUnitPhotoDraft? = nil,
        quantity: Int,
        cost: Double?,
        supplier: String,
        notes: String,
        branchID: String? = nil,
        commandID: String
    ) async -> Bool {
        var draftsMap: [String: PPLivePetUnitPhotoDraft] = [:]
        if let photoDraft { draftsMap[unit.id] = photoDraft }
        return await intake(
            mode: mode,
            units: [unit],
            photoDrafts: draftsMap,
            quantity: quantity,
            cost: cost,
            supplier: supplier,
            notes: notes,
            branchID: branchID,
            commandID: commandID
        )
    }

    func reserve(unit: PPLivePetInventoryUnit, customerName: String, phone: String, branchID: String, validUntil: Date, commandID: String) async -> Bool {
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
                validUntil: validUntil,
                commandID: commandID
            )
        }, successKey: "LivePet_Reservation_Success", successFallback: "تم حجز الحيوان وربطه بالعميل ونقطة البيع.")
    }

    func complete(reservation: PPLivePetReservation, cashReceived: Double, commandID: String) async -> Bool {
        await perform({
            try await PPLivePetInventoryService.completeReservation(reservation, cashReceived: cashReceived, commandID: commandID)
        }, successKey: "LivePet_Reservation_Complete_Success", successFallback: "اكتمل البيع وتم تحويل الحيوان إلى حالة مباع.")
    }

    func cancel(reservation: PPLivePetReservation, commandID: String) async -> Bool {
        await perform({
            try await PPLivePetInventoryService.cancelReservation(reservation, commandID: commandID)
        }, successKey: "LivePet_Reservation_Release_Success", successFallback: "تم تحرير الحجز وإعادة الحيوان إلى المتاح.")
    }

    func transfer(unit: PPLivePetInventoryUnit, sourceBranchID: String, destinationBranchID: String, reason: String, commandID: String) async -> Bool {
        await perform({
            _ = try await PPLivePetInventoryService.callInventory(
                action: "transfer_units_branch",
                productID: self.item.accessoryID,
                commandID: commandID,
                payload: [
                    "unitIds": [unit.id],
                    "expectedSourceBranchId": sourceBranchID,
                    "destinationBranchId": destinationBranchID,
                    "reason": reason,
                ]
            )
        }, successKey: "LivePet_Transfer_Success", successFallback: "تم نقل عهدة الحيوان إلى الفرع المحدد.")
    }

    func lifecycle(action: String, unit: PPLivePetInventoryUnit, reason: String, causeCode: String = "UNKNOWN", notes: String = "", veterinaryReference: String = "", observedDeathAt: Date? = nil, commandID: String) async -> Bool {
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
                commandID: commandID,
                payload: payload
            )
        }, successKey: "LivePet_Lifecycle_Success", successFallback: "تم تحديث حالة الحيوان وتسجيل الحركة في سجل التدقيق.")
    }

    func remove(unit: PPLivePetInventoryUnit, reason: String, commandID: String) async -> Bool {
        let unitID = unit.id
        // Optimistically remove unit from active units list so the row disappears immediately
        self.units.removeAll { $0.id == unitID }
        self.objectWillChange.send()
        let ok = await perform({
            _ = try await PPLivePetInventoryService.callInventory(
                action: "remove_unit",
                productID: self.item.accessoryID,
                commandID: commandID,
                payload: ["unitId": unitID, "reason": reason]
            )
        }, successKey: "LivePet_Remove_Success", successFallback: "تمت إزالة السجل المتاح من المخزون مع حفظ الأثر التشغيلي.")
        if !ok {
            await load()
        }
        return ok
    }

    func updatePrice(unit: PPLivePetInventoryUnit, price: Double, commandID: String) async -> Bool {
        await perform({
            _ = try await PPLivePetInventoryService.callInventory(
                action: "update_unit_selling_price",
                productID: self.item.accessoryID,
                commandID: commandID,
                payload: ["unitId": unit.id, "sellingPrice": price]
            )
        }, successKey: "LivePet_Price_Success", successFallback: "تم تحديث سعر بيع الحيوان.")
    }

    func updateUnitProfile(
        unit: PPLivePetInventoryUnit,
        ringTag: String,
        gender: PPLivePetUnitGender,
        notes: String,
        sellingPrice: Double,
        photoDraft: PPLivePetUnitPhotoDraft?,
        removeExistingPhoto: Bool = false,
        subSubKindID: Int? = nil,
        subSubKindNameAr: String? = nil,
        subSubKindNameEn: String? = nil,
        subSubKindItemID: Int? = nil,
        subSubKindItemNameAr: String? = nil,
        subSubKindItemNameEn: String? = nil,
        commandID: String
    ) async -> Bool {
        await perform({
            var mediaURLs: [String]? = nil
            var expectedMediaURLs: [String]? = nil

            if var draft = photoDraft {
                guard let actorUID = Auth.auth().currentUser?.uid, !actorUID.isEmpty else {
                    throw PPLivePetUnitPhotoStorageService.livePetUnitPhotoError(
                        code: 2,
                        key: "LivePetIntake_UnitPhotoSessionExpired",
                        fallback: "انتهت جلسة الموظف. سجّل الدخول مجدداً قبل رفع صورة الحيوان."
                    )
                }
                let uploadedURL = try await PPLivePetUnitPhotoStorageService.upload(
                    photo: &draft,
                    unitID: unit.id,
                    commandID: commandID,
                    actorUID: actorUID
                )
                if !uploadedURL.isEmpty {
                    mediaURLs = [uploadedURL]
                    expectedMediaURLs = unit.mediaURLs
                }
            } else if removeExistingPhoto {
                mediaURLs = []
                expectedMediaURLs = unit.mediaURLs
            }

            var payload: [String: Any] = [
                "unitId": unit.id,
                "ringTag": ringTag,
                "gender": gender.rawValue,
                "notes": notes,
                "sellingPrice": sellingPrice,
            ]
            if let mediaURLs {
                payload["mediaURLs"] = mediaURLs
                payload["expectedMediaURLs"] = expectedMediaURLs ?? []
            }
            if let subSubKindID {
                payload["subSubKindID"] = subSubKindID
                if let subSubKindNameAr { payload["subSubKindNameAr"] = subSubKindNameAr }
                if let subSubKindNameEn { payload["subSubKindNameEn"] = subSubKindNameEn }
            } else {
                payload["subSubKindID"] = NSNull()
            }
            if let subSubKindItemID {
                payload["subSubKindItemID"] = subSubKindItemID
                if let subSubKindItemNameAr { payload["subSubKindItemNameAr"] = subSubKindItemNameAr }
                if let subSubKindItemNameEn { payload["subSubKindItemNameEn"] = subSubKindItemNameEn }
            } else {
                payload["subSubKindItemID"] = NSNull()
            }

            _ = try await PPLivePetInventoryService.callInventory(
                action: "update_unit_profile",
                productID: self.item.accessoryID,
                commandID: commandID,
                payload: payload
            )
        }, successKey: "LivePet_Profile_Success", successFallback: "تم تحديث ملف الحيوان بنجاح.")
    }

    func adjustGroup(targetQuantity: Int, reason: String, commandID: String) async -> Bool {
        await perform({
            _ = try await PPLivePetInventoryService.callInventory(
                action: "adjust",
                productID: self.item.accessoryID,
                commandID: commandID,
                expectedRevision: self.item.revision > 0 ? self.item.revision : nil,
                payload: [
                    "adjustmentType": "manual",
                    "targetQuantity": max(0, targetQuantity),
                    "reason": reason,
                ]
            )
        }, successKey: "LivePet_Group_Adjust_Success", successFallback: "تم تحديث كمية المجموعة وتسجيل سبب التعديل.")
    }

    func archive(_ archived: Bool, reason: String, commandID: String) async -> Bool {
        await perform({
            _ = try await PPLivePetInventoryService.callInventory(
                action: "archive",
                productID: self.item.accessoryID,
                commandID: commandID,
                expectedRevision: self.item.revision > 0 ? self.item.revision : nil,
                payload: ["archived": archived, "reason": reason]
            )
            self.item.isArchived = archived
        }, successKey: archived ? "LivePet_Archive_Success" : "LivePet_Restore_Success", successFallback: archived ? "تمت أرشفة سجل الكتالوج." : "تمت استعادة سجل الكتالوج.")
    }

    private func validatedUnitPayloads(_ drafts: [PPLivePetUnitDraft], mediaURLs: [String: [String]] = [:], allowEmpty: Bool = false) throws -> [[String: Any]] {
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
                "mediaURLs": mediaURLs[draft.id] ?? [],
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

/// Firestore registrations support thread-safe removal. This lifetime token
/// also tears down a listener when Swift 6 destroys an actor-isolated model.
///
/// Shared by Inventory (`PPInventoryListViewModel`) and POS
/// (`POSFastSellViewModel`): a `@MainActor` model cannot touch a non-`Sendable`
/// `ListenerRegistration` from `deinit` under the Swift 6 language mode, so
/// without this wrapper a model can only detach in an explicit teardown call
/// and leaks its snapshot listener on any path that skips one.
///
/// Belongs in a shared layer rather than this Inventory file; kept here for now
/// because adding a file requires a `project.pbxproj` change.
final class PPFirestoreListenerToken: @unchecked Sendable {
    let registration: ListenerRegistration
    init(_ registration: ListenerRegistration) { self.registration = registration }
    func remove() { registration.remove() }
    deinit { registration.remove() }
}

@MainActor
final class PPInventoryListViewModel: ObservableObject {
    @Published private(set) var allItems: [PetAccessory] = []
    @Published private(set) var filteredItems: [PetAccessory] = []
    /// `filteredItems` collapsed so one logical product appears once.
    ///
    /// A colour family becomes a single grouping row whose children are the same
    /// per-colour cards as before; a product with no family stays a plain row.
    /// Derived from the already-loaded items, so grouping costs no extra reads.
    @Published private(set) var displayGroups: [PPInventoryDisplayGroup] = []
    @Published var branches: [PPInventoryBranchOption] = []
    @Published var searchText: String = ""
    @Published fileprivate var activeFilter: InventoryFilter = .all
    @Published var activeTab: CatalogHorizonTab
    @Published private(set) var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    @Published var selectedItemForDossier: PetAccessory? = nil

    private var listener: PPFirestoreListenerToken?
    private var listenerGeneration = UUID()
    private var refreshContinuation: CheckedContinuation<Void, Never>?
    private var branchInventoryCancellable: AnyCancellable?
    @Published private(set) var pendingQuantityItemIDs = Set<String>()
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
        allItems = []
        filteredItems = []
        displayGroups = []
        startListening()
    }

    func startListening() {
        stopListening()
        let generation = listenerGeneration
        isLoading = true
        errorMessage = nil
        Task { [weak self] in
            do {
                let loaded = try await PPLivePetInventoryService.listBranches()
                guard let self, self.listenerGeneration == generation else { return }
                self.branches = loaded
            } catch {
                guard let self, self.listenerGeneration == generation else { return }
                self.errorMessage = error.localizedDescription
            }
        }
        listener = PPFirestoreListenerToken(AccessoryManager.shared().observeAccessories(of: currentKind) { [weak self] items, error in
            DispatchQueue.main.async {
                guard let self, self.listenerGeneration == generation else { return }
                defer {
                    self.refreshContinuation?.resume()
                    self.refreshContinuation = nil
                }
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
        })
    }

    func stopListening() {
        listenerGeneration = UUID()
        listener?.remove()
        listener = nil
        refreshContinuation?.resume()
        refreshContinuation = nil
    }

    deinit {
        listener?.remove()
        refreshContinuation?.resume()
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
        displayGroups = PPInventoryDisplayGroup.grouped(result)
    }

    private func itemDiscountValue(_ item: PetAccessory) -> Double {
        let percent = item.discountPercent?.doubleValue ?? 0
        let amount = item.discountAmount?.doubleValue ?? 0
        return max(percent, amount)
    }

    func refresh() async {
        // Refresh the same owned projection, never replace it with a separate
        // 50-item query whose callback can race a category switch or listener.
        await withCheckedContinuation { continuation in
            startListening()
            refreshContinuation = continuation
        }
    }

    // MARK: - Explicit Quantity Adjustment

    func adjustQuantity(by delta: Int, for item: PetAccessory) {
        let docID = item.accessoryID
        guard !docID.isEmpty, delta != 0 else { return }

        if item.isLivePet {
            errorMessage = Language.get(
                "LivePet_Exact_Quantity_Derived",
                alter: "يُدار مخزون الحيوانات الحية من تفاصيل الصنف حتى تُسجل الهوية أو الكمية والسبب بأمان."
            )
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        guard !pendingQuantityItemIDs.contains(docID) else {
            PPHUD.showError(
                Language.get("Inventory_AdjustmentPending", alter: "التعديل قيد التأكيد"),
                subtitle: Language.get("Inventory_AdjustmentPendingDetail", alter: "انتظر تأكيد التعديل الحالي قبل إرسال تعديل آخر للصنف نفسه.")
            )
            return
        }
        guard let branchId = BranchContextStore.shared.activeBranch?.branchID
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !branchId.isEmpty,
              branchId != "main_store" else {
            PPHUD.showError(
                Language.get("Error", alter: "خطأ"),
                subtitle: Language.get("SelectSpecificBranchFirst", alter: "يرجى اختيار فرع محدد أولاً")
            )
            return
        }

        let previousQuantity = effectiveStock(for: item)
        let currentStaff = PPStaffAuth.shared().cachedCurrentStaff
        guard currentStaff?.hasPermission(kStaffPermStockManage, inBranch: branchId) == true || currentStaff?.isAdmin() == true else {
            errorMessage = Language.get("NoPermissionToManage", alter: "ليس لديك صلاحية تعديل بيانات المخزون")
            return
        }
        guard PPBranchInventoryService.shared.isServerConfirmed else {
            errorMessage = Language.get("Inventory_ProjectionUnavailable", alter: "تعذر التحقق من رصيد الفرع. أعد تحميل المخزون.")
            return
        }
        let targetQuantity = previousQuantity + delta
        guard targetQuantity >= 0 else {
            PPHUD.showError(
                Language.get("Error", alter: "خطأ"),
                subtitle: Language.get("Inventory_NegativeStockRejected", alter: "لا يمكن أن يصبح الرصيد المتاح أقل من صفر.")
            )
            return
        }
        pendingQuantityItemIDs.insert(docID)
        let expectedRevision = PPBranchInventoryService.shared.inventory(for: docID)?.projectionRevision
        let commandID = PPInventoryCommandService.shared.generateCommandId(action: "adjust", targetId: docID)
        PPInventoryCommandService.shared.adjustStock(
            productId: docID,
            branchId: branchId,
            delta: delta,
            newQuantity: nil,
            reason: "manual_adjustment",
            notes: "admin_inventory_list",
            expectedRevision: expectedRevision,
            commandId: commandID
        ) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.pendingQuantityItemIDs.remove(docID)
                    let message = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                    PPHUD.showError(Language.get("Error", alter: "خطأ"), subtitle: message)
                } else {
                    // An accepted callable is not yet the balance on screen.
                    // Keep this product locked through server readback, including
                    // the revision returned by the existing adjustment command.
                    PPBranchInventoryService.shared.refreshInventory(
                        for: docID, branchId: branchId, minimumRevision: result?.revision ?? 0
                    ) { [weak self] observation in
                        guard let self else { return }
                        self.pendingQuantityItemIDs.remove(docID)
                        switch observation {
                        case .success:
                            self.errorMessage = nil
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        case .failure(let error):
                            guard !(error is CancellationError) else { return }
                            self.errorMessage = Language.get("InventoryCell_ReadbackPending", alter: "تم استلام التعديل، وتعذر تأكيد الرصيد. اسحب للتحديث قبل تعديل الصنف مرة أخرى.")
                            PPHUD.showError(Language.get("Inventory_AdjustmentPending", alter: "التعديل قيد التأكيد"), subtitle: self.errorMessage)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quick Out of Stock Toggle

    func toggleStockAvailability(for item: PetAccessory) {
        // Availability is derived from authoritative branch quantity (or live-pet
        // unit state). Never translate a presentation toggle into a quantity
        // reconciliation: doing so can destroy stock history and on-hand counts.
        let message = item.isLivePet
            ? Language.get(
                "LivePet_Availability_ServerOwned",
                alter: "توفر الحيوان يتغير من خلال البيع أو الحجر أو النقل أو الوفاة، وليس من مفتاح يدوي."
            )
            : Language.get(
                "Inventory_Availability_DerivedFromQuantity",
                alter: "حالة التوفر مشتقة من الرصيد الفعلي. استخدم تعديل الكمية لتحديث المخزون بأمان."
            )
        errorMessage = message
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        PPHUD.showError(Language.get("Inventory_StockProtected", alter: "المخزون محمي"), subtitle: message)
    }

    // MARK: - Quick App Market Visibility Toggle

    func toggleAppMarketVisibility(for item: PetAccessory) {
        let docID = item.accessoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !docID.isEmpty else { return }

        let previousValue = item.showInAppMarket
        let newValue = !previousValue

        item.showInAppMarket = newValue
        objectWillChange.send()
        applyFilter()

        let commandID = PPInventoryCommandService.shared.generateCommandId(action: "visibility", targetId: docID)
        PPInventoryCommandService.shared.setAppMarketVisibility(
            productId: docID,
            visible: newValue,
            expectedRevision: item.revision > 0 ? item.revision : nil,
            commandId: commandID
        ) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    item.showInAppMarket = previousValue
                    self?.objectWillChange.send()
                    self?.applyFilter()
                    PPHUD.showError(Language.get("Error", alter: "خطأ"), subtitle: PPBranchInventoryErrorHelper.localizedMessage(for: error))
                } else {
                    if let revision = result?.revision, revision > 0 { item.revision = revision }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    let msg = newValue ? Language.get("AppMarket_NowVisible_Toast", alter: "تم إظهار الصنف في متجر التطبيق") : Language.get("AppMarket_NowHidden_Toast", alter: "تم إخفاء الصنف من متجر التطبيق")
                    PPHUD.showSuccess(msg)
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
        displayGroups = PPInventoryDisplayGroup.grouped(filteredItems)
        applyFilter()
        objectWillChange.send()

        PPHUD.showIndeterminate(in: nil, title: Language.get("Deleting", alter: "جاري الحذف..."), subtitle: nil)
        Task { @MainActor in
            do {
                _ = try await PPLivePetInventoryService.callInventory(
                    action: "delete",
                    productID: docID,
                    commandID: PPLivePetInventoryService.commandID("delete"),
                    expectedRevision: item.revision > 0 ? item.revision : nil,
                    payload: ["reason": "admin_ios_soft_delete"]
                )

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
    }

    func toggleActive(_ item: PetAccessory) {
        let docID = item.accessoryID
        guard !docID.isEmpty else { return }
        let newActive = !item.active
        Task { @MainActor in
            do {
                _ = try await PPLivePetInventoryService.callInventory(
                    action: "update",
                    productID: docID,
                    commandID: PPLivePetInventoryService.commandID("active-state"),
                    expectedRevision: item.revision > 0 ? item.revision : nil,
                    payload: ["active": newActive]
                )
                item.active = newActive
                await refresh()
            } catch {
                PPHUD.showError(
                    Language.get("Error", alter: nil),
                    subtitle: PPLivePetInventoryService.localizedMessage(for: error)
                )
            }
        }
    }
}

// MARK: - Reimagined Flagship Inventory Screen

@available(iOS 16.0, *)
@MainActor
struct PPInventoryListView: View {
    private let session: AdminSession?
    @StateObject private var viewModel: PPInventoryListViewModel
    @ObservedObject private var branchProjection = PPBranchInventoryService.shared
    @ObservedObject private var branchContext = BranchContextStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    private let onPushViewController: (UIViewController) -> Void
    private let onDismiss: (() -> Void)?
    private let showsCatalogSwitcher: Bool

    @FocusState private var isSearchFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var showingBranchSwitcherSheet: Bool = false
    @State private var itemForDamage: PetAccessory? = nil
    /// Families the operator has expanded. Collapsed by default so the list
    /// shows one row per logical product until a colour is actually needed.
    @State private var expandedFamilyIds: Set<String> = []
    /// One selected sellable member per expanded family. Keeping selection
    /// outside the row prevents child state from being recreated while scrolling.
    @State private var selectedFamilyProductIds: [String: String] = [:]
    @State private var itemForQuarantine: PetAccessory? = nil
    @State private var itemForLots: PetAccessory? = nil
    @State private var showCycleCountStudio: Bool = false
    @State private var itemForActionMenu: PetAccessory? = nil

    private var staff: PPStaffDoc? { PPStaffAuth.shared().cachedCurrentStaff }
    private var canManageStock: Bool {
        if let session {
            return session.hasPermission("stock.manage") || session.grantsAllPermissions || session.roleIdentifier == "admin" || session.roleIdentifier == "super_admin" || session.roleIdentifier == "owner"
        }
        return (staff?.hasPermission(kStaffPermStockManage) ?? false) || (staff?.isAdmin() ?? false)
    }
    private var canCreateStock: Bool {
        if let session {
            return session.hasPermission("stock.create") || session.grantsAllPermissions || session.roleIdentifier == "admin" || session.roleIdentifier == "super_admin" || session.roleIdentifier == "owner"
        }
        return (staff?.hasPermission("stock.create") ?? false) || (staff?.isAdmin() ?? false)
    }
    private var canDeleteStock: Bool {
        if let session {
            return session.hasPermission("stock.delete") || session.grantsAllPermissions || session.roleIdentifier == "admin" || session.roleIdentifier == "super_admin" || session.roleIdentifier == "owner"
        }
        return (staff?.hasPermission("stock.delete") ?? false) || (staff?.isAdmin() ?? false)
    }
    private var canReleaseQuarantine: Bool {
        if let session {
            return canManageStock && session.hasPermission("stock.quarantine.release")
        }
        return canManageStock && (staff?.hasPermission("stock.quarantine.release") ?? false)
    }
    private var canViewCosts: Bool {
        if let session {
            return session.hasPermission("stock.cost.view") || session.grantsAllPermissions || session.roleIdentifier == "admin" || session.roleIdentifier == "super_admin" || session.roleIdentifier == "owner"
        }
        return (staff?.hasPermission("stock.cost.view") ?? false) || (staff?.isAdmin() ?? false)
    }

    init(
        kind: AccessKindType = .typeAccessory,
        session: AdminSession? = nil,
        showsCatalogSwitcher: Bool = true,
        onPushViewController: ((UIViewController) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.session = session
        _viewModel = StateObject(wrappedValue: PPInventoryListViewModel(kind: kind))
        self.showsCatalogSwitcher = showsCatalogSwitcher
        self.onPushViewController = onPushViewController ?? { targetVC in
            PPAdminNavigationFallback.presentOrPush(targetVC)
        }
        self.onDismiss = onDismiss
    }

    private func openAddEditor() {
        guard canCreateStock else {
            PPHUD.showError(
                Language.get("Error", alter: "خطأ"),
                subtitle: Language.get("NoPermissionToCreate", alter: "ليس لديك صلاحية إضافة أصناف جديدة للمخزون")
            )
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let addVC = AddAccessoryViewController(accessory: nil)
        addVC.showTypeRow = false
        addVC.defaultKind = viewModel.currentKind
        addVC.onDismissBlock = {
            viewModel.applyFilter()
        }
        onPushViewController(addVC)
    }

    private func openEditEditor(for item: PetAccessory) {
        guard canManageStock else {
            PPHUD.showError(
                Language.get("Error", alter: "خطأ"),
                subtitle: Language.get("NoPermissionToManage", alter: "ليس لديك صلاحية تعديل بيانات المخزون")
            )
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let editVC = AddAccessoryViewController(accessory: item)
        editVC.showTypeRow = false
        editVC.defaultKind = viewModel.currentKind
        editVC.onDismissBlock = {
            viewModel.applyFilter()
        }
        onPushViewController(editVC)
    }

    private func openItemDetail(for item: PetAccessory) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let detailVC = PPInventoryItemDetailHostingController(
            item: item,
            viewModel: viewModel,
            onOpenFullEditor: {
                openEditEditor(for: item)
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
                confirmDelete(item: item)
            }
        )
        onPushViewController(detailVC)
    }

    public var body: some View {
        GeometryReader { geometry in
            let isRegular = geometry.size.width >= 760

            ZStack(alignment: .bottom) {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    sovereignHeaderBar
                        .frame(maxWidth: isRegular ? 980 : .infinity)
                        .frame(maxWidth: .infinity)

                    if showsCatalogSwitcher {
                        catalogHorizonSwitcher
                            .frame(maxWidth: isRegular ? 980 : .infinity)
                            .frame(maxWidth: .infinity)
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: AdminSpacing.base) {
                            inventoryHero

                            if viewModel.isLoading && viewModel.allItems.isEmpty {
                                loadingSkeletonView
                                    .accessibilityHidden(true)
                            } else if viewModel.allItems.isEmpty && viewModel.errorMessage != nil {
                                inventoryUnavailableState
                            } else if viewModel.allItems.isEmpty {
                                flagshipCatalogEmptyStateView(isRegular: isRegular)
                            } else {
                                if viewModel.filteredItems.isEmpty {
                                    filterEmptyStateCard
                                } else {
                                    itemsListSection
                                }
                            }
                        }
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.top, 10)
                        .padding(.bottom, 115)
                        .frame(maxWidth: isRegular ? 980 : .infinity)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboardCompat()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .refreshable {
                        await refreshHero()
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)

                if !viewModel.allItems.isEmpty {
                    bottomFloatingSearchDock(isRegular: isRegular, safeBottom: geometry.safeAreaInsets.bottom)
                }
            }
        }
        .ignoresSafeArea()
        .dismissKeyboardOnTapOutside()
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = frame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
        .sheet(isPresented: $showingBranchSwitcherSheet) {
            PPBranchSelectionGateView()
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .fullScreenCover(item: $itemForLots) { item in
            InventoryLotsSheet(
                item: item,
                branchId: BranchContextStore.shared.activeBranch?.branchID ?? item.resolvedBranchID(),
                onLotsChanged: {
                    viewModel.applyFilter()
                }
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .fullScreenCover(item: $itemForQuarantine) { item in
            QuarantineStudioSheet(
                item: item,
                branchId: BranchContextStore.shared.activeBranch?.branchID ?? item.resolvedBranchID(),
                onResolved: {
                    viewModel.applyFilter()
                }
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .fullScreenCover(item: $itemForDamage) { item in
            DamageStockSheet(
                item: item,
                branchId: BranchContextStore.shared.activeBranch?.branchID ?? item.resolvedBranchID(),
                onDamageRecorded: {
                    viewModel.applyFilter()
                }
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .fullScreenCover(isPresented: $showCycleCountStudio) {
            CycleCountStudioView(
                branchId: BranchContextStore.shared.activeBranch?.branchID ?? ""
            ) {
                viewModel.applyFilter()
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(item: $itemForActionMenu) { item in
            PPInventoryActionMenuSheet(
                item: item,
                onEdit: {
                    itemForActionMenu = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        openEditEditor(for: item)
                    }
                },
                onRecordDamage: {
                    itemForActionMenu = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        itemForDamage = item
                    }
                },
                onQuarantineStudio: {
                    itemForActionMenu = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        itemForQuarantine = item
                    }
                },
                onManageLots: {
                    itemForActionMenu = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        itemForLots = item
                    }
                },
                onShare: {
                    if let root = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .flatMap({ $0.windows })
                        .first(where: { $0.isKeyWindow })?.rootViewController {
                        PetAccessory.share(item, from: root)
                    }
                },
                onToggleStock: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    itemForActionMenu = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        openItemDetail(for: item)
                    }
                },
                onDelete: {
                    itemForActionMenu = nil
                    confirmDelete(item: item)
                },
                onOpenPOS: {
                    itemForActionMenu = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let controller = PPAdminRouteFactory.viewController(routeIdentifier: "pos", payload: item.accessoryID) {
                            onPushViewController(controller)
                        }
                    }
                },
                onRecordMortality: {
                    itemForActionMenu = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        openItemDetail(for: item)
                    }
                },
                onLiveIntake: {
                    itemForActionMenu = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        openItemDetail(for: item)
                    }
                },
                onToggleAppMarket: {
                    viewModel.toggleAppMarketVisibility(for: item)
                }
            )
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
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
        guard canDeleteStock else {
            PPHUD.showError(
                Language.get("Error", alter: "خطأ"),
                subtitle: Language.get("NoPermissionToDelete", alter: "ليس لديك صلاحية حذف الأصناف من المخزون")
            )
            return
        }
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("Confirm Delete", alter: "تأكيد حذف المنتج"),
            subtitle: Language.get("Confirm_Delete_Desc", alter: "هل أنت متأكد من رغبتك في حذف هذا الصنف من المخزون؟ سيتم إلغاء تفعيله وإيقاف ظهوره بأمان."),
            confirmButton: Language.get("Delete", alter: "حذف من المخزون"),
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
                HStack(spacing: 8) {
                    if canCreateStock {
                        AdminPrimaryPillButton(
                            title: Language.get("Add", alter: "إضافة منتج"),
                            systemImage: "plus"
                        ) {
                            openAddEditor()
                        }
                    }

                    if canManageStock {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showCycleCountStudio = true
                        } label: {
                            Image(systemName: "slider.horizontal.2.square.on.square")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Color(uiColor: .ppPrimary))
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(uiColor: .systemBackground))
                                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color(uiColor: .ppPrimary).opacity(0.20), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Language.get("Inventory_Action_Cycle_Count", alter: "استوديو جرد وتسوية المخزون"))
                    }
                }
            }

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) { viewModel.startListening() }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 4)
            }
            if let error = branchProjection.inventoryError ?? branchProjection.settingsError {
                AdminErrorBanner(message: error) {
                    branchProjection.bindToBranch(branchProjection.currentBranchId)
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
            } else if branchProjection.currentBranchId != nil && !branchProjection.isServerConfirmed && !branchProjection.isLoading {
                Text(Language.get("Inventory_CachedStockNotice", alter: "الرصيد المعروض محفوظ مؤقتاً ولم يؤكده الخادم بعد."))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .padding(.horizontal, AdminSpacing.screenMargin)
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

    // MARK: - Branch Inventory Hero

    private var heroIsAwaitingBranch: Bool {
        let selectedID = branchContext.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines)
        return selectedID != branchProjection.currentBranchId || branchProjection.isLoading
    }

    private var heroHasMetrics: Bool {
        !heroIsAwaitingBranch &&
        branchProjection.inventoryError == nil &&
        branchProjection.settingsError == nil &&
        !(viewModel.allItems.isEmpty && (viewModel.isLoading || viewModel.errorMessage != nil))
    }

    private var heroStatus: (title: String, symbol: String, color: Color) {
        if viewModel.errorMessage != nil || branchProjection.inventoryError != nil || branchProjection.settingsError != nil {
            return (
                Language.get("InventoryHero_Status_Interrupted", alter: "تعذّر تحديث البيانات"),
                "exclamationmark.triangle",
                Color(uiColor: .ppWarning)
            )
        }
        if viewModel.isLoading || heroIsAwaitingBranch {
            return (
                Language.get("InventoryHero_Status_Loading", alter: "جارٍ تحديث المخزون"),
                "arrow.triangle.2.circlepath",
                AdminSurface.primary
            )
        }
        if branchProjection.currentBranchId != nil && !branchProjection.isServerConfirmed {
            return (
                Language.get("InventoryHero_Status_Cached", alter: "بيانات محفوظة · بانتظار التأكيد"),
                "clock",
                Color(uiColor: .ppWarning)
            )
        }
        if branchProjection.isServerConfirmed {
            return (
                Language.get("InventoryHero_Status_Confirmed", alter: "رصيد الفرع مؤكّد"),
                "checkmark.circle",
                Color(uiColor: .ppSuccess)
            )
        }
        return (
            Language.get("InventoryHero_Status_Catalog", alter: "عرض الكتالوج"),
            "square.stack.3d.up",
            AdminCommandInk.secondary
        )
    }

    private var inventoryHero: some View {
        // Capture each aggregate once per render. No new listeners or queries.
        let available = viewModel.inStockCount
        let low = viewModel.lowStockCount
        let out = viewModel.outOfStockCount
        let offers = viewModel.offersCount
        let total = viewModel.totalCount
        let newCount = viewModel.allItems.filter { $0.condition == .new }.count
        let usedCount = viewModel.allItems.filter { $0.condition == .used }.count
        let unpriced = viewModel.unpricedItemsCount
        let valuation = viewModel.totalValuation

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: AdminSpacing.md) {
                PPAdminBranchSwitcherBar(style: .embeddedHero, horizontalPadding: 0)
                    .frame(maxWidth: .infinity)
                heroRefreshButton
            }
            .padding(.horizontal, AdminSpacing.base)
            .padding(.vertical, AdminSpacing.md)
            .background(Color.white)

            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.35))
                .frame(height: AdminStroke.hairline)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AdminSpacing.base) {
                        heroValuation(valuation, total: total, unpriced: unpriced)
                        heroAvailability(available: available, total: total)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: AdminSpacing.lg) {
                            heroValuation(valuation, total: total, unpriced: unpriced)
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: AdminSpacing.sm)
                            heroAvailability(available: available, total: total)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        VStack(alignment: .leading, spacing: AdminSpacing.base) {
                            heroValuation(valuation, total: total, unpriced: unpriced)
                            heroAvailability(available: available, total: total)
                        }
                    }
                }

                inventoryHealthBand(available: available, low: low, out: out)
                    .padding(.top, AdminSpacing.xs)

                // One continuous ledger; selected filters have an underline as
                // well as a tint, so selection never depends on color alone.
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: AdminSpacing.sm, alignment: .leading),
                        count: dynamicTypeSize >= .accessibility3 ? 1 : (dynamicTypeSize.isAccessibilitySize ? 2 : 4)
                    ),
                    alignment: .leading,
                    spacing: AdminSpacing.md
                ) {
                    heroMetric(
                        filter: .inStock,
                        title: Language.get("InStock", alter: "متوفر"),
                        count: available,
                        color: Color(uiColor: .ppSuccess),
                        icon: "checkmark.circle"
                    )
                    heroMetric(
                        filter: .lowStock,
                        title: Language.get("InventoryHero_Low", alter: "منخفض"),
                        count: low,
                        color: Color(uiColor: .ppWarning),
                        icon: "exclamationmark.triangle"
                    )
                    heroMetric(
                        filter: .outOfStock,
                        title: Language.get("InventoryHero_Out", alter: "نافد"),
                        count: out,
                        color: Color(uiColor: .ppError),
                        icon: "minus.circle"
                    )
                    heroMetric(
                        filter: .hasOffer,
                        title: Language.get("Offers", alter: "تخفيضات"),
                        count: offers,
                        color: AdminSurface.primary,
                        icon: "tag"
                    )
                }
                .disabled(!heroHasMetrics || total == 0)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: AdminSpacing.sm),
                        count: dynamicTypeSize.isAccessibilitySize ? 1 : 3
                    ),
                    spacing: AdminSpacing.sm
                ) {
                    heroCatalogFilter(.all, count: total)
                    heroCatalogFilter(.conditionNew, count: newCount)
                    heroCatalogFilter(.conditionUsed, count: usedCount)
                }
                .disabled(!heroHasMetrics || total == 0)

                if heroHasMetrics && low > 0 {
                    Text(Language.get(
                        "InventoryHero_LowIncluded",
                        alter: "الأصناف منخفضة المخزون ضمن المتوفر."
                    ))
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if heroHasMetrics && unpriced > 0 {
                    Label {
                        Text(verbatim: String(
                            format: Language.get(
                                "Inventory_Unpriced_Items_Format",
                                alter: "لم يُحدَّد سعر البيع لعدد %@ من الأصناف. لا تشملها قيمة المخزون."
                            ),
                            unpriced.englishDigits
                        ).normalizedEnglishDigits)
                        .foregroundStyle(AdminCommandInk.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color(uiColor: .ppWarning))
                    }
                    .font(AdminType.caption1)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if heroHasMetrics {
                    Text(verbatim: String(
                        format: Language.get("Inventory_Showing_Count", alter: "%@ معروض"),
                        viewModel.filteredItems.count.englishDigits
                    ).normalizedEnglishDigits)
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("inventory.hero.visible-count")
                }
            }
            .padding(AdminSpacing.base)
        }
        .multilineTextAlignment(.leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inventory.hero")
    }

    private var heroRefreshButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await refreshHero() }
        } label: {
            Group {
                if viewModel.isLoading && !reduceMotion {
                    ProgressView()
                        .tint(AdminSurface.primary)
                } else {
                    Image(systemName: viewModel.isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }
            }
            .frame(width: AdminTouchTarget.comfortable, height: AdminTouchTarget.comfortable)
            .background(Color.white, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(CatalogPressStyle())
        .disabled(viewModel.isLoading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
        .accessibilityValue(viewModel.isLoading
            ? Language.get("InventoryHero_Status_Loading", alter: "جارٍ تحديث المخزون")
            : "")
        .accessibilityIdentifier("inventory.hero.refresh")
    }

    private func refreshHero() async {
        guard !viewModel.isLoading else { return }
        if branchProjection.inventoryError != nil || branchProjection.settingsError != nil {
            branchProjection.bindToBranch(branchProjection.currentBranchId)
        }
        await viewModel.refresh()
    }

    private func heroValuation(_ valuation: Double, total: Int, unpriced: Int) -> some View {
        let hasValue = heroHasMetrics && (total == 0 || unpriced < total)
        let title = unpriced > 0
            ? Language.get("InventoryHero_PricedValue", alter: "قيمة الأصناف المسعّرة")
            : Language.get("InventoryHero_Value", alter: "قيمة المخزون")
        let amount = hasValue
            ? valuation.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US")))
            : "—"
        let currency = Language.get("Currency", alter: "ر.ق")

        return VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            Text(title)
                .font(AdminType.footnote)
                .foregroundStyle(AdminCommandInk.secondary)
            HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.xs) {
                Text(verbatim: amount)
                    .font(PPBrandFont.bold(size: 36, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .environment(\.layoutDirection, .leftToRight)
                    .layoutPriority(1)
                Text(currency)
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .fixedSize()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(hasValue
            ? "\(amount) \(currency)"
            : Language.get("InventoryHero_ValueUnavailable", alter: "القيمة غير متاحة"))
        .accessibilityIdentifier("inventory.hero.valuation")
    }

    private func heroAvailability(available: Int, total: Int) -> some View {
        let hasRatio = heroHasMetrics && total > 0
        let percentage = hasRatio
            ? (Double(available) / Double(total)).formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
            : "—"
        let detail = String(
            format: Language.get("InventoryHero_CountFraction", alter: "%@ من %@ صنف"),
            available.englishDigits,
            total.englishDigits
        ).normalizedEnglishDigits

        return VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            Text(Language.get("InventoryHero_Availability", alter: "نسبة التوفر"))
                .font(AdminType.footnote)
                .foregroundStyle(AdminCommandInk.secondary)
            Text(verbatim: percentage)
                .font(PPBrandFont.bold(size: 28, relativeTo: .title))
                .monospacedDigit()
                .foregroundStyle(AdminSurface.primaryText)
                .environment(\.layoutDirection, .leftToRight)
            if hasRatio {
                Text(verbatim: detail)
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("InventoryHero_Availability", alter: "نسبة التوفر"))
        .accessibilityValue(hasRatio
            ? "\(percentage), \(detail)"
            : Language.get("InventoryHero_DataUnavailable", alter: "لا تتوفر بيانات"))
    }

    private func heroCatalogFilter(_ filter: InventoryFilter, count: Int) -> some View {
        let isSelected = viewModel.activeFilter == filter

        return Button {
            guard !isSelected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                viewModel.activeFilter = filter
            }
        } label: {
            HStack(spacing: AdminSpacing.xs) {
                Text(filter.defaultTitle)
                    .font(AdminType.captionBold)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(verbatim: heroHasMetrics ? count.englishDigits : "—")
                    .font(AdminType.caption1Bold)
                    .monospacedDigit()
                    .fixedSize()
                    .environment(\.layoutDirection, .leftToRight)
            }
            .foregroundStyle(AdminSurface.primaryText)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, AdminSpacing.sm)
            .padding(.vertical, AdminSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum)
            .background(
                isSelected ? Color(uiColor: .systemGray6) : Color.white,
                in: RoundedRectangle(cornerRadius: AdminRadius.small)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.small)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(isSelected ? AdminSurface.primary : .clear)
                    .frame(height: 2)
                    .padding(.horizontal, AdminSpacing.sm)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CatalogPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(filter.defaultTitle)
        .accessibilityValue(heroHasMetrics
            ? count.englishDigits
            : Language.get("InventoryHero_DataUnavailable", alter: "لا تتوفر بيانات"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "" : Language.get("DoubleTapToFilter", alter: "اضغط مرتين لتصفية القائمة"))
        .accessibilityIdentifier("inventory.hero.filter.\(filter.id)")
    }

    private func heroMetric(
        filter: InventoryFilter,
        title: String,
        count: Int,
        color: Color,
        icon: String
    ) -> some View {
        let isSelected = viewModel.activeFilter == filter

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                viewModel.activeFilter = isSelected ? .all : filter
            }
        } label: {
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(count > 0 || isSelected ? color : AdminCommandInk.secondary)
                    .accessibilityHidden(true)
                Text(verbatim: heroHasMetrics ? count.englishDigits : "—")
                    .font(AdminType.title2)
                    .monospacedDigit()
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .environment(\.layoutDirection, .leftToRight)
                Text(title)
                    .font(AdminType.captionBold)
                    .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminCommandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
            .padding(.horizontal, AdminSpacing.xs)
            .padding(.vertical, AdminSpacing.sm)
            .background(isSelected ? Color.white : .clear, in: RoundedRectangle(cornerRadius: AdminRadius.small))
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(isSelected ? color : .clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CatalogPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(filter.defaultTitle)
        .accessibilityValue(heroHasMetrics
            ? count.englishDigits
            : Language.get("InventoryHero_DataUnavailable", alter: "لا تتوفر بيانات"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected
            ? Language.get("DoubleTapToDeselect", alter: "اضغط مرتين لإلغاء التصفية")
            : Language.get("DoubleTapToFilter", alter: "اضغط مرتين لتصفية القائمة"))
        .accessibilityIdentifier("inventory.hero.filter.\(filter.id)")
    }

    private func inventoryHealthBand(available: Int, low: Int, out: Int) -> some View {
        // Low inventory is already included in available. Chart segments must
        // form a partition, otherwise the old bar overflowed and hid warnings.
        let healthy = max(0, available - low)
        let counts = [healthy, low, out]
        let colors = [Color(uiColor: .ppSuccess), Color(uiColor: .ppWarning), Color(uiColor: .ppError)]
        let total = max(1, counts.reduce(0, +))
        let segmentCount = counts.filter { $0 > 0 }.count

        return GeometryReader { proxy in
            if heroHasMetrics {
                let usableWidth = max(0, proxy.size.width - CGFloat(max(0, segmentCount - 1)) * 3)
                HStack(spacing: 3) {
                    ForEach(counts.indices, id: \.self) { index in
                        if counts[index] > 0 {
                            Capsule()
                                .fill(colors[index])
                                .frame(width: usableWidth * CGFloat(counts[index]) / CGFloat(total))
                        }
                    }
                }
            }
        }
        .frame(height: 6)
        .background(Color(uiColor: .systemGray5), in: Capsule())
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private var inventoryUnavailableState: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Label(
                Language.get("InventoryHero_Unavailable_Title", alter: "تعذّر تحميل المخزون"),
                systemImage: "exclamationmark.triangle"
            )
            .font(AdminType.headline)
            Text(Language.get(
                "InventoryHero_Unavailable_Detail",
                alter: "لم نتمكن من تأكيد بيانات الكتالوج. أعد المحاولة باستخدام زر التحديث أعلاه."
            ))
            .font(AdminType.body)
            .foregroundStyle(AdminCommandInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
    }

    // MARK: - Category-Defining Bottom Floating Search Dock

    @ViewBuilder
    private func bottomFloatingSearchDock(isRegular: Bool, safeBottom: CGFloat) -> some View {
        HStack(spacing: 10) {
            // Interactive Search Glass with live focus animation
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: isSearchFocused ? .bold : .semibold))
                .foregroundStyle(isSearchFocused ? AdminSurface.primary : AdminCommandInk.secondary)
                .scaleEffect(isSearchFocused ? 1.08 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSearchFocused)
                .accessibilityHidden(true)

            // Fluid Search Input
            TextField(
                Language.get("Inventory_Search_Placeholder", alter: "ابحث بالاسم، الباركود، المتجر، أو المعرّف..."),
                text: $viewModel.searchText
            )
            .font(AdminType.callout)
            .foregroundStyle(AdminSurface.primaryText)
            .focused($isSearchFocused)
            .submitLabel(.search)
            .onSubmit {
                isSearchFocused = false
            }

            // Dynamic Live Match Counter Pill (when query is entered)
            if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 3) {
                    Text(String(format: Language.get("Inventory_Search_Count", alter: "%@ صنف"), "\(viewModel.filteredItems.count)".normalizedEnglishDigits))
                        .font(AdminType.caption2.weight(.bold))
                        .foregroundStyle(viewModel.filteredItems.isEmpty ? Color(uiColor: .ppWarning) : AdminSurface.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(viewModel.filteredItems.isEmpty ? Color(uiColor: .ppWarning).opacity(0.12) : AdminSurface.primarySoft)
                )
                .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity), removal: .opacity))

                // Instant Clear Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AdminCommandInk.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Language.get("Clear_Search", alter: "إلغاء التصفية وإظهار الكل"))
            }

            // Dismiss Keyboard Action when keyboard is up & focused
            if isSearchFocused {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isSearchFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.primarySoft, in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Language.get("Dismiss_Keyboard", alter: "إخفاء لوحة المفاتيح"))
            }

            // Integrated Barcode Viewfinder Reticle Button
            AdminBarcodeScanButton(isCircle: true) { scanned in
                viewModel.searchText = scanned
                isSearchFocused = false
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AdminSurface.surface.opacity(0.92))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    isSearchFocused ? AdminSurface.primary : Color(uiColor: .separator).opacity(0.35),
                    lineWidth: isSearchFocused ? 1.5 : 0.75
                )
        )
        .shadow(
            color: isSearchFocused ? AdminSurface.primary.opacity(0.18) : Color.black.opacity(0.09),
            radius: isSearchFocused ? 20 : 14,
            x: 0,
            y: isSearchFocused ? 8 : 5
        )
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        .frame(maxWidth: isRegular ? 640 : .infinity)
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.bottom, keyboardHeight > 0 ? (keyboardHeight + 10) : max(safeBottom, 14))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isSearchFocused)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.searchText.isEmpty)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: keyboardHeight)
    }

    // MARK: - Items List Section

    @ViewBuilder
    private var itemsListSection: some View {
        ForEach(viewModel.displayGroups) { group in
            switch group {
            case .single(let item):
                inventoryCard(for: item)
            case .family(let familyId, let members):
                let defaultMember = members.first(where: { $0.isDefaultVariant }) ?? members[0]
                let selectedMember = members.first(where: {
                    $0.accessoryID == selectedFamilyProductIds[familyId]
                }) ?? defaultMember

                VStack(alignment: .leading, spacing: 8) {
                    PPInventoryFamilyRow(
                        members: members,
                        isExpanded: Binding(
                            get: { expandedFamilyIds.contains(familyId) },
                            set: { isOn in
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    if isOn {
                                        expandedFamilyIds = [familyId]
                                        let current = selectedFamilyProductIds[familyId]
                                        if current == nil || !members.contains(where: { $0.accessoryID == current }) {
                                            selectedFamilyProductIds[familyId] = defaultMember.accessoryID
                                        }
                                    } else {
                                        expandedFamilyIds.remove(familyId)
                                    }
                                }
                            }
                        ),
                        selectedProductId: Binding(
                            get: {
                                let current = selectedFamilyProductIds[familyId]
                                return members.contains(where: { $0.accessoryID == current })
                                    ? (current ?? defaultMember.accessoryID)
                                    : defaultMember.accessoryID
                            },
                            set: { selectedFamilyProductIds[familyId] = $0 }
                        ),
                        // Same branch projection the selected color inspector uses,
                        // so family totals and child detail cannot disagree.
                        availability: { member in
                            PPBranchInventoryService.shared.availableStock(
                                for: member.accessoryID,
                                fallback: member.quantity
                            )
                        },
                        retailPrice: { member in
                            guard member.hasResolvedSellingPrice else { return nil }
                            let fallback = member.finalPrice.doubleValue
                            let resolved = PPBranchInventoryService.shared.effectiveSellingPrice(
                                for: member.accessoryID,
                                fallbackPrice: fallback
                            )
                            return resolved > 0 ? resolved : nil
                        },
                        lowStockThreshold: 3
                    )

                    // One product family unfolds into ONE exact color inspector.
                    // Changing the rail selection swaps this child in place rather
                    // than stacking full duplicate product cards down the list.
                    if expandedFamilyIds.contains(familyId) {
                        inventoryVariantInspector(for: selectedMember)
                            .padding(.trailing, 32)
                            .id(selectedMember.accessoryID)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .opacity
                                    )
                            )
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.18),
                                value: selectedMember.accessoryID
                            )
                    }
                }
            }
        }
    }

    /// Compact child workspace for one selected color. It receives the exact
    /// same branch projection and mutation closures as the full inventory card,
    /// but does not repeat family-level product identity or imagery.
    @ViewBuilder
    private func inventoryVariantInspector(for item: PetAccessory) -> some View {
        let selectedBranch = branchContext.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasBranch = !selectedBranch.isEmpty && selectedBranch != "main_store"
        let matchesBranch = branchProjection.currentBranchId == selectedBranch
        let record = matchesBranch && hasBranch ? branchProjection.inventory(for: item.accessoryID) : nil
        let state = inventoryCellStockState(for: item, hasBranch: hasBranch, matchesBranch: matchesBranch, record: record)
        let sellingPrice: NSNumber? = {
            guard item.hasResolvedSellingPrice else { return nil }
            guard hasBranch else { return item.finalPrice }
            guard matchesBranch, branchProjection.hasConfirmedCommercePrice(for: item.accessoryID) else { return nil }
            let price = branchProjection.effectiveSellingPrice(
                for: item.accessoryID,
                fallbackPrice: item.finalPrice.doubleValue
            )
            return price > 0 ? NSNumber(value: price) : nil
        }()

        PPInventoryVariantChildInspector(
            item: item,
            sellingPrice: sellingPrice,
            quantity: hasBranch ? record?.availableQuantity : max(0, item.quantity),
            branchName: "",
            stockState: state,
            canManageStock: canAccessInventoryCell(kStaffPermStockManage, branchID: hasBranch ? selectedBranch : nil),
            onOpen: { openItemDetail(for: item) },
            onEdit: { openEditEditor(for: item) },
            onAdjustQuantity: { delta in
                viewModel.adjustQuantity(by: delta, for: item)
            },
            onMore: { itemForActionMenu = item }
        )
    }

    /// Family members and standalone products share one presentation and the
    /// same branch projection. No card owns an additional Firebase listener.
    @ViewBuilder
    private func inventoryCard(for item: PetAccessory) -> some View {
        let selectedBranch = branchContext.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasBranch = !selectedBranch.isEmpty && selectedBranch != "main_store"
        let matchesBranch = branchProjection.currentBranchId == selectedBranch
        let record = matchesBranch && hasBranch ? branchProjection.inventory(for: item.accessoryID) : nil
        let state = inventoryCellStockState(for: item, hasBranch: hasBranch, matchesBranch: matchesBranch, record: record)
        let sellingPrice: NSNumber? = {
            guard item.hasResolvedSellingPrice else { return nil }
            guard hasBranch else { return item.finalPrice }
            guard matchesBranch, branchProjection.hasConfirmedCommercePrice(for: item.accessoryID) else { return nil }
            return NSNumber(value: branchProjection.effectiveSellingPrice(for: item.accessoryID, fallbackPrice: item.finalPrice.doubleValue))
        }()
        FlagshipInventoryCard(
            item: item,
            sellingPrice: sellingPrice,
            quantity: hasBranch ? record?.availableQuantity : max(0, item.quantity),
            reservedQuantity: hasBranch ? (record?.reservedQuantity ?? 0) : max(0, item.reservedQuantity),
            branchName: hasBranch ? (branchContext.activeBranch?.localizedName() ?? "") : item.resolvedBranchName(),
            stockState: state,
            canManageStock: canAccessInventoryCell(kStaffPermStockManage, branchID: hasBranch ? selectedBranch : nil),
            canDeleteStock: canAccessInventoryCell("stock.delete", branchID: hasBranch ? selectedBranch : nil),
            canViewCosts: canAccessInventoryCell("stock.cost.view", branchID: hasBranch ? selectedBranch : nil),
            onTap: {
                openItemDetail(for: item)
            },
            onEdit: {
                openEditEditor(for: item)
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
            },
            onRecordDamage: {
                if item.isLivePet {
                    openItemDetail(for: item)
                } else {
                    itemForDamage = item
                }
            },
            onQuarantineStudio: {
                itemForQuarantine = item
            },
            onManageLots: {
                if item.isLivePet {
                    openItemDetail(for: item)
                } else {
                    itemForLots = item
                }
            },
            onOpenActionMenu: {
                itemForActionMenu = item
            }
        )
    }

    private func canAccessInventoryCell(_ permission: String, branchID: String?) -> Bool {
        guard let staff else { return false }
        // Both methods reject inactive staff. Preserve Infra's active-admin
        // exception without granting authority from a session role string.
        return staff.isAdmin() || staff.hasPermission(permission, inBranch: branchID)
    }

    private func inventoryCellStockState(
        for item: PetAccessory,
        hasBranch: Bool,
        matchesBranch: Bool,
        record: PPBranchInventory?
    ) -> PPInventoryCellStockState {
        if !hasBranch { return .selectBranch }
        if !matchesBranch || branchProjection.isLoading { return .loading }
        if viewModel.pendingQuantityItemIDs.contains(item.accessoryID) { return .pending }
        if !branchProjection.isServerConfirmed || branchProjection.inventoryError != nil { return .unconfirmed }
        return record == nil ? .missing : .ready
    }

    // MARK: - Flagship Empty State View (Zero Catalog Items)

    @ViewBuilder
    private func flagshipCatalogEmptyStateView(isRegular: Bool) -> some View {
        Group {
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
                    if canCreateStock {
                        Button {
                            openAddEditor()
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
                    }

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

                if canCreateStock {
                    Button {
                        openAddEditor()
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

// MARK: - Category Specimen Aura Theme Engine

struct CategorySpecimenAuraTheme {
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
            gradient: [AdminSurface.primary.opacity(0.8), AdminSurface.primary],
            glyphName: "sparkles",
            accentTint: AdminSurface.primary,
            categoryName: catDisplay.isEmpty ? Language.get("Accessory", alter: "إكسسوار") : catDisplay
        )
    }
}

// MARK: - Inventory product cells

/// A cell receives the screen's existing projection; it never starts a listener
/// or invents availability from an image, a health label, or a catalog total.
private enum PPInventoryCellStockState: Equatable {
    case ready, selectBranch, loading, unconfirmed, missing, pending

    var caption: String? {
        switch self {
        case .ready: return nil
        case .selectBranch: return Language.get("InventoryCell_SelectBranch", alter: "اختر فرعاً لتعديل الرصيد")
        case .loading: return Language.get("InventoryCell_Loading", alter: "جارٍ تحميل رصيد الفرع")
        case .unconfirmed: return Language.get("InventoryCell_Unconfirmed", alter: "الرصيد غير مؤكد · اسحب للتحديث")
        case .missing: return Language.get("InventoryCell_Missing", alter: "رصيد الفرع غير متاح")
        case .pending: return Language.get("Inventory_AdjustmentPending", alter: "التعديل قيد التأكيد")
        }
    }

    var isBusy: Bool { self == .loading || self == .pending }
}

@available(iOS 16.0, *)
private struct PPInventoryVariantChildInspector: View {
    let item: PetAccessory
    let sellingPrice: NSNumber?
    let quantity: Int?
    let branchName: String
    let stockState: PPInventoryCellStockState
    let canManageStock: Bool
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onAdjustQuantity: (Int) -> Void
    let onMore: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var colour: PPAccessoryVariantColor? {
        item.variantColorDictionary.flatMap { PPAccessoryVariantColor(dictionary: $0) }
    }

    private var accent: Color {
        colour.map { Color(uiColor: $0.uiColor) } ?? AdminSurface.primary
    }

    private var variantTitle: String {
        let name = item.pos_variantDisplayName
        if !name.isEmpty && name != item.accessoryID { return name }
        if let colour, !colour.localizedName.isEmpty { return colour.localizedName }
        if let sku = item.sku?.trimmingCharacters(in: .whitespacesAndNewlines), !sku.isEmpty { return sku }
        return item.accessoryID
    }

    private var formattedPrice: String {
        sellingPrice.map { PetAccessory.formatCurrency($0) }
            ?? Language.get("Inventory_Price_Unavailable", alter: "السعر غير متاح")
    }

    private var isInactive: Bool {
        !item.active || item.isArchived || item.isDeleted || item.isDisabled || item.isBlocked
    }

    private var tracksLots: Bool {
        item.inventoryTrackingPolicy?.lowercased() == "lot"
    }

    private var tracksUnits: Bool {
        item.inventoryMode?.uppercased() == PPLivePetInventoryMode.individual.rawValue
            || item.inventoryTrackingPolicy?.lowercased() == "unit"
    }

    private var canAdjust: Bool {
        canManageStock && stockState == .ready && quantity != nil
            && !item.isLivePet && !tracksLots && !tracksUnits && !isInactive
    }

    private var statusColor: Color {
        guard stockState == .ready, let quantity else { return AdminCommandInk.secondary }
        if quantity <= 0 { return AdminSurface.crimson }
        if quantity <= 3 { return AdminSurface.amber }
        return AdminSurface.emerald
    }

    private var statusTitle: String {
        if let caption = stockState.caption { return caption }
        guard let quantity else { return Language.get("InventoryCell_Available", alter: "المتاح") }
        if quantity <= 0 { return Language.get("OutOfStock", alter: "نفذ من المخزون") }
        if quantity <= 3 { return Language.get("InventoryCell_Low", alter: "رصيد منخفض") }
        return Language.get("InventoryCell_Available", alter: "المتاح")
    }

    private var statusSymbol: String {
        switch stockState {
        case .ready:
            guard let quantity else { return "clock" }
            return quantity <= 0 ? "minus.circle.fill" : (quantity <= 3 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
        case .pending: return "clock.badge.checkmark"
        case .loading: return "arrow.triangle.2.circlepath"
        case .selectBranch: return "building.2"
        case .unconfirmed, .missing: return "exclamationmark.circle"
        }
    }

    private var accessibilitySummary: String {
        var parts = [variantTitle, formattedPrice, statusTitle]
        if let quantity, stockState == .ready {
            parts.append(String(
                format: Language.get("Variant_State_AvailableCount", alter: "%@ متوفر"),
                NSNumber(value: quantity)
            ))
        }
        if item.isDefaultVariant {
            parts.append(Language.get("Variant_State_Default", alter: "اللون الافتراضي"))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        variantIdentity
                        Spacer(minLength: 12)
                        commercialStatus
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        variantIdentity
                        commercialStatus
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(Language.get("InventoryCell_OpenHint", alter: "يفتح تفاصيل الصنف وإجراءاته"))

            Divider()
                .background(AdminSurface.hairline.opacity(0.55))

            actionDock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.borderSubtle.opacity(0.65), lineWidth: 0.75)
        }
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(AdminSurface.primary.opacity(0.95))
                .frame(width: 3.5)
                .padding(.vertical, 12)
                .accessibilityHidden(true)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 8, x: 0, y: 3)
    }

    private var variantIdentity: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent.opacity(0.10))
                    .frame(width: 46, height: 46)

                if item.pos_hasRealColor, let colour = colour {
                    Circle()
                        .fill(Color(uiColor: colour.uiColor))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    colour.requiresContrastBorder
                                        ? AdminSurface.primaryText.opacity(0.28)
                                        : Color.white.opacity(0.24),
                                    lineWidth: 1
                                )
                        }
                } else if !item.pos_variantShortBadge.isEmpty {
                    Text(item.pos_variantShortBadge)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AdminSurface.primary)
                } else {
                    Image(systemName: item.pos_variantDimension.sfSymbolName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AdminSurface.primary)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(variantTitle)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                    if item.isDefaultVariant {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(accent)
                            .accessibilityLabel(Language.get("Variant_State_Default", alter: "اللون الافتراضي"))
                    }
                }

                HStack(spacing: 6) {
                    if let sku = item.sku?.trimmingCharacters(in: .whitespacesAndNewlines), !sku.isEmpty {
                        HStack(spacing: 2) {
                            Text("SKU:")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                            Text(verbatim: sku)
                                .font(AdminType.caption2.monospaced())
                        }
                        .foregroundStyle(AdminCommandInk.tertiary)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                    }
                    if let barcode = item.barcode?.trimmingCharacters(in: .whitespacesAndNewlines), !barcode.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "barcode")
                                .font(.system(size: 8))
                            Text(verbatim: barcode)
                                .font(AdminType.caption2.monospaced())
                        }
                        .foregroundStyle(AdminCommandInk.tertiary)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                    }
                    if !branchName.isEmpty {
                        if !(item.sku?.isEmpty == false) && !(item.barcode?.isEmpty == false) {
                            Image(systemName: "building.2")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AdminCommandInk.tertiary)
                        }
                        Text(branchName)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var commercialStatus: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(formattedPrice.normalizedEnglishDigits)
                .font(AdminType.headline)
                .foregroundStyle(sellingPrice == nil ? AdminCommandInk.tertiary : AdminSurface.primaryText)
                .environment(\.layoutDirection, .leftToRight)

            HStack(spacing: 5) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 11, weight: .semibold))
                if stockState == .ready, let quantity {
                    Text(verbatim: quantity.englishDigits)
                        .font(AdminType.caption2Bold)
                    Text(statusTitle)
                        .font(AdminType.caption2)
                } else {
                    Text(statusTitle)
                        .font(AdminType.caption2)
                        .lineLimit(2)
                }
            }
            .foregroundStyle(statusColor)
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
    }

    private var actionDock: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                quantityControl
                Spacer(minLength: 8)
                secondaryActions
            }
            VStack(alignment: .leading, spacing: 8) {
                quantityControl
                secondaryActions
            }
        }
    }

    private var quantityControl: some View {
        HStack(spacing: 0) {
            compactActionButton(
                systemImage: "minus",
                accessibilityLabel: Language.get("InventoryCell_Decrease", alter: "تقليل الكمية بمقدار واحد"),
                enabled: canAdjust && (quantity ?? 0) > 0
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onAdjustQuantity(-1)
            }

            Text(quantity.map { $0.englishDigits } ?? "—")
                .font(AdminType.calloutBold)
                .foregroundStyle(AdminSurface.primaryText)
                .frame(minWidth: 42, minHeight: 44)

            compactActionButton(
                systemImage: "plus",
                accessibilityLabel: Language.get("InventoryCell_Increase", alter: "زيادة الكمية بمقدار واحد"),
                enabled: canAdjust
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onAdjustQuantity(1)
            }
        }
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        }
    }

    private var secondaryActions: some View {
        HStack(spacing: 8) {
            Button(action: onEdit) {
                HStack(spacing: 5) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                    Text(Language.get("Edit", alter: "تعديل"))
                        .font(AdminType.caption2Bold)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AdminSurface.primary)
            .disabled(!canManageStock)
            .opacity(canManageStock ? 1 : 0.45)
            .accessibilityLabel(Language.get("Edit", alter: "تعديل"))

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: 44, height: 44)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.get("MoreActions", alter: "إجراءات إضافية"))
        }
    }

    private func compactActionButton(
        systemImage: String,
        accessibilityLabel: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? AdminSurface.primaryText : AdminCommandInk.tertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

@available(iOS 16.0, *)
private struct FlagshipInventoryCard: View {
    let item: PetAccessory
    let sellingPrice: NSNumber?
    let quantity: Int?
    let reservedQuantity: Int
    let branchName: String
    let stockState: PPInventoryCellStockState
    let canManageStock: Bool
    let canDeleteStock: Bool
    let canViewCosts: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onAdjustQuantity: (Int) -> Void
    let onToggleStock: () -> Void
    let onDelete: () -> Void
    var onRecordDamage: (() -> Void)?
    var onQuarantineStudio: (() -> Void)?
    var onManageLots: (() -> Void)?
    var onOpenActionMenu: (() -> Void)?

    @State private var showQuantityPad = false
    @State private var quantityAtPresentation = 0
    @State private var branchAtPresentation: String?
    @State private var revisionAtPresentation: Int?
    @State private var isHovered = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        let primary = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let english = (item.nameEn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = Language.isRTL() ? primary : english
        let fallback = Language.isRTL() ? english : primary
        return !preferred.isEmpty ? preferred : (!fallback.isEmpty ? fallback : Language.get("InventoryCell_Unnamed", alter: "صنف بدون اسم"))
    }

    private var theme: CategorySpecimenAuraTheme { CategorySpecimenAuraTheme.resolve(for: item) }
    private var imageURL: URL? { PetAccessory.firstImageURL(for: item) }
    private var formattedPrice: String {
        sellingPrice.map { PetAccessory.formatCurrency($0) }
            ?? Language.get("Inventory_Price_Unavailable", alter: "السعر غير متاح")
    }
    private var tracksLots: Bool { item.inventoryTrackingPolicy?.lowercased() == "lot" }
    private var tracksUnits: Bool {
        item.inventoryMode?.uppercased() == PPLivePetInventoryMode.individual.rawValue
            || item.inventoryTrackingPolicy?.lowercased() == "unit"
    }
    private var isInactive: Bool {
        !item.active || item.isArchived || item.isDeleted || item.isDisabled || item.isBlocked
    }
    private var canAdjust: Bool {
        canManageStock && stockState == .ready && quantity != nil
            && !item.isLivePet && !tracksLots && !tracksUnits
            && !isInactive
    }
    private var statusColor: Color {
        guard stockState == .ready, let quantity else { return AdminSurface.secondaryText }
        if quantity == 0 { return Color(uiColor: .ppError) }
        if quantity <= 3 { return Color(uiColor: .ppWarning) }
        return Color(uiColor: .ppSuccess)
    }
    private var statusTitle: String {
        if stockState == .selectBranch {
            return Language.get("InventoryCell_CatalogQuantity", alter: "رصيد الصنف")
        }
        guard stockState == .ready, let quantity else {
            return Language.get("InventoryCell_Available", alter: "المتاح")
        }
        if quantity == 0 { return Language.get("OutOfStock", alter: "نفذ من المخزون") }
        if quantity <= 3 { return Language.get("InventoryCell_Low", alter: "رصيد منخفض") }
        return Language.get("InventoryCell_Available", alter: "المتاح")
    }
    private var statusSymbol: String {
        guard stockState == .ready, let quantity else { return "clock" }
        return quantity == 0 ? "minus.circle" : (quantity <= 3 ? "exclamationmark.circle" : "checkmark.circle")
    }
    private var operationalAccent: Color {
        switch stockState {
        case .ready:
            return statusColor
        case .pending:
            return AdminSurface.amber
        case .selectBranch, .loading, .unconfirmed, .missing:
            return AdminSurface.primary
        }
    }
    private var hasDiscount: Bool {
        guard let sellingPrice, sellingPrice.doubleValue == item.finalPrice.doubleValue else { return false }
        return item.price.doubleValue > sellingPrice.doubleValue
    }
    private var trackingTitle: String {
        if item.isLivePet {
            if tracksUnits { return Language.get("LivePet_Tracking_Individual", alter: "تتبع كل حيوان") }
            if item.inventoryMode?.uppercased() == PPLivePetInventoryMode.quantity.rawValue {
                return Language.get("LivePet_Tracking_Group", alter: "مجموعة بالكمية")
            }
            return Language.get("LivePets", alter: "حيوانات أليفة")
        }
        return Language.get("InventoryCell_LotTracking", alter: "تتبع الشحنات والصلاحية")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleIdentity
            } else {
                ViewThatFits(in: .horizontal) {
                    wideIdentity.frame(minWidth: 620)
                    compactIdentity
                }
            }
            operationalPanel
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isHovered ? AdminSurface.primary.opacity(0.40) : AdminSurface.borderSubtle.opacity(0.65), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 3)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { isHovered = hovering }
        }
        .contextMenu { contextActions }
        .tactileQuantityPad(
            isPresented: $showQuantityPad,
            title: Language.get("EditQuantity", alter: "تعديل الكمية"),
            currentQuantity: quantityAtPresentation,
            referenceQuantity: quantityAtPresentation,
            specimen: PPTactileSpecimenInfo(
                title: title,
                imageURL: imageURL,
                sku: item.sku,
                barcode: item.barcode,
                unitCost: canViewCosts ? item.costPrice?.doubleValue : nil
            )
        ) { newQuantity in
            // An absolute edit must not be rebased silently after a live update.
            let projection = PPBranchInventoryService.shared
            let currentRecord = projection.inventory(for: item.accessoryID)
            guard canAdjust, projection.isServerConfirmed,
                  let branchAtPresentation,
                  BranchContextStore.shared.activeBranch?.branchID == branchAtPresentation,
                  projection.currentBranchId == branchAtPresentation,
                  currentRecord?.projectionRevision == revisionAtPresentation,
                  currentRecord?.availableQuantity == quantityAtPresentation else {
                PPHUD.showError(
                    Language.get("InventoryCell_QuantityChanged", alter: "تغير رصيد الصنف"),
                    subtitle: Language.get("InventoryCell_QuantityChangedDetail", alter: "راجع الرصيد الحالي ثم أعد التعديل.")
                )
                return
            }
            let delta = newQuantity - quantityAtPresentation
            if delta != 0 { onAdjustQuantity(delta) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inventory.product.\(item.accessoryID)")
    }

    // The portrait and selling price form one identity. The operational panel
    // is a separate touch region, so quantity buttons never open the dossier.
    private var compactIdentity: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    categoryLine
                    productTitle
                    priceReadout
                    metadata
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                portrait(size: dynamicTypeSize >= .xxLarge ? 72 : 88)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CatalogPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(identityAccessibilityLabel)
        .accessibilityHint(Language.get("InventoryCell_OpenHint", alter: "يفتح التفاصيل وإجراءات الصنف"))
        .accessibilityIdentifier("inventory.product.details.\(item.accessoryID)")
    }

    private var wideIdentity: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    categoryLine
                    productTitle
                    metadata
                    technicalIdentity
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                priceReadout
                    .frame(width: 180, alignment: .leading)
                portrait(size: 112)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CatalogPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(identityAccessibilityLabel)
        .accessibilityHint(Language.get("InventoryCell_OpenHint", alter: "يفتح التفاصيل وإجراءات الصنف"))
        .accessibilityIdentifier("inventory.product.details.\(item.accessoryID)")
    }

    private var accessibleIdentity: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                categoryLine
                productTitle
                portrait(size: 104)
                priceReadout
                metadata
                technicalIdentity
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CatalogPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(identityAccessibilityLabel)
        .accessibilityHint(Language.get("InventoryCell_OpenHint", alter: "يفتح التفاصيل وإجراءات الصنف"))
        .accessibilityIdentifier("inventory.product.details.\(item.accessoryID)")
    }

    private var identityAccessibilityLabel: String {
        var parts = [title, theme.categoryName, branchName, formattedPrice]
        if !item.isLivePet, item.condition.rawValue != -1 { parts.append(PetAccessory.conditionText(for: item)) }
        parts.append(contentsOf: [item.size, item.weightText, item.sku, item.barcode].compactMap { $0 })
        if hasDiscount {
            parts.append("\(Language.get("InventoryCell_PreviousPrice", alter: "السعر السابق")) \(PetAccessory.formatCurrency(item.price))")
        }
        if item.imageURLsArray.count > 1 {
            parts.append(String(format: Language.get("InventoryCell_PhotoCount", alter: "%@ صور"), item.imageURLsArray.count.englishDigits))
        }
        if let wholesale = item.wholesalePrice, wholesale.doubleValue > 0 {
            parts.append("\(Language.get("Wholesale_Short", alter: "جملة:")) \(PetAccessory.formatCurrency(wholesale))")
        }
        if item.isLivePet, canViewCosts, let cost = item.costPrice, cost.doubleValue > 0 {
            parts.append("\(Language.get("Cost_Short", alter: "تكلفة:")) \(PetAccessory.formatCurrency(cost))")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var categoryLine: some View {
        Label(theme.categoryName, systemImage: item.isLivePet ? "pawprint" : (item.isFood ? "leaf" : "tag"))
            .font(AdminType.captionBold)
            .foregroundStyle(AdminSurface.secondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var productTitle: some View {
        Text(verbatim: title)
            .font(AdminType.title3Bold)
            .foregroundStyle(AdminSurface.primaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func portrait(size: CGFloat) -> some View {
        AdminRemoteImage(url: imageURL, contentMode: .fill, targetSize: CGSize(width: size, height: size)) {
            ZStack {
                AdminSurface.control
                Image(systemName: theme.glyphName)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            // The shared loader uses this for both loading and failure. A quiet
            // category placeholder cannot become a permanent progress spinner.
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if item.imageURLsArray.count > 1 {
                Label(item.imageURLsArray.count.englishDigits, systemImage: "photo.on.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(6)
            }
        }
        .accessibilityHidden(true)
    }

    private var metadata: some View {
        PPInventoryMetadataLayout(spacing: 10, lineSpacing: 6, direction: layoutDirection) {
            if !branchName.isEmpty {
                Label(branchName, systemImage: "building.2")
            }
            if !item.isLivePet, item.condition.rawValue != -1 {
                Text(PetAccessory.conditionText(for: item))
            }
            if let size = item.size?.trimmingCharacters(in: .whitespacesAndNewlines), !size.isEmpty {
                Label(size, systemImage: "ruler")
            }
            if let weight = item.weightText?.trimmingCharacters(in: .whitespacesAndNewlines), !weight.isEmpty {
                Label(weight, systemImage: "scalemass")
            }
        }
        .font(AdminType.caption)
        .foregroundStyle(AdminSurface.secondaryText)
        .multilineTextAlignment(.leading)
    }

    private var technicalIdentity: some View {
        PPInventoryMetadataLayout(spacing: 8, lineSpacing: 6, direction: layoutDirection) {
            if let sku = item.sku?.trimmingCharacters(in: .whitespacesAndNewlines), !sku.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "number")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AdminCommandInk.tertiary)
                    Text(sku)
                        .font(AdminType.caption.monospaced())
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(AdminSurface.control.opacity(0.7), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .environment(\.layoutDirection, .leftToRight)
            }
            if let barcode = item.barcode?.trimmingCharacters(in: .whitespacesAndNewlines), !barcode.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "barcode")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AdminCommandInk.tertiary)
                    Text(barcode)
                        .font(AdminType.caption.monospaced())
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(AdminSurface.control.opacity(0.7), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .font(AdminType.caption)
    }

    private var priceReadout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: formattedPrice.normalizedEnglishDigits)
                .font(sellingPrice != nil ? AdminType.title2 : AdminType.footnoteBold)
                .foregroundStyle(sellingPrice != nil ? AdminSurface.primary : AdminSurface.secondaryText)
                .monospacedDigit()
                .environment(\.layoutDirection, sellingPrice != nil ? .leftToRight : layoutDirection)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasDiscount {
                Text(verbatim: PetAccessory.formatCurrency(item.price).normalizedEnglishDigits)
                    .font(AdminType.caption)
                    .strikethrough()
                    .foregroundStyle(AdminSurface.secondaryText)
                    .environment(\.layoutDirection, .leftToRight)
            }
            if let wholesale = item.wholesalePrice, wholesale.doubleValue > 0 {
                supportingPrice(Language.get("Wholesale_Short", alter: "جملة:"), value: wholesale)
                if let price = sellingPrice?.doubleValue, price.isFinite, price > wholesale.doubleValue {
                    let margin = Int(round((price - wholesale.doubleValue) / price * 100))
                    Text(String(format: Language.get("InventoryCell_WholesaleMargin", alter: "فرق الجملة %@%%"), margin.englishDigits))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if item.isLivePet, canViewCosts, let cost = item.costPrice, cost.doubleValue > 0 {
                supportingPrice(Language.get("Cost_Short", alter: "تكلفة:"), value: cost)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func supportingPrice(_ label: String, value: NSNumber) -> some View {
        Text(verbatim: "\(label) \u{2066}\(PetAccessory.formatCurrency(value).normalizedEnglishDigits)\u{2069}")
            .font(AdminType.caption)
            .foregroundStyle(AdminSurface.secondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var operationalPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                availabilityReadout
                operationControls
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
                        availabilityReadout.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        operationControls.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        availabilityReadout
                        operationControls
                    }
                }
            }

            if let caption = stockState.caption {
                Label(caption, systemImage: stockState == .unconfirmed ? "wifi.exclamationmark" : "info.circle")
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !canManageStock || isInactive {
                Label(
                    !canManageStock ? Language.get("InventoryCell_ReadOnly", alter: "عرض فقط") : Language.get("InventoryCell_Inactive", alter: "الصنف غير نشط"),
                    systemImage: !canManageStock ? "lock" : "pause.circle"
                )
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            if item.isLivePet {
                PPInventoryMetadataLayout(spacing: 10, lineSpacing: 6, direction: layoutDirection) {
                    Label(trackingTitle, systemImage: tracksUnits ? "tag" : "square.stack")
                    if reservedQuantity > 0 {
                        Label(String(format: Language.get("LivePet_Reserved_Format", alter: "محجوز (%@)"), reservedQuantity.englishDigits), systemImage: "lock")
                    }
                    if canManageStock, let action = onQuarantineStudio {
                        Button(action: action) {
                            Label(Language.get("Quarantine_Studio", alter: "الحجر البيطري"), systemImage: "cross.case")
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(CatalogPressStyle())
                        .foregroundStyle(AdminSurface.primary)
                    }
                }
                .font(AdminType.captionBold)
                .foregroundStyle(AdminSurface.secondaryText)
            } else if tracksLots {
                Label(trackingTitle, systemImage: "shippingbox")
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AdminSurface.backgroundSecondary)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [operationalAccent.opacity(0.13), operationalAccent.opacity(0.035)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(operationalAccent.opacity(0.24), lineWidth: 0.75)
        }
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(operationalAccent.opacity(0.82))
                .frame(width: 3)
                .padding(.vertical, 10)
                .accessibilityHidden(true)
        }
    }

    private var availabilityReadout: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 6))
        return layout {
            Text(verbatim: quantity.map { $0.englishDigits } ?? "—")
                .font(AdminType.title3Bold)
                .monospacedDigit()
                .foregroundStyle(AdminSurface.primaryText)
                .environment(\.layoutDirection, .leftToRight)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .modifier(PPInventoryCellCountTransition(value: quantity, isConfirmed: stockState == .ready))
            Label {
                Text(statusTitle).foregroundStyle(AdminSurface.primaryText)
            } icon: {
                Image(systemName: statusSymbol).foregroundStyle(statusColor)
            }
            .font(AdminType.captionBold)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusTitle)
        .accessibilityValue(quantity.map { $0.englishDigits } ?? Language.get("InventoryCell_Missing", alter: "رصيد الفرع غير متاح"))
    }

    private var operationControls: some View {
        PPInventoryMetadataLayout(spacing: 8, lineSpacing: 8, direction: layoutDirection) {
            if item.isLivePet || tracksUnits {
                detailAction
            } else if tracksLots {
                if canManageStock, let action = onManageLots {
                    lotAction(action: action, compact: false)
                }
            } else if canManageStock {
                quantityControl
            }

            if !tracksLots, !item.isLivePet, canManageStock,
               (item.isFood || item.isPetMedicine), let action = onManageLots {
                lotAction(action: action, compact: true)
            }
            if let action = onOpenActionMenu {
                Button(action: action) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CatalogPressStyle())
                .accessibilityLabel(Language.get("Specimen_Actions", alter: "خيارات الصنف"))
                .accessibilityIdentifier("inventory.product.actions.\(item.accessoryID)")
            }
        }
    }

    private var quantityControl: some View {
        HStack(spacing: 0) {
            adjustmentButton(symbol: "minus", delta: -1, key: "InventoryCell_Decrease", fallback: "إنقاص الكمية بمقدار واحد")
                .disabled(!canAdjust || (quantity ?? 0) <= 0)
            Button(action: presentQuantityPad) {
                Group {
                    if stockState.isBusy {
                        ProgressView().tint(AdminSurface.primary)
                    } else {
                        Image(systemName: "pencil")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(canAdjust ? AdminSurface.primary : AdminSurface.secondaryText)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(CatalogPressStyle())
            .disabled(!canAdjust)
            .accessibilityLabel(Language.get("EditQuantity", alter: "تعديل الكمية"))
            .accessibilityValue(quantity.map { $0.englishDigits } ?? "")
            .accessibilityHint(Language.get("InventoryCell_QuantityHint", alter: "يفتح لوحة إدخال الكمية"))
            .accessibilityIdentifier("inventory.product.quantity.\(item.accessoryID)")
            adjustmentButton(symbol: "plus", delta: 1, key: "InventoryCell_Increase", fallback: "زيادة الكمية بمقدار واحد")
                .disabled(!canAdjust)
        }
        // Arithmetic order is stable; the containing panel follows the app language.
        .environment(\.layoutDirection, .leftToRight)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(AdminSurface.borderSubtle, lineWidth: 0.75))
    }

    private func adjustmentButton(symbol: String, delta: Int, key: String, fallback: String) -> some View {
        Button {
            guard canAdjust, delta > 0 || (quantity ?? 0) > 0 else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onAdjustQuantity(delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(canAdjust && (delta > 0 || (quantity ?? 0) > 0) ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.4))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(CatalogPressStyle())
        .accessibilityLabel(Language.get(key, alter: fallback))
        .accessibilityIdentifier("inventory.product.\(symbol).\(item.accessoryID)")
    }

    private var detailAction: some View {
        Button(action: onTap) {
            Label(
                item.isLivePet && tracksUnits
                    ? Language.get("InventoryCell_AnimalRecords", alter: "سجل الحيوانات")
                    : Language.get("ViewDetails", alter: "عرض التفاصيل"),
                systemImage: item.isLivePet ? "pawprint" : "tag"
            )
            .font(AdminType.footnoteBold)
            .foregroundStyle(AdminSurface.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .fixedSize(horizontal: false, vertical: true)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(CatalogPressStyle())
    }

    private func lotAction(action: @escaping () -> Void, compact: Bool) -> some View {
        Button(action: action) {
            Group {
                if compact {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                } else {
                    Label(Language.get("InventoryCell_Lots", alter: "الشحنات والصلاحية"), systemImage: "shippingbox")
                        .font(AdminType.footnoteBold)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(AdminSurface.primary)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(CatalogPressStyle())
        .accessibilityLabel(Language.get("Manage_Lots", alter: "إدارة الشحنات والصلاحية"))
    }

    @ViewBuilder private var contextActions: some View {
        Button(action: onTap) {
            Label(Language.get("ViewDetails", alter: "عرض التفاصيل"), systemImage: "eye")
        }
        if canManageStock {
            Button(action: onEdit) {
                Label(Language.get("Edit", alter: "تعديل"), systemImage: "pencil")
            }
            if !item.isLivePet && !tracksLots && !tracksUnits {
                Button(action: presentQuantityPad) {
                    Label(Language.get("EditQuantity", alter: "تعديل الكمية"), systemImage: "number")
                }
                .disabled(!canAdjust)
            }
            if !item.isLivePet, (tracksLots || item.isFood || item.isPetMedicine), let action = onManageLots {
                Button(action: action) {
                    Label(Language.get("Manage_Lots", alter: "إدارة الشحنات والصلاحية"), systemImage: "shippingbox")
                }
            }
            if item.isLivePet, let action = onQuarantineStudio {
                Button(action: action) {
                    Label(Language.get("Quarantine_Studio", alter: "الحجر البيطري"), systemImage: "cross.case")
                }
            }
            if item.isLivePet {
                Button(action: onToggleStock) {
                    Label(
                        item.noStock ? Language.get("MarkInStock", alter: "تفعيل التوفر") : Language.get("MarkOutOfStock", alter: "إيقاف مؤقت"),
                        systemImage: item.noStock ? "checkmark.seal" : "eye.slash"
                    )
                }
            }
            if let action = onRecordDamage {
                Button(action: action) {
                    Label(
                        item.isLivePet ? Language.get("LivePet_Mortality_Record", alter: "تسجيل فقدان أو نفوق") : Language.get("Record_Damage", alter: "تسجيل تالف"),
                        systemImage: item.isLivePet ? "heart.slash" : "exclamationmark.triangle"
                    )
                }
            }
        }
        if canDeleteStock {
            Button(role: .destructive, action: onDelete) {
                Label(Language.get("Delete", alter: "حذف"), systemImage: "trash")
            }
        }
    }

    private func presentQuantityPad() {
        let projection = PPBranchInventoryService.shared
        guard canAdjust, let quantity,
              let branchID = projection.currentBranchId,
              let record = projection.inventory(for: item.accessoryID),
              record.availableQuantity == quantity else { return }
        quantityAtPresentation = quantity
        branchAtPresentation = branchID
        revisionAtPresentation = record.projectionRevision
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showQuantityPad = true
    }
}

@available(iOS 16.0, *)
private struct PPInventoryCellCountTransition: ViewModifier {
    let value: Int?
    let isConfirmed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 17.0, *), !reduceMotion, isConfirmed {
            content.contentTransition(.numericText())
                .animation(.easeOut(duration: 0.18), value: value)
        } else {
            content
        }
    }
}

/// Content-sized metadata wraps as a unit, including at accessibility sizes.
/// Placement is logical-leading in both languages; identifiers keep their own
/// semantic direction inside each subview.
@available(iOS 16.0, *)
private struct PPInventoryMetadataLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    let direction: LayoutDirection

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var result: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = subview.sizeThatFits(ProposedViewSize(width: min(ideal.width, width), height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            result.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idealWidth = subviews.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(.unspecified).width }
            + CGFloat(max(0, subviews.count - 1)) * spacing
        let finiteWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let width = max(0, finiteWidth ?? idealWidth)
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, frame) in frames(width: bounds.width, subviews: subviews).enumerated() {
            let x = direction == .rightToLeft ? bounds.maxX - frame.maxX : bounds.minX + frame.minX
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY + frame.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}

// MARK: - Barcode & Retail Label Studio (NextGen Category-Defining Engine)

public enum BarcodeStudioFormat: String, CaseIterable, Identifiable {
    case code128 = "code128"
    case qr = "qr"
    case shelfTag = "shelfTag"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .code128:
            return Language.get("BarcodeStudio_Format_Barcode", alter: "كود 128")
        case .qr:
            return Language.get("BarcodeStudio_Format_QR", alter: "رمز QR")
        case .shelfTag:
            return Language.get("BarcodeStudio_Format_ShelfTag", alter: "ملصق الرف")
        }
    }

    public var icon: String {
        switch self {
        case .code128: return "barcode"
        case .qr: return "qrcode"
        case .shelfTag: return "tag.fill"
        }
    }
}

private struct BarcodeActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.permittedArrowDirections = []
            if let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

public struct BarcodeRenderer {
    private static let ciContext = CIContext()

    public static func generateCode128(from string: String) -> UIImage? {
        guard !string.isEmpty, let data = string.data(using: .ascii) else { return nil }
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(NSNumber(value: 8.0), forKey: "inputQuietSpace")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    public static func generateQRCode(from string: String) -> UIImage? {
        guard !string.isEmpty, let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Renders a studio-grade retail printable shelf tag (50x30mm ratio, 300 DPI)
    public static func renderRetailShelfTag(item: PetAccessory, code: String, isQR: Bool = false) -> UIImage {
        let size = CGSize(width: 600, height: 380)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // Clean White Background
            cgCtx.setFillColor(UIColor.white.cgColor)
            cgCtx.fill(CGRect(origin: .zero, size: size))

            // Outer Rounded Border
            let borderRect = CGRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24)
            let path = UIBezierPath(roundedRect: borderRect, cornerRadius: 18)
            cgCtx.setStrokeColor(UIColor(white: 0.88, alpha: 1.0).cgColor)
            cgCtx.setLineWidth(2.5)
            cgCtx.addPath(path.cgPath)
            cgCtx.strokePath()

            // Header Brand Ribbon
            let brandFont = UIFont.systemFont(ofSize: 18, weight: .black)
            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: brandFont,
                .foregroundColor: UIColor(red: 0.08, green: 0.48, blue: 0.95, alpha: 1.0)
            ]
            let brandText = "PURE PETS • بيور بيتس"
            (brandText as NSString).draw(at: CGPoint(x: 24, y: 22), withAttributes: brandAttrs)

            // Category tag
            let catFont = UIFont.systemFont(ofSize: 14, weight: .bold)
            let catAttrs: [NSAttributedString.Key: Any] = [
                .font: catFont,
                .foregroundColor: UIColor(white: 0.45, alpha: 1.0)
            ]
            let categoryText = (item.category?.isEmpty == false ? item.category : "PurePets Retail") ?? "Retail"
            let catSize = (categoryText as NSString).size(withAttributes: catAttrs)
            (categoryText as NSString).draw(at: CGPoint(x: size.width - catSize.width - 24, y: 24), withAttributes: catAttrs)

            // Product Name
            let nameFont = UIFont(name: "Beiruti-Bold", size: 28) ?? UIFont.systemFont(ofSize: 26, weight: .bold)
            let nameParagraph = NSMutableParagraphStyle()
            nameParagraph.alignment = Language.isRTL() ? .right : .left
            nameParagraph.lineBreakMode = .byTruncatingTail
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: nameFont,
                .foregroundColor: UIColor(white: 0.1, alpha: 1.0),
                .paragraphStyle: nameParagraph
            ]
            let nameRect = CGRect(x: 24, y: 52, width: size.width - 48, height: 68)
            (item.name as NSString).draw(in: nameRect, withAttributes: nameAttrs)

            // Barcode Graphic
            if isQR {
                if let qrImg = generateQRCode(from: code) {
                    let qrRect = CGRect(x: (size.width - 130) / 2, y: 124, width: 130, height: 130)
                    qrImg.draw(in: qrRect)
                }
            } else {
                if let bcImg = generateCode128(from: code) {
                    let bcRect = CGRect(x: 36, y: 124, width: size.width - 72, height: 120)
                    bcImg.draw(in: bcRect)
                }
            }

            // Human readable code
            let codeFont = UIFont.monospacedSystemFont(ofSize: 20, weight: .bold)
            let codeParagraph = NSMutableParagraphStyle()
            codeParagraph.alignment = .center
            let codeAttrs: [NSAttributedString.Key: Any] = [
                .font: codeFont,
                .foregroundColor: UIColor(white: 0.15, alpha: 1.0),
                .paragraphStyle: codeParagraph
            ]
            let codeRect = CGRect(x: 24, y: 254, width: size.width - 48, height: 26)
            (code as NSString).draw(in: codeRect, withAttributes: codeAttrs)

            // Price Divider line
            cgCtx.setStrokeColor(UIColor(white: 0.88, alpha: 1.0).cgColor)
            cgCtx.setLineWidth(1.5)
            cgCtx.move(to: CGPoint(x: 24, y: 288))
            cgCtx.addLine(to: CGPoint(x: size.width - 24, y: 288))
            cgCtx.strokePath()

            // Bottom Left: SKU / ID
            let skuFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
            let skuAttrs: [NSAttributedString.Key: Any] = [
                .font: skuFont,
                .foregroundColor: UIColor(white: 0.4, alpha: 1.0)
            ]
            let skuStr = "SKU: \(item.sku ?? item.accessoryID)"
            (skuStr as NSString).draw(at: CGPoint(x: 24, y: 310), withAttributes: skuAttrs)

            // Bottom Right: Price Display
            let priceFont = UIFont(name: "Beiruti-Bold", size: 36) ?? UIFont.systemFont(ofSize: 34, weight: .black)
            let priceAttrs: [NSAttributedString.Key: Any] = [
                .font: priceFont,
                .foregroundColor: UIColor(red: 0.05, green: 0.65, blue: 0.45, alpha: 1.0)
            ]
            let formattedPrice = String(format: "%.2f %@", item.finalPrice.doubleValue, Language.get("QAR", alter: "ر.ق"))
            let priceSize = (formattedPrice as NSString).size(withAttributes: priceAttrs)
            (formattedPrice as NSString).draw(at: CGPoint(x: size.width - priceSize.width - 24, y: 300), withAttributes: priceAttrs)
        }
    }
}

@available(iOS 16.0, *)
public struct PPBarcodeStudioSheet: View {
    let item: PetAccessory
    var onBarcodeUpdated: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentBarcode: String
    @State private var originalBarcode: String
    @State private var selectedFormat: BarcodeStudioFormat = .code128
    @State private var labelCopies: Int = 1
    @State private var isGenerating: Bool = false
    @State private var isSaving: Bool = false
    @State private var showSaveSuccessBanner: Bool = false
    @State private var isCopied: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var shareSheetImage: UIImage? = nil
    @State private var isShowingScanner: Bool = false

    public init(item: PetAccessory, onBarcodeUpdated: ((String) -> Void)? = nil) {
        self.item = item
        self.onBarcodeUpdated = onBarcodeUpdated
        let initialCode = item.barcode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? item.barcode!
            : (item.sku?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? item.sku! : item.accessoryID)
        _currentBarcode = State(initialValue: initialCode)
        _originalBarcode = State(initialValue: initialCode)
        _labelCopies = State(initialValue: max(1, min(item.quantity, 10)))
    }

    private var hasChanges: Bool {
        currentBarcode.trimmingCharacters(in: .whitespacesAndNewlines) != originalBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidCode: Bool {
        let trimmed = currentBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.canBeConverted(to: .ascii)
    }

    public var body: some View {
        ZStack {
            AdminSurface.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        headerNavigationRail
                        formatSwitcherSegment
                        specimenCanvasCard
                        generatorAndScannerRow
                        inPlaceEditorCard
                        labelPrintStationCard
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                }

                bottomCommandDock
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .background(
                        AdminSurface.background
                            .opacity(0.96)
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.05), radius: 12, x: 0, y: -4)
                    )
            }
            .frame(maxWidth: 580)
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .presentationDetents([.fraction(0.88), .large])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showShareSheet) {
            if let img = shareSheetImage {
                BarcodeActivityShareSheet(items: [img])
            }
        }
    }

    // MARK: - Subviews

    private var headerNavigationRail: some View {
        HStack(alignment: .center) {
            AdminSquircleCloseButton {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("BarcodeStudio_Title", alter: "استوديو الباركود والملصقات"))
                    .font(Font.custom("Beiruti-Bold", size: 18))
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                Text(Language.get("BarcodeStudio_Subtitle", alter: "معاينة وتوليد وتعديل وطباعة باركود الصنف وملصقات الرفوف"))
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                shareBarcodeLabel()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 40, height: 40)
                    .background(AdminSurface.primarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel(Language.get("BarcodeStudio_ShareAction", alter: "مشاركة الملصق"))
        }
    }

    private var formatSwitcherSegment: some View {
        HStack(spacing: 8) {
            ForEach(BarcodeStudioFormat.allCases) { format in
                let isSelected = selectedFormat == format
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selectedFormat = format
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: format.icon)
                            .font(.system(size: 12, weight: .bold))
                        Text(format.localizedTitle)
                            .font(Font.custom("Beiruti-Bold", size: 13))
                    }
                    .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        isSelected
                            ? AnyView(AdminSurface.primary)
                            : AnyView(AdminSurface.control)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var specimenCanvasCard: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 14, x: 0, y: 4)

                VStack(spacing: 10) {
                    if selectedFormat == .shelfTag {
                        shelfTagPreviewView
                    } else if selectedFormat == .qr {
                        qrPreviewView
                    } else {
                        linearBarcodePreviewView
                    }
                }
                .padding(16)
            }
            .frame(height: 240)
            .scaleEffect(isGenerating ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isGenerating)
        }
        .padding(.horizontal, 4)
    }

    private var shelfTagPreviewView: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 10, weight: .black))
                    Text("PURE PETS")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                }
                .foregroundColor(Color(red: 0.08, green: 0.48, blue: 0.95))

                Spacer()

                Text((item.category?.isEmpty == false ? item.category : "PurePets Retail") ?? "Retail")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.gray)
            }

            Text(item.name)
                .font(Font.custom("Beiruti-Bold", size: 16))
                .foregroundColor(Color.black)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: Language.isRTL() ? .trailing : .leading)

            if let bcImage = BarcodeRenderer.generateCode128(from: currentBarcode) {
                Image(uiImage: bcImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(height: 52)
            } else {
                emptyBarcodePlaceholder
            }

            Text(currentBarcode)
                .font(Font.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Color.black)

            Divider()

            HStack {
                Text("SKU: \(item.sku ?? item.accessoryID)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.gray)
                    .lineLimit(1)

                Spacer()

                Text(String(format: "%.2f %@", item.finalPrice.doubleValue, Language.get("QAR", alter: "ر.ق")))
                    .font(Font.custom("Beiruti-Bold", size: 18))
                    .foregroundColor(Color(red: 0.05, green: 0.65, blue: 0.45))
            }
        }
    }

    private var qrPreviewView: some View {
        VStack(spacing: 10) {
            Text(item.name)
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundColor(Color.black)
                .lineLimit(1)

            if let qrImage = BarcodeRenderer.generateQRCode(from: currentBarcode) {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 120, height: 120)
            } else {
                emptyBarcodePlaceholder
            }

            Text(currentBarcode)
                .font(Font.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(Color.black)
        }
    }

    private var linearBarcodePreviewView: some View {
        VStack(spacing: 12) {
            Text(item.name)
                .font(Font.custom("Beiruti-Bold", size: 16))
                .foregroundColor(Color.black)
                .lineLimit(1)

            if let bcImage = BarcodeRenderer.generateCode128(from: currentBarcode) {
                Image(uiImage: bcImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(height: 75)
                    .padding(.horizontal, 8)
            } else {
                emptyBarcodePlaceholder
            }

            HStack {
                Text(currentBarcode)
                    .font(Font.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.black)

                Spacer()

                Text(String(format: "%.2f %@", item.finalPrice.doubleValue, Language.get("QAR", alter: "ر.ق")))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundColor(Color(red: 0.05, green: 0.65, blue: 0.45))
            }
            .padding(.horizontal, 4)
        }
    }

    private var emptyBarcodePlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 36))
                .foregroundColor(Color.gray.opacity(0.5))
            Text(Language.get("BarcodeStudio_EmptyWarning", alter: "أدخل رمز الباركود أو اضغط توليد"))
                .font(Font.custom("Beiruti-Regular", size: 12))
                .foregroundColor(Color.gray)
        }
        .frame(height: 80)
    }

    private var generatorAndScannerRow: some View {
        HStack(spacing: 10) {
            Button {
                generateAutoBarcode()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                    Text(Language.get("BarcodeStudio_AutoGenerate", alter: "توليد تلقائي"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                }
                .foregroundColor(AdminSurface.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(AdminSurface.primarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.primary.opacity(0.24), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            AdminBarcodeScanButton { scanned in
                currentBarcode = scanned
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            .frame(width: 44, height: 44)
        }
    }

    private var inPlaceEditorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "pencil.line")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)

                Text(Language.get("BarcodeStudio_EditBarcode", alter: "رمز الباركود"))
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                if isValidCode {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text(Language.get("BarcodeStudio_ValidCode", alter: "باركود صالح"))
                            .font(Font.custom("Beiruti-Bold", size: 11))
                    }
                    .foregroundColor(Color(uiColor: .ppSuccess))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                }

                if hasChanges {
                    Button {
                        currentBarcode = originalBarcode
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text(Language.get("BarcodeStudio_ResetOriginal", alter: "استعادة الأصلي"))
                                .font(Font.custom("Beiruti-Regular", size: 11))
                        }
                        .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Barcode", text: $currentBarcode)
                    .font(Font.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(AdminSurface.primaryText)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)

                if !currentBarcode.isEmpty {
                    Button {
                        currentBarcode = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                    }
                }
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(hasChanges ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1)
            )

            if hasChanges {
                Button {
                    saveBarcodeToCatalog()
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(Language.get("BarcodeStudio_SaveToCatalog", alter: "حفظ الكود بالصنف"))
                                .font(Font.custom("Beiruti-Bold", size: 14))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSaving || !isValidCode)
            }

            if showSaveSuccessBanner {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(uiColor: .ppSuccess))
                    Text(Language.get("BarcodeStudio_SaveSuccess", alter: "تم تحديث باركود الصنف بنجاح"))
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
                .padding(.vertical, 4)
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AdminSurface.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var labelPrintStationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "printer.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)

                Text(Language.get("BarcodeStudio_PrintCopies", alter: "عدد الملصقات للطباعة"))
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        if labelCopies > 1 {
                            labelCopies -= 1
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(labelCopies > 1 ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.3))
                    }
                    .disabled(labelCopies <= 1)

                    Text("\(labelCopies)")
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(minWidth: 24)

                    Button {
                        labelCopies += 1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AdminSurface.primary)
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach([1, 5, 10], id: \.self) { count in
                    Button {
                        labelCopies = count
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text("\(count)")
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .foregroundColor(labelCopies == count ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(
                                labelCopies == count
                                    ? AnyView(AdminSurface.primary)
                                    : AnyView(AdminSurface.control)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if item.quantity > 0 {
                    Button {
                        labelCopies = item.quantity
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(String(format: Language.get("BarcodeStudio_PrintAllStock", alter: "المخزون: %d"), item.quantity))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .foregroundColor(labelCopies == item.quantity ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                labelCopies == item.quantity
                                    ? AnyView(AdminSurface.primary)
                                    : AnyView(AdminSurface.control)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AdminSurface.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var bottomCommandDock: some View {
        HStack(spacing: 12) {
            Button {
                UIPasteboard.general.string = currentBarcode
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { isCopied = false }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(isCopied ? Language.get("Copied", alter: "تم النسخ") : Language.get("Barcode_CopyQuickButton", alter: "نسخ"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                }
                .foregroundColor(isCopied ? Color(uiColor: .ppSuccess) : AdminSurface.primaryText)
                .frame(width: 96, height: 50)
                .background(
                    isCopied
                        ? Color(uiColor: .ppSuccess).opacity(0.12)
                        : AdminSurface.control,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isCopied ? Color(uiColor: .ppSuccess).opacity(0.3) : AdminSurface.hairline, lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            Button {
                executePrint(copies: labelCopies)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "printer.fill")
                        .font(.system(size: 16, weight: .bold))

                    Text(Language.get("BarcodeStudio_PrintAction", alter: "طباعة الملصق"))
                        .font(Font.custom("Beiruti-Bold", size: 16))

                    Spacer()

                    Text("× \(labelCopies)")
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.2), in: Capsule())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.52, blue: 0.98),
                            Color(red: 0.05, green: 0.40, blue: 0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color(red: 0.08, green: 0.52, blue: 0.98).opacity(0.35), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(!isValidCode)
        }
    }

    // MARK: - Actions

    private func generateAutoBarcode() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            isGenerating = true
        }
        let randomDigits = String(format: "%08d", Int.random(in: 10000000...99999999))
        currentBarcode = "PP" + randomDigits

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isGenerating = false
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func saveBarcodeToCatalog() {
        let trimmed = currentBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Routed through the catalog callable rather than written directly.
        //
        // A direct `setData` bypassed the entire server chain: no permission
        // re-check, no duplicate-barcode scan, no revision guard and no audit
        // record. Barcode uniqueness matters more now that each colour of a
        // product carries its own code, and `barcode` is already accepted by
        // updateCatalogPresentation, so there is no reason to write around it.
        let productId = item.accessoryID
        let expectedRevision = item.revision
        Task { @MainActor in
            do {
                let response = try await PPLivePetInventoryService.updateCatalogPresentation(
                    productID: productId,
                    values: ["barcode": trimmed],
                    commandID: "barcode-\(productId)-\(UUID().uuidString)",
                    expectedRevision: expectedRevision > 0 ? expectedRevision : nil
                )
                // Adopt the confirmed revision. Without this the local copy stays
                // stale, so a second barcode edit in the same session sends an
                // outdated `expectedRevision` and is refused by the revision guard.
                let confirmedRevision = PPLivePetInventoryService.integer(response["revision"])
                if confirmedRevision > 0 {
                    item.revision = confirmedRevision
                }
                isSaving = false
                item.barcode = trimmed
                originalBarcode = trimmed
                onBarcodeUpdated?(trimmed)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSaveSuccessBanner = true
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        showSaveSuccessBanner = false
                    }
                }
            } catch {
                isSaving = false
                await PPAlertHelper.showError(
                    in: nil,
                    title: Language.get("Error", alter: "خطأ"),
                    subtitle: error.localizedDescription
                )
            }
        }
    }

    private func executePrint(copies: Int) {
        guard UIPrintInteractionController.isPrintingAvailable else {
            PPAlertHelper.showError(
                in: nil,
                title: Language.get("PrintUnavailable_Title", alter: "الطباعة غير متاحة"),
                subtitle: Language.get("PrintUnavailable_Subtitle", alter: "يرجى التأكد من اتصال الطابعة عبر AirPrint أو الشبكة المحلية.")
            )
            return
        }

        let rendered = BarcodeRenderer.renderRetailShelfTag(
            item: item,
            code: currentBarcode,
            isQR: selectedFormat == .qr
        )

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "\(item.name) - Barcode"
        printInfo.duplex = .none

        printController.printInfo = printInfo
        printController.showsNumberOfCopies = true
        printController.printingItem = rendered

        printController.present(animated: true) { _, completed, _ in
            if completed {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func shareBarcodeLabel() {
        let rendered = BarcodeRenderer.renderRetailShelfTag(
            item: item,
            code: currentBarcode,
            isQR: selectedFormat == .qr
        )
        shareSheetImage = rendered
        showShareSheet = true
    }
}

// MARK: - Flagship Item Master Detail Screen (Push Navigation)

private struct PPLivePetReturnCaseRoute: Identifiable {
    let id: String
}

private struct LivePetArchivePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

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
    var onToggleAppMarket: (() -> Void)? = nil

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
    @State private var showActionsHub: Bool = false
    @State private var showDamageSheet: Bool = false
    @State private var showQuarantineSheet: Bool = false
    @State private var showLotsSheet: Bool = false
    @State private var showTactileQuantityPad: Bool = false
    @State private var showBarcodeStudio: Bool = false
    @State private var activeCommandUnit: PPLivePetInventoryUnit? = nil
    @State private var activeReturnCaseRoute: PPLivePetReturnCaseRoute? = nil
    @State private var showHistoryUnits: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(
        item: PetAccessory,
        viewModel: PPInventoryListViewModel? = nil,
        onDismiss: @escaping () -> Void,
        onOpenFullEditor: @escaping () -> Void,
        onOpenPOS: @escaping () -> Void,
        onAdjustQuantity: ((Int) -> Void)? = nil,
        onToggleStock: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onToggleAppMarket: (() -> Void)? = nil
    ) {
        self.item = item
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onOpenFullEditor = onOpenFullEditor
        self.onOpenPOS = onOpenPOS
        self.onAdjustQuantity = onAdjustQuantity
        self.onToggleStock = onToggleStock
        self.onDelete = onDelete
        self.onToggleAppMarket = onToggleAppMarket
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
                    Color.clear.frame(height: 58)

                    // Flagship Hero Specimen Stage (Expansive Vessel with Carousel / Lightbox / 3D Emblems)
                    heroSpecimenStage

                    // Sovereign Nomenclature & Identification Deck (Title, Condition, Tracking, Interactive SKU Cryptopill)
                    sovereignIdentificationDeck

                    // Unified Commerce & Stock Velocity Engine (Valuation, Margins, Stock Gauge, Precision Stepper)
                    unifiedCommerceAndStockInstrument

                    // Specimen Telemetry Ribbon (Sculpted 2x2 Glass Grid: Branch, Condition, Weight, Category)
                    specimenTelemetryRibbon

                    // Category-Defining App Marketplace Visibility Deck
                    appMarketVisibilityControlCard

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

            // Floating Apex Navigation Bar with Top Fade
            VStack(spacing: 0) {
                apexNavigationBar
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                    .background(
                        topNavigationBarFade
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
                            if case .releaseQuarantine(let unit) = op,
                               !unit.activeReturnCaseID.isEmpty {
                                activeReturnCaseRoute = PPLivePetReturnCaseRoute(id: unit.activeReturnCaseID)
                            } else {
                                liveModel.operation = op
                            }
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .move(edge: .bottom))
                ))
                .zIndex(100)
            }

            // Category-Defining Item Actions Hub (iPhone Deck / iPad Cockpit)
            if showActionsHub {
                PPItemActionsHubView(
                    item: item,
                    currentQuantity: currentQuantity,
                    onDismiss: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            showActionsHub = false
                        }
                    },
                    onOpenFullEditor: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showActionsHub = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            onOpenFullEditor()
                        }
                    },
                    onOpenPOS: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showActionsHub = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            onOpenPOS()
                        }
                    },
                    onEditBasicData: item.isLivePet ? {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showActionsHub = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            showBasicDataEditor = true
                        }
                    } : nil,
                    onRecordDamage: !item.isLivePet ? {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showActionsHub = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            showDamageSheet = true
                        }
                    } : nil,
                    onQuarantineStudio: !item.isLivePet ? {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showActionsHub = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            showQuarantineSheet = true
                        }
                    } : nil,
                    onManageLots: !item.isLivePet ? {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showActionsHub = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            showLotsSheet = true
                        }
                    } : nil,
                    onTransferStock: (!item.isLivePet && currentQuantity > 0) ? {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showActionsHub = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            showTransferSheet = true
                        }
                    } : nil,
                    onToggleStock: !item.isLivePet ? {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showActionsHub = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            showTactileQuantityPad = true
                        }
                    } : nil,
                    onToggleAppMarket: {
                        toggleAppMarketVisibility()
                    },
                    onShare: {
                        if let root = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene })
                            .flatMap({ $0.windows })
                            .first(where: { $0.isKeyWindow })?.rootViewController {
                            PetAccessory.share(item, from: root)
                        }
                    },
                    onDelete: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showActionsHub = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                            promptDeleteConfirm()
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
                .zIndex(150)
                .ignoresSafeArea()
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
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
        .sheet(item: $liveModel.operation, onDismiss: {
            liveModel.errorMessage = nil
        }) { operation in
            switch operation {
            case .price(let unit):
                PPLivePetUnitProfileEditorSheet(unit: unit, model: liveModel)
            default:
                PPLivePetOperationSheet(context: operation, model: liveModel) { returnCaseId in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        activeReturnCaseRoute = PPLivePetReturnCaseRoute(id: returnCaseId)
                    }
                }
            }
        }
        .fullScreenCover(item: $activeReturnCaseRoute, onDismiss: {
            Task { await liveModel.load() }
        }) { route in
            ReturnCaseDetailView(returnCaseId: route.id)
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
                        branchInventory.refreshInventory(
                            for: item.accessoryID,
                            branchId: branchId
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
        .sheet(isPresented: $showDamageSheet) {
            DamageStockSheet(
                item: item,
                branchId: BranchContextStore.shared.activeBranch?.branchID ?? item.resolvedBranchID(),
                onDamageRecorded: {
                    Task { await viewModel?.refresh() }
                }
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $showQuarantineSheet) {
            QuarantineStudioSheet(
                item: item,
                branchId: BranchContextStore.shared.activeBranch?.branchID ?? item.resolvedBranchID(),
                onResolved: {
                    Task { await viewModel?.refresh() }
                }
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $showLotsSheet) {
            InventoryLotsSheet(
                item: item,
                branchId: BranchContextStore.shared.activeBranch?.branchID ?? item.resolvedBranchID()
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $showBarcodeStudio) {
            PPBarcodeStudioSheet(item: item)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .tactileQuantityPad(
            isPresented: $showTactileQuantityPad,
            title: Language.get("EditQuantity", alter: "تعديل الكمية"),
            currentQuantity: currentQuantity,
            referenceQuantity: currentQuantity,
            specimen: PPTactileSpecimenInfo(
                title: item.name ?? "",
                imageURL: PetAccessory.firstImageURL(for: item),
                sku: (item.sku?.isEmpty ?? true) ? nil : item.sku,
                barcode: (item.barcode?.isEmpty ?? true) ? nil : item.barcode,
                unitCost: item.costPrice?.doubleValue
            )
        ) { newQty in
            setExactQuantity(newQty)
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
        showTactileQuantityPad = true
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

    // MARK: - Apex Navigation Bar & Top Fade

    private var appForegroundColor: Color {
        Color(uiColor: UIColor(named: "AppForgroundColr") ?? .ppElevatedSurface)
    }

    private var topNavigationBarFade: some View {
        // Shared optical recipe — see PPGlobalNavigationTopFade.
        PPGlobalNavigationTopFade(surface: appForegroundColor)
    }

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

            // Category-Defining Actions Hub Jewel Trigger
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    showActionsHub = true
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 0.85)
                        )
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }
                .frame(width: 44, height: 44)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(CatalogPressStyle())
            .accessibilityLabel(Language.get("Actions", alter: "خيارات وإجراءات الصنف"))
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

    private var specimenBarcodeText: String {
        if let barcode = item.barcode, !barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return barcode
        }
        return item.accessoryID
    }

    private var specimenSKUText: String? {
        if let sku = item.sku, !sku.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sku
        }
        return nil
    }

    private var specimenIdentifierText: String {
        specimenBarcodeText
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

                // App Marketplace Visibility Pill
                Button {
                    toggleAppMarketVisibility()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.showInAppMarket ? "storefront.fill" : "eye.slash.fill")
                            .font(.system(size: 9))
                        Text(item.showInAppMarket ? Language.get("AppMarket_Status_Visible", alter: "معروض بالمتجر") : Language.get("AppMarket_Status_Hidden", alter: "مخفي من المتجر"))
                            .font(Font.custom("Beiruti-Bold", size: 11))
                    }
                    .foregroundStyle(item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background((item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText).opacity(0.10), in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder((item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText).opacity(0.25), lineWidth: 0.5))
                }
                .buttonStyle(CatalogPressStyle())
            }

            // Barcode Primary Command Deck (Preserved First Row with Studio Launcher, Quick Print, Quick Copy)
            HStack(spacing: 8) {
                // Interactive Barcode Specimen Card (Tapping launches Barcode Studio)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showBarcodeStudio = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)

                        Text(specimenBarcodeText)
                            .font(Font.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 4)

                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                            Text(Language.get("Barcode_StudioTriggerHint", alter: "الاستوديو"))
                                .font(Font.custom("Beiruti-Bold", size: 11))
                        }
                        .foregroundStyle(AdminSurface.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                    )
                }
                .buttonStyle(CatalogPressStyle())
                .accessibilityLabel(Language.get("BarcodeStudio_Title", alter: "استوديو الباركود"))

                // Quick Print Barcode Label Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let rendered = BarcodeRenderer.renderRetailShelfTag(
                        item: item,
                        code: specimenBarcodeText
                    )
                    quickPrintBarcodeLabel(image: rendered, jobName: "\(item.name) - Barcode")
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "printer.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(Language.get("Barcode_PrintQuickButton", alter: "طباعة"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                    }
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 0.75)
                    )
                }
                .buttonStyle(CatalogPressStyle())
                .accessibilityLabel(Language.get("Barcode_PrintQuickButton", alter: "طباعة"))

                // Quick Copy Barcode Button (Matched Proportions)
                Button {
                    copyToClipboard(specimenBarcodeText, field: "barcode")
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copiedField == "barcode" ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(copiedField == "barcode" ? Language.get("Copied", alter: "تم النسخ") : Language.get("Barcode_CopyQuickButton", alter: "نسخ"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                    }
                    .foregroundStyle(copiedField == "barcode" ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        copiedField == "barcode"
                            ? Color(uiColor: .ppSuccess).opacity(0.12)
                            : AdminSurface.control,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                copiedField == "barcode"
                                    ? Color(uiColor: .ppSuccess).opacity(0.4)
                                    : AdminSurface.hairline,
                                lineWidth: 0.75
                            )
                    )
                }
                .buttonStyle(CatalogPressStyle())
                .accessibilityLabel(Language.get("Barcode_CopyQuickButton", alter: "نسخ"))
            }

            // SKU Secondary Identification Deck (Preserved & Moved Below Barcode)
            if let sku = specimenSKUText {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "number.square.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AdminCommandInk.secondary)

                        Text("SKU:")
                            .font(Font.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(AdminSurface.secondaryText)

                        Text(sku)
                            .font(Font.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AdminSurface.control.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.6)
                    )

                    Spacer(minLength: 4)

                    // Quick Copy SKU Button
                    Button {
                        copyToClipboard(sku, field: "sku_field")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedField == "sku_field" ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.system(size: 11, weight: .bold))
                            Text(copiedField == "sku_field" ? Language.get("Copied", alter: "تم النسخ") : Language.get("TapToCopy", alter: "نسخ"))
                                .font(Font.custom("Beiruti-Bold", size: 11))
                        }
                        .foregroundStyle(copiedField == "sku_field" ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            copiedField == "sku_field"
                                ? Color(uiColor: .ppSuccess).opacity(0.12)
                                : AdminSurface.control.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    copiedField == "sku_field"
                                        ? Color(uiColor: .ppSuccess).opacity(0.4)
                                        : AdminSurface.hairline,
                                    lineWidth: 0.6
                                )
                        )
                    }
                    .buttonStyle(CatalogPressStyle())
                }
            }
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
                                    Text(verbatim: String(format: Language.get("Profit_Margin_Format", alter: "+%.2f ر.ق (%.0f%%)"), margin.margin, margin.percent).normalizedEnglishDigits)
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
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
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
                    value: item.accessoryCategoryName ?? (item.accessoryCategoryID?.isEmpty == false ? item.accessoryCategoryID! : PetAccessory.typeText(for: item)),
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
                .multilineTextAlignment(.leading)
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

    private func quickPrintBarcodeLabel(image: UIImage, jobName: String) {
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = jobName
        printInfo.duplex = .none
        printController.printInfo = printInfo
        printController.showsNumberOfCopies = true
        printController.printingItem = image

        if UIDevice.current.userInterfaceIdiom == .pad {
            if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
               let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                printController.present(from: CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0), in: rootVC.view, animated: true)
            }
        } else {
            printController.present(animated: true) { _, _, _ in }
        }
    }

    private func adjustQuantity(_ delta: Int) {
        if onAdjustQuantity == nil, viewModel == nil {
            let branchID = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !branchID.isEmpty, branchID != "main_store" else {
                PPHUD.showError(
                    Language.get("Error", alter: "خطأ"),
                    subtitle: Language.get(
                        "Inventory_SpecificBranchRequired",
                        alter: "اختر فرعاً محدداً قبل تعديل المخزون."
                    )
                )
                return
            }
        }
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
                // The guard above makes this path unreachable for a raw
                // detail view. Keep the failure explicit instead of falling
                // back to a parent/catalog mutation with an unknown branch.
                PPHUD.showError(
                    Language.get("Error", alter: "خطأ"),
                    subtitle: Language.get(
                        "Inventory_SpecificBranchRequired",
                        alter: "اختر فرعاً محدداً قبل تعديل المخزون."
                    )
                )
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
        guard !item.isLivePet else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // “Availability” is quantity-derived. Route the control to the exact
        // quantity pad rather than mutating a synthetic noStock state.
        showTactileQuantityPad = true
    }

    private func toggleAppMarketVisibility() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // The owner callback is authoritative when present. It performs the
        // optimistic update and the audited command exactly once; pre-toggling
        // here would invert the value a second time.
        if let onToggleAppMarket {
            onToggleAppMarket()
            return
        }

        let docID = item.accessoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !docID.isEmpty else { return }
        let previous = item.showInAppMarket
        let next = !previous
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            item.showInAppMarket = next
        }

        let commandID = PPInventoryCommandService.shared.generateCommandId(action: "visibility", targetId: docID)
        PPInventoryCommandService.shared.setAppMarketVisibility(
            productId: docID,
            visible: next,
            expectedRevision: item.revision > 0 ? item.revision : nil,
            commandId: commandID
        ) { result, error in
            DispatchQueue.main.async {
                if let error {
                    item.showInAppMarket = previous
                    viewModel?.applyFilter()
                    PPHUD.showError(Language.get("Error", alter: "خطأ"), subtitle: PPBranchInventoryErrorHelper.localizedMessage(for: error))
                    return
                }
                if let revision = result?.revision, revision > 0 { item.revision = revision }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                let msg = next ? Language.get("AppMarket_NowVisible_Toast", alter: "تم إظهار الصنف في متجر التطبيق") : Language.get("AppMarket_NowHidden_Toast", alter: "تم إخفاء الصنف من متجر التطبيق")
                PPHUD.showSuccess(msg)
                viewModel?.applyFilter()
            }
        }
    }

    // MARK: - App Marketplace Visibility Control Card

    private var appMarketVisibilityControlCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill((item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText).opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: item.showInAppMarket ? "storefront.fill" : "eye.slash.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Language.get("AppMarket_Card_Title", alter: "العرض في متجر التطبيق"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(item.showInAppMarket ? Language.get("AppMarket_Status_Visible", alter: "معروض") : Language.get("AppMarket_Status_Hidden", alter: "مخفي"))
                        .font(Font.custom("Beiruti-Bold", size: 10))
                        .foregroundStyle(item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText).opacity(0.12), in: Capsule())
                }

                Text(item.showInAppMarket ? Language.get("AppMarket_Card_Desc_On", alter: "الصنف معروض ومتاح لعملاء تطبيق Pure Pets للشراء والتصفح") : Language.get("AppMarket_Card_Desc_Off", alter: "مخفي من متجر التطبيق، ومتاح فقط داخلياً لعمليات الكاشير والفرع"))
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Toggle("", isOn: Binding(
                get: { item.showInAppMarket },
                set: { _ in toggleAppMarketVisibility() }
            ))
            .labelsHidden()
            .tint(Color(uiColor: .systemIndigo))
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(item.showInAppMarket ? Color(uiColor: .systemIndigo).opacity(0.22) : AdminSurface.hairline, lineWidth: 0.85)
        )
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
            if let error = liveModel.errorMessage, liveModel.operation == nil {
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
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
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
        let activeUnits = liveModel.units.filter { 
            $0.status == "AVAILABLE" || $0.status == "RESERVED" || $0.status == "QUARANTINED" || $0.status == "UNDER_INSPECTION" || $0.isUnderInspection 
        }.sorted()
        let historyUnits = liveModel.units.filter { !activeUnits.contains($0) }.sorted()
        let availableCount = liveModel.units.filter { $0.status == "AVAILABLE" }.count
        let underInspectionCount = liveModel.units.filter { $0.isUnderInspection }.count
        let soldCount = liveModel.units.filter { $0.status == "SOLD" && !$0.isUnderInspection }.count

        var subtitleParts: [String] = []
        if availableCount > 0 {
            subtitleParts.append(String(format: Language.get("LivePetDossier_ActiveOnHandCount", alter: "%ld متاح بالمخزون"), availableCount))
        } else if activeUnits.isEmpty {
            subtitleParts.append(Language.get("LivePetDossier_NoActiveInStock", alter: "لا توجد حيوانات متاحة حالياً بالمخزون"))
        }
        if underInspectionCount > 0 {
            subtitleParts.append(String(format: Language.get("LivePetDossier_UnderInspectionCount", alter: "%ld قيد الفحص والتقييم"), underInspectionCount))
        }
        if soldCount > 0 {
            subtitleParts.append(String(format: Language.get("LivePetDossier_SoldCount", alter: "%ld مباع"), soldCount))
        }
        let ledgerSubtitle = subtitleParts.joined(separator: " • ")

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("LivePetDossier_UnitLedgerTitle", alter: "سجل الحيوانات الفردية"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(ledgerSubtitle)
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(activeUnits.isEmpty && soldCount == 0 ? Color(uiColor: .ppError) : AdminCommandInk.secondary)
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
                    VStack(alignment: .leading, spacing: 10) {
                        livePetArchiveDisclosureHeader(count: historyUnits.count)

                        if showHistoryUnits {
                            VStack(spacing: 8) {
                                ForEach(historyUnits) { unit in
                                    livePetUnitRow(unit)
                                        .opacity(0.85)
                                }
                            }
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                )
                            )
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(.top, 4)
    }

    private func livePetArchiveDisclosureHeader(count: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                showHistoryUnits.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                // Leading Archive Jewel / Emblem
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: showHistoryUnits
                                    ? [Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.18), Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.08)]
                                    : [AdminSurface.control, AdminSurface.control.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: showHistoryUnits ? "archivebox.fill" : "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(showHistoryUnits ? Color(red: 0.55, green: 0.36, blue: 0.96) : AdminCommandInk.secondary)
                }
                .frame(width: 34, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            showHistoryUnits
                                ? Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.24)
                                : AdminSurface.hairline,
                            lineWidth: 0.75
                        )
                )

                // Title and Subtitle Text Stack
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Language.get("LivePet_Units_Archived_Title", alter: Language.isRTL() ? "سجل المبيعات والأرشيف" : "Sales History & Archived"))
                            .font(Language.isRTL() ? Font.custom("Beiruti-Bold", size: 15) : Font.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)

                        // Count Telemetry Pill Badge
                        HStack(spacing: 3.5) {
                            Circle()
                                .fill(showHistoryUnits ? Color(red: 0.55, green: 0.36, blue: 0.96) : AdminCommandInk.secondary)
                                .frame(width: 4.5, height: 4.5)
                            Text("\(count)")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(showHistoryUnits ? Color(red: 0.55, green: 0.36, blue: 0.96) : AdminCommandInk.secondary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    showHistoryUnits
                                        ? Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.12)
                                        : AdminSurface.control
                                )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    showHistoryUnits
                                        ? Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.24)
                                        : AdminSurface.hairline,
                                    lineWidth: 0.5
                                )
                        )
                    }

                    Text(
                        showHistoryUnits
                            ? Language.get("LivePet_Units_Archived_ExpandedHint", alter: Language.isRTL() ? "يتم الآن عرض سجل الحيوانات المباعة والمؤرشفة" : "Showing all sold and archived records")
                            : Language.get("LivePet_Units_Archived_CollapsedHint", alter: Language.isRTL() ? "انقر لعرض سجل الحيوانات المباعة والمؤرشفة" : "Tap to view sold and archived records")
                    )
                    .font(Language.isRTL() ? Font.custom("Beiruti-Regular", size: 11.5) : Font.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Trailing Interactive Chevron Orb
                ZStack {
                    Circle()
                        .fill(showHistoryUnits ? Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.12) : AdminSurface.control)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(showHistoryUnits ? Color(red: 0.55, green: 0.36, blue: 0.96) : AdminCommandInk.secondary)
                        .rotationEffect(.degrees(showHistoryUnits ? 180 : 0))
                }
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .strokeBorder(
                            showHistoryUnits
                                ? Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.20)
                                : AdminSurface.hairline,
                            lineWidth: 0.5
                        )
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        showHistoryUnits
                            ? (colorScheme == .dark ? Color(white: 0.14) : Color(red: 0.97, green: 0.96, blue: 1.0))
                            : (colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.975))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        showHistoryUnits
                            ? Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.30)
                            : AdminSurface.hairline,
                        lineWidth: showHistoryUnits ? 1.0 : 0.75
                    )
            )
            .shadow(
                color: showHistoryUnits
                    ? Color(red: 0.55, green: 0.36, blue: 0.96).opacity(colorScheme == .dark ? 0.20 : 0.08)
                    : Color.black.opacity(0.02),
                radius: showHistoryUnits ? 6 : 2,
                y: 1
            )
        }
        .buttonStyle(LivePetArchivePressStyle())
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
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
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
        let identity = unit.displayIdentity
        let status = liveUnitStatus(unit)
        let statusColor = liveUnitStatusColor(unit)
        let statusSymbol = liveUnitStatusSymbol(unit)
        let firstMediaURL = unit.mediaURLs.first.flatMap { URL(string: $0) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                // Status Jewel or Specimen Photo (Right in RTL)
                ZStack(alignment: .bottomTrailing) {
                    if let url = firstMediaURL {
                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 44, height: 44)) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(statusColor.opacity(0.12))
                                .overlay(
                                    Image(systemName: statusSymbol)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(statusColor)
                                )
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(statusColor.opacity(0.4), lineWidth: 1)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(AdminSurface.surface, lineWidth: 2))
                                .offset(x: 2, y: 2)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(statusColor.opacity(0.12))
                            .overlay(
                                Image(systemName: statusSymbol)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(statusColor)
                            )
                            .frame(width: 44, height: 44)
                    }
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
                            symbol: statusSymbol,
                            tint: statusColor
                        )

                        if unit.gender != .unspecified {
                            livePetGenderPill(unit.gender)
                        }

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

                        if let subSub = unit.subSubKindName, !subSub.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 9))
                                Text(verbatim: subSub + (unit.subSubKindItemName.map { " · \($0)" } ?? ""))
                                    .font(Font.custom("Beiruti-Regular", size: 11))
                            }
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))
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

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            activeCommandUnit = unit
                        }
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
                    .buttonStyle(CatalogPressStyle())
                    .disabled(liveModel.isMutating)
                    .accessibilityLabel(String(
                        format: Language.get("LivePetDossier_UnitActionsAccessibility", alter: "إجراءات الحيوان %@"),
                        identity
                    ))
                }
            }

            if unit.isUnderInspection {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .systemPurple))
                        .frame(width: 28, height: 28)
                        .background(Color(uiColor: .systemPurple).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("LivePet_Custody_UnderInspection", alter: "الحيوان مسترجع وقيد الفحص والتقييم"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.primaryText)
                        let reasonDisplay = !unit.returnReason.isEmpty ? unit.returnReason : unit.quarantineReason
                        if !reasonDisplay.isEmpty {
                            Text(reasonDisplay)
                                .font(Font.custom("Beiruti-Regular", size: 11))
                                .foregroundStyle(AdminCommandInk.secondary)
                        }
                        if !unit.linkedReturnCaseReference.isEmpty {
                            Text(String(format: Language.get("LivePet_ReturnCase_Ref", alter: "ملف الاسترجاع: %@"), unit.linkedReturnCaseReference))
                                .font(Font.custom("Beiruti-Regular", size: 10))
                                .foregroundStyle(Color(uiColor: .systemPurple))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color(uiColor: .systemPurple).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if unit.status == "QUARANTINED" {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: unit.isLegacyReturnedQuarantine ? "arrow.uturn.backward.circle.fill" : "cross.case.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .ppWarning))
                        .frame(width: 28, height: 28)
                        .background(Color(uiColor: .ppWarning).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        let title = unit.isLegacyReturnedQuarantine
                            ? Language.get("LivePet_LegacyReturn_Notice_Title", alter: "حيوان مسترجع في عهدة الحجر")
                            : Language.get("LivePet_Quarantine_Notice_Title", alter: "الحيوان خاضع للعزل البيطري")
                        Text(title)
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.primaryText)
                        let rawReason = !unit.returnReason.isEmpty ? unit.returnReason : unit.quarantineReason
                        if !rawReason.isEmpty && rawReason != "LIVE_ANIMAL_RETURN" {
                            Text(rawReason)
                                .font(Font.custom("Beiruti-Regular", size: 11))
                                .foregroundStyle(AdminCommandInk.secondary)
                        }
                        if !unit.returnTransactionId.isEmpty {
                            Text(String(format: Language.get("LivePet_ReturnTx_Ref", alter: "معاملة الاسترجاع: %@"), unit.returnTransactionId))
                                .font(Font.custom("Beiruti-Regular", size: 10))
                                .foregroundStyle(Color(uiColor: .ppWarning))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color(uiColor: .ppWarning).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                activeCommandUnit = unit
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                activeCommandUnit = unit
            }
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

    private func liveUnitStatus(_ unit: PPLivePetInventoryUnit) -> String {
        if unit.isUnderInspection {
            return Language.get("LivePet_Status_UnderInspection", alter: "قيد الفحص والتقييم")
        }
        return liveUnitStatus(unit.status)
    }

    private func liveUnitStatus(_ status: String) -> String {
        switch status {
        case "AVAILABLE": return Language.get("LivePet_Status_Available", alter: "متاح")
        case "RESERVED": return Language.get("LivePet_Status_Reserved", alter: "محجوز")
        case "SOLD": return Language.get("LivePet_Status_Sold", alter: "مباع")
        case "QUARANTINED": return Language.get("LivePet_Status_Quarantined", alter: "في الحجر")
        case "UNDER_INSPECTION": return Language.get("LivePet_Status_UnderInspection", alter: "قيد الفحص والتقييم")
        case "DECEASED": return Language.get("LivePet_Status_Deceased", alter: "متوفى")
        case "TRANSFERRED": return Language.get("LivePet_Status_Transferred", alter: "منقول نهائياً")
        default: return Language.get("LivePet_Status_Removed", alter: "مزال")
        }
    }

    private func liveUnitStatusColor(_ unit: PPLivePetInventoryUnit) -> Color {
        if unit.isUnderInspection {
            return Color(uiColor: .systemPurple)
        }
        return liveUnitStatusColor(unit.status)
    }

    private func liveUnitStatusColor(_ status: String) -> Color {
        switch status {
        case "AVAILABLE": return Color(uiColor: .ppSuccess)
        case "RESERVED", "QUARANTINED": return Color(uiColor: .ppWarning)
        case "UNDER_INSPECTION": return Color(uiColor: .systemPurple)
        case "SOLD", "TRANSFERRED": return AdminCommandInk.secondary
        default: return Color(uiColor: .ppError)
        }
    }

    private func liveUnitStatusSymbol(_ unit: PPLivePetInventoryUnit) -> String {
        if unit.isUnderInspection {
            return "stethoscope"
        }
        return liveUnitStatusSymbol(unit.status)
    }

    private func liveUnitStatusSymbol(_ status: String) -> String {
        switch status {
        case "AVAILABLE": return "checkmark.circle.fill"
        case "RESERVED": return "calendar.badge.clock"
        case "SOLD": return "checkmark.seal.fill"
        case "QUARANTINED": return "cross.case.fill"
        case "UNDER_INSPECTION": return "stethoscope"
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

    private func livePetGenderPill(_ gender: PPLivePetUnitGender) -> some View {
        let tint = Color(uiColor: gender.tint)
        return HStack(spacing: 3) {
            Image(systemName: gender.symbolName)
                .font(.system(size: 8, weight: .bold))
            Text(gender.localizedShortTitle)
                .font(Font.custom("Beiruti-Bold", size: 11))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(tint.opacity(0.12), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.30), lineWidth: 0.5))
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
                            .background(Color(uiColor: .ppBackgroundSecondary).opacity(0.6), in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.5)
                            )
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
                    ? AdminSurface.surface
                    : (isDestructive ? Color(uiColor: .ppError).opacity(0.03) : AdminSurface.surface),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isHero
                            ? iconTint.opacity(0.18)
                            : (isDestructive ? Color(uiColor: .ppError).opacity(0.18) : AdminSurface.hairline),
                        lineWidth: 0.75
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
        if unit.isUnderInspection {
            return Language.get("LivePet_Status_UnderInspection", alter: "قيد الفحص والتقييم")
        }
        switch unit.status {
        case "AVAILABLE": return Language.get("LivePet_Status_Available", alter: "متاح بالمخزون")
        case "RESERVED": return Language.get("LivePet_Status_Reserved", alter: "محجوز لعميل")
        case "SOLD": return Language.get("LivePet_Status_Sold", alter: "مباع ومسلّم")
        case "QUARANTINED": return Language.get("LivePet_Status_Quarantined", alter: "في الحجر الصحي")
        case "UNDER_INSPECTION": return Language.get("LivePet_Status_UnderInspection", alter: "قيد الفحص والتقييم")
        case "DECEASED": return Language.get("LivePet_Status_Deceased", alter: "متوفى")
        case "TRANSFERRED": return Language.get("LivePet_Status_Transferred", alter: "منقول لفرع آخر")
        default: return Language.get("LivePet_Status_Removed", alter: "مزال من المخزون")
        }
    }

    private var statusColor: Color {
        if unit.isUnderInspection {
            return Color(uiColor: .systemPurple)
        }
        switch unit.status {
        case "AVAILABLE": return Color(uiColor: .ppSuccess)
        case "RESERVED": return Color(uiColor: .ppWarning)
        case "QUARANTINED": return Color(uiColor: .ppInfo)
        case "UNDER_INSPECTION": return Color(uiColor: .systemPurple)
        case "SOLD", "TRANSFERRED": return AdminCommandInk.secondary
        default: return Color(uiColor: .ppError)
        }
    }

    private var statusSymbol: String {
        if unit.isUnderInspection {
            return "stethoscope"
        }
        switch unit.status {
        case "AVAILABLE": return "checkmark.circle.fill"
        case "RESERVED": return "calendar.badge.clock"
        case "SOLD": return "checkmark.seal.fill"
        case "QUARANTINED": return "cross.case.fill"
        case "UNDER_INSPECTION": return "stethoscope"
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

                    // Active Quarantine Notice if Quarantined or under inspection
                    if unit.status == "QUARANTINED" || unit.isUnderInspection {
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
                            } else if unit.status == "QUARANTINED" || unit.isUnderInspection {
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
            .frame(maxWidth: .infinity)
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
            .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: -4)
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
                        .background(AdminSurface.surface, in: Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                        )
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
                    .background(Color(uiColor: .ppBackgroundSecondary).opacity(0.6), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.5)
                    )
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
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppWarning).opacity(0.20), lineWidth: 0.75)
        )
    }

    // MARK: - Active Quarantine Notice

    private var activeQuarantineNotice: some View {
        let isInspection = unit.isUnderInspection
        let isLegacyReturn = unit.isLegacyReturnedQuarantine
        let symbol = isInspection ? "stethoscope" : (isLegacyReturn ? "arrow.uturn.backward.circle.fill" : "cross.case.fill")
        let tint = isInspection ? Color(uiColor: .systemPurple) : (isLegacyReturn ? Color(uiColor: .ppWarning) : Color(uiColor: .ppInfo))
        let title = isInspection
            ? Language.get("LivePet_Inspection_Notice_Title", alter: "الحيوان خاضع للفحص والتقييم")
            : (isLegacyReturn
                ? Language.get("LivePet_LegacyReturn_Notice_Title", alter: "حيوان مسترجع في عهدة الحجر")
                : Language.get("LivePet_Quarantine_Notice_Title", alter: "الحيوان خاضع للعزل البيطري"))
        let desc = isInspection
            ? Language.get("LivePet_Inspection_Notice_Desc", alter: "تم استرجاع هذا الحيوان وهو قيد الفحص والتقييم البيطري لتحديد حالته قبل الإفراج أو البيع.")
            : (isLegacyReturn
                ? Language.get("LivePet_LegacyReturn_Notice_Desc", alter: "تم استلام هذا الحيوان عبر مسار الاسترجاع السابق. يبقى غير متاح للبيع حتى مراجعة الحجر وإصداره بالصلاحيات المعتمدة.")
                : Language.get("LivePet_Quarantine_Notice_Desc", alter: "تم إيقاف عرض هذا الحيوان من نقاط البيع لحين التحقق من التعافي وإصدار إذن خروج."))

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
                Text(desc)
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                let reason = !unit.returnReason.isEmpty ? unit.returnReason : unit.quarantineReason
                if !reason.isEmpty {
                    Text(String(format: Language.get("LivePet_ReturnReason_Label", alter: "سبب الإرجاع: %@"), reason))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(tint)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 0.75)
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
                    title: Language.get("LivePet_Edit_Price_Action", alter: "تعديل بيانات وسعر الحيوان"),
                    subtitle: Language.get("LivePet_Edit_Price_Action_Desc", alter: "تحديث صورة الحيوان، رقم الحجل، الجنس، الملاحظات، وسعر البيع"),
                    icon: "pawprint.fill",
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
        let hasReturnCase = !unit.activeReturnCaseID.isEmpty
        let canUsePrimaryAction = hasReturnCase ? liveModel.canViewLivePetReturns : liveModel.canReleaseQuarantine

        return VStack(alignment: .leading, spacing: 10) {
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
                    title: hasReturnCase
                        ? Language.get("LivePet_Open_ReturnCase_Action", alter: "فتح ملف الاسترجاع والفحص")
                        : Language.get("LivePet_Release_Quarantine_Action", alter: "إخراج من الحجر الصحي"),
                    subtitle: hasReturnCase
                        ? Language.get("LivePet_Open_ReturnCase_Desc", alter: "مراجعة الملف المعتمد وإكمال الفحص قبل إعادة الإتاحة للبيع")
                        : Language.get("LivePet_Release_Quarantine_Desc", alter: "إعادة إتاحة الحيوان للبيع بعد التأكد من سلامته البيطرية"),
                    icon: hasReturnCase ? "doc.text.magnifyingglass" : "checkmark.shield",
                    iconTint: hasReturnCase ? Color(uiColor: .systemPurple) : Color(uiColor: .ppSuccess),
                    iconBackground: (hasReturnCase ? Color(uiColor: .systemPurple) : Color(uiColor: .ppSuccess)).opacity(0.14),
                    badge: hasReturnCase
                        ? Language.get("Badge_ReturnCase", alter: "ملف معتمد")
                        : Language.get("Badge_Medical_Clearance", alter: "تصريح طبي"),
                    isHero: true,
                    isLocked: !canUsePrimaryAction,
                    lockReason: !canUsePrimaryAction
                        ? (hasReturnCase
                            ? Language.get("LivePet_Return_View_Perm_Required", alter: "صلاحية عرض ملفات الاسترجاع مطلوبة")
                            : Language.get("Stock_Perm_Required", alter: "صلاحية الفحص الطبي"))
                        : nil
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
                    title: Language.get("LivePet_Edit_Price_Action", alter: "تعديل بيانات وسعر الحيوان"),
                    subtitle: Language.get("LivePet_Edit_Price_Desc_Quarantine", alter: "تحديث صورة الحيوان، رقم الحجل، الجنس، الملاحظات، وسعر البيع خلال فترة العزل"),
                    icon: "pawprint.fill",
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

// MARK: - Category-Defining Sovereign Item Actions Hub (iPhone Deck & iPad Cockpit)

private struct PPCockpitPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct PPActionHubContentHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

@available(iOS 16.0, *)
public struct PPItemActionsHubView: View {
    let item: PetAccessory
    let currentQuantity: Int
    let onDismiss: () -> Void
    let onOpenFullEditor: () -> Void
    let onOpenPOS: () -> Void
    var onEditBasicData: (() -> Void)? = nil
    var onRecordDamage: (() -> Void)? = nil
    var onQuarantineStudio: (() -> Void)? = nil
    var onManageLots: (() -> Void)? = nil
    var onTransferStock: (() -> Void)? = nil
    var onToggleStock: (() -> Void)? = nil
    var onToggleAppMarket: (() -> Void)? = nil
    let onShare: () -> Void
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var hasAppeared: Bool = false
    @State private var showBarcodeStudio: Bool = false
    @State private var streamContentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var imageURL: URL? {
        PetAccessory.firstImageURL(for: item)
    }

    private var stockTone: Color {
        if (item.noStock && !item.isLivePet) || currentQuantity <= 0 {
            return Color(uiColor: .ppError)
        } else if currentQuantity <= 3 {
            return Color(uiColor: .ppWarning)
        } else {
            return Color(uiColor: .ppSuccess)
        }
    }

    private var stockStatusText: String {
        if item.noStock && !item.isLivePet {
            return Language.get("HiddenFromCatalog", alter: "موقوف مؤقتاً")
        } else if currentQuantity <= 0 {
            return Language.get("OutOfStock", alter: "نفذ من المخزون")
        } else if currentQuantity <= 3 {
            return Language.get("LowStock", alter: "وشك النفاذ")
        } else {
            return Language.get("InStock", alter: "متوفر بالمخزون")
        }
    }

    public var body: some View {
        GeometryReader { geometry in
            let isIPad = UIDevice.current.userInterfaceIdiom == .pad && geometry.size.width > 550

            ZStack(alignment: isIPad ? .center : .bottom) {
                // High-Performance Ambient Dimmed Scrim
                Color.black.opacity(hasAppeared ? 0.52 : 0.0)
                    .ignoresSafeArea()
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onDismiss()
                    }

                if isIPad {
                    iPadCockpit(geometry: geometry)
                        .scaleEffect(hasAppeared ? 1.0 : 0.94)
                        .opacity(hasAppeared ? 1.0 : 0.0)
                } else {
                    iPhoneDeck(geometry: geometry)
                        .offset(y: max(0, dragOffset))
                        .offset(y: hasAppeared ? 0 : geometry.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .onAppear {
                if accessibilityReduceMotion {
                    hasAppeared = true
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        hasAppeared = true
                    }
                }
            }
            .sheet(isPresented: $showBarcodeStudio) {
                PPBarcodeStudioSheet(item: item)
                    .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }
        }
    }

    // MARK: - iPhone Compact Thumb-Zone Sensory Deck
    @ViewBuilder
    private func iPhoneDeck(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Sensory Dismiss Handle
            Capsule()
                .fill(Color(uiColor: .systemGray4))
                .frame(width: 44, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            // Specimen Telemetry HUD Bar
            HStack(spacing: 12) {
                // Specimen Thumbnail
                ZStack {
                    if let imageURL = imageURL {
                        AdminRemoteImage(url: imageURL, contentMode: .fill, targetSize: CGSize(width: 52, height: 52)) {
                            AdminSurface.control
                        }
                        .frame(width: 52, height: 52)
                        .clipped()
                    } else {
                        ZStack {
                            AdminSurface.control
                            Image(systemName: item.isLivePet ? "pawprint.fill" : "cube.box.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(AdminSurface.primary.opacity(0.6))
                        }
                        .frame(width: 52, height: 52)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                )

                // Identity & Telemetry Details
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        // Stock Indicator Capsule
                        HStack(spacing: 4) {
                            Circle()
                                .fill(stockTone)
                                .frame(width: 6, height: 6)
                            Text(stockStatusText)
                                .font(Font.custom("Beiruti-Bold", size: 11))
                                .foregroundStyle(stockTone)
                            if currentQuantity > 0 {
                                Text("(\(currentQuantity.englishDigits))")
                                    .font(PPBrandFont.bold(size: 11))
                                    .foregroundStyle(stockTone.opacity(0.9))
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(stockTone.opacity(0.12), in: Capsule(style: .continuous))

                        // Valuation Readout
                        Text(item.inventoryDisplayPrice)
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.primary)

                        if let barcode = item.barcode, !barcode.isEmpty {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showBarcodeStudio = true
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "barcode.viewfinder")
                                        .font(.system(size: 9))
                                    Text(barcode)
                                        .font(Font.system(size: 10, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(CatalogPressStyle())
                            .accessibilityLabel(Language.get("BarcodeStudio_Title", alter: "استوديو الباركود"))
                        }
                    }
                }

                Spacer(minLength: 0)

                // Quick Close Button
                AdminSquircleCloseButton {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            Divider()
                .background(AdminSurface.hairline.opacity(0.7))

            // Action Portfolio Scrollable Stream
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Twin Hero Commercial Launchers (2-Column Grid)
                    HStack(spacing: 12) {
                        // Edit Full Specimen
                        heroLauncherCard(
                            title: Language.get("Edit", alter: "تعديل الصنف"),
                            subtitle: Language.get("ItemActions_Edit_Desc", alter: "المحرر الشامل"),
                            icon: "square.and.pencil",
                            tint: AdminSurface.primary,
                            action: onOpenFullEditor
                        )

                        // Open in POS
                        heroLauncherCard(
                            title: Language.get("LivePet_Open_POS", alter: "نقطة البيع"),
                            subtitle: Language.get("ItemActions_POS_Desc", alter: "إضافة للسلة والبيع"),
                            icon: "cart.fill.badge.plus",
                            tint: Color(uiColor: .ppSuccess),
                            action: onOpenPOS
                        )
                    }

                    // Barcode & Shelf Label Studio Launcher Row
                    actionHubRow(
                        title: Language.get("BarcodeStudio_Title", alter: "استوديو الباركود والملصقات"),
                        subtitle: Language.get("BarcodeStudio_Subtitle", alter: "معاينة، توليد، تعديل وطباعة الملصقات"),
                        icon: "barcode.viewfinder",
                        tint: AdminSurface.primary,
                        action: {
                            showBarcodeStudio = true
                        }
                    )

                    // Live Pet Basic Data Editor (if applicable)
                    if item.isLivePet, let onEditBasicData = onEditBasicData {
                        actionHubRow(
                            title: Language.get("LivePet_EditBasicData", alter: "تعديل البيانات الأساسية"),
                            subtitle: Language.get("ItemActions_LivePet_Desc", alter: "تحديث السلالة، العمر، الجنس ورقم الحجل"),
                            icon: "pencil.and.list.clipboard",
                            tint: Color(uiColor: .ppInfo),
                            action: onEditBasicData
                        )
                    }

                    // Logistics & Supply Chain Operations Matrix (if not live pet)
                    if !item.isLivePet {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "shippingbox.and.arrow.backward.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AdminSurface.primary)
                                Text(Language.get("Inventory_Ops_Section", alter: "عمليات المخزون والرقابة"))
                                    .font(Font.custom("Beiruti-Bold", size: 13))
                                    .foregroundStyle(AdminCommandInk.secondary)
                            }
                            .padding(.horizontal, 4)

                            VStack(spacing: 8) {
                                if let onManageLots = onManageLots {
                                    actionHubRow(
                                        title: Language.get("Inventory_Action_Manage_Lots", alter: "إدارة التشغيلات وتواريخ الصلاحية (FEFO)"),
                                        subtitle: Language.get("ItemActions_Lots_Desc", alter: "تتبع الدفعات وأولويات الصرف الذكية"),
                                        icon: "calendar.badge.clock",
                                        tint: Color(uiColor: .ppInfo),
                                        action: onManageLots
                                    )
                                }

                                if let onQuarantineStudio = onQuarantineStudio {
                                    actionHubRow(
                                        title: Language.get("Inventory_Action_Quarantine_Studio", alter: "استوديو الفحص والتصرف (الحجر)"),
                                        subtitle: Language.get("ItemActions_Quarantine_Desc", alter: "حجر العينات وفحص الجودة وإعادة التوجيه"),
                                        icon: "shield.lefthalf.filled",
                                        tint: Color(uiColor: .ppWarning),
                                        action: onQuarantineStudio
                                    )
                                }

                                if let onRecordDamage = onRecordDamage {
                                    actionHubRow(
                                        title: Language.get("Inventory_Action_Record_Damage", alter: "تسجيل إتلاف مخزون"),
                                        subtitle: Language.get("ItemActions_Damage_Desc", alter: "توثيق التالف وإسقاط الكميات رسمياً"),
                                        icon: "exclamationmark.octagon.fill",
                                        tint: Color(uiColor: .ppError),
                                        action: onRecordDamage
                                    )
                                }

                                if let onTransferStock = onTransferStock, currentQuantity > 0 {
                                    actionHubRow(
                                        title: Language.get("Stock_Transfer_Action", alter: "نقل كمية إلى فرع آخر"),
                                        subtitle: Language.get("ItemActions_Transfer_Desc", alter: "مناقلة المخزون بين الفروع المعتمدة"),
                                        icon: "arrow.left.arrow.right",
                                        tint: Color(uiColor: .ppSuccess),
                                        trailingPill: "\(Language.get("Available", alter: "متاح")): \(currentQuantity.englishDigits)",
                                        action: onTransferStock
                                    )
                                }
                            }
                        }

                        // Availability Controller Card
                        if let onToggleStock = onToggleStock {
                            availabilityControllerCard(onToggle: onToggleStock)
                        }

                        // App Marketplace Visibility Controller Card
                        if let onToggleAppMarket = onToggleAppMarket {
                            appMarketControllerCard(onToggle: onToggleAppMarket)
                        }
                    }

                    // Collaboration & Sharing
                    actionHubRow(
                        title: Language.get("Share", alter: "مشاركة الصنف"),
                        subtitle: Language.get("ItemActions_Share_Desc", alter: "مشاركة بطاقة الصنف والمواصفات"),
                        icon: "square.and.arrow.up",
                        tint: AdminCommandInk.secondary,
                        action: onShare
                    )

                    // Guarded Destructive Safety Zone
                    destructiveSafetyCard(onDelete: onDelete)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PPActionHubContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .frame(height: streamContentHeight > 0 ? min(streamContentHeight, geometry.size.height * 0.78) : nil)
            .onPreferenceChange(PPActionHubContentHeightKey.self) { val in
                if val > 0 {
                    streamContentHeight = val
                }
            }

            // Safe Area Bottom Clearance for Home Indicator
            Color.clear
                .frame(height: max(geometry.safeAreaInsets.bottom, 16))
        }
        .background(
            AdminSurface.surface
                .clipShape(PPSheetTopRoundedShape(radius: 28))
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: -6)
        )
        .overlay(
            PPSheetTopRoundedShape(radius: 28)
                .stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.85), lineWidth: 0.8)
        )
        .gesture(
            DragGesture()
                .onChanged { val in
                    if val.translation.height > 0 {
                        dragOffset = val.translation.height
                    }
                }
                .onEnded { val in
                    if val.translation.height > 90 || val.predictedEndTranslation.height > 180 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    // MARK: - iPad Floating Tactical Cockpit (Spatial 2-Column Command Hub)
    @ViewBuilder
    private func iPadCockpit(geometry: GeometryProxy) -> some View {
        let cockpitWidth = min(660, geometry.size.width - 64)
        let cockpitHeight = min(720, geometry.size.height - 80)

        VStack(spacing: 0) {
            // Apex Command Cockpit Header
            HStack(spacing: 16) {
                // High-Res Specimen Avatar
                ZStack {
                    if let imageURL = imageURL {
                        AdminRemoteImage(url: imageURL, contentMode: .fill, targetSize: CGSize(width: 64, height: 64)) {
                            AdminSurface.control
                        }
                        .frame(width: 64, height: 64)
                        .clipped()
                    } else {
                        ZStack {
                            AdminSurface.control
                            Image(systemName: item.isLivePet ? "pawprint.fill" : "cube.box.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(AdminSurface.primary.opacity(0.6))
                        }
                        .frame(width: 64, height: 64)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.85), lineWidth: 0.8)
                )

                // Specimen Dossier Telemetry
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(Font.custom("Beiruti-Bold", size: 19))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // Stock Indicator Pill
                        HStack(spacing: 5) {
                            Circle()
                                .fill(stockTone)
                                .frame(width: 7, height: 7)
                            Text(stockStatusText)
                                .font(Font.custom("Beiruti-Bold", size: 12))
                                .foregroundStyle(stockTone)
                            if currentQuantity > 0 {
                                Text("(\(currentQuantity.englishDigits))")
                                    .font(PPBrandFont.bold(size: 12))
                                    .foregroundStyle(stockTone.opacity(0.9))
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(stockTone.opacity(0.12), in: Capsule(style: .continuous))

                        // Price Badge
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 10))
                            Text(item.inventoryDisplayPrice)
                                .font(Font.custom("Beiruti-Bold", size: 13))
                        }
                        .foregroundStyle(AdminSurface.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))

                        if let barcode = item.barcode, !barcode.isEmpty {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showBarcodeStudio = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "barcode.viewfinder")
                                        .font(.system(size: 11))
                                    Text(barcode)
                                        .font(Font.system(size: 11, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(AdminSurface.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(AdminSurface.primary.opacity(0.12), in: Capsule(style: .continuous))
                            }
                            .buttonStyle(CatalogPressStyle())
                            .accessibilityLabel(Language.get("BarcodeStudio_Title", alter: "استوديو الباركود"))
                        }
                    }
                }

                Spacer(minLength: 0)

                // Dismiss Squircle
                AdminSquircleCloseButton {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider()
                .background(AdminSurface.hairline.opacity(0.7))

            // Two-Column Spatial Operations Matrix
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    // Column 1: Commercial Engine & Quick Controls
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AdminSurface.primary)
                            Text(Language.get("Commercial_Controls", alter: "التحكم المالي والتجاري"))
                                .font(Font.custom("Beiruti-Bold", size: 14))
                                .foregroundStyle(AdminCommandInk.secondary)
                        }
                        .padding(.horizontal, 2)

                        // Edit Full Specimen
                        heroLauncherCard(
                            title: Language.get("Edit", alter: "تعديل الصنف"),
                            subtitle: Language.get("ItemActions_Edit_Desc", alter: "المحرر الشامل للأسعار والصور والبيانات"),
                            icon: "square.and.pencil",
                            tint: AdminSurface.primary,
                            action: onOpenFullEditor
                        )

                        // Open in POS
                        heroLauncherCard(
                            title: Language.get("LivePet_Open_POS", alter: "فتح في نقطة البيع"),
                            subtitle: Language.get("ItemActions_POS_Desc", alter: "إضافة مباشرة للسلة وإصدار فاتورة سريعة"),
                            icon: "cart.fill.badge.plus",
                            tint: Color(uiColor: .ppSuccess),
                            action: onOpenPOS
                        )

                        // Barcode & Shelf Label Studio Launcher Row
                        actionHubRow(
                            title: Language.get("BarcodeStudio_Title", alter: "استوديو الباركود والملصقات"),
                            subtitle: Language.get("BarcodeStudio_Subtitle", alter: "معاينة، توليد، تعديل وطباعة الملصقات"),
                            icon: "barcode.viewfinder",
                            tint: AdminSurface.primary,
                            action: {
                                showBarcodeStudio = true
                            }
                        )

                        if item.isLivePet, let onEditBasicData = onEditBasicData {
                            actionHubRow(
                                title: Language.get("LivePet_EditBasicData", alter: "تعديل البيانات الأساسية"),
                                subtitle: Language.get("ItemActions_LivePet_Desc", alter: "تحديث السلالة، العمر، الجنس ورقم الحجل"),
                                icon: "pencil.and.list.clipboard",
                                tint: Color(uiColor: .ppInfo),
                                action: onEditBasicData
                            )
                        }

                        if !item.isLivePet, let onToggleStock = onToggleStock {
                            availabilityControllerCard(onToggle: onToggleStock)
                        }

                        if let onToggleAppMarket = onToggleAppMarket {
                            appMarketControllerCard(onToggle: onToggleAppMarket)
                        }

                        actionHubRow(
                            title: Language.get("Share", alter: "مشاركة الصنف"),
                            subtitle: Language.get("ItemActions_Share_Desc", alter: "مشاركة بطاقة الصنف والمواصفات"),
                            icon: "square.and.arrow.up",
                            tint: AdminCommandInk.secondary,
                            action: onShare
                        )
                    }
                    .frame(maxWidth: .infinity)

                    // Column 2: Logistics, Operations & Safety
                    VStack(alignment: .leading, spacing: 14) {
                        if !item.isLivePet {
                            HStack(spacing: 6) {
                                Image(systemName: "shippingbox.and.arrow.backward.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color(uiColor: .ppInfo))
                                Text(Language.get("Inventory_Ops_Section", alter: "عمليات المخزون والرقابة"))
                                    .font(Font.custom("Beiruti-Bold", size: 14))
                                    .foregroundStyle(AdminCommandInk.secondary)
                            }
                            .padding(.horizontal, 2)

                            VStack(spacing: 8) {
                                if let onManageLots = onManageLots {
                                    actionHubRow(
                                        title: Language.get("Inventory_Action_Manage_Lots", alter: "إدارة التشغيلات وتواريخ الصلاحية (FEFO)"),
                                        subtitle: Language.get("ItemActions_Lots_Desc", alter: "تتبع الدفعات وأولويات الصرف الذكية"),
                                        icon: "calendar.badge.clock",
                                        tint: Color(uiColor: .ppInfo),
                                        action: onManageLots
                                    )
                                }

                                if let onQuarantineStudio = onQuarantineStudio {
                                    actionHubRow(
                                        title: Language.get("Inventory_Action_Quarantine_Studio", alter: "استوديو الفحص والتصرف (الحجر)"),
                                        subtitle: Language.get("ItemActions_Quarantine_Desc", alter: "حجر العينات وفحص الجودة وإعادة التوجيه"),
                                        icon: "shield.lefthalf.filled",
                                        tint: Color(uiColor: .ppWarning),
                                        action: onQuarantineStudio
                                    )
                                }

                                if let onRecordDamage = onRecordDamage {
                                    actionHubRow(
                                        title: Language.get("Inventory_Action_Record_Damage", alter: "تسجيل إتلاف مخزون"),
                                        subtitle: Language.get("ItemActions_Damage_Desc", alter: "توثيق التالف وإسقاط الكميات رسمياً"),
                                        icon: "exclamationmark.octagon.fill",
                                        tint: Color(uiColor: .ppError),
                                        action: onRecordDamage
                                    )
                                }

                                if let onTransferStock = onTransferStock, currentQuantity > 0 {
                                    actionHubRow(
                                        title: Language.get("Stock_Transfer_Action", alter: "نقل كمية إلى فرع آخر"),
                                        subtitle: Language.get("ItemActions_Transfer_Desc", alter: "مناقلة المخزون بين الفروع المعتمدة"),
                                        icon: "arrow.left.arrow.right",
                                        tint: Color(uiColor: .ppSuccess),
                                        trailingPill: "\(Language.get("Available", alter: "متاح")): \(currentQuantity.englishDigits)",
                                        action: onTransferStock
                                    )
                                }
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(uiColor: .ppError))
                            Text(Language.get("Safety_Sector", alter: "الإجراءات الحرجة والأمان"))
                                .font(Font.custom("Beiruti-Bold", size: 14))
                                .foregroundStyle(Color(uiColor: .ppError).opacity(0.85))
                        }
                        .padding(.horizontal, 2)

                        destructiveSafetyCard(onDelete: onDelete)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
        }
        .frame(width: cockpitWidth, height: cockpitHeight)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.24), radius: 32, x: 0, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.85), lineWidth: 0.8)
        )
    }

    // MARK: - Tactical Card Primitives

    @ViewBuilder
    private func heroLauncherCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.14))
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 36, height: 36)

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.backward")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.08), tint.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 0.8)
            )
        }
        .buttonStyle(PPCockpitPressStyle())
    }

    @ViewBuilder
    private func actionHubRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        trailingPill: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.12))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 38, height: 38)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 0.75)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let pill = trailingPill {
                    Text(pill)
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.12), in: Capsule(style: .continuous))
                }

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AdminCommandInk.tertiary.opacity(0.6))
            }
            .padding(10)
            .background(AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.75)
            )
        }
        .buttonStyle(PPCockpitPressStyle())
    }

    @ViewBuilder
    private func availabilityControllerCard(onToggle: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onToggle()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(item.noStock ? Color(uiColor: .ppError).opacity(0.12) : Color(uiColor: .ppSuccess).opacity(0.12))
                    Image(systemName: item.noStock ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(item.noStock ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess))
                }
                .frame(width: 38, height: 38)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder((item.noStock ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess)).opacity(0.22), lineWidth: 0.75)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.noStock ? Language.get("MarkInStock", alter: "تفعيل التوفر بالمخزون") : Language.get("MarkOutOfStock", alter: "تعيين كنفاذ المخزون"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(item.noStock ? Language.get("ItemActions_Inactive_Desc", alter: "الصنف موقوف حالياً من العرض بالمخزون") : Language.get("ItemActions_Active_Desc", alter: "الصنف نشط وجاهز للطلب والبيع"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // State Pill Toggle
                Text(item.noStock ? Language.get("Action_Enable", alter: "تفعيل") : Language.get("Action_Disable", alter: "إيقاف"))
                    .font(Font.custom("Beiruti-Bold", size: 12))
                    .foregroundStyle(item.noStock ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((item.noStock ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.12), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder((item.noStock ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.3), lineWidth: 0.75)
                    )
            }
            .padding(10)
            .background(AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.75)
            )
        }
        .buttonStyle(PPCockpitPressStyle())
    }

    @ViewBuilder
    private func appMarketControllerCard(onToggle: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onToggle()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(item.showInAppMarket ? Color(uiColor: .systemIndigo).opacity(0.12) : AdminSurface.secondaryText.opacity(0.12))
                    Image(systemName: item.showInAppMarket ? "storefront.fill" : "eye.slash.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText)
                }
                .frame(width: 38, height: 38)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder((item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText).opacity(0.22), lineWidth: 0.75)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("AppMarket_Visibility_Title", alter: "العرض في متجر التطبيق"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(item.showInAppMarket ? Language.get("AppMarket_Currently_Visible", alter: "الصنف معروض للعملاء في تطبيق Pure Pets") : Language.get("AppMarket_Currently_Hidden", alter: "مخفي عن متجر التطبيق ومتاح للكاشير فقط"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // State Pill Toggle
                Text(item.showInAppMarket ? Language.get("AppMarket_Status_Visible", alter: "معروض") : Language.get("AppMarket_Status_Hidden", alter: "مخفي"))
                    .font(Font.custom("Beiruti-Bold", size: 12))
                    .foregroundStyle(item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText).opacity(0.12), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder((item.showInAppMarket ? Color(uiColor: .systemIndigo) : AdminSurface.secondaryText).opacity(0.3), lineWidth: 0.75)
                    )
            }
            .padding(10)
            .background(AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.75)
            )
        }
        .buttonStyle(PPCockpitPressStyle())
    }

    @ViewBuilder
    private func destructiveSafetyCard(onDelete: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDelete()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .ppError).opacity(0.12))
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(uiColor: .ppError))
                }
                .frame(width: 38, height: 38)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppError).opacity(0.25), lineWidth: 0.75)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Delete", alter: "حذف من المخزون"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(Color(uiColor: .ppError))
                        .lineLimit(1)

                    Text(Language.get("ItemActions_Delete_Warning", alter: "إسقاط نهائي من قاعدة البيانات - يتطلب تأكيداً"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(Color(uiColor: .ppError).opacity(0.75))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .ppError).opacity(0.8))
            }
            .padding(10)
            .background(Color(uiColor: .ppError).opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppError).opacity(0.25), lineWidth: 0.75)
            )
        }
        .buttonStyle(PPCockpitPressStyle())
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
                    if let nav = self.navigationController {
                        nav.pushViewController(editVC, animated: true)
                    } else {
                        PPAdminNavigationFallback.presentOrPush(editVC, from: self)
                    }
                }
            },
            onOpenPOS: { [weak self] in
                guard let self = self else { return }
                if let block = self.onOpenPOS {
                    block()
                } else if let controller = PPAdminRouteFactory.viewController(routeIdentifier: "pos", payload: self.item.accessoryID) {
                    if let nav = self.navigationController {
                        nav.pushViewController(controller, animated: true)
                    } else {
                        PPAdminNavigationFallback.presentOrPush(controller, from: self)
                    }
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

        let host = UIHostingController(
            rootView: detailView.environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        )
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
            },
            onToggleAppMarket: {
                viewModel.toggleAppMarketVisibility(for: item)
            }
        )
    }
}

// MARK: - Live-Pet Specimen Profile Editor Sheet (Category-Defining Studio)

private struct PPLivePetUnitProfileEditorSheet: View {
    let unit: PPLivePetInventoryUnit
    @ObservedObject var model: PPLivePetOperationsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Form state
    @State private var ringTag: String
    @State private var selectedGender: PPLivePetUnitGender
    @State private var sellingPriceText: String
    @State private var notes: String
    @State private var photoDraft: PPLivePetUnitPhotoDraft? = nil
    @State private var existingPhotoRemoved: Bool = false
    @State private var selectedSubSubKindID: Int?
    @State private var selectedSubSubKindNameAr: String?
    @State private var selectedSubSubKindNameEn: String?
    @State private var selectedSubSubKindItemID: Int?
    @State private var selectedSubSubKindItemNameAr: String?
    @State private var selectedSubSubKindItemNameEn: String?

    // Media picking sheets
    @State private var showPhotoSourceDialog: Bool = false
    @State private var showPhotoLibrary: Bool = false
    @State private var showCamera: Bool = false
    @State private var showCameraAccessAlert: Bool = false
    @State private var previewMedia: PPLivePetPreviewMedia? = nil

    // Interaction & execution states
    @State private var isSubmitting: Bool = false
    @State private var submissionStep: SubmissionStep = .idle
    @State private var validationError: String? = nil

    private enum SubmissionStep {
        case idle
        case uploadingPhoto
        case savingProfile

        var message: String {
            switch self {
            case .idle:
                return ""
            case .uploadingPhoto:
                return Language.get("LivePet_Profile_Save_Uploading", alter: "جارٍ تجهيز ورفع صورة الحيوان...")
            case .savingProfile:
                return Language.get("LivePet_Profile_Save_Committing", alter: "جارٍ حفظ البيانات وتحديث السجل...")
            }
        }
    }

    private let quickNotesTags: [String] = [
        Language.get("LivePet_Profile_Tag_Vaccinated", alter: "تطعيم مكتمل"),
        Language.get("LivePet_Profile_Tag_HealthOK", alter: "صحة ممتازة"),
        Language.get("LivePet_Profile_Tag_SpecialDiet", alter: "تغذية خاصة"),
        Language.get("LivePet_Profile_Tag_Docile", alter: "أليف وهادئ")
    ]

    init(unit: PPLivePetInventoryUnit, model: PPLivePetOperationsViewModel) {
        self.unit = unit
        self.model = model
        let liveUnit = model.units.first(where: { $0.id == unit.id }) ?? unit
        _ringTag = State(initialValue: liveUnit.ringTag)
        _selectedGender = State(initialValue: liveUnit.gender)
        _notes = State(initialValue: liveUnit.notes)
        if let price = liveUnit.sellingPrice, price > 0 {
            _sellingPriceText = State(initialValue: String(format: "%g", price))
        } else if let stdPrice = model.item.standardSellingPrice?.doubleValue ?? (model.item.price.doubleValue > 0 ? model.item.price.doubleValue : nil) {
            _sellingPriceText = State(initialValue: String(format: "%g", stdPrice))
        } else {
            _sellingPriceText = State(initialValue: "")
        }
        _selectedSubSubKindID = State(initialValue: liveUnit.subSubKindID)
        _selectedSubSubKindNameAr = State(initialValue: liveUnit.subSubKindNameAr)
        _selectedSubSubKindNameEn = State(initialValue: liveUnit.subSubKindNameEn)
        _selectedSubSubKindItemID = State(initialValue: liveUnit.subSubKindItemID)
        _selectedSubSubKindItemNameAr = State(initialValue: liveUnit.subSubKindItemNameAr)
        _selectedSubSubKindItemNameEn = State(initialValue: liveUnit.subSubKindItemNameEn)
    }

    private var currentLiveUnit: PPLivePetInventoryUnit {
        model.units.first(where: { $0.id == unit.id }) ?? unit
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    private var isDirty: Bool {
        let live = currentLiveUnit
        let livePriceText = live.sellingPrice != nil ? String(format: "%g", live.sellingPrice!) : ""
        let currentPriceText = sellingPriceText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
        return ringTag.trimmingCharacters(in: .whitespacesAndNewlines) != live.ringTag ||
            selectedGender != live.gender ||
            notes.trimmingCharacters(in: .whitespacesAndNewlines) != live.notes ||
            currentPriceText != livePriceText ||
            photoDraft != nil ||
            existingPhotoRemoved ||
            selectedSubSubKindID != live.subSubKindID ||
            selectedSubSubKindItemID != live.subSubKindItemID
    }

    private var effectivePhotoURL: URL? {
        if existingPhotoRemoved { return nil }
        return currentLiveUnit.mediaURLs.first.flatMap { URL(string: $0) }
    }

    private var hasActivePhoto: Bool {
        photoDraft != nil || effectivePhotoURL != nil
    }

    private var standardCatalogPrice: Double {
        model.item.standardSellingPrice?.doubleValue ?? model.item.price.doubleValue
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                Group {
                    if isPad {
                        iPadStudioLayout
                    } else {
                        iPhoneMobileLayout
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        if isDirty {
                            promptDiscardChanges()
                        } else {
                            dismiss()
                        }
                    }
                    .font(Font.custom("Beiruti-Medium", size: 16))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .disabled(isSubmitting)
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(Language.get("LivePet_Profile_Studio_Title", alter: "ملف الحيوان والبيانات الحية"))
                            .font(Font.custom("Beiruti-Bold", size: 17))
                            .foregroundStyle(AdminCommandInk.primary)
                        Text(verbatim: (unit.ringTag.isEmpty ? unit.id : unit.ringTag).normalizedEnglishDigits)
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { Task { await commitProfile() } }) {
                        if isSubmitting {
                            ProgressView()
                                .tint(AdminSurface.primary)
                        } else {
                            Text(Language.get("Save", alter: "حفظ"))
                                .font(Font.custom("Beiruti-Bold", size: 16))
                                .foregroundStyle(AdminSurface.primary)
                        }
                    }
                    .disabled(isSubmitting)
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
            .confirmationDialog(
                Language.get("LivePet_Profile_Hero_Photo", alter: "صورة الحيوان الحية"),
                isPresented: $showPhotoSourceDialog,
                titleVisibility: .visible
            ) {
                Button(Language.get("LivePet_Profile_Camera_Capture", alter: "التقاط بالكاميرا")) {
                    requestCamera()
                }
                Button(Language.get("LivePet_Profile_Library_Select", alter: "اختيار من الألبوم")) {
                    showPhotoLibrary = true
                }
                if hasActivePhoto {
                    Button(Language.get("LivePet_Profile_Remove_Photo", alter: "إزالة الصورة الحالية"), role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            photoDraft = nil
                            existingPhotoRemoved = true
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
                Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
            }
            .sheet(isPresented: $showPhotoLibrary) {
                PPLivePetPhotoPicker(maxSelection: 1) { images, _ in
                    if let image = images.first {
                        acceptSelectedPhoto(image)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                PPLivePetCameraPicker { image in
                    acceptSelectedPhoto(image)
                }
            }
            .alert(
                Language.get("LivePetIntake_UnitPhotoCameraPermissionTitle", alter: "السماح باستخدام الكاميرا"),
                isPresented: $showCameraAccessAlert
            ) {
                Button(Language.get("LivePetIntake_OpenSettings", alter: "فتح الإعدادات")) {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
            } message: {
                Text(Language.get("LivePetIntake_UnitPhotoCameraPermissionMessage", alter: "فعّل إذن الكاميرا من الإعدادات لالتقاط صورة خاصة بهذا الحيوان."))
                    .font(Font.custom("Beiruti-Regular", size: 14))
            }
            .fullScreenCover(item: $previewMedia) { media in
                PPLivePetMediaPreview(media: media)
            }
            .onAppear {
                model.fetchTaxonomy()
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - iPhone Mobile Layout
    private var iPhoneMobileLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = validationError {
                    errorBanner(error)
                }

                if isSubmitting {
                    submissionStatusBanner
                }

                // 1. Specimen Photo Hero
                iPhonePhotoHeroCard

                // 2. Ring ID / Tag
                ringTagCard

                // 3. Biological Sex
                genderSelectorCard

                // 4. SubSubKind & Variety
                subSubKindCard

                // 5. Selling Price
                sellingPriceCard

                // 6. Clinical & Internal Notes
                notesCard

                // Primary Bottom CTA
                Button(action: { Task { await commitProfile() } }) {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                            Text(submissionStep.message)
                                .font(Font.custom("Beiruti-Bold", size: 16))
                                .foregroundStyle(Color.white)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text(Language.get("LivePet_Profile_Save_Button", alter: "حفظ وتثبيت التعديلات"))
                                .font(Font.custom("Beiruti-Bold", size: 17))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AdminSurface.primary)
                    )
                }
                .disabled(isSubmitting)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - iPad Studio Layout
    private var iPadStudioLayout: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 24) {
                // Left Studio Bay: Specimen Media & Identity HUD
                VStack(spacing: 18) {
                    iPadPhotoStudioBay
                    iPadSpecimenHUDCard
                    Spacer(minLength: 0)
                }
                .frame(width: max(320, min(380, geometry.size.width * 0.40)))

                // Right Dossier Bay: Editable Parameters
                ScrollView {
                    VStack(spacing: 18) {
                        if let error = validationError {
                            errorBanner(error)
                        }

                        if isSubmitting {
                            submissionStatusBanner
                        }

                        // Product Taxonomy Breadcrumb
                        iPadTaxonomyHeader

                        // 1. Ring Tag / Microchip
                        ringTagCard

                        // 2. Biological Sex
                        iPadGenderCards

                        // 3. SubSubKind & Variety
                        subSubKindCard

                        // 4. Selling Price Deck
                        sellingPriceCard

                        // 5. Clinical & Internal Notes
                        notesCard

                        // Bottom Actions
                        HStack(spacing: 14) {
                            Button(action: {
                                if isDirty { promptDiscardChanges() } else { dismiss() }
                            }) {
                                Text(Language.get("Cancel", alter: "إلغاء"))
                                    .font(Font.custom("Beiruti-Bold", size: 16))
                                    .foregroundStyle(AdminCommandInk.secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                                    )
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)

                            Button(action: { Task { await commitProfile() } }) {
                                HStack(spacing: 10) {
                                    if isSubmitting {
                                        ProgressView()
                                            .tint(.white)
                                        Text(submissionStep.message)
                                            .font(Font.custom("Beiruti-Bold", size: 16))
                                            .foregroundStyle(Color.white)
                                    } else {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(Color.white)
                                        Text(Language.get("LivePet_Profile_Save_Button", alter: "حفظ وتثبيت التعديلات"))
                                            .font(Font.custom("Beiruti-Bold", size: 17))
                                            .foregroundStyle(Color.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                            .disabled(isSubmitting)
                        }
                        .padding(.top, 6)
                        .padding(.bottom, 24)
                    }
                    .padding(.trailing, 4)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Subviews: Photo Handling

    private var iPhonePhotoHeroCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ZStack {
                    if let draft = photoDraft {
                        Image(uiImage: draft.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 190)
                            .clipped()
                    } else if let url = effectivePhotoURL {
                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 400, height: 200)) {
                            photoPlaceholderView
                        }
                        .frame(height: 190)
                        .clipped()
                    } else {
                        photoPlaceholderView
                            .frame(height: 190)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(AdminSurface.control)

                // Bottom Action Bar over photo
                HStack(spacing: 8) {
                    Button(action: { showPhotoSourceDialog = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(hasActivePhoto
                                 ? Language.get("LivePet_Profile_Replace_Photo", alter: "تغيير الصورة")
                                 : Language.get("LivePet_Profile_Hero_Photo", alter: "إضافة صورة"))
                                .font(Font.custom("Beiruti-Bold", size: 13))
                        }
                        .foregroundStyle(AdminCommandInk.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)

                    if hasActivePhoto {
                        Button(action: {
                            if let draft = photoDraft {
                                previewMedia = PPLivePetPreviewMedia(source: .local(draft.image))
                            } else if let url = effectivePhotoURL {
                                previewMedia = PPLivePetPreviewMedia(source: .remote(url))
                            }
                        }) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AdminCommandInk.primary)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                photoDraft = nil
                                existingPhotoRemoved = true
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(uiColor: .ppError))
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer()
                    }
                }
                .padding(12)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.6), Color.clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var photoPlaceholderView: some View {
        Button(action: { showPhotoSourceDialog = true }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "camera.badge.ellipsis")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(AdminSurface.primary)
                }
                Text(Language.get("LivePet_Profile_Hero_Photo", alter: "صورة الحيوان الحية"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminCommandInk.primary)
                Text(Language.get("LivePet_Profile_Studio_Subtitle", alter: "اضغط لالتقاط بالكاميرا أو اختيار من الألبوم"))
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(AdminCommandInk.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var iPadPhotoStudioBay: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                ZStack {
                    if let draft = photoDraft {
                        Image(uiImage: draft.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 310)
                            .clipped()
                    } else if let url = effectivePhotoURL {
                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 500, height: 400)) {
                            photoPlaceholderView
                        }
                        .frame(height: 310)
                        .clipped()
                    } else {
                        photoPlaceholderView
                            .frame(height: 310)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(AdminSurface.control)

                // Studio inspection button top trailing
                if hasActivePhoto {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                                if let draft = photoDraft {
                                    previewMedia = PPLivePetPreviewMedia(source: .local(draft.image))
                                } else if let url = effectivePhotoURL {
                                    previewMedia = PPLivePetPreviewMedia(source: .remote(url))
                                }
                            }) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AdminCommandInk.primary)
                                    .padding(9)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                            .padding(12)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 310)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )

            // Capture Actions
            HStack(spacing: 10) {
                Button(action: { requestCamera() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(Language.get("LivePet_Profile_Camera_Capture", alter: "التقاط بالكاميرا"))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                    }
                    .foregroundStyle(AdminSurface.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)

                Button(action: { showPhotoLibrary = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 14, weight: .bold))
                        Text(Language.get("LivePet_Profile_Library_Select", alter: "من الألبوم"))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                    }
                    .foregroundStyle(AdminCommandInk.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
            }

            if hasActivePhoto {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        photoDraft = nil
                        existingPhotoRemoved = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .bold))
                        Text(Language.get("LivePet_Profile_Remove_Photo", alter: "إزالة الصورة الحالية"))
                            .font(Font.custom("Beiruti-Medium", size: 13))
                    }
                    .foregroundStyle(Color(uiColor: .ppError))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
            }
        }
    }

    private var iPadSpecimenHUDCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("LivePet_Sector_Identity", alter: "بيانات العهدة الحية"))
                .font(Font.custom("Beiruti-Bold", size: 13))
                .foregroundStyle(AdminCommandInk.secondary)

            HStack {
                Text(Language.get("LivePet_Status_Label", alter: "الحالة"))
                    .font(Font.custom("Beiruti-Regular", size: 13))
                    .foregroundStyle(AdminCommandInk.secondary)
                Spacer()
                Text(verbatim: currentLiveUnit.status)
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(currentLiveUnit.status == "AVAILABLE" ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        (currentLiveUnit.status == "AVAILABLE" ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.12),
                        in: Capsule()
                    )
            }

            if !currentLiveUnit.currentBranchID.isEmpty {
                HStack {
                    Text(Language.get("LivePet_Branch_Label", alter: "الفرع الحالي"))
                        .font(Font.custom("Beiruti-Regular", size: 13))
                        .foregroundStyle(AdminCommandInk.secondary)
                    Spacer()
                    let bName = model.branches.first(where: { $0.id == currentLiveUnit.currentBranchID })?.displayName ?? currentLiveUnit.currentBranchID
                    Text(verbatim: bName)
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminCommandInk.primary)
                }
            }

            HStack {
                Text(Language.get("LivePet_UnitID_Label", alter: "معرف السجل"))
                    .font(Font.custom("Beiruti-Regular", size: 13))
                    .foregroundStyle(AdminCommandInk.secondary)
                Spacer()
                Text(verbatim: String(currentLiveUnit.id.prefix(16)))
                    .font(Font.custom("Beiruti-Medium", size: 12))
                    .foregroundStyle(AdminCommandInk.tertiary)
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var iPadTaxonomyHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.item.name)
                    .font(Font.custom("Beiruti-Bold", size: 18))
                    .foregroundStyle(AdminCommandInk.primary)
                    .lineLimit(1)

                let sub = selectedSubSubKindID != nil ? currentSubSubKindTitle : currentLiveUnit.subSubKindName
                if let sub, !sub.isEmpty {
                    Text(verbatim: sub)
                        .font(Font.custom("Beiruti-Regular", size: 13))
                        .foregroundStyle(AdminCommandInk.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Subviews: Form Cards

    private var ringTagCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("LivePet_Profile_RingTag_Title", alter: "رقم الحجل / الشريحة التعريفية"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminCommandInk.primary)
                Spacer()
            }

            HStack(spacing: 10) {
                TextField(
                    Language.get("LivePet_Profile_RingTag_Prompt", alter: "رقم الحجل أو الرمز التعريفي"),
                    text: Binding(get: {
                        ringTag
                    }, set: {
                        ringTag = $0.normalizedEnglishDigits(allowsDecimal: false)
                    })
                )
                .font(Font.custom("Beiruti-SemiBold", size: 16))
                .foregroundStyle(AdminCommandInk.primary)
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )
            }

            Text(Language.get("LivePet_Profile_RingTag_Hint", alter: "الرمز التعريفي الفريد لهذا الحيوان داخل النظام والكتالوج."))
                .font(Font.custom("Beiruti-Regular", size: 12))
                .foregroundStyle(AdminCommandInk.secondary)
                .padding(.horizontal, 2)
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var genderSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "circle.circle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("LivePet_Profile_Gender_Title", alter: "الجنس البيولوجي"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminCommandInk.primary)
                Spacer()
            }

            // Tactile 4-pill selector
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(PPLivePetUnitGender.allCases) { gender in
                    let isSelected = selectedGender == gender
                    let tint = Color(uiColor: gender.tint)

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedGender = gender
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: gender.symbolName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(tint)

                            Text(gender.localizedTitle)
                                .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 15))
                                .foregroundStyle(AdminCommandInk.primary)

                            Spacer(minLength: 0)

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(tint)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            isSelected ? tint.opacity(0.14) : AdminSurface.control,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isSelected ? tint : AdminSurface.hairline,
                                    lineWidth: isSelected ? 1.5 : 0.75
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var iPadGenderCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "circle.circle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("LivePet_Profile_Gender_Title", alter: "الجنس البيولوجي"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminCommandInk.primary)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(PPLivePetUnitGender.allCases) { gender in
                    let isSelected = selectedGender == gender
                    let tint = Color(uiColor: gender.tint)

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedGender = gender
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(tint.opacity(isSelected ? 0.25 : 0.12))
                                    .frame(width: 38, height: 38)
                                Image(systemName: gender.symbolName)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(tint)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(gender.localizedTitle)
                                    .font(Font.custom("Beiruti-Bold", size: 16))
                                    .foregroundStyle(AdminCommandInk.primary)
                                Text(verbatim: gender.rawValue)
                                    .font(Font.custom("Beiruti-Regular", size: 11))
                                    .foregroundStyle(AdminCommandInk.tertiary)
                            }

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(tint)
                            }
                        }
                        .padding(12)
                        .background(
                            isSelected ? tint.opacity(0.12) : AdminSurface.control,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    isSelected ? tint : AdminSurface.hairline,
                                    lineWidth: isSelected ? 1.5 : 0.75
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - SubSubKind & Variety Taxonomy Card

    private var shouldShowSubSubKindCard: Bool {
        model.hasSubSubKinds || !model.availableSubSubKinds.isEmpty || selectedSubSubKindID != nil || model.isLoadingSubSubTaxonomy
    }

    private var availableSubSubKindItems: [AdminSubKindItemDetail] {
        guard let id = selectedSubSubKindID else { return [] }
        return model.subSubKindItemsBySubSubID[id] ?? []
    }

    private var hasSelectedSubSub: Bool {
        selectedSubSubKindID != nil
    }

    private var hasSelectedSubSubItem: Bool {
        selectedSubSubKindItemID != nil
    }

    private var showSubSubKindItemSelector: Bool {
        hasSelectedSubSub && (!availableSubSubKindItems.isEmpty || hasSelectedSubSubItem)
    }

    private var currentSubSubKindTitle: String {
        if let selected = model.availableSubSubKinds.first(where: { $0.numericID == selectedSubSubKindID }) {
            return selected.localizedName
        }
        if Language.isRTL() {
            if let ar = selectedSubSubKindNameAr, !ar.isEmpty { return ar }
            if let en = selectedSubSubKindNameEn, !en.isEmpty { return en }
        } else {
            if let en = selectedSubSubKindNameEn, !en.isEmpty { return en }
            if let ar = selectedSubSubKindNameAr, !ar.isEmpty { return ar }
        }
        return Language.get("LivePet_Profile_SubSubKind_Prompt", alter: "اختر التفريع الفرعي...")
    }

    private var currentSubSubKindItemTitle: String {
        if let subSubID = selectedSubSubKindID,
           let selected = availableSubSubKindItems.first(where: { $0.numericID == selectedSubSubKindItemID }) {
            return selected.localizedName
        }
        if Language.isRTL() {
            if let ar = selectedSubSubKindItemNameAr, !ar.isEmpty { return ar }
            if let en = selectedSubSubKindItemNameEn, !en.isEmpty { return en }
        } else {
            if let en = selectedSubSubKindItemNameEn, !en.isEmpty { return en }
            if let ar = selectedSubSubKindItemNameAr, !ar.isEmpty { return ar }
        }
        return Language.get("LivePet_Profile_SubSubKind_Item_Prompt", alter: "اختر عنصر التفريع / الطفرة...")
    }

    private func selectSubSubKind(_ subSub: AdminSubSubKindItem?) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            if let subSub = subSub {
                selectedSubSubKindID = subSub.numericID
                selectedSubSubKindNameAr = subSub.nameAr
                selectedSubSubKindNameEn = subSub.nameEn
            } else {
                selectedSubSubKindID = nil
                selectedSubSubKindNameAr = nil
                selectedSubSubKindNameEn = nil
            }
            selectedSubSubKindItemID = nil
            selectedSubSubKindItemNameAr = nil
            selectedSubSubKindItemNameEn = nil
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func selectSubSubKindItem(_ item: AdminSubKindItemDetail?) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            if let item = item {
                selectedSubSubKindItemID = item.numericID
                selectedSubSubKindItemNameAr = item.itemNameAr
                selectedSubSubKindItemNameEn = item.itemNameEn
            } else {
                selectedSubSubKindItemID = nil
                selectedSubSubKindItemNameAr = nil
                selectedSubSubKindItemNameEn = nil
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @ViewBuilder
    private var subSubKindCard: some View {
        if shouldShowSubSubKindCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("LivePet_Profile_SubSubKind_Title", alter: "التفريع الفرعي واللون / الطفرة"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminCommandInk.primary)
                    Spacer()
                    if model.isLoadingSubSubTaxonomy {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(AdminSurface.primary)
                    }
                }

                // 1. SubSubKind Selector Menu
                VStack(alignment: .leading, spacing: 5) {
                    Text(Language.get("LivePetIntake_SubSubKindLabel", alter: "التفريع الفرعي (SubSubKind)"))
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminCommandInk.secondary)

                    HStack(spacing: 8) {
                        Menu {
                            Button(role: .destructive) {
                                selectSubSubKind(nil)
                            } label: {
                                Label(Language.get("LivePet_Profile_SubSubKind_None", alter: "بدون تفريع"), systemImage: "xmark.circle")
                            }

                            if !model.availableSubSubKinds.isEmpty {
                                Divider()
                                ForEach(model.availableSubSubKinds) { subSub in
                                    Button {
                                        selectSubSubKind(subSub)
                                    } label: {
                                        HStack {
                                            Text(subSub.localizedName)
                                            if selectedSubSubKindID == subSub.numericID {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(hasSelectedSubSub ? AdminSurface.primary : AdminCommandInk.tertiary)

                                Text(currentSubSubKindTitle)
                                    .font(Font.custom(hasSelectedSubSub ? "Beiruti-Bold" : "Beiruti-Regular", size: 15))
                                    .foregroundStyle(hasSelectedSubSub ? AdminCommandInk.primary : AdminCommandInk.tertiary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AdminCommandInk.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                hasSelectedSubSub ? AdminSurface.primary.opacity(0.06) : AdminSurface.control,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        hasSelectedSubSub ? AdminSurface.primary.opacity(0.35) : AdminSurface.hairline,
                                        lineWidth: hasSelectedSubSub ? 1 : 0.75
                                    )
                            )
                        }
                        .buttonStyle(.plain)

                        if hasSelectedSubSub {
                            Button {
                                selectSubSubKind(nil)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(AdminCommandInk.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 2. SubSubKindItem Selector Menu
                if showSubSubKindItemSelector {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Language.get("LivePetIntake_SubSubKindItemLabel", alter: "عنصر التفريع / الطفرة اللونية (SubSubKindItem)"))
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminCommandInk.secondary)

                        HStack(spacing: 8) {
                            Menu {
                                Button(role: .destructive) {
                                    selectSubSubKindItem(nil)
                                } label: {
                                    Label(Language.get("LivePet_Profile_SubSubKind_Item_None", alter: "بدون عنصر"), systemImage: "xmark.circle")
                                }

                                if !availableSubSubKindItems.isEmpty {
                                    Divider()
                                    ForEach(availableSubSubKindItems) { item in
                                        Button {
                                            selectSubSubKindItem(item)
                                        } label: {
                                            HStack {
                                                Text(item.localizedName)
                                                if selectedSubSubKindItemID == item.numericID {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "tag.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(hasSelectedSubSubItem ? AdminSurface.primary : AdminCommandInk.tertiary)

                                    Text(currentSubSubKindItemTitle)
                                        .font(Font.custom(hasSelectedSubSubItem ? "Beiruti-Bold" : "Beiruti-Regular", size: 15))
                                        .foregroundStyle(hasSelectedSubSubItem ? AdminCommandInk.primary : AdminCommandInk.tertiary)
                                        .lineLimit(1)

                                    Spacer(minLength: 0)

                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AdminCommandInk.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    hasSelectedSubSubItem ? AdminSurface.primary.opacity(0.06) : AdminSurface.control,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            hasSelectedSubSubItem ? AdminSurface.primary.opacity(0.35) : AdminSurface.hairline,
                                            lineWidth: hasSelectedSubSubItem ? 1 : 0.75
                                        )
                                )
                            }
                            .buttonStyle(.plain)

                            if hasSelectedSubSubItem {
                                Button {
                                    selectSubSubKindItem(nil)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(AdminCommandInk.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Text(Language.get("LivePet_Profile_SubSubKind_Hint", alter: "تحديد السلالة الفرعية أو الطفرة اللونية الخاصة بهذا الحيوان في الكتالوج."))
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .padding(.horizontal, 2)
            }
            .padding(16)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
    }

    private var sellingPriceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "banknote")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("LivePet_Profile_SellingPrice_Title", alter: "سعر البيع الفردي المعتمد"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminCommandInk.primary)
                Spacer()
            }

            HStack(spacing: 12) {
                TextField(
                    Language.get("LivePet_Profile_SellingPrice_Prompt", alter: "سعر البيع"),
                    text: Binding(get: {
                        sellingPriceText
                    }, set: {
                        sellingPriceText = $0.normalizedEnglishDigits(allowsDecimal: true)
                    })
                )
                .font(Font.custom("Beiruti-Bold", size: 22))
                .foregroundStyle(AdminCommandInk.primary)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )

                Text(Language.get("QAR", alter: "ر.ق"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if standardCatalogPrice > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(AdminCommandInk.tertiary)
                    Text(Language.get("LivePet_Profile_Catalog_Standard_Price", alter: "سعر الكتالوج الموحد:"))
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminCommandInk.secondary)
                    Text(verbatim: PetAccessory.formatCurrency(NSNumber(value: standardCatalogPrice)))
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundStyle(AdminCommandInk.primary)
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("LivePet_Profile_Notes_Title", alter: "السجل الطبي والملاحظات الداخلية"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminCommandInk.primary)
                Spacer()
                Text("\(notes.count)/500")
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(AdminCommandInk.tertiary)
            }

            // Quick suggestion chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickNotesTags, id: \.self) { tag in
                        Button(action: {
                            appendTagToNotes(tag)
                        }) {
                            Text(verbatim: tag)
                                .font(Font.custom("Beiruti-Medium", size: 13))
                                .foregroundStyle(AdminSurface.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                                .overlay(Capsule().strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text(Language.get("LivePet_Profile_Notes_Prompt", alter: "ملاحظات السلوك، التغذية، الفحص الطبي..."))
                        .font(Font.custom("Beiruti-Regular", size: 14))
                        .foregroundStyle(AdminCommandInk.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }

                TextEditor(text: Binding(get: {
                    notes
                }, set: {
                    if $0.count <= 500 { notes = $0 }
                }))
                .font(Font.custom("Beiruti-Regular", size: 14))
                .foregroundStyle(AdminCommandInk.primary)
                .frame(minHeight: 80)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(uiColor: .ppError))
            Text(verbatim: message)
                .font(Font.custom("Beiruti-Medium", size: 14))
                .foregroundStyle(Color(uiColor: .ppError))
            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .ppError).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(uiColor: .ppError).opacity(0.35), lineWidth: 0.75)
        )
    }

    private var submissionStatusBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(AdminSurface.primary)
            Text(submissionStep.message)
                .font(Font.custom("Beiruti-SemiBold", size: 14))
                .foregroundStyle(AdminCommandInk.primary)
            Spacer()
        }
        .padding(14)
        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 0.75)
        )
    }

    // MARK: - Actions & Mutations

    private func appendTagToNotes(_ tag: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.isEmpty {
            notes = clean
        } else if !notes.contains(clean) {
            notes = "\(notes) - \(clean)"
        }
    }

    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            validationError = Language.get(
                "LivePetIntake_UnitPhotoCameraUnavailable",
                alter: "الكاميرا غير متاحة على هذا الجهاز. اختر صورة من المكتبة."
            )
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.showCamera = true
                    } else {
                        self.showCameraAccessAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraAccessAlert = true
        @unknown default:
            showCamera = true
        }
    }

    private func acceptSelectedPhoto(_ image: UIImage) {
        if let draft = PPLivePetUnitPhotoStorageService.prepareLivePetUnitPhoto(image) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                photoDraft = draft
                existingPhotoRemoved = false
                validationError = nil
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            validationError = Language.get(
                "LivePet_Profile_Error_UploadFailed",
                alter: "تعذر استيراد الصورة المحددة. اختر صورة أخرى وحاول مجدداً."
            )
        }
    }

    private func commitProfile() async {
        let trimmedRing = ringTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRing.isEmpty else {
            validationError = Language.get("LivePet_Profile_Error_RingEmpty", alter: "يرجى كتابة رقم الحجل أو الرمز التعريفي للحيوان.")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        let cleanPriceText = sellingPriceText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
        guard let price = Double(cleanPriceText), price > 0, price <= 999_999_999.99,
              abs(price * 100 - (price * 100).rounded()) < 0.000001 else {
            validationError = Language.get("LivePet_Profile_Error_InvalidPrice", alter: "يرجى إدخال سعر بيع صحيح وموجب وبحد أقصى منزلتين عشريتين.")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        validationError = nil
        isSubmitting = true
        if photoDraft != nil {
            submissionStep = .uploadingPhoto
        } else {
            submissionStep = .savingProfile
        }

        let commandID = UUID().uuidString
        let ok = await model.updateUnitProfile(
            unit: unit,
            ringTag: trimmedRing,
            gender: selectedGender,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            sellingPrice: price,
            photoDraft: photoDraft,
            removeExistingPhoto: existingPhotoRemoved,
            subSubKindID: selectedSubSubKindID,
            subSubKindNameAr: selectedSubSubKindNameAr,
            subSubKindNameEn: selectedSubSubKindNameEn,
            subSubKindItemID: selectedSubSubKindItemID,
            subSubKindItemNameAr: selectedSubSubKindItemNameAr,
            subSubKindItemNameEn: selectedSubSubKindItemNameEn,
            commandID: commandID
        )

        isSubmitting = false
        submissionStep = .idle

        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } else {
            validationError = model.errorMessage ?? Language.get("Error_Operation_Failed", alter: "تعذر حفظ التعديلات. يرجى المحاولة مرة أخرى.")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - Discard Confirmation (PPAlertHelper)

    private func promptDiscardChanges() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("LivePet_Profile_Discard_Title", alter: "تجاهل التغييرات؟"),
            subtitle: Language.get("LivePet_Profile_Discard_Message", alter: "لديك تعديلات غير محفوظة على هذا الحيوان، هل تود إغلاق المحرر؟"),
            confirmButton: Language.get("LivePet_Profile_Discard_Confirm", alter: "تجاهل"),
            cancelButton: Language.get("LivePet_Profile_Keep_Editing", alter: "متابعة التعديل"),
            icon: UIImage(systemName: "exclamationmark.triangle.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                dismiss()
            },
            cancelBlock: nil
        )
    }
}

// MARK: - Live-Pet Operation Sheet

private struct PPLivePetOperationSheet: View {
    let context: PPLivePetOperationContext
    @ObservedObject var model: PPLivePetOperationsViewModel
    var onOpenReturnCase: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var selectedMode: PPLivePetInventoryMode = .individual
    @State private var unitDrafts: [PPLivePetUnitDraft]
    @State private var unitPhotos: [String: PPLivePetUnitPhotoDraft] = [:]
    @State private var showUnitPhotoSource: Bool = false
    @State private var showUnitPhotoCamera: Bool = false
    @State private var showUnitPhotoLibrary: Bool = false
    @State private var showCameraAccessAlert: Bool = false
    @State private var unitPhotoTargetID: String? = nil
    @State private var previewMedia: PPLivePetPreviewMedia? = nil
    @State private var expandedUnitIDs: Set<String> = []
    @Namespace private var genderSelectionNamespace

    private enum FocusedField: Hashable {
        case unitRing(String)
        case unitSellingPrice(String)
        case unitPurchaseCost(String)
        case unitSupplier(String)
        case unitNotes(String)
    }
    @FocusState private var focusedField: FocusedField?

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
    @State private var operationCommandID: String
    @State private var submittedIntentSignature: String? = nil

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

    init(context: PPLivePetOperationContext, model: PPLivePetOperationsViewModel, onOpenReturnCase: ((String) -> Void)? = nil) {
        self.context = context
        self.model = model
        self.onOpenReturnCase = onOpenReturnCase
        _operationCommandID = State(initialValue: PPLivePetInventoryService.commandID(context.id))
        let standardPrice = model.item.standardSellingPrice?.doubleValue ?? model.item.price.doubleValue
        _standardPriceText = State(initialValue: standardPrice > 0 ? String(format: "%g", standardPrice) : "")
        _quantityText = State(initialValue: "\(max(0, model.item.quantity))")

        let draftCount: Int
        if case .migrate = context, model.item.quantity <= 100 {
            draftCount = max(0, model.item.quantity)
        } else {
            draftCount = 1
        }
        let initialDrafts = (0..<draftCount).map { _ in
            PPLivePetUnitDraft(sellingPriceText: standardPrice > 0 ? String(format: "%g", standardPrice) : "")
        }
        _unitDrafts = State(initialValue: initialDrafts)
        _expandedUnitIDs = State(initialValue: Set(initialDrafts.map { $0.id }))

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

    private var currentIntentSignature: String {
        let unitSignature = unitDrafts.map { unit in
            [
                unit.id,
                unit.ringTag,
                unit.gender.rawValue,
                ISO8601DateFormatter().string(from: unit.acquisitionDate),
                unit.purchaseCostText,
                unit.sellingPriceText,
                unit.supplier,
                unit.notes,
                unit.subSubKindID.map { String($0) } ?? "",
                unit.subSubKindItemID.map { String($0) } ?? "",
                unitPhotos[unit.id]?.contentSHA256 ?? ""
            ].joined(separator: "|")
        }.joined(separator: "||")
        return [
            context.id,
            selectedMode.rawValue,
            quantityText,
            costText,
            standardPriceText,
            supplier,
            notes,
            reason,
            customerName,
            customerPhone,
            selectedBranchID,
            ISO8601DateFormatter().string(from: reservationValidUntil),
            cashReceivedText,
            causeCode,
            veterinaryReference,
            ISO8601DateFormatter().string(from: observedDeathAt),
            unitSignature
        ].joined(separator: "\u{1f}")
    }

    private func stableCommandIDForCurrentIntent() -> String {
        let signature = currentIntentSignature
        if submittedIntentSignature != signature {
            submittedIntentSignature = signature
            operationCommandID = PPLivePetInventoryService.commandID(context.id)
        }
        return operationCommandID
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }

                PPKeyboardDismissOverlay()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)

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
                .scrollDismissesKeyboardCompat()
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
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        dismiss()
                    }
                    .disabled(model.isMutating)
                }
            }
        }
        .navigationViewStyle(.stack)
        .dismissKeyboardOnTapOutside()
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $isBranchPickerPresented) {
            PPBranchSelectionStudioSheet(
                branches: model.branches,
                selectedBranchID: $selectedBranchID,
                excludedBranchID: branchPickerExcludedID
            )
        }
        .confirmationDialog(
            Language.get("LivePetIntake_UnitPhotoSourceTitle", alter: "صورة هذا الحيوان"),
            isPresented: $showUnitPhotoSource,
            titleVisibility: .visible
        ) {
            Button(Language.get("LivePetIntake_UnitPhotoCamera", alter: "التقاط صورة")) {
                requestUnitPhotoCamera()
            }
            Button(Language.get("LivePetIntake_UnitPhotoLibrary", alter: "اختيار من مكتبة الصور")) {
                showUnitPhotoLibrary = true
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
        } message: {
            Text(Language.get(
                "LivePetIntake_UnitPhotoSourceMessage",
                alter: "سترتبط الصورة بسجل هذا الحيوان فقط ولن تُنسخ إلى الحيوانات الأخرى."
            ))
        }
        .sheet(isPresented: $showUnitPhotoLibrary) {
            PPLivePetPhotoPicker(maxSelection: 1) { images, failedCount in
                if let image = images.first {
                    acceptUnitPhoto(image)
                } else if failedCount > 0 {
                    validationMessage = Language.get(
                        "LivePetIntake_UnitPhotoImportFailed",
                        alter: "تعذر استيراد الصورة المحددة. اختر صورة أخرى وحاول مجدداً."
                    )
                }
            }
        }
        .fullScreenCover(isPresented: $showUnitPhotoCamera) {
            PPLivePetCameraPicker { image in
                acceptUnitPhoto(image)
            }
        }
        .alert(
            Language.get("LivePetIntake_UnitPhotoCameraPermissionTitle", alter: "السماح باستخدام الكاميرا"),
            isPresented: $showCameraAccessAlert
        ) {
            Button(Language.get("LivePetIntake_OpenSettings", alter: "فتح الإعدادات")) {
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(settingsURL)
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
        } message: {
            Text(Language.get(
                "LivePetIntake_UnitPhotoCameraPermissionMessage",
                alter: "فعّل إذن الكاميرا من الإعدادات لالتقاط صورة خاصة بهذا الحيوان، أو اختر صورة من المكتبة."
            ))
        }
        .fullScreenCover(item: $previewMedia) { media in
            PPLivePetMediaPreview(media: media)
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
        case .quarantine:
            return Color(uiColor: .ppInfo)
        case .releaseQuarantine(let contextUnit):
            let unit = currentLiveUnit ?? contextUnit
            return !unit.activeReturnCaseID.isEmpty ? Color(uiColor: .systemPurple) : Color(uiColor: .ppInfo)
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
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center) {
                            Text(Language.get("LivePet_Intake_Roster_Title", alter: "جوازات الحيوانات المضافة"))
                                .font(Font.custom("Beiruti-Bold", size: 16))
                                .foregroundStyle(AdminSurface.primaryText)
                            Spacer()
                            if unitDrafts.count < 100 {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    let newDraft = PPLivePetUnitDraft(
                                        sellingPriceText: standardPriceText.isEmpty ? "" : standardPriceText
                                    )
                                    unitDrafts.append(newDraft)
                                    expandedUnitIDs.insert(newDraft.id)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 13, weight: .bold))
                                        Text(Language.get("LivePetIntake_AddAnimal", alter: "إضافة حيوان آخر"))
                                            .font(Font.custom("Beiruti-Bold", size: 13))
                                    }
                                    .foregroundStyle(AdminSurface.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        ForEach(Array($unitDrafts.enumerated()), id: \.element.id) { index, $unit in
                            unitPassport(index: index, unit: $unit)
                        }
                    }
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
                if !unit.activeReturnCaseID.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(uiColor: .systemPurple))
                                .frame(width: 32, height: 32)
                                .background(Color(uiColor: .systemPurple).opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Language.get("LivePet_ReturnCase_Notice_Title", alter: "حيوان مسجل ضمن ملف استرجاع معتمد"))
                                    .font(Font.custom("Beiruti-Bold", size: 14))
                                    .foregroundStyle(AdminSurface.primaryText)
                                Text(String(format: Language.get("LivePet_Release_ReturnCase_Notice", alter: "هذا الحيوان مسجل ضمن حالة استرجاع نشطة (%@). لا يمكن إخراجه مباشرة من المخزون، بل يجب استكمال الفحص البيطري واعتماد إعادة البيع من خلال ملف الاسترجاع."), unit.linkedReturnCaseReference))
                                    .font(Font.custom("Beiruti-Regular", size: 12))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .background(Color(uiColor: .systemPurple).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(uiColor: .systemPurple).opacity(0.20), lineWidth: 0.75))

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            let caseId = unit.activeReturnCaseID
                            dismiss()
                            onOpenReturnCase?(caseId)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right.square.fill")
                                Text(Language.get("LivePet_Open_ReturnCase_Action", alter: "فتح ملف الاسترجاع والفحص"))
                            }
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(Color(uiColor: .systemPurple))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color(uiColor: .systemPurple).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(CatalogPressStyle())
                    }
                } else {
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
                }

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
                Text(verbatim: unit.displayIdentity.normalizedEnglishDigits)
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
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    let commandID = stableCommandIDForCurrentIntent()
                    Task {
                        let ok = await model.cancel(reservation: reservation, commandID: commandID)
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
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    if case .releaseQuarantine(let contextUnit) = context {
                        let unit = currentLiveUnit ?? contextUnit
                        if !unit.activeReturnCaseID.isEmpty {
                            let caseId = unit.activeReturnCaseID
                            dismiss()
                            onOpenReturnCase?(caseId)
                            return
                        }
                    }
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
        case .releaseQuarantine(let contextUnit):
            let unit = currentLiveUnit ?? contextUnit
            return !unit.activeReturnCaseID.isEmpty ? "doc.text.magnifyingglass" : "checkmark.shield.fill"
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
            let commandID = stableCommandIDForCurrentIntent()
            Task {
                if case .reservation(let reservation) = context {
                    let ok = await model.cancel(reservation: reservation, commandID: commandID)
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
            ForEach(Array($unitDrafts.enumerated()), id: \.element.id) { index, $unit in
                unitPassport(index: index, unit: $unit)
            }
        }
    }

    // MARK: - Unit Passport

    private func unitPassport(index: Int, unit: Binding<PPLivePetUnitDraft>) -> some View {
        let draft = unit.wrappedValue
        let expanded = expandedUnitIDs.contains(draft.id)
        let readiness = unitReadiness(for: draft)
        let photo = unitPhotos[draft.id]?.image

        return VStack(spacing: 0) {
            passportSpine(
                index: index,
                unit: draft,
                readiness: readiness,
                expanded: expanded,
                photo: photo
            )

            if expanded {
                Rectangle()
                    .fill(AdminSurface.hairline.opacity(0.72))
                    .frame(height: 0.75)

                passportBody(index: index, unit: unit, readiness: readiness)
            }
        }
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(
                    expanded
                        ? readiness.tint.opacity(0.54)
                        : (readiness.isSubmittable ? AdminSurface.hairline : readiness.tint.opacity(0.42)),
                    lineWidth: expanded ? 1.25 : (readiness.isSubmittable ? 0.75 : 1)
                )
        )
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(readiness.tint)
                .frame(width: 3)
                .padding(.vertical, AdminSpacing.md)
                .opacity(expanded ? 1 : 0.52)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .shadow(
            color: Color.black.opacity(expanded ? 0.065 : 0.025),
            radius: expanded ? 14 : 5,
            x: 0,
            y: expanded ? 6 : 2
        )
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.22), value: expanded)
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.2), value: readiness.isSubmittable)
    }

    private func passportSpine(
        index: Int,
        unit: PPLivePetUnitDraft,
        readiness: PPUnitReadiness,
        expanded: Bool,
        photo: UIImage?
    ) -> some View {
        let ring = unit.ringTag.trimmingCharacters(in: .whitespacesAndNewlines)

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if expanded {
                expandedUnitIDs.remove(unit.id)
            } else {
                expandedUnitIDs.insert(unit.id)
            }
        } label: {
            HStack(alignment: .center, spacing: AdminSpacing.md) {
                passportIdentityAperture(
                    index: index,
                    readiness: readiness,
                    photo: photo
                )

                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    HStack(spacing: AdminSpacing.xs) {
                        readinessStatusPill(readiness)
                        if photo != nil {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AdminSurface.primary)
                                .accessibilityHidden(true)
                        }
                    }

                    Text(ring.isEmpty ? Language.get("LivePetIntake_IdentifierMissing", alter: "الهوية مطلوبة") : ring.normalizedEnglishDigits)
                        .font(ring.isEmpty ? Font.custom("Beiruti-Bold", size: 14) : PPBrandFont.bold(size: 16))
                        .foregroundStyle(ring.isEmpty ? AdminSurface.secondaryText : AdminSurface.primaryText)
                        .environment(\.layoutDirection, ring.isEmpty && Language.isRTL() ? .rightToLeft : .leftToRight)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: AdminSpacing.xs) {
                        genderTag(unit.gender)

                        if isPositiveMoney(unit.sellingPriceText) {
                            Text(verbatim: String(
                                format: Language.get("LivePetIntake_UnitPriceFormat", alter: "%@ ر.ق"),
                                unit.sellingPriceText.normalizedEnglishDigits
                            ))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .foregroundStyle(AdminSurface.primaryText)
                            .environment(\.layoutDirection, .leftToRight)
                        }
                    }

                    if !readiness.isSubmittable {
                        Text(readiness.isDuplicateIdentity
                            ? Language.get("LivePetIntake_DuplicateIdentity", alter: "هذه الهوية مستخدمة في حيوان آخر")
                            : String(
                                format: Language.get("LivePetIntake_MissingFormat", alter: "ناقص: %@"),
                                readiness.missingLabels.joined(separator: Language.get("ListSeparator", alter: "، "))
                            ))
                            .font(Font.custom("Beiruti-Regular", size: 11))
                            .foregroundStyle(readiness.tint)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: AdminSpacing.xs)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
            }
            .padding(AdminSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func passportIdentityAperture(
        index: Int,
        readiness: PPUnitReadiness,
        photo: UIImage?
    ) -> some View {
        ZStack {
            Circle()
                .fill(readiness.tint.opacity(0.09))

            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else if readiness.isDuplicateIdentity {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(readiness.tint)
            } else if readiness.isSubmittable {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(readiness.tint)
                    .transition(.opacity)
            } else {
                Text(verbatim: String(format: "%02d", index + 1).normalizedEnglishDigits)
                    .font(PPBrandFont.bold(size: 13))
                    .foregroundStyle(AdminSurface.primaryText)
                    .environment(\.layoutDirection, .leftToRight)
            }

            Circle()
                .strokeBorder(AdminSurface.hairline, lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: max(0.001, readiness.progress))
                .stroke(readiness.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.28), value: readiness.progress)
        }
        .frame(width: 52, height: 52)
        .overlay(alignment: .bottomTrailing) {
            if photo != nil {
                Text(verbatim: "\(index + 1)")
                    .font(PPBrandFont.bold(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 19, height: 19)
                    .background(readiness.tint, in: Circle())
                    .overlay(Circle().strokeBorder(AdminSurface.surface, lineWidth: 2))
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .accessibilityHidden(true)
    }

    private func readinessStatusPill(_ readiness: PPUnitReadiness) -> some View {
        let symbol: String
        if readiness.isDuplicateIdentity {
            symbol = "exclamationmark.triangle.fill"
        } else if readiness.isSubmittable {
            symbol = "checkmark.circle.fill"
        } else if readiness.isUntouched {
            symbol = "circle.dashed"
        } else {
            symbol = "circle.lefthalf.filled"
        }

        return Label(readiness.statusSummary, systemImage: symbol)
            .font(Font.custom("Beiruti-Bold", size: 11))
            .foregroundStyle(readiness.tint)
            .padding(.horizontal, AdminSpacing.xs)
            .padding(.vertical, 3)
            .background(readiness.tint.opacity(0.10), in: Capsule(style: .continuous))
    }

    private func genderTag(_ gender: PPLivePetUnitGender) -> some View {
        let tint = Color(uiColor: gender.tint)
        return HStack(spacing: 3) {
            Image(systemName: gender.symbolName)
                .font(.system(size: 9, weight: .bold))
            Text(gender.localizedShortTitle)
                .font(Font.custom("Beiruti-Bold", size: 11))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, AdminSpacing.xs)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.30), lineWidth: 0.5))
    }

    // MARK: - Passport Body

    private func passportBody(
        index: Int,
        unit: Binding<PPLivePetUnitDraft>,
        readiness: PPUnitReadiness
    ) -> some View {
        let draft = unit.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            // 01 Identity & Gender
            VStack(alignment: .leading, spacing: 8) {
                passportSectionHeader(
                    sequence: 1,
                    symbol: "viewfinder.circle.fill",
                    title: Language.get("LivePetIntake_PassportIdentityTitle", alter: "إشارة الهوية")
                )

                identityCaptureLayout(unit: unit, readiness: readiness)
                unitGenderSelector(unit: unit)
            }

            passportSectionDivider

            // 02 Commercial
            VStack(alignment: .leading, spacing: 8) {
                passportSectionHeader(
                    sequence: 2,
                    symbol: "point.3.filled.connected.trianglepath.dotted",
                    title: Language.get("LivePetIntake_PassportCommercialTitle", alter: "الإحداثيات التجارية")
                )
                moneyFields(unit: unit)
            }

            passportSectionDivider

            // 03 Provenance & Arrival Context
            VStack(alignment: .leading, spacing: 8) {
                passportSectionHeader(
                    sequence: 3,
                    symbol: "clock.arrow.circlepath",
                    title: Language.get("LivePetIntake_PassportProvenanceTitle", alter: "سياق الوصول")
                )

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        receivedDateField(unit: unit)
                        supplierField(unit: unit)
                    }
                } else {
                    HStack(alignment: .top, spacing: AdminSpacing.sm) {
                        receivedDateField(unit: unit)
                        supplierField(unit: unit)
                    }
                }

                notesField(unit: unit)
            }

            passportActions(index: index, unit: draft)
        }
        .padding(AdminSpacing.md)
        .background(
            LinearGradient(
                colors: [readiness.tint.opacity(0.045), AdminSurface.primaryText.opacity(0.018)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func passportSectionHeader(
        sequence: Int,
        symbol: String,
        title: String
    ) -> some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AdminSurface.primary.opacity(0.10))
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
            }
            .frame(width: 22, height: 22)

            Text(verbatim: String(format: "%02d", sequence).normalizedEnglishDigits)
                .font(PPBrandFont.bold(size: 10))
                .foregroundStyle(AdminSurface.primary)
                .environment(\.layoutDirection, .leftToRight)

            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 13))
                .foregroundStyle(AdminSurface.primaryText)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var passportSectionDivider: some View {
        Rectangle()
            .fill(AdminSurface.hairline.opacity(0.50))
            .frame(height: 0.5)
            .padding(.vertical, 1)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func identityCaptureLayout(
        unit: Binding<PPLivePetUnitDraft>,
        readiness: PPUnitReadiness
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                unitPhotoCard(unitID: unit.wrappedValue.id)
                identityFieldsColumn(unit: unit, readiness: readiness)
            }
        } else {
            HStack(alignment: .top, spacing: AdminSpacing.sm) {
                unitPhotoCard(unitID: unit.wrappedValue.id)
                    .frame(width: 104)
                identityFieldsColumn(unit: unit, readiness: readiness)
            }
        }
    }

    @ViewBuilder
    private func identityFieldsColumn(
        unit: Binding<PPLivePetUnitDraft>,
        readiness: PPUnitReadiness
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            identityField(unit: unit, readiness: readiness)

            if model.hasSubSubKinds {
                unitSubSubKindSelector(unit: unit)
            }

            if let subSubID = unit.wrappedValue.subSubKindID,
               let items = model.subSubKindItemsBySubSubID[subSubID],
               !items.isEmpty {
                unitSubSubKindItemSelector(unit: unit, items: items)
            }
        }
    }

    private func unitPhotoCard(unitID: String) -> some View {
        let photo = unitPhotos[unitID]?.image
        let canAttach = model.canManageStock

        return VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                Button {
                    if let photo {
                        previewMedia = PPLivePetPreviewMedia(source: .local(photo))
                    } else {
                        presentUnitPhotoSource(for: unitID)
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .fill(photo == nil ? AdminSurface.primary.opacity(0.055) : AdminSurface.control)

                        if let photo {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()

                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.44)],
                                startPoint: .center,
                                endPoint: .bottom
                            )

                            Label(
                                Language.get("LivePetIntake_UnitPhotoPreview", alter: "معاينة"),
                                systemImage: "arrow.up.left.and.arrow.down.right"
                            )
                            .font(Font.custom("Beiruti-Bold", size: 10))
                            .foregroundStyle(.white)
                            .padding(AdminSpacing.xs)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        } else {
                            VStack(spacing: 3) {
                                Image(systemName: canAttach ? "camera.aperture" : "lock.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(canAttach ? AdminSurface.primary : AdminSurface.secondaryText)
                                Text(Language.get("LivePetIntake_UnitPhotoAdd", alter: "أضف صورة"))
                                    .font(Font.custom("Beiruti-Bold", size: 11))
                                    .foregroundStyle(AdminSurface.primaryText)
                                Text(Language.get("LivePetIntake_Optional", alter: "اختياري"))
                                    .font(Font.custom("Beiruti-Regular", size: 9))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                            .multilineTextAlignment(.center)
                            .padding(6)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 130 : 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                photo == nil ? AdminSurface.primary.opacity(0.30) : AdminSurface.hairline,
                                style: StrokeStyle(lineWidth: 1, dash: photo == nil ? [4, 3] : [])
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
                .disabled(!canAttach && photo == nil)

                if photo != nil {
                    Button(role: .destructive) {
                        unitPhotos.removeValue(forKey: unitID)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.65), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(3)
                }
            }

            Label(
                Language.get("LivePetIntake_UnitPhotoInternalNote", alter: "ترتبط بسجل هذا الحيوان فقط"),
                systemImage: "link.badge.plus"
            )
            .font(Font.custom("Beiruti-Regular", size: 9))
            .foregroundStyle(AdminSurface.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private func identityField(
        unit: Binding<PPLivePetUnitDraft>,
        readiness: PPUnitReadiness
    ) -> some View {
        let ring = unit.wrappedValue.ringTag.trimmingCharacters(in: .whitespacesAndNewlines)

        return intakeField(
            caption: Language.get("LivePetIntake_RingLabel", alter: "رقم الحلقة أو الشريحة"),
            symbol: "number",
            required: true,
            focused: focusedField == .unitRing(unit.wrappedValue.id),
            invalid: readiness.isDuplicateIdentity,
            footnote: readiness.isDuplicateIdentity
                ? Language.get("LivePetIntake_DuplicateIdentity", alter: "هذه الهوية مستخدمة في حيوان آخر")
                : nil,
            footnoteTint: Color(uiColor: .ppError)
        ) {
            HStack(spacing: AdminSpacing.xs) {
                TextField(
                    "",
                    text: unit.ringTag,
                    prompt: promptText("QA-RING-000")
                )
                .font(PPBrandFont.bold(size: 17))
                .foregroundStyle(AdminSurface.primaryText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .textContentType(.none)
                .keyboardType(.asciiCapable)
                .environment(\.layoutDirection, .leftToRight)
                .multilineTextAlignment(.leading)
                .focused($focusedField, equals: .unitRing(unit.wrappedValue.id))
                .submitLabel(.next)
                .onSubmit { focusedField = .unitSellingPrice(unit.wrappedValue.id) }

                if !ring.isEmpty {
                    Button {
                        unit.ringTag.wrappedValue = ""
                        focusedField = .unitRing(unit.wrappedValue.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .frame(width: 30, height: AdminTouchTarget.minimum)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                AdminBarcodeScanButton { scanned in
                    unit.ringTag.wrappedValue = scanned
                    focusedField = nil
                }
            }
        }
    }

    private func unitSubSubKindSelector(unit: Binding<PPLivePetUnitDraft>) -> some View {
        let selectedSubSub = model.availableSubSubKinds.first { $0.numericID == unit.wrappedValue.subSubKindID }
        let title = selectedSubSub?.localizedName ?? Language.get("LivePetIntake_SelectSubSubKind", alter: "اختر التفريع الفرعي...")
        let hasSelection = selectedSubSub != nil

        return intakeField(
            caption: Language.get("LivePetIntake_SubSubKindLabel", alter: "التفريع الفرعي (SubSubKind)"),
            symbol: "arrow.triangle.branch",
            required: false,
            optionalNote: Language.get("LivePetIntake_Optional", alter: "اختياري"),
            focused: false
        ) {
            Menu {
                Button {
                    setUnitSubSubKind(nil, unitID: unit.wrappedValue.id)
                } label: {
                    Label(Language.get("LivePetIntake_None", alter: "بدون تفريع"), systemImage: "xmark")
                }
                Divider()
                ForEach(model.availableSubSubKinds) { subSub in
                    Button {
                        setUnitSubSubKind(subSub, unitID: unit.wrappedValue.id)
                    } label: {
                        HStack {
                            Text(subSub.localizedName)
                            if unit.wrappedValue.subSubKindID == subSub.numericID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: AdminSpacing.xs) {
                    Text(title)
                        .font(Font.custom("Beiruti-Regular", size: 14))
                        .foregroundStyle(hasSelection ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func unitSubSubKindItemSelector(unit: Binding<PPLivePetUnitDraft>, items: [AdminSubKindItemDetail]) -> some View {
        let selectedItem = items.first { $0.numericID == unit.wrappedValue.subSubKindItemID }
        let title = selectedItem?.localizedName ?? Language.get("LivePetIntake_SelectSubSubKindItem", alter: "اختر تصنيف العنصر...")
        let hasSelection = selectedItem != nil

        return intakeField(
            caption: Language.get("LivePetIntake_SubSubKindItemLabel", alter: "عنصر التفريع (SubSubKindItem)"),
            symbol: "tag.fill",
            required: false,
            optionalNote: Language.get("LivePetIntake_Optional", alter: "اختياري"),
            focused: false
        ) {
            Menu {
                Button {
                    setUnitSubSubKindItem(nil, unitID: unit.wrappedValue.id)
                } label: {
                    Label(Language.get("LivePetIntake_None", alter: "بدون عنصر"), systemImage: "xmark")
                }
                Divider()
                ForEach(items) { item in
                    Button {
                        setUnitSubSubKindItem(item, unitID: unit.wrappedValue.id)
                    } label: {
                        HStack {
                            Text(item.localizedName)
                            if unit.wrappedValue.subSubKindItemID == item.numericID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: AdminSpacing.xs) {
                    Text(title)
                        .font(Font.custom("Beiruti-Regular", size: 14))
                        .foregroundStyle(hasSelection ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func unitGenderSelector(unit: Binding<PPLivePetUnitDraft>) -> some View {
        let draft = unit.wrappedValue
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.xs) {
                Image(systemName: "allergens.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("LivePetIntake_UnitGender", alter: "جنس هذا الحيوان"))
                    .font(Font.custom("Beiruti-Bold", size: 11))
                    .foregroundStyle(AdminSurface.secondaryText)
                Spacer(minLength: AdminSpacing.xs)
                if draft.gender == .unspecified {
                    Text(Language.get("LivePetIntake_GenderUnsetNote", alter: "سيُحفظ كغير محدد"))
                        .font(Font.custom("Beiruti-Regular", size: 10))
                        .foregroundStyle(Color(uiColor: .ppTextTertiary))
                }
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 3) {
                        ForEach(PPLivePetUnitGender.allCases) { option in
                            genderOption(option, unit: unit, compact: false)
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        ForEach(PPLivePetUnitGender.allCases) { option in
                            genderOption(option, unit: unit, compact: true)
                        }
                    }
                }
            }
            .padding(3)
            .background(AdminSurface.primaryText.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AdminSurface.hairline.opacity(0.75), lineWidth: 0.75)
            )
        }
    }

    private func genderOption(
        _ option: PPLivePetUnitGender,
        unit: Binding<PPLivePetUnitDraft>,
        compact: Bool
    ) -> some View {
        let selected = unit.wrappedValue.gender == option
        let tint = Color(uiColor: option.tint)

        return Button {
            setUnitGender(option, unitID: unit.wrappedValue.id)
        } label: {
            Group {
                if compact {
                    HStack(spacing: 4) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 11, weight: .bold))
                        Text(option.localizedShortTitle)
                            .font(Font.custom("Beiruti-Bold", size: 11))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                } else {
                    HStack(spacing: AdminSpacing.sm) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                        Text(option.localizedTitle)
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .padding(.horizontal, AdminSpacing.md)
                    .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
                }
            }
            .foregroundStyle(selected ? tint : AdminSurface.primaryText)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AdminSurface.surface)
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(tint.opacity(0.14))
                            .matchedGeometryEffect(id: unit.wrappedValue.id, in: genderSelectionNamespace)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? tint.opacity(0.50) : AdminSurface.hairline.opacity(0.4), lineWidth: selected ? 1.2 : 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .animation(
            accessibilityReduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84),
            value: unit.wrappedValue.gender
        )
    }

    @ViewBuilder
    private func moneyFields(unit: Binding<PPLivePetUnitDraft>) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AdminSpacing.base) {
                sellingPriceField(unit: unit)
                if model.canViewCosts {
                    purchaseCostField(unit: unit)
                }
            }
        } else {
            HStack(alignment: .top, spacing: AdminSpacing.sm) {
                sellingPriceField(unit: unit)
                if model.canViewCosts {
                    purchaseCostField(unit: unit)
                }
            }
        }
    }

    private func sellingPriceField(unit: Binding<PPLivePetUnitDraft>) -> some View {
        let entered = !unit.wrappedValue.sellingPriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return intakeField(
            caption: Language.get("LivePetIntake_UnitSellingPriceShort", alter: "سعر البيع"),
            symbol: "tag.fill",
            required: true,
            focused: focusedField == .unitSellingPrice(unit.wrappedValue.id),
            invalid: entered && !isPositiveMoney(unit.wrappedValue.sellingPriceText),
            trailingAffix: Language.get("QAR", alter: "ر.ق"),
            footnote: entered && !isPositiveMoney(unit.wrappedValue.sellingPriceText)
                ? Language.get("LivePetIntake_MoneyFormat", alter: "مبلغ صالح بمنزلتين عشريتين كحد أقصى")
                : nil,
            footnoteTint: Color(uiColor: .ppError)
        ) {
            moneyTextField(
                text: unit.sellingPriceText,
                field: .unitSellingPrice(unit.wrappedValue.id),
                label: Language.get("LivePetIntake_UnitSellingPrice", alter: "سعر البيع (ر.ق)")
            )
        }
    }

    private func purchaseCostField(unit: Binding<PPLivePetUnitDraft>) -> some View {
        let entered = !unit.wrappedValue.purchaseCostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return intakeField(
            caption: Language.get("LivePetIntake_UnitCostShort", alter: "تكلفة الاستلام"),
            symbol: "arrow.down.circle.fill",
            required: true,
            focused: focusedField == .unitPurchaseCost(unit.wrappedValue.id),
            invalid: entered && !isNonNegativeMoney(unit.wrappedValue.purchaseCostText),
            trailingAffix: Language.get("QAR", alter: "ر.ق"),
            footnote: entered && !isNonNegativeMoney(unit.wrappedValue.purchaseCostText)
                ? Language.get("LivePetIntake_MoneyFormat", alter: "مبلغ صالح بمنزلتين عشريتين كحد أقصى")
                : nil,
            footnoteTint: Color(uiColor: .ppError)
        ) {
            moneyTextField(
                text: unit.purchaseCostText,
                field: .unitPurchaseCost(unit.wrappedValue.id),
                label: Language.get("LivePetIntake_UnitCost", alter: "تكلفة الاستلام (ر.ق)")
            )
        }
    }

    private func moneyTextField(text: Binding<String>, field: FocusedField, label: String) -> some View {
        TextField("", text: text, prompt: promptText("0.00"))
            .font(PPBrandFont.bold(size: 18))
            .foregroundStyle(AdminSurface.primaryText)
            .englishNumericInput(text: text, allowsDecimal: true)
            .monospacedDigit()
            .multilineTextAlignment(.leading)
            .focused($focusedField, equals: field)
            .accessibilityLabel(label)
    }

    private func receivedDateField(unit: Binding<PPLivePetUnitDraft>) -> some View {
        intakeField(
            caption: Language.get("LivePetIntake_ReceivedDate", alter: "تاريخ الاستلام"),
            symbol: "calendar",
            required: false,
            focused: false
        ) {
            DatePicker(
                Language.get("LivePetIntake_ReceivedDate", alter: "تاريخ الاستلام"),
                selection: unit.acquisitionDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .font(Font.custom("Beiruti-Regular", size: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func supplierField(unit: Binding<PPLivePetUnitDraft>) -> some View {
        intakeField(
            caption: Language.get("LivePetIntake_SupplierField", alter: "المورد أو المصدر"),
            symbol: "shippingbox.fill",
            required: false,
            optionalNote: Language.get("LivePetIntake_Optional", alter: "اختياري"),
            focused: focusedField == .unitSupplier(unit.wrappedValue.id)
        ) {
            TextField(
                "",
                text: unit.supplier,
                prompt: promptText(Language.get("LivePetIntake_SupplierPrompt", alter: "اسم المورد أو المزرعة"))
            )
            .font(Font.custom("Beiruti-Regular", size: 14))
            .foregroundStyle(AdminSurface.primaryText)
            .focused($focusedField, equals: .unitSupplier(unit.wrappedValue.id))
            .submitLabel(.next)
            .onSubmit { focusedField = .unitNotes(unit.wrappedValue.id) }
        }
    }

    private func notesField(unit: Binding<PPLivePetUnitDraft>) -> some View {
        intakeField(
            caption: Language.get("LivePetIntake_NotesField", alter: "ملاحظات الاستلام الداخلية"),
            symbol: "text.alignleft",
            required: false,
            optionalNote: Language.get("LivePetIntake_Optional", alter: "اختياري"),
            focused: focusedField == .unitNotes(unit.wrappedValue.id)
        ) {
            TextField(
                "",
                text: unit.notes,
                prompt: promptText(Language.get("LivePetIntake_NotesPrompt", alter: "حالة الوصول، ملاحظة بيطرية، أي تحفظ"))
            )
            .font(Font.custom("Beiruti-Regular", size: 14))
            .foregroundStyle(AdminSurface.primaryText)
            .focused($focusedField, equals: .unitNotes(unit.wrappedValue.id))
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
        }
    }

    private func passportActions(index: Int, unit: PPLivePetUnitDraft) -> some View {
        let hasNext = index + 1 < unitDrafts.count

        return HStack(spacing: 8) {
            if unitDrafts.count > 1 {
                removeUnitButton(unit.id)
            }
            cloneUnitButton(unit)

            if hasNext || unitDrafts.count < 100 {
                Button {
                    advanceFromUnit(at: index)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: hasNext ? "arrow.forward.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(hasNext
                            ? Language.get("LivePetIntake_NextAnimal", alter: "الحيوان التالي")
                            : Language.get("LivePetIntake_AddAnimal", alter: "إضافة حيوان آخر"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
            }
        }
        .padding(.top, 2)
    }

    private func advanceFromUnit(at index: Int) {
        focusedField = nil
        if index + 1 < unitDrafts.count {
            let nextID = unitDrafts[index + 1].id
            UISelectionFeedbackGenerator().selectionChanged()
            expandedUnitIDs = [nextID]
        } else if unitDrafts.count < 100 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let newDraft = PPLivePetUnitDraft(
                sellingPriceText: standardPriceText.isEmpty ? "" : standardPriceText
            )
            unitDrafts.append(newDraft)
            expandedUnitIDs = [newDraft.id]
        }
    }

    private func cloneUnitButton(_ unit: PPLivePetUnitDraft) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            var nextRing = unit.ringTag.trimmingCharacters(in: .whitespacesAndNewlines)
            if let regex = try? NSRegularExpression(pattern: #"(\d+)$"#),
               let match = regex.firstMatch(in: nextRing, range: NSRange(nextRing.startIndex..., in: nextRing)),
               let range = Range(match.range(at: 1), in: nextRing) {
                let digitStr = String(nextRing[range])
                if let num = Int(digitStr) {
                    let nextNumStr = String(format: "%0\(digitStr.count)d", num + 1)
                    nextRing.replaceSubrange(range, with: nextNumStr)
                }
            }

            let clone = PPLivePetUnitDraft(
                ringTag: nextRing,
                gender: unit.gender,
                acquisitionDate: unit.acquisitionDate,
                purchaseCostText: unit.purchaseCostText,
                sellingPriceText: unit.sellingPriceText,
                supplier: unit.supplier,
                notes: unit.notes,
                subSubKindID: unit.subSubKindID,
                subSubKindItemID: unit.subSubKindItemID
            )
            unitDrafts.append(clone)
            expandedUnitIDs = [clone.id]
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 11, weight: .semibold))
                Text(Language.get("LivePetIntake_Clone", alter: "نسخ كحيوان جديد"))
                    .font(Font.custom("Beiruti-Bold", size: 12))
                    .lineLimit(1)
            }
            .foregroundStyle(Color(uiColor: .ppSuccess))
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Color(uiColor: .ppSuccess).opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.24), lineWidth: 0.75)
            )
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
        .disabled(unitDrafts.count >= 100)
    }

    private func removeUnitButton(_ id: String) -> some View {
        Button(role: .destructive) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            unitDrafts.removeAll(where: { $0.id == id })
            unitPhotos.removeValue(forKey: id)
            expandedUnitIDs.remove(id)
            if expandedUnitIDs.isEmpty, let first = unitDrafts.first {
                expandedUnitIDs.insert(first.id)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                Text(Language.get("LivePetIntake_Remove", alter: "إزالة"))
                    .font(Font.custom("Beiruti-Bold", size: 12))
                    .lineLimit(1)
            }
            .foregroundStyle(Color(uiColor: .ppError))
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Color(uiColor: .ppError).opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppError).opacity(0.24), lineWidth: 0.75)
            )
        }
        .buttonStyle(PPLivePetPressStyle(reduceMotion: accessibilityReduceMotion))
    }

    private func intakeField<Control: View>(
        caption: String,
        symbol: String,
        required: Bool,
        optionalNote: String? = nil,
        focused: Bool,
        invalid: Bool = false,
        trailingAffix: String? = nil,
        footnote: String? = nil,
        footnoteTint: Color = Color(uiColor: .ppError),
        @ViewBuilder control: () -> Control
    ) -> some View {
        let borderColor: Color = {
            if invalid { return Color(uiColor: .ppError) }
            if focused { return AdminSurface.primary }
            return AdminSurface.hairline
        }()
        let borderWidth: CGFloat = invalid ? 1.4 : (focused ? 1.6 : 1)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: AdminSpacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(focused ? AdminSurface.primary : AdminSurface.secondaryText)
                Text(caption)
                    .font(Font.custom("Beiruti-Bold", size: 11))
                    .foregroundStyle(focused ? AdminSurface.primary : AdminSurface.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if required {
                    Circle()
                        .fill(Color(uiColor: .ppError))
                        .frame(width: 4, height: 4)
                        .accessibilityHidden(true)
                } else if let optionalNote {
                    Text(optionalNote)
                        .font(Font.custom("Beiruti-Regular", size: 10))
                        .foregroundStyle(Color(uiColor: .ppTextTertiary))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: AdminSpacing.xs) {
                control()
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .contentShape(Rectangle())

                if let trailingAffix {
                    Text(trailingAffix)
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(AdminSurface.primaryText.opacity(0.06), in: Capsule(style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.16), value: focused)

            if let footnote {
                Text(footnote)
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(footnoteTint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func promptText(_ value: String) -> Text {
        Text(value).foregroundColor(AdminSurface.secondaryText.opacity(0.75))
    }

    private func unitReadiness(for unit: PPLivePetUnitDraft) -> PPUnitReadiness {
        let ring = unit.ringTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRing = !ring.isEmpty
        let hasPrice = isPositiveMoney(unit.sellingPriceText)
        let costRequired = model.canViewCosts
        let hasCost = !costRequired || isNonNegativeMoney(unit.purchaseCostText)

        var missing: [String] = []
        if !hasRing { missing.append(Language.get("LivePetIntake_MissingIdentity", alter: "الهوية")) }
        if !hasPrice { missing.append(Language.get("LivePetIntake_MissingPrice", alter: "سعر البيع")) }
        if costRequired && !hasCost { missing.append(Language.get("LivePetIntake_MissingCost", alter: "تكلفة الاستلام")) }

        let required = costRequired ? 3 : 2
        let satisfied = [hasRing, hasPrice, hasCost].filter { $0 }.count - (costRequired ? 0 : 1)

        let ringKey = PPAccessoryEditorViewModel.ringTagKey(unit.ringTag)
        let duplicateInDrafts = hasRing && unitDrafts.filter({ PPAccessoryEditorViewModel.ringTagKey($0.ringTag) == ringKey }).count > 1
        let duplicateInStock = hasRing && model.units.contains(where: { PPAccessoryEditorViewModel.ringTagKey($0.ringTag) == ringKey })
        let duplicate = duplicateInDrafts || duplicateInStock

        let untouched = !hasRing && !hasPrice && unit.purchaseCostText.isEmpty
            && unit.supplier.isEmpty && unit.notes.isEmpty && unit.gender == .unspecified

        let tint: Color
        let summary: String
        if duplicate {
            tint = Color(uiColor: .ppError)
            summary = Language.get("LivePetIntake_StatusDuplicate", alter: "هوية مكررة")
        } else if satisfied == required {
            tint = Color(uiColor: .ppSuccess)
            summary = Language.get("LivePetIntake_StatusReady", alter: "مكتمل")
        } else if untouched {
            tint = Color(uiColor: .ppTextTertiary)
            summary = Language.get("LivePetIntake_StatusEmpty", alter: "فارغ")
        } else {
            tint = Color(uiColor: .ppWarning)
            summary = Language.get("LivePetIntake_StatusPartial", alter: "غير مكتمل")
        }

        return PPUnitReadiness(
            satisfied: max(0, satisfied),
            required: required,
            missingLabels: missing,
            isDuplicateIdentity: duplicate,
            isUntouched: untouched,
            genderRecorded: unit.gender != .unspecified,
            statusSummary: summary,
            tint: tint
        )
    }

    private func isPositiveMoney(_ raw: String) -> Bool {
        let clean = raw.normalizedEnglishDigits.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(clean), value > 0, value <= 999_999_999.99 else { return false }
        return abs(value * 100 - (value * 100).rounded()) < 0.000_001
    }

    private func isNonNegativeMoney(_ raw: String) -> Bool {
        let clean = raw.normalizedEnglishDigits.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let value = Double(clean), value >= 0, value <= 999_999_999.99 else { return false }
        return abs(value * 100 - (value * 100).rounded()) < 0.000_001
    }

    private func presentUnitPhotoSource(for unitID: String) {
        focusedField = nil
        guard model.canManageStock else {
            validationMessage = Language.get(
                "LivePetIntake_UnitPhotoPermissionRequired",
                alter: "تحتاج إلى صلاحية إدارة المخزون لإرفاق صورة الحيوان."
            )
            return
        }
        unitPhotoTargetID = unitID
        showUnitPhotoSource = true
    }

    private func acceptUnitPhoto(_ image: UIImage) {
        guard let unitID = unitPhotoTargetID else { return }
        if let draft = PPLivePetUnitPhotoStorageService.prepareLivePetUnitPhoto(image) {
            unitPhotos[unitID] = draft
            let message = Language.get(
                "LivePetIntake_UnitPhotoSelectedAnnouncement",
                alter: "تم إرفاق الصورة بهذا الحيوان فقط."
            )
            UIAccessibility.post(notification: .announcement, argument: message)
        } else {
            validationMessage = Language.get(
                "LivePetIntake_UnitPhotoImportFailed",
                alter: "تعذر استيراد الصورة المحددة. اختر صورة أخرى وحاول مجدداً."
            )
        }
    }

    private func requestUnitPhotoCamera() {
        guard unitPhotoTargetID != nil else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            validationMessage = Language.get(
                "LivePetIntake_UnitPhotoCameraUnavailable",
                alter: "الكاميرا غير متاحة على هذا الجهاز. اختر صورة من المكتبة."
            )
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showUnitPhotoCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showUnitPhotoCamera = true
                    } else {
                        showCameraAccessAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraAccessAlert = true
        @unknown default:
            showCameraAccessAlert = true
        }
    }

    private func setUnitSubSubKind(_ subSub: AdminSubSubKindItem?, unitID: String) {
        guard let idx = unitDrafts.firstIndex(where: { $0.id == unitID }) else { return }
        unitDrafts[idx].subSubKindID = subSub?.numericID
        unitDrafts[idx].subSubKindItemID = nil
    }

    private func setUnitSubSubKindItem(_ item: AdminSubKindItemDetail?, unitID: String) {
        guard let idx = unitDrafts.firstIndex(where: { $0.id == unitID }) else { return }
        unitDrafts[idx].subSubKindItemID = item?.numericID
    }

    private func setUnitGender(_ gender: PPLivePetUnitGender, unitID: String) {
        guard let idx = unitDrafts.firstIndex(where: { $0.id == unitID }) else { return }
        unitDrafts[idx].gender = gender
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
                    .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)

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
                    .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                Text(Language.get("QAR", alter: "ر.ق"))
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
                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
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
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
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
        case .releaseQuarantine(let contextUnit):
            let unit = currentLiveUnit ?? contextUnit
            if !unit.activeReturnCaseID.isEmpty {
                return Language.get("LivePet_ReturnCase_Release_Title", alter: "ملف الاسترجاع والفحص البيطري")
            }
            return Language.get("LivePet_Release_Quarantine_Title", alter: "إخراج من الحجر الصحي")
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
        case .releaseQuarantine(let contextUnit):
            let unit = currentLiveUnit ?? contextUnit
            return !unit.activeReturnCaseID.isEmpty ? "doc.text.magnifyingglass" : "checkmark.shield.fill"
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
        case .releaseQuarantine(let contextUnit):
            let unit = currentLiveUnit ?? contextUnit
            if !unit.activeReturnCaseID.isEmpty {
                return Language.get("LivePet_ReturnCase_Release_Hint", alter: "هذا الحيوان مسجل ضمن حالة استرجاع نشطة، ويجب استكمال الفحص البيطري واعتماد إعادته للبيع عبر ملف الاسترجاع.")
            }
            return Language.get("LivePet_Release_Quarantine_Hint", alter: "يُعاد الحيوان إلى المخزون المتاح بعد انتهاء فترة الفحص.")
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
        case .releaseQuarantine(let contextUnit):
            let unit = currentLiveUnit ?? contextUnit
            if !unit.activeReturnCaseID.isEmpty {
                return Language.get("LivePet_Open_ReturnCase_Action", alter: "فتح ملف الاسترجاع والفحص")
            }
            return Language.get("LivePet_Confirm_Release", alter: "تأكيد الإخراج من الحجر")
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
        let commandID = stableCommandIDForCurrentIntent()
        Task {
            let ok: Bool
            switch context {
            case .migrate:
                let cleanPriceText = standardPriceText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
                let price = Double(cleanPriceText) ?? 0
                if selectedMode == .individual && !unitDrafts.isEmpty {
                    for draft in unitDrafts {
                        let readiness = unitReadiness(for: draft)
                        if !readiness.isSubmittable {
                            if readiness.isDuplicateIdentity {
                                validationMessage = Language.get("LivePetIntake_DuplicateIdentity", alter: "هذه الهوية مستخدمة في حيوان آخر")
                            } else {
                                validationMessage = String(
                                    format: Language.get("LivePetIntake_MissingFormat", alter: "ناقص: %@"),
                                    readiness.missingLabels.joined(separator: Language.get("ListSeparator", alter: "، "))
                                )
                            }
                            expandedUnitIDs.insert(draft.id)
                            return
                        }
                    }
                }
                ok = await model.migrate(
                    mode: selectedMode,
                    units: selectedMode == .individual ? unitDrafts : [],
                    standardSellingPrice: price,
                    commandID: commandID
                )
            case .intake:
                let targetBranch = selectedBranchID.isEmpty ? (BranchContextStore.shared.activeBranch?.branchID ?? model.item.storeID ?? "") : selectedBranchID
                if model.mode == .individual {
                    for draft in unitDrafts {
                        let readiness = unitReadiness(for: draft)
                        if !readiness.isSubmittable {
                            if readiness.isDuplicateIdentity {
                                validationMessage = Language.get("LivePetIntake_DuplicateIdentity", alter: "هذه الهوية مستخدمة في حيوان آخر")
                            } else {
                                validationMessage = String(
                                    format: Language.get("LivePetIntake_MissingFormat", alter: "ناقص: %@"),
                                    readiness.missingLabels.joined(separator: Language.get("ListSeparator", alter: "، "))
                                )
                            }
                            expandedUnitIDs.insert(draft.id)
                            return
                        }
                    }
                    ok = await model.intake(
                        mode: .individual,
                        units: unitDrafts,
                        photoDrafts: unitPhotos,
                        quantity: unitDrafts.count,
                        cost: nil,
                        supplier: unitDrafts.first?.supplier.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        notes: unitDrafts.first?.notes.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        branchID: targetBranch,
                        commandID: commandID
                    )
                } else {
                    let cleanQty = quantityText.normalizedEnglishDigits(allowsDecimal: false).trimmingCharacters(in: .whitespacesAndNewlines)
                    let qty = Int(cleanQty) ?? 0
                    guard qty > 0 else {
                        validationMessage = Language.get("LivePet_Validation_GroupQuantity", alter: "أدخل كمية صحيحة لا تقل عن حيوان واحد.")
                        return
                    }
                    let cleanCostText = costText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
                    let normalizedCostText = cleanCostText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cost = normalizedCostText.isEmpty ? nil : Double(normalizedCostText)
                    if model.canViewCosts {
                        guard let cost, cost >= 0, cost <= 999_999_999.99,
                              abs(cost * 100 - (cost * 100).rounded()) < 0.000_001 else {
                            validationMessage = Language.get(
                                "LivePet_Validation_UnitCost",
                                alter: "أدخل تكلفة استلام صالحة وبحد أقصى منزلتين عشريتين."
                            )
                            return
                        }
                    }
                    ok = await model.intake(
                        mode: .quantity,
                        unit: unitDrafts[0],
                        quantity: qty,
                        cost: cost,
                        supplier: supplier.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        branchID: targetBranch,
                        commandID: commandID
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
                    validUntil: reservationValidUntil,
                    commandID: commandID
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
                ok = await model.complete(reservation: reservation, cashReceived: cash, commandID: commandID)
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
                    reason: trimmedReason,
                    commandID: commandID
                )
            case .quarantine(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedReason.count >= 3 else {
                    validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
                    return
                }
                ok = await model.lifecycle(action: "quarantine_unit", unit: unit, reason: trimmedReason, commandID: commandID)
            case .releaseQuarantine(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedReason.count >= 3 else {
                    validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
                    return
                }
                ok = await model.lifecycle(action: "release_quarantine", unit: unit, reason: trimmedReason, commandID: commandID)
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
                    observedDeathAt: observedDeathAt,
                    commandID: commandID
                )
            case .price(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                let cleanPriceText = standardPriceText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
                guard let price = Double(cleanPriceText), price > 0, price <= 999_999_999.99 else {
                    validationMessage = Language.get("LivePet_Validation_UnitPrice", alter: "حدد سعر بيع صالحاً لكل حيوان وبحد أقصى منزلتين عشريتين.")
                    return
                }
                ok = await model.updatePrice(unit: unit, price: price, commandID: commandID)
            case .remove(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedReason.count >= 3 else {
                    validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
                    return
                }
                ok = await model.remove(unit: unit, reason: trimmedReason, commandID: commandID)
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
                ok = await model.adjustGroup(targetQuantity: target, reason: trimmedReason, commandID: commandID)
            case .archive(let target):
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedReason.count >= 3 else {
                    validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
                    return
                }
                ok = await model.archive(target, reason: trimmedReason, commandID: commandID)
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
                AdminSurface.background
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }

                PPKeyboardDismissOverlay()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)

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
                .scrollDismissesKeyboardCompat()
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
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .dismissKeyboardOnTapOutside()
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isPressed)
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
                if let nav = self?.navigationController {
                    nav.pushViewController(targetVC, animated: true)
                } else if let self = self {
                    PPAdminNavigationFallback.presentOrPush(targetVC, from: self)
                } else {
                    PPAdminNavigationFallback.presentOrPush(targetVC)
                }
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

// MARK: - Keyboard Dismiss Overlay & Extensions

private struct PPKeyboardDismissOverlay: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private var dismissTap: UITapGestureRecognizer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            setupTap()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setupTap()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let tap = dismissTap {
                tap.view?.removeGestureRecognizer(tap)
                dismissTap = nil
            }
        }

        private func setupTap() {
            guard dismissTap == nil, let hostView = parent?.view ?? view.window else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            hostView.addGestureRecognizer(tap)
            dismissTap = tap
        }

        @objc private func handleTap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var current = touch.view
            while let v = current {
                if v is UITextField || v is UITextView {
                    return false
                }
                current = v.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

fileprivate extension View {
    @ViewBuilder
    func scrollDismissesKeyboardCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }

    func dismissKeyboardOnTapOutside() -> some View {
        self.background(
            PPKeyboardDismissOverlay()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}
