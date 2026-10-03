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
            "isAllCategories": accessory.isAllCategories,
            "isAllSubCategories": accessory.isAllSubCategories,
            "condition": accessory.condition.rawValue,
            "imageURLsArray": accessory.imageURLsArray,
            "isNew": accessory.isNew,
            "hasOffer": accessory.hasOffer,
            "showInAppMarket": accessory.showInAppMarket,
            "active": accessory.active
        ]
        if let mainIDs = accessory.petMainCategoryIDs as? [NSNumber], !mainIDs.isEmpty {
            payload["petMainCategoryIDs"] = mainIDs.map { $0.intValue }
        } else if accessory.petMainCategoryID > 0 {
            payload["petMainCategoryIDs"] = [accessory.petMainCategoryID]
        }
        if let subIDs = accessory.petSubCategoryIDs as? [NSNumber], !subIDs.isEmpty {
            payload["petSubCategoryIDs"] = subIDs.map { $0.intValue }
        } else if accessory.petSubCategoryID > 0 {
            payload["petSubCategoryIDs"] = [accessory.petSubCategoryID]
        }
        if let catID = accessory.accessoryCategoryID, !catID.isEmpty {
            payload["AccessoryCategoryID"] = catID
        }
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
        // Infra treats a missing/zero legacy revision as one. Still send that
        // baseline so a concurrent update cannot turn this into an unchecked save.
        let authoritativeExpectedRevision = expectedRevision ?? (isUpdate ? max(1, accessory.revision) : nil)
        if let rev = authoritativeExpectedRevision {
            requestData["expectedRevision"] = rev
        }

        return requestData
    }

    public func executeProductSave(
        request: [String: Any],
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
                // A conflict requires reloading and reviewing the current product.
                // Rebasing this old payload (or replacing its durable command ID)
                // would overwrite the concurrent editor's accepted changes.
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

    // MARK: - Inventory failure presentation and retry classification

    /// A rejection of this attempt does not prove that an earlier timed-out
    /// attempt failed. Callers must retain recovery when it may have committed.
    @nonobjc public static func isDefinitiveSaveRejection(_ error: Error) -> Bool {
        let chain = inventoryErrorChain(error)
        if chain.contains(where: { $0.domain == errorDomain && $0.code == unsupportedFieldsErrorCode }) {
            return true
        }
        guard let callable = chain.first(where: isCallableError) else { return false }
        return [FunctionsErrorCode.invalidArgument.rawValue,
                FunctionsErrorCode.permissionDenied.rawValue,
                FunctionsErrorCode.unauthenticated.rawValue,
                FunctionsErrorCode.failedPrecondition.rawValue,
                FunctionsErrorCode.notFound.rawValue].contains(callable.code)
    }

    /// Keep diagnostics out of operator copy. These messages describe the cause
    /// and next action without claiming an ambiguous save never reached the server.
    @nonobjc public static func userFacingErrorMessage(for error: Error) -> String {
        let chain = inventoryErrorChain(error)
        let domainCode = chain.lazy.compactMap { item -> String? in
            let details = inventoryErrorDetails(item)
            return (details["domainCode"] as? String) ?? (item.userInfo["domainCode"] as? String)
        }.first ?? ""
        switch domainCode {
        case "INVENTORY_UNKNOWN_FIELDS", "INVENTORY_CONTRACT_VERSION_UNSUPPORTED":
            return Language.get("Inventory_Error_UpdateRequired", alter: "بيانات الحفظ غير متوافقة مع إصدار الخدمة. حدّث التطبيق ثم أعد المحاولة. إذا استمرت المشكلة، تواصل مع الدعم مع إبقاء الحفظ المعلّق محفوظاً.")
        case "BRANCH_ID_REQUIRED":
            return Language.get("Inventory_SpecificBranchRequired", alter: "اختر فرعاً محدداً قبل إنشاء مخزون أولي لهذا الصنف.")
        case "BRANCH_INACTIVE", "INVENTORY_UNIT_BRANCH_MISMATCH":
            return Language.get("Inventory_Error_BranchUnavailable", alter: "الفرع المختار غير متاح لهذه العملية. اختر فرعاً نشطاً تملك صلاحية الوصول إليه، أو اطلب من المسؤول مراجعة الفرع وصلاحياتك.")
        case "STALE_REVISION":
            return Language.get("Inventory_CatalogChangedReopen", alter: "تغير الصنف أثناء التحرير. أغلق المحرر وأعد فتح الصنف لمراجعة أحدث البيانات قبل الحفظ.")
        case "INVENTORY_COMMAND_CONFLICT":
            return Language.get("Inventory_Error_CommandConflict", alter: "يرتبط سجل الحفظ بعملية أخرى. لا تنشئ نسخة جديدة من الصنف. راجع نتيجة العملية في المخزون، ثم تواصل مع الدعم لاستعادة الحفظ المعلّق.")
        case "INVENTORY_LOT_MIGRATION_REQUIRED", "TRACKED_INVENTORY_OPERATION_REQUIRED", "INVALID_TRACKING_POLICY":
            return Language.get("Inventory_Error_TrackingOperation", alter: "يتطلب نوع التتبع عملية مخزون مخصصة. افتح سجل الصنف واستخدم استلام الدفعات أو إدارة الحيوانات الفردية حسب نوعه. اطلب مساعدة مسؤول المخزون إذا لم تتوفر العملية.")
        case "VARIANT_VISIBILITY_REQUIRES_FAMILY_COMMAND":
            return Language.get("Inventory_Error_VariantVisibility", alter: "عرض هذا الصنف مرتبط بمجموعة المتغيرات. افتح محرر المتغيرات وحدد المتغير المعروض أو الافتراضي، ثم احفظ المجموعة.")
        case "INVENTORY_DELETE_BLOCKED_BY_STOCK":
            return Language.get("Inventory_Error_RemainingStock", alter: "لا يمكن أرشفة الصنف لوجود مخزون متبقٍ. راجع كميات الفروع والحجوزات وأكمل عملية المخزون المناسبة قبل الأرشفة.")
        case "LIVE_PET_UNIT_MEDIA_STALE":
            return Language.get("LivePetIntake_UnitPhotoStagedConflict", alter: "تعارضت الصورة المجهزة مع ملف موجود. اختر الصورة مجدداً وحاول مرة أخرى.")
        default:
            break
        }
        if chain.contains(where: { $0.domain == errorDomain && $0.code == unsupportedFieldsErrorCode }) {
            return Language.get("Inventory_Error_UpdateRequired", alter: "بيانات الحفظ غير متوافقة مع إصدار الخدمة. حدّث التطبيق ثم أعد المحاولة. إذا استمرت المشكلة، تواصل مع الدعم مع إبقاء الحفظ المعلّق محفوظاً.")
        }
        if let serviceError = chain.first(where: { isCallableError($0) || $0.domain == "FIRFirestoreErrorDomain" }) {
            switch serviceError.code {
            case FunctionsErrorCode.unauthenticated.rawValue:
                return Language.get("Inventory_Error_SessionExpired", alter: "تعذر التحقق من جلسة الحساب. أعد تسجيل الدخول بالحساب نفسه ثم افتح المحرر لاستعادة أي حفظ معلّق.")
            case FunctionsErrorCode.permissionDenied.rawValue:
                return Language.get("Inventory_Error_PermissionDenied", alter: "حسابك لا يملك صلاحية هذه العملية أو الفرع المختار. اطلب من المسؤول مراجعة صلاحية إدارة الأصناف ونطاق الفروع، ثم أعد المحاولة.")
            case FunctionsErrorCode.invalidArgument.rawValue, FunctionsErrorCode.outOfRange.rawValue:
                if isCallableError(serviceError), let guidance = legacyValidationGuidance(serviceError) {
                    return guidance
                }
                return Language.get("Inventory_Error_InvalidInput", alter: "رفضت الخدمة إحدى قيم الصنف. راجع الاسم والتصنيف والفرع، والأسعار غير السالبة بمنزلتين عشريتين، والكميات الصحيحة. صحح الحقول المشار إليها ثم احفظ. إذا استمرت المشكلة، تواصل مع الدعم.")
            case FunctionsErrorCode.failedPrecondition.rawValue:
                return Language.get("Inventory_Error_Precondition", alter: "حالة الصنف أو الفرع لا تسمح بهذه العملية حالياً. راجع أحدث بيانات الصنف وحالة الفرع. إذا ظهر حفظ معلّق، احتفظ به واطلب من مسؤول المخزون مراجعة النتيجة قبل بدء حفظ جديد.")
            case FunctionsErrorCode.notFound.rawValue:
                return Language.get("Inventory_Error_NotFound", alter: "تعذر العثور على الصنف أو الفرع المطلوب. حدّث قائمة المخزون وتحقق من وجودهما. احتفظ بأي حفظ معلّق وتواصل مع المسؤول إذا بقيت المشكلة.")
            case FunctionsErrorCode.alreadyExists.rawValue:
                return Language.get("Inventory_Error_AlreadyExists", alter: "يوجد سجل أو عملية بهذه الهوية بالفعل. راجع الصنف الموجود والباركود ورمز الصنف قبل المحاولة. إذا ظهر حفظ معلّق، احتفظ به وتواصل مع الدعم لتأكيد النتيجة.")
            case FunctionsErrorCode.resourceExhausted.rawValue:
                return Language.get("Inventory_Error_Busy", alter: "الخدمة مشغولة حالياً. انتظر قليلاً ثم أعد المحاولة. إذا ظهر حفظ معلّق، استخدم استعادة الحفظ المعلّق لإكمال العملية نفسها.")
            case FunctionsErrorCode.deadlineExceeded.rawValue, FunctionsErrorCode.unavailable.rawValue,
                 FunctionsErrorCode.cancelled.rawValue, FunctionsErrorCode.aborted.rawValue:
                return Language.get("Inventory_Error_Connection", alter: "انقطع الاتصال أو انتهت مهلة العملية. تحقق من الإنترنت ثم أعد المحاولة. إذا ظهر حفظ معلّق، استخدم استعادة الحفظ المعلّق دون تغيير البيانات أو إنشاء صنف آخر.")
            default:
                break
            }
        }
        if chain.contains(where: { $0.domain == NSURLErrorDomain }) {
            return Language.get("Inventory_Error_Connection", alter: "انقطع الاتصال أو انتهت مهلة العملية. تحقق من الإنترنت ثم أعد المحاولة. إذا ظهر حفظ معلّق، استخدم استعادة الحفظ المعلّق دون تغيير البيانات أو إنشاء صنف آخر.")
        }
        // Errors created by this facade already contain app-localized guidance;
        // never trust arbitrary SDK/server descriptions through this exception.
        if let local = chain.first(where: { $0.domain == errorDomain && [400, 404, 409].contains($0.code) }),
           let message = local.userInfo[NSLocalizedDescriptionKey] as? String, !message.isEmpty {
            return message
        }
        return Language.get("Inventory_Error_Unknown", alter: "تعذر إكمال العملية أو تأكيد نتيجتها. أعد المحاولة من المحرر نفسه لاستعادة أي حفظ معلّق. إذا استمرت المشكلة، احتفظ بالبيانات وتواصل مع الدعم قبل إنشاء صنف آخر.")
    }

    @nonobjc private static func inventoryErrorChain(_ error: Error) -> [NSError] {
        var chain: [NSError] = []
        var next: NSError? = error as NSError
        while let current = next, chain.count < 8 {
            guard !chain.contains(where: { $0 === current }) else { break }
            chain.append(current)
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return chain
    }

    @nonobjc private static func isCallableError(_ error: NSError) -> Bool {
        error.domain == FunctionsErrorDomain || error.domain == "com.firebase.functions"
    }

    @nonobjc private static func inventoryErrorDetails(_ error: NSError) -> [String: Any] {
        (error.userInfo["details"] as? [String: Any])
            ?? (error.userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any])
            ?? [:]
    }

    /// Older validation errors do not carry a domainCode. Match only the
    /// documented field prefix from Infra, never display the server sentence.
    /// This affects copy only; retry/permission classification stays code-based.
    @nonobjc private static func legacyValidationGuidance(_ error: NSError) -> String? {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let field = String(message.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
        switch field {
        case "name", "nameEn":
            return Language.get("Inventory_Error_Name", alter: "راجع خطوة الهوية: أدخل اسم الصنف، واجعل الاسم العربي والإنجليزي لا يزيد كل منهما على 90 حرفاً، ثم احفظ.")
        case "desc", "descEn":
            return Language.get("Inventory_Error_Description", alter: "راجع وصف الصنف في خطوة الهوية. اختصر الوصف العربي والإنجليزي إلى 4000 حرف لكل منهما، ثم احفظ.")
        case "sku":
            return Language.get("Inventory_Error_SKU", alter: "راجع رمز الصنف في خطوة الهوية. استخدم رمزاً لا يزيد على 40 حرفاً أو امسح الحقل الاختياري، ثم احفظ.")
        case "barcode":
            return Language.get("Inventory_Error_Barcode", alter: "راجع الباركود في خطوة الهوية. استخدم باركوداً لا يزيد على 80 حرفاً أو امسح الحقل الاختياري، ثم احفظ.")
        case "price", "sellPrice", "finalPrice", "standardSellingPrice", "wholesalePrice":
            return Language.get("CatalogIntake_ValidationPrice", alter: "أدخل سعراً صالحاً لا يتجاوز 999999999.99 وبحد أقصى منزلتين عشريتين.")
        case "costPrice", "buyPrice":
            return Language.get("CatalogIntake_ValidationCost", alter: "أدخل تكلفة استلام صالحة وبحد أقصى منزلتين عشريتين.")
        case "discountPercent":
            return Language.get("CatalogIntake_ValidationDiscountPercent", alter: "أدخل نسبة خصم بين 0 و100 وبحد أقصى منزلتين عشريتين.")
        case "discountAmount":
            return Language.get("CatalogIntake_ValidationDiscountAmount", alter: "أدخل مبلغ خصم صالحاً وبحد أقصى منزلتين عشريتين.")
        case "quantity", "reorderLevel":
            return Language.get("Inventory_Error_Quantity", alter: "راجع الكمية وحد إعادة الطلب في خطوة السعر والمخزون. أدخل أعداداً صحيحة غير سالبة ثم احفظ.")
        case "weight", "weightUnit":
            return Language.get("CatalogIntake_ValidationWeight", alter: "أدخل وزناً أو حجماً صالحاً وبحد أقصى ثلاث منازل عشرية.")
        case "petMainCategoryID", "petSubCategoryID", "petMainCategoryIDs", "petSubCategoryIDs", "accessoryCategoryID", "AccessoryCategoryID":
            return Language.get("Inventory_Error_Category", alter: "تعذر اعتماد تصنيف الصنف. في خطوة المواصفات، أعد اختيار الفئة الرئيسية والفرعية وتصنيف الإكسسوار من القوائم المتاحة، ثم احفظ.")
        case "branchID", "branchId", "storeID", "requestedBranchId":
            return Language.get("Inventory_SpecificBranchRequired", alter: "اختر فرعاً محدداً قبل إنشاء مخزون أولي لهذا الصنف.")
        case "quantityGroup", "quantityGroups", "baseUnit", "retailPriceMinor", "wholesalePriceMinor", "unitsPerGroup", "commerce", "sellingModes":
            return Language.get("Inventory_Error_SellingUnits", alter: "راجع وحدات البيع في خطوة السعر والمخزون: الاسم، وعدد القطع الصحيح، وسعر كل قناة مفعّلة. حدد وحدة افتراضية واحدة لكل قناة وأزل الباركود المكرر، ثم احفظ.")
        case "imageURLsArray", "imageMeta":
            return Language.get("Inventory_Error_Images", alter: "تعذر اعتماد صور الصنف. احتفظ باثنتي عشرة صورة كحد أقصى، وأعد اختيار الصورة التي فشل رفعها، ثم احفظ.")
        default:
            if message.hasPrefix("At least one quantity group is required.")
                || message.hasPrefix("Duplicate quantityGroup id:")
                || message.hasPrefix("Duplicate barcode across quantity groups:")
                || message.hasPrefix("Only one active quantity group may be defaultFor") {
                return Language.get("Inventory_Error_SellingUnits", alter: "راجع وحدات البيع في خطوة السعر والمخزون: الاسم، وعدد القطع الصحيح، وسعر كل قناة مفعّلة. حدد وحدة افتراضية واحدة لكل قناة وأزل الباركود المكرر، ثم احفظ.")
            }
            return nil
        }
    }

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

        let message = userFacingErrorMessage(for: error)

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

        firestore.collection("petAccessories").document(normalizedProductId).getDocument(source: .server) { snapshot, error in
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
            guard !snapshot.metadata.isFromCache, !snapshot.metadata.hasPendingWrites,
                  revision >= minimumRevision else {
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
