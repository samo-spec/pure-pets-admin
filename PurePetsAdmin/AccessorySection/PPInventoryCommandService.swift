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
        do {
            let request = try prepareProductSave(accessory: accessory, branchId: branchId, commerce: commerce,
                expectedRevision: expectedRevision, commandId: suppliedCommandId)
            executeProductSave(request: request, completion: completion)
        } catch {
            completion(nil, error)
        }
    }

    /// Builds the one canonical wire envelope so an editor can persist it before
    /// sending and replay the exact same command after an ambiguous outcome.
    public func prepareProductSave(
        accessory: PetAccessory,
        branchId: String?,
        commerce: [String: Any]? = nil,
        expectedRevision: Int? = nil,
        commandId suppliedCommandId: String? = nil
    ) throws -> [String: Any] {
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
                throw error
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
        // A variant member's public visibility is family-owned and governed
        // exclusively by upsertProductVariantFamily. Sending showInAppMarket on
        // catalog update is rejected by the backend to prevent competing writers.
        if isUpdate, let familyId = accessory.productFamilyId?.trimmingCharacters(in: .whitespacesAndNewlines), !familyId.isEmpty {
            payload.removeValue(forKey: "showInAppMarket")
        }
        // Image metadata (width/height per asset) was previously dropped here:
        // only the URL array was sent, so the server never received dimensions
        // and a client could not rely on them coming back. `imageMeta` is
        // allowlisted by validateInventoryChange for both create and update, so
        // it is safe to send, and per-colour media needs it.
        //
        // `blurHash` is deliberately NOT sent. It is absent from both backend
        // payload allowlists and is server-owned — forced to "" on create at
        // validateInventoryChange.js:469 — so sending it would be rejected with
        // INVENTORY_UNKNOWN_FIELDS and, since Phase 3b, that now fails the whole
        // save closed instead of being silently stripped.
        if let imageMeta = accessory.imageMeta, !imageMeta.isEmpty {
            payload["imageMeta"] = imageMeta
        }
        if !isUpdate {
            if let catID = accessory.accessoryCategoryID, !catID.isEmpty {
                payload["AccessoryCategoryID"] = catID
            }
            payload["quantity"] = accessory.quantity
            payload["product_type"] = accessory.accessKindType == .typeLivePets ? "live" : "normal"
            payload["accessKindType"] = accessory.accessKindType.rawValue
        } else if accessory.accessKindType != .typeLivePets {
            payload["quantity"] = accessory.quantity
        }
        // Cost is deliberately **not** sent for live pets.
        //
        // Sending it for a normal product is correct and valuable: on update the
        // server records a `stockMovements` entry with
        // `movementCategory: "cost_adjustment"` / `reason: "catalog_update_cost"`
        // (validateInventoryChange.js:2304-2317), which is the durable, non-public
        // home for cost — and is exactly what the editor's cost fallback reads
        // back. It is always scrubbed from the world-readable catalog document
        // (`delete updatePayload.costPrice`, :2084) and is never stored on create
        // either (destructured out at :1107).
        //
        // For a live pet the same field is rejected outright on update (:2076,
        // "Live-pet costs must be recorded through protected intake or
        // individual-unit records"). Live-pet cost is legitimate only on the
        // protected create action and on individual-unit records.
        //
        // This is a boundary assertion, not a bug fix: `saveAccessory` routes every
        // live pet to `finalizeLivePetSave` before reaching here, so no live pet
        // travels this path today. But `prepareProductSave` is public on a shared
        // service and accepts any `PetAccessory`, so the invariant is enforced
        // where the payload is actually built rather than left to the caller.
        let isLiveProduct = accessory.accessKindType == .typeLivePets
        if !isLiveProduct, let costPrice = accessory.costPrice {
            payload["costPrice"] = costPrice
        }
        if let sku = accessory.sku, !sku.isEmpty { payload["sku"] = sku }
        if let barcode = accessory.barcode, !barcode.isEmpty { payload["barcode"] = barcode }
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

        return requestData
    }

    public func executeProductSave(
        request: [String: Any],
        completion: @escaping @Sendable (PPInventoryCommandResult?, Error?) -> Void
    ) {
        executeProductSave(request: request, retryOnStaleRevision: true, completion: completion)
    }

    @nonobjc public func executeProductSave(
        request: [String: Any],
        retryOnStaleRevision: Bool,
        completion: @escaping @Sendable (PPInventoryCommandResult?, Error?) -> Void
    ) {
        guard let commandId = request["commandId"] as? String, !commandId.isEmpty,
              let action = request["action"] as? String, ["create", "update"].contains(action),
              request["payload"] as? [String: Any] != nil else {
            completion(nil, NSError(domain: "pp.inventory.command", code: 400,
                userInfo: [NSLocalizedDescriptionKey: Language.get("Inventory_InvalidCommandResponse", alter: "تعذر التحقق من استجابة خدمة المخزون.")]))
            return
        }
        let productId = request["productId"] as? String ?? ""
        let boxed = PPSendableRequest(data: request)
        functions.httpsCallable("validateInventoryChange").call(boxed.data) { [weak self] result, error in
            guard let self = self else {
                completion(nil, error)
                return
            }
            if let error = error {
                // Fail closed on an unsupported-field rejection.
                if let rejection = PPInventoryCommandService.unsupportedFieldRejection(from: error) {
                    completion(nil, rejection)
                    return
                }
                // If this is a stale revision conflict, retry once with the current authoritative revision
                if retryOnStaleRevision, let stale = PPInventoryCommandService.staleRevision(from: error) {
                    var retriedRequest = boxed.data
                    retriedRequest["expectedRevision"] = stale.current
                    let freshCommandId = self.generateCommandId(action: action, targetId: productId.isEmpty ? "new" : productId)
                    retriedRequest["commandId"] = freshCommandId
                    self.executeProductSave(request: retriedRequest, retryOnStaleRevision: false, completion: completion)
                    return
                }
                completion(nil, error)
                return
            }
            self.parseCommandResponse(
                result: result,
                commandId: commandId,
                productId: productId,
                action: action,
                completion: completion
            )
        }
    }

    /// Domain for client-side inventory command failures raised by this facade.
    @objc public static let errorDomain = "pp.inventory.command"
    /// Raised when the backend rejected one or more payload fields outright.
    @objc public static let unsupportedFieldsErrorCode = 422

    /// Recognizes optimistic concurrency stale revision conflicts from the backend.
    /// Returns (expected, current) revision if the error is a STALE_REVISION conflict.
    @nonobjc public static func staleRevision(from error: Error) -> (expected: Int, current: Int)? {
        let nsError = error as NSError
        let details = (nsError.userInfo["details"] as? [String: Any])
            ?? (nsError.userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any])
            ?? [:]

        var current: Int? = nil
        var expected: Int? = nil

        if (details["domainCode"] as? String) == "STALE_REVISION" {
            if let cur = details["currentRevision"] as? Int {
                current = cur
            } else if let curNum = details["currentRevision"] as? NSNumber {
                current = curNum.intValue
            }
            if let exp = details["expectedRevision"] as? Int {
                expected = exp
            } else if let expNum = details["expectedRevision"] as? NSNumber {
                expected = expNum.intValue
            }
        }

        if current == nil {
            let candidates = [
                nsError.localizedDescription,
                nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? "",
                nsError.description
            ]
            let pattern = "Expected\\s+(\\d+),\\s*current\\s+is\\s+(\\d+)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                for text in candidates where !text.isEmpty {
                    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
                    if let match = regex.firstMatch(in: text, options: [], range: nsRange),
                       match.numberOfRanges >= 3 {
                        if let r1 = Range(match.range(at: 1), in: text), let expVal = Int(text[r1]) {
                            expected = expVal
                        }
                        if let r2 = Range(match.range(at: 2), in: text), let curVal = Int(text[r2]) {
                            current = curVal
                            break
                        }
                    }
                }
            }
        }

        if let current = current {
            return (expected ?? 0, current)
        }
        return nil
    }

    /// Recognizes the backend's unsupported-field rejection.
    ///
    /// Matches on the structured `domainCode` the callable sends
    /// (`INVENTORY_UNKNOWN_FIELDS`), never on the localized message. Returns nil
    /// for every other failure so the original error is propagated unchanged.
    static func unsupportedFieldRejection(from error: Error) -> NSError? {
        let nsError = error as NSError
        let details = (nsError.userInfo["details"] as? [String: Any])
            ?? (nsError.userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any])
            ?? [:]
        guard (details["domainCode"] as? String) == "INVENTORY_UNKNOWN_FIELDS" else { return nil }

        let fields = (details["fields"] as? [String])?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        let message: String
        if fields.isEmpty {
            message = Language.get(
                "Inventory_UnsupportedFields_Generic",
                alter: "رفض الخادم بعض الحقول. لم يتم الحفظ. حدّث التطبيق وحاول مرة أخرى."
            )
        } else {
            let template = Language.get(
                "Inventory_UnsupportedFields_Named",
                alter: "رفض الخادم هذه الحقول ولم يتم الحفظ: %@. حدّث التطبيق."
            )
            message = String(format: template, fields.joined(separator: ", "))
        }

        return NSError(
            domain: PPInventoryCommandService.errorDomain,
            code: PPInventoryCommandService.unsupportedFieldsErrorCode,
            userInfo: [
                NSLocalizedDescriptionKey: message,
                "domainCode": "INVENTORY_UNKNOWN_FIELDS",
                "fields": fields,
                NSUnderlyingErrorKey: nsError,
            ]
        )
    }

    private func parseCommandResponse(
        result: HTTPSCallableResult?,
        commandId: String,
        productId: String,
        action: String,
        completion: @escaping @Sendable (PPInventoryCommandResult?, Error?) -> Void
    ) {
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

        let boxed = PPSendableRequest(data: ["contractVersion": 2, "payload": payload])
        functions.httpsCallable("adjustBranchStock").call(boxed.data) { result, error in
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

    public func setAppMarketVisibility(
        productId: String,
        visible: Bool,
        expectedRevision: Int? = nil,
        commandId suppliedCommandId: String? = nil,
        completion: @escaping @Sendable (PPInventoryCommandResult?, Error?) -> Void
    ) {
        let normalizedProductId = productId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProductId.isEmpty else {
            let err = NSError(domain: "pp.inventory.command", code: 400, userInfo: [NSLocalizedDescriptionKey: Language.get("Inventory_MissingProductIdentifier", alter: "تعذر تنفيذ العملية لأن معرّف الصنف غير صالح.")])
            completion(nil, err)
            return
        }
        let normalizedSuppliedCommandId = suppliedCommandId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let commandId = normalizedSuppliedCommandId.isEmpty
            ? generateCommandId(action: "visibility", targetId: normalizedProductId)
            : normalizedSuppliedCommandId

        var requestData: [String: Any] = [
            "contractVersion": 2,
            "action": "update",
            "productId": normalizedProductId,
            "commandId": commandId,
            "payload": ["showInAppMarket": visible]
        ]
        if let expectedRevision { requestData["expectedRevision"] = expectedRevision }

        let boxed = PPSendableRequest(data: requestData)
        functions.httpsCallable("validateInventoryChange").call(boxed.data) { result, error in
            if let error {
                completion(nil, error)
                return
            }
            guard let data = result?.data as? [String: Any],
                  data["ok"] as? Bool == true,
                  (data["commandId"] as? String) == commandId else {
                let err = NSError(domain: "pp.inventory.command", code: 500, userInfo: [NSLocalizedDescriptionKey: Language.get("Inventory_InvalidCommandResponse", alter: "تعذر التحقق من استجابة خدمة المخزون.")])
                completion(nil, err)
                return
            }
            let idempotent = data["idempotent"] as? Bool ?? false
            completion(PPInventoryCommandResult(
                success: true,
                commandId: commandId,
                productId: normalizedProductId,
                revision: data["revision"] as? Int ?? 0,
                idempotent: idempotent,
                action: "update",
                resultKind: data["resultKind"] as? String ?? (idempotent ? "already_applied" : "confirmed"),
                branchId: data["branchId"] as? String,
                projectionState: data["projectionState"] as? String
            ), nil)
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
        let boxed = PPSendableRequest(data: requestData)
        functions.httpsCallable("validateInventoryChange").call(boxed.data) { result, error in
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
        let boxed = PPSendableRequest(data: ["payload": payload])
        functions.httpsCallable("getInventoryCostSummary").call(boxed.data) { result, error in
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

private struct PPSendableRequest: @unchecked Sendable {
    let data: [String: Any]
}
