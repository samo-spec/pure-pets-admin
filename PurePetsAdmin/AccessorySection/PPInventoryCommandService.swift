//
//  PPInventoryCommandService.swift
//  PurePetsAdmin
//
//  Authoritative Inventory Mutation Facade
//  Implements Section 7.1 of the Pure Pets Admin Inventory Lifecycle Repair specification.
//  Routes all catalog, stock, and delete mutations through Cloud Functions with command IDs,
//  revisions, and typed results. Zero direct Firestore catalog writes.
//

import Foundation
import Firebase
import FirebaseFunctions

@objc public final class PPInventoryCommandResult: NSObject, @unchecked Sendable {
    @objc public let success: Bool
    @objc public let commandId: String?
    @objc public let productId: String?
    @objc public let revision: Int
    @objc public let idempotent: Bool
    @objc public let action: String?
    @objc public let errorMessage: String?
    @objc public let resultKind: String
    @objc public let branchId: String?
    @objc public let projectionState: String?

    @objc public init(
        success: Bool,
        commandId: String?,
        productId: String?,
        revision: Int,
        idempotent: Bool,
        action: String?,
        resultKind: String = "confirmed",
        branchId: String? = nil,
        projectionState: String? = nil,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.commandId = commandId
        self.productId = productId
        self.revision = revision
        self.idempotent = idempotent
        self.action = action
        self.resultKind = resultKind
        self.branchId = branchId
        self.projectionState = projectionState
        self.errorMessage = errorMessage
        super.init()
    }
}

@objc public final class PPInventoryCostSummary: NSObject, @unchecked Sendable {
    @objc public let productId: String
    @objc public let branchId: String?
    @objc public let acquisitionCost: NSNumber?
    @objc public let averageUnitCost: NSNumber?
    @objc public let costSource: String
    @objc public let activeLotsCount: Int
    @objc public let currency: String

    @objc public init(
        productId: String,
        branchId: String?,
        acquisitionCost: NSNumber?,
        averageUnitCost: NSNumber?,
        costSource: String,
        activeLotsCount: Int,
        currency: String
    ) {
        self.productId = productId
        self.branchId = branchId
        self.acquisitionCost = acquisitionCost
        self.averageUnitCost = averageUnitCost
        self.costSource = costSource
        self.activeLotsCount = activeLotsCount
        self.currency = currency
        super.init()
    }
}

@objcMembers
public final class PPInventoryCommandService: NSObject, @unchecked Sendable {
    public static let shared = PPInventoryCommandService()

    private let functions = Functions.functions()
    private let firestore = Firestore.firestore()

    private override init() {
        super.init()
    }

    public func generateCommandId(action: String, targetId: String) -> String {
        return "cmd_\(action)_\(targetId)_\(UUID().uuidString.prefix(8))"
    }

    public func saveProduct(
        accessory: PetAccessory,
        branchId: String?,
        commerce: [String: Any]? = nil,
        expectedRevision: Int? = nil,
        commandId suppliedCommandId: String? = nil,
        completion: @escaping @Sendable (PPInventoryCommandResult?, Error?) -> Void
    ) {
        let isUpdate = !accessory.accessoryID.isEmpty
        let action = isUpdate ? "update" : "create"
        let productId = accessory.accessoryID
        let normalizedCommandId = suppliedCommandId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let commandId = normalizedCommandId.isEmpty
            ? generateCommandId(action: action, targetId: productId.isEmpty ? "new" : productId)
            : normalizedCommandId

        if !isUpdate, accessory.quantity > 0 {
            let normalizedBranchId = branchId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !normalizedBranchId.isEmpty, normalizedBranchId != "main_store" else {
                let error = NSError(
                    domain: "pp.inventory.command",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: Language.get(
                        "Inventory_SpecificBranchRequired",
                        alter: "اختر فرعاً محدداً قبل إنشاء مخزون أولي لهذا الصنف."
                    )]
                )
                completion(nil, error)
                return
            }
        }

