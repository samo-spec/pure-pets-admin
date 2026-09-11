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

    @objc public init(
        success: Bool,
        commandId: String?,
        productId: String?,
        revision: Int,
        idempotent: Bool,
        action: String?,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.commandId = commandId
        self.productId = productId
        self.revision = revision
        self.idempotent = idempotent
        self.action = action
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
        completion: @escaping @Sendable (PPInventoryCommandResult?, Error?) -> Void
    ) {
        let isUpdate = !accessory.accessoryID.isEmpty
        let action = isUpdate ? "update" : "create"
        let productId = accessory.accessoryID
        let commandId = generateCommandId(action: action, targetId: productId.isEmpty ? "new" : productId)

        var payload: [String: Any] = [
            "name": accessory.name,
            "category": accessory.category ?? "",
            "quantity": accessory.quantity,
            "product_type": accessory.accessKindType == .typeLivePets ? "live" : "normal",
            "accessKindType": accessory.accessKindType.rawValue
        ]
        if let sku = accessory.sku, !sku.isEmpty { payload["sku"] = sku }
        if let barcode = accessory.barcode, !barcode.isEmpty { payload["barcode"] = barcode }
        payload["price"] = accessory.price
        payload["finalPrice"] = accessory.finalPrice
        if !accessory.desc.isEmpty { payload["description"] = accessory.desc }
        if !accessory.imageURLsArray.isEmpty { payload["imageURLs"] = accessory.imageURLsArray }

        if let bId = branchId, !bId.isEmpty, bId != "main_store" {
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
        if let rev = expectedRevision {
            requestData["expectedRevision"] = rev
        }

        functions.httpsCallable("validateInventoryChange").call(requestData) { result, error in
            if let error = error {
                completion(nil, error)
                return
            }
            guard let data = result?.data as? [String: Any],
                  let ok = data["ok"] as? Bool, ok else {
                let err = NSError(domain: "pp.inventory.command", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response from inventory service"])
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
                action: action
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
        completion: @escaping @Sendable (PPInventoryCommandResult?, Error?) -> Void
    ) {
        guard !branchId.isEmpty && branchId != "main_store" else {
            let err = NSError(domain: "pp.inventory.command", code: 400, userInfo: [NSLocalizedDescriptionKey: Language.get("SelectSpecificBranchFirst", alter: "يرجى اختيار فرع محدد أولاً")])
            completion(nil, err)
            return
        }
        let commandId = generateCommandId(action: "adjust", targetId: productId)
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

        functions.httpsCallable("adjustBranchStock").call(["payload": payload]) { result, error in
            if let error = error {
                completion(nil, error)
                return
            }
            guard let data = result?.data as? [String: Any] else {
                let err = NSError(domain: "pp.inventory.command", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response from branch stock adjustment"])
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
                action: "adjust"
            )
            completion(cmdResult, nil)
        }
    }

    public func softDelete(
        productId: String,
        branchId: String? = nil,
        reason: String = "deleted_by_admin",
        completion: @escaping @Sendable (PPInventoryCommandResult?, Error?) -> Void
    ) {
        let commandId = generateCommandId(action: "delete", targetId: productId)
        var payload: [String: Any] = ["reason": reason]
        if let bid = branchId, !bid.isEmpty, bid != "main_store" {
            payload["branchId"] = bid
        }
        let requestData: [String: Any] = [
            "contractVersion": 2,
            "action": "delete",
            "productId": productId,
            "commandId": commandId,
            "payload": payload
        ]
        functions.httpsCallable("validateInventoryChange").call(requestData) { result, error in
            if let error = error {
                completion(nil, error)
                return
            }
            let cmdResult = PPInventoryCommandResult(
                success: true,
                commandId: commandId,
                productId: productId,
                revision: 0,
                idempotent: false,
                action: "delete"
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
}