        var payload: [String: Any] = [
            "name": accessory.name,
            "nameEn": accessory.nameEn ?? "",
            "desc": accessory.desc,
            "descEn": accessory.descEn ?? "",
            "category": accessory.category ?? "",
            "price": accessory.price,
            "discountPercent": accessory.discountPercent ?? 0,
            "discountAmount": accessory.discountAmount ?? 0,
            "petMainCategoryID": accessory.petMainCategoryID,
            "petSubCategoryID": accessory.petSubCategoryID,
            "condition": accessory.condition.rawValue,
            "imageURLsArray": accessory.imageURLsArray,
            "isNew": accessory.isNew,
            "hasOffer": accessory.hasOffer,
            "showInAppMarket": accessory.showInAppMarket,
            "active": accessory.active
        ]
        if !isUpdate {
            payload["quantity"] = accessory.quantity
            payload["product_type"] = accessory.accessKindType == .typeLivePets ? "live" : "normal"
            payload["accessKindType"] = accessory.accessKindType.rawValue
        }
        if let sku = accessory.sku, !sku.isEmpty { payload["sku"] = sku }
        if let barcode = accessory.barcode, !barcode.isEmpty { payload["barcode"] = barcode }
        if !isUpdate, let costPrice = accessory.costPrice { payload["costPrice"] = costPrice }
        if let wholesalePrice = accessory.wholesalePrice { payload["wholesalePrice"] = wholesalePrice }
        if let weight = accessory.weight { payload["weight"] = weight }
        if let weightUnit = accessory.weightUnit, !weightUnit.isEmpty { payload["weightUnit"] = weightUnit }
        if let size = accessory.size, !size.isEmpty { payload["size"] = size }
        if let expiryDate = accessory.expiryDate { payload["expiryDate"] = ISO8601DateFormatter().string(from: expiryDate) }
        if let policy = accessory.inventoryTrackingPolicy, !policy.isEmpty { payload["inventoryTrackingPolicy"] = policy }
        if let days = accessory.shelfLifeDays { payload["shelfLifeDays"] = days }
        if let days = accessory.guaranteedShelfLifeDays { payload["guaranteedShelfLifeDays"] = days }
        if let days = accessory.expiryCutoffDays { payload["expiryCutoffDays"] = days }

        if !isUpdate, let bId = branchId, !bId.isEmpty, bId != "main_store" {
            payload["storeID"] = bId
            payload["branchId"] = bId
        }

        if let commerce = commerce {
            payload["commerce"] = commerce
        }

        var requestData: [String: Any] = [
            "contractVersion": 2,
            "action": action,
            "commandId": commandId,
            "payload": payload
        ]
        if !productId.isEmpty {
            requestData["productId"] = productId
        }
        let authoritativeExpectedRevision = expectedRevision ?? (isUpdate && accessory.revision > 0 ? accessory.revision : nil)
        if let rev = authoritativeExpectedRevision {
            requestData["expectedRevision"] = rev
        }

        functions.httpsCallable("validateInventoryChange").call(requestData) { result, error in
            if let error = error {
                completion(nil, error)
                return
            }
            guard let data = result?.data as? [String: Any],
                  let ok = data["ok"] as? Bool, ok,
                  (data["commandId"] as? String) == commandId else {
                let err = NSError(domain: "pp.inventory.command", code: 500, userInfo: [NSLocalizedDescriptionKey: Language.get("Inventory_InvalidCommandResponse", alter: "تعذر التحقق من استجابة خدمة المخزون.")])
                completion(nil, err)
                return
            }
            let resId = data["productId"] as? String ?? productId
            let rev = data["revision"] as? Int ?? 1
            let idempotent = data["idempotent"] as? Bool ?? false
            let cmdResult = PPInventoryCommandResult(
                success: true,
                commandId: commandId,
                productId: resId,
                revision: rev,
                idempotent: idempotent,
                action: action,
                resultKind: data["resultKind"] as? String ?? (idempotent ? "already_applied" : "confirmed"),
                branchId: data["branchId"] as? String,
                projectionState: data["projectionState"] as? String
            )
            completion(cmdResult, nil)
        }
    }

    public func adjustStock(
        productId: String,
        branchId: String,
        delta: Int?,
        newQuantity: Int?,
        reason: String = "manual_adjustment",
        notes: String? = nil,
        expectedRevision: Int? = nil,
        commandId suppliedCommandId: String? = nil,
        completion: @escaping @Sendable (PPInventoryCommandResult?, Error?) -> Void
    ) {
        guard !branchId.isEmpty && branchId != "main_store" else {
            let err = NSError(domain: "pp.inventory.command", code: 400, userInfo: [NSLocalizedDescriptionKey: Language.get("SelectSpecificBranchFirst", alter: "يرجى اختيار فرع محدد أولاً")])
            completion(nil, err)
            return
        }
        let commandId = suppliedCommandId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? suppliedCommandId!
            : generateCommandId(action: "adjust", targetId: productId)
        var payload: [String: Any] = [
            "productId": productId,
            "branchId": branchId,
            "reason": reason,
            "commandId": commandId
        ]
        if let d = delta { payload["delta"] = d }
        if let n = newQuantity { payload["newQuantity"] = n }
        if let nt = notes { payload["notes"] = nt }
        if let rev = expectedRevision { payload["expectedRevision"] = rev }

        functions.httpsCallable("adjustBranchStock").call(["contractVersion": 2, "payload": payload]) { result, error in
            if let error = error {
                completion(nil, error)
                return
            }
            guard let data = result?.data as? [String: Any],
                  data["ok"] as? Bool == true,
                  (data["commandId"] as? String) == commandId else {
                let err = NSError(domain: "pp.inventory.command", code: 500, userInfo: [NSLocalizedDescriptionKey: Language.get("Inventory_InvalidAdjustmentResponse", alter: "تعذر التحقق من نتيجة تعديل المخزون.")])
                completion(nil, err)
                return
            }
            let rev = data["revision"] as? Int ?? 1
            let idempotent = data["idempotent"] as? Bool ?? false
            let cmdResult = PPInventoryCommandResult(
                success: true,
                commandId: commandId,
                productId: productId,
                revision: rev,
                idempotent: idempotent,
                action: "adjust",
                resultKind: idempotent ? "already_applied" : "confirmed",
                branchId: data["branchId"] as? String
            )
            completion(cmdResult, nil)
        }
    }

    public func softDelete(
        productId: String,
        branchId: String? = nil,
        reason: String = "deleted_by_admin",
        expectedRevision: Int? = nil,
        commandId suppliedCommandId: String? = nil,
        completion: @escaping @Sendable (PPInventoryCommandResult?, Error?) -> Void
    ) {
        let commandId = suppliedCommandId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? suppliedCommandId!
            : generateCommandId(action: "delete", targetId: productId)
        var payload: [String: Any] = ["reason": reason]
        if let bid = branchId, !bid.isEmpty, bid != "main_store" {
            payload["branchId"] = bid
        }
        var requestData: [String: Any] = [
            "contractVersion": 2,
            "action": "delete",
            "productId": productId,
            "commandId": commandId,
            "payload": payload
        ]
        if let expectedRevision { requestData["expectedRevision"] = expectedRevision }
        functions.httpsCallable("validateInventoryChange").call(requestData) { result, error in
            if let error = error {
                completion(nil, error)
                return
            }
            guard let data = result?.data as? [String: Any],
                  data["ok"] as? Bool == true,
                  (data["commandId"] as? String) == commandId else {
                let err = NSError(domain: "pp.inventory.command", code: 500, userInfo: [NSLocalizedDescriptionKey: Language.get("Inventory_InvalidDeleteResponse", alter: "تعذر التحقق من نتيجة أرشفة الصنف.")])
                completion(nil, err)
                return
            }
            let cmdResult = PPInventoryCommandResult(
                success: true,
                commandId: commandId,
                productId: productId,
                revision: data["revision"] as? Int ?? 0,
                idempotent: data["idempotent"] as? Bool ?? false,
                action: "delete",
                resultKind: data["resultKind"] as? String ?? "accepted_waiting_projection",
                branchId: data["branchId"] as? String,
                projectionState: data["projectionState"] as? String
            )
            completion(cmdResult, nil)
        }
    }

    public func fetchCostSummary(
        productId: String,
        branchId: String? = nil,
        completion: @escaping @Sendable (PPInventoryCostSummary?, Error?) -> Void
    ) {
        var payload: [String: Any] = ["productId": productId]
        if let bid = branchId, !bid.isEmpty, bid != "main_store" {
            payload["branchId"] = bid
        }
        functions.httpsCallable("getInventoryCostSummary").call(["payload": payload]) { result, error in
            if let error = error {
                completion(nil, error)
                return
            }
            guard let data = result?.data as? [String: Any] else {
                completion(nil, nil)
                return
            }
            let summary = PPInventoryCostSummary(
                productId: productId,
                branchId: data["branchId"] as? String,
                acquisitionCost: data["acquisitionCost"] as? NSNumber,
                averageUnitCost: data["averageUnitCost"] as? NSNumber,
                costSource: data["costSource"] as? String ?? "unknown",
                activeLotsCount: data["activeLotsCount"] as? Int ?? 0,
                currency: data["currency"] as? String ?? "QAR"
            )
            completion(summary, nil)
        }
    }

    /// Confirms that a command result is visible in the authoritative catalog
    /// before a screen reports a fully saved state or deletes replaced media.
    public func readBackProduct(
        productId: String,
        minimumRevision: Int,
        completion: @escaping @Sendable (PetAccessory?, Error?) -> Void
    ) {
        let normalizedProductId = productId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProductId.isEmpty else {
            let error = NSError(
                domain: "pp.inventory.command",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: Language.get(
                    "Inventory_MissingProductIdentifier",
                    alter: "تعذر تأكيد الحفظ لأن معرّف الصنف غير صالح."
                )]
            )
            completion(nil, error)
            return
        }

        firestore.collection("petAccessories").document(normalizedProductId).getDocument { snapshot, error in
            if let error {
                completion(nil, error)
                return
            }
            guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                let error = NSError(
                    domain: "pp.inventory.command",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: Language.get(
                        "Inventory_ReadbackMissing",
                        alter: "اعتمد الخادم العملية، لكن تعذر العثور على الصنف عند التحقق النهائي. أعد المحاولة دون تغيير البيانات."
                    )]
                )
                completion(nil, error)
                return
            }
            let revision = (data["revision"] as? NSNumber)?.intValue ?? (data["revision"] as? Int) ?? 0
            guard revision >= minimumRevision else {
                let error = NSError(
                    domain: "pp.inventory.command",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: Language.get(
                        "Inventory_ReadbackPending",
                        alter: "اعتمد الخادم العملية، لكن النسخة المؤكدة لم تصل بعد. أعد المحاولة دون تعديل البيانات."
                    )]
                )
                completion(nil, error)
                return
            }
            completion(PetAccessory(dictionary: data, documentID: normalizedProductId), nil)
        }
    }
}
