//
//  PPAccessoryVariantService.swift
//  PurePetsAdmin
//
//  Command facade for accessory colour families.
//
//  Mirrors PPInventoryCommandService's contract: every mutation goes through a
//  Cloud Function with a command id, no direct Firestore catalog writes, and a
//  typed result. Reads are direct Firestore because ProductFamilies and
//  petAccessories are both server-owned and client-readable.
//
//  Default-colour visibility transfer is intentionally server-owned and atomic.
//  This facade never writes `showInAppMarket` for a family member.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@objc public final class PPAccessoryVariantSaveResult: NSObject, @unchecked Sendable {
    @objc public let familyId: String
    @objc public let revision: Int
    @objc public let idempotent: Bool
    @objc public let resultKind: String
    @objc public let defaultVariantProductId: String
    @objc public let variantProductIds: [String]

    init(
        familyId: String,
        revision: Int,
        idempotent: Bool,
        resultKind: String,
        defaultVariantProductId: String,
        variantProductIds: [String]
    ) {
        self.familyId = familyId
        self.revision = revision
        self.idempotent = idempotent
        self.resultKind = resultKind
        self.defaultVariantProductId = defaultVariantProductId
        self.variantProductIds = variantProductIds
        super.init()
    }
}

@objc public final class PPAccessoryVariantService: NSObject, @unchecked Sendable {
    @objc public static let shared = PPAccessoryVariantService()

    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    private override init() { super.init() }

    // MARK: - Authorization surface
    //
    // UI gating only. The callable performs the authoritative check against an
    // active `staff_users` record plus an active `UsersCol` staff account, so a
    // hidden control is never the security boundary.

    @objc public var canManageVariants: Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff else { return false }
        return staff.isAdmin()
            || staff.hasPermission("stock.manage")
            || staff.hasPermission("stock.create")
    }

    // MARK: - Read

    /// Loads a family and its member products.
    ///
    /// The family document is the ordering authority; member products carry live
    /// stock and identifiers. Members are fetched by id list (chunked `in`
    /// query) rather than by a `productFamilyId` query, so the read stays a
    /// bounded, index-free two-step instead of an N+1 fetch.
    public func loadFamily(familyId: String, minimumRevision: Int = 0) async throws -> PPAccessoryVariantFamily {
        let trimmed = familyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PPAccessoryVariantServiceError.invalidFamilyIdentifier }

        let snapshot = try await db.collection("ProductFamilies").document(trimmed).getDocument(source: .server)
        guard snapshot.exists, let data = snapshot.data() else {
            throw PPAccessoryVariantServiceError.familyNotFound
        }

        let productIds = (data["variantProductIds"] as? [Any])?
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        let products = try await loadProducts(ids: productIds)
        let missing = productIds.filter { products[$0] == nil || products[$0]?.isDeleted == true }
        guard missing.isEmpty else {
            throw Self.unavailableProducts(missing)
        }
        guard ((data["revision"] as? NSNumber)?.intValue ?? 0) >= minimumRevision else {
            throw PPAccessoryVariantServiceError.invalidResponse
        }

        guard let family = PPAccessoryVariantFamily.family(
            fromDocument: data,
            documentID: trimmed,
            products: products
        ) else {
            throw PPAccessoryVariantServiceError.familyNotFound
        }
        return family
    }

    /// Resolves a family for an accessory, falling back to the legacy
    /// single-variant presentation when the product has never been grouped,
    /// or when a referenced family document is missing/orphaned on the server.
    public func resolveFamily(for accessory: PetAccessory) async throws -> PPAccessoryVariantFamily {
        let familyId = (accessory.productFamilyId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !familyId.isEmpty else {
            try await hydrateCost(for: accessory)
            return PPAccessoryVariantFamily.legacySingleVariant(from: accessory)
        }
        do {
            return try await loadFamily(familyId: familyId)
        } catch PPAccessoryVariantServiceError.familyNotFound,
                PPAccessoryVariantServiceError.invalidFamilyIdentifier {
            print("[PPAccessoryVariantService] Family \(familyId) missing for accessory \(accessory.accessoryID). Self-healing to legacy single-variant.")
            accessory.productFamilyId = nil
            try await hydrateCost(for: accessory)
            return PPAccessoryVariantFamily.legacySingleVariant(from: accessory)
        }
    }

    /// Chunked `in` fetch. Firestore caps `in` at 30 values per query.
    private func loadProducts(ids: [String]) async throws -> [String: PetAccessory] {
        guard !ids.isEmpty else { return [:] }
        var result: [String: PetAccessory] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 30).map({ Array(ids[$0..<min($0 + 30, ids.count)]) }) {
            let snapshot = try await db.collection("petAccessories")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments(source: .server)
            for document in snapshot.documents {
                result[document.documentID] = PetAccessory(
                    dictionary: document.data(),
                    documentID: document.documentID
                )
            }
        }
        for product in result.values {
            try await hydrateCost(for: product)
        }
        return result
    }

    /// Loads one exact sellable color product. Used by exact-variant editor
    /// navigation and by Add Color template cloning; never a family projection.
    public func loadProduct(productId: String) async throws -> PetAccessory {
        let trimmed = productId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PPAccessoryVariantServiceError.invalidFamilyIdentifier }
        let snapshot = try await db.collection("petAccessories").document(trimmed).getDocument(source: .server)
        guard snapshot.exists, let data = snapshot.data() else {
            throw Self.unavailableProducts([trimmed])
        }
        let product = PetAccessory(dictionary: data, documentID: trimmed)
        guard !product.isDeleted else { throw Self.unavailableProducts([trimmed]) }
        try await hydrateCost(for: product)
        return product
    }

    /// Catalog cost is deliberately removed by the server. The newest protected
    /// inbound/cost-adjustment movement is the editor's saved unit cost; a zero
    /// is a legitimate value and must not fall through to an older purchase.
    @MainActor
    private func hydrateCost(for product: PetAccessory) async throws {
        let legacyCost = product.costPrice
        product.costPrice = nil
        let branch = Self.costBranch(for: product)
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff,
              staff.isActive(), branch != nil || staff.hasGlobalScope(),
              staff.isAdmin() || staff.hasPermission("stock.cost.view", inBranch: branch) else { return }
        guard !product.isDeleted, product.accessKindType != .typeLivePets else { return }
        var query = db.collection("stockMovements")
            .whereField("productId", isEqualTo: product.accessoryID)
            .whereField("type", isEqualTo: "stock_in")
        if let branch { query = query.whereField("branchId", isEqualTo: branch) }
        query = query.order(by: "timestamp", descending: true).limit(to: 50)
        // Paginate because recent inbound movements may legitimately omit cost.
        // Stop with an explicit read failure at the bound instead of presenting
        // an invented empty/older value as authoritative.
        for _ in 0..<10 {
            let snapshot = try await query.getDocuments(source: .server)
            for document in snapshot.documents {
                if let cost = Self.recordedCost(in: document.data()) {
                    product.costPrice = NSNumber(value: cost)
                    return
                }
            }
            guard snapshot.documents.count == 50, let last = snapshot.documents.last else {
                if let legacyCost, legacyCost.doubleValue.isFinite, legacyCost.doubleValue >= 0 {
                    product.costPrice = legacyCost
                }
                return
            }
            query = query.start(afterDocument: last)
        }
        throw PPAccessoryVariantServiceError.invalidResponse
    }

    static func costBranch(for product: PetAccessory) -> String? {
        for value in [product.branchID, product.storeID] {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != "main_store" { return trimmed }
        }
        return nil
    }

    static func recordedCost(in movement: [String: Any]) -> Double? {
        let value: Double?
        if let number = movement["costPrice"] as? NSNumber { value = number.doubleValue }
        else if let string = movement["costPrice"] as? String { value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        else { value = nil }
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func unavailableProducts(_ ids: [String]) -> PPAccessoryVariantServiceError {
        .server(PPAccessoryVariantError(
            domainCode: PPAccessoryVariantError.Code.productNotFound,
            message: Language.get("Variant_Error_ProductMissingServer", alter: "أحد الألوان لم يعد موجودًا. أعد تحميل البيانات."),
            recovery: .reloadAndCompare,
            affectedProductIds: ids
        ))
    }

    /// Check a real family edit before any catalog/media mutation. The callable
    /// still performs its own transaction checks; this only prevents predictable
    /// partial saves when a member disappeared or another editor advanced it.
    func validateStudioFamily(_ family: PPAccessoryVariantFamily) async throws {
        guard !family.familyId.isEmpty, !family.isLegacySingleVariant else { return }
        let current = try await loadFamily(familyId: family.familyId)
        guard current.revision == family.revision else {
            throw Self.staleRevision(expected: family.revision, current: current.revision)
        }
        for variant in family.variants {
            guard let member = current.variant(forProductId: variant.productId) else {
                throw Self.unavailableProducts([variant.productId])
            }
            guard member.revision == variant.revision else {
                throw Self.staleRevision(expected: variant.revision, current: member.revision)
            }
        }
    }

    static func staleRevision(expected: Int, current: Int) -> PPAccessoryVariantServiceError {
        .server(PPAccessoryVariantError(
            domainCode: PPAccessoryVariantError.Code.staleVariantRevision,
            message: Language.get("Variant_Error_StaleRevisionServer", alter: "عدّل موظف آخر هذا المنتج أثناء تعديلك. أعد التحميل وقارن قبل الحفظ."),
            recovery: .reloadAndCompare,
            expectedRevision: NSNumber(value: expected),
            currentRevision: NSNumber(value: current)
        ))
    }

    /// Keep all selling units and their identifiers. Only the selected default
    /// retail/wholesale prices change; pricing concurrency belongs to commerce.
    @MainActor
    func prepareStudioCommerce(
        product: PetAccessory,
        retailPrice: Double,
        wholesalePrice: Double?,
        commandId: String
    ) async throws -> [String: Any]? {
        let previousWholesale = product.wholesalePrice?.doubleValue
        guard product.price.doubleValue != retailPrice || previousWholesale != wholesalePrice else { return nil }
        let response = try await functions.httpsCallable("getProductCommerce").call(["productId": product.accessoryID])
        guard let data = response.data as? [String: Any],
              let commerce = data["productCommerce"] as? [String: Any],
              let base = commerce["baseUnit"] as? [String: Any],
              var groups = commerce["quantityGroups"] as? [[String: Any]], !groups.isEmpty,
              let revision = commerce["pricingRevision"] as? NSNumber else {
            throw PPAccessoryVariantServiceError.invalidResponse
        }
        // A redacted wholesale projection cannot safely be written back.
        guard data["hasWholesaleAccess"] as? Bool == true else {
            throw PPAccessoryVariantServiceError.validationFailed([Language.get("Variant_Studio_FullPricingRequired", alter: "افتح السجل الكامل لإدارة أسعار وحدات البيع لهذا الصنف.")])
        }
        guard let retailIndex = groups.firstIndex(where: { $0["defaultForRetail"] as? Bool == true && $0["retailEnabled"] as? Bool == true })
            ?? groups.firstIndex(where: { $0["retailEnabled"] as? Bool == true }) else {
            throw PPAccessoryVariantServiceError.invalidResponse
        }
        groups[retailIndex]["retailPriceMinor"] = Int((retailPrice * 100).rounded())
        if previousWholesale != wholesalePrice {
            let wholesaleIndices = groups.indices.filter { groups[$0]["wholesaleEnabled"] as? Bool == true }
            // Turning off a simple default must never destroy the other units'
            // independent wholesale offers. Their editor lives in the full record.
            if wholesalePrice == nil && wholesaleIndices.count > 1 {
                throw PPAccessoryVariantServiceError.validationFailed([Language.get("Variant_Studio_FullPricingRequired", alter: "افتح السجل الكامل لإدارة أسعار وحدات البيع لهذا الصنف.")])
            }
            let wholesaleIndex = groups.firstIndex(where: { $0["defaultForWholesale"] as? Bool == true && $0["wholesaleEnabled"] as? Bool == true })
                ?? wholesaleIndices.first ?? retailIndex
            groups[wholesaleIndex]["wholesaleEnabled"] = wholesalePrice != nil
            groups[wholesaleIndex]["defaultForWholesale"] = wholesalePrice != nil
            groups[wholesaleIndex]["wholesalePriceMinor"] = wholesalePrice.map { Int(($0 * 100).rounded()) } as Any? ?? NSNull()
        }
        return [
            "productId": product.accessoryID, "commandId": commandId,
            "expectedRevision": revision, "currency": commerce["currency"] as? String ?? "QAR",
            "baseUnit": base, "quantityGroups": groups,
        ]
    }

    @MainActor
    func persistStudioCommerce(_ request: [String: Any]) async throws {
        let boxed = PPVariantSendableDictionary(dict: request)
        let response = try await functions.httpsCallable("upsertProductCommerce").call(boxed.dict)
        guard let result = response.data as? [String: Any], result["ok"] as? Bool == true,
              result["productId"] as? String == request["productId"] as? String else {
            throw PPAccessoryVariantServiceError.invalidResponse
        }
    }

    /// Creates the standalone sellable product that will become a new color.
    /// Catalog creation remains owned by `validateInventoryChange`; this method
    /// deliberately sends NO family/variant identity fields. Initial stock is 0,
    /// media starts empty (color-specific), and public visibility is false until
    /// the family command binds it. A retained command id makes ambiguous create
    /// responses safely replayable.
    public func createStandaloneVariantProduct(
        template: PetAccessory,
        sku: String,
        barcode: String,
        retailPrice: Double,
        wholesalePrice: Double?,
        costPrice: Double? = nil,
        quantity: Int = 0,
        commandId: String
    ) async throws -> PetAccessory {
        guard retailPrice.isFinite, retailPrice > 0, retailPrice <= 999_999_999.99,
              wholesalePrice == nil || (wholesalePrice!.isFinite && wholesalePrice! > 0 && wholesalePrice! <= 999_999_999.99),
              costPrice == nil || (costPrice!.isFinite && costPrice! >= 0 && costPrice! <= 999_999_999.99), quantity >= 0 else {
            throw PPAccessoryVariantServiceError.validationFailed([Language.get("Variant_Add_InvalidPrice", alter: "أدخل سعر بيع صالحاً للون الجديد.")])
        }
        let created = PetAccessory.deepCopy(from: template)
        created.accessoryID = ""
        created.productFamilyId = nil
        created.variantSchemaVersion = 0
        created.isVariant = false
        created.isDefaultVariant = false
        created.variantSortOrder = 0
        created.variantColorDictionary = nil
        created.revision = 0
        created.createdAt = Date()
        created.quantity = max(0, quantity)
        created.noStock = (quantity <= 0)
        created.showInAppMarket = false
        created.sku = sku.trimmingCharacters(in: .whitespacesAndNewlines)
        created.barcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        created.price = NSNumber(value: retailPrice)
        created.wholesalePrice = wholesalePrice.map { NSNumber(value: $0) }
        let allowedCost = await MainActor.run {
            let branch = Self.costBranch(for: template)
            guard let staff = PPStaffAuth.shared().cachedCurrentStaff,
                  staff.isActive(), branch != nil || staff.hasGlobalScope(),
                  staff.isAdmin() || staff.hasPermission("stock.cost.view", inBranch: branch) else { return Optional<Double>.none }
            return costPrice
        }
        created.costPrice = allowedCost.map { NSNumber(value: $0) }
        created.discountPercent = nil
        created.discountAmount = nil
        created.hasOffer = false
        created.imageURLsArray = []
        created.imageMeta = []
        created.normalizeInventoryState()

        let retailMinor = Int((retailPrice * 100.0).rounded())
        let wholesaleMinor = wholesalePrice.map { Int(($0 * 100.0).rounded()) }
        var singleGroup: [String: Any] = [
            "id": "single",
            "nameAr": "حبة",
            "nameEn": "Single",
            "unitsPerGroup": 1,
            "barcode": created.barcode?.isEmpty == false ? created.barcode! : NSNull(),
            "sku": created.sku?.isEmpty == false ? created.sku! : NSNull(),
            "sortOrder": 0,
            "retailEnabled": true,
            "wholesaleEnabled": wholesaleMinor != nil,
            "retailPriceMinor": retailMinor,
            "wholesalePriceMinor": wholesaleMinor ?? NSNull(),
            "defaultForRetail": true,
            "defaultForWholesale": wholesaleMinor != nil,
            "active": true,
        ]
        // Keep payload JSON-compatible when wholesale is disabled.
        if wholesaleMinor == nil { singleGroup["wholesalePriceMinor"] = NSNull() }
        let commerce: [String: Any] = [
            "currency": "QAR",
            "baseUnit": ["id": "piece", "nameAr": "قطعة", "nameEn": "Piece"],
            "quantityGroups": [singleGroup],
        ]

        let branchId = (created.branchID ?? created.storeID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let result: PPInventoryCommandResult = try await withCheckedThrowingContinuation { continuation in
            PPInventoryCommandService.shared.saveProduct(
                accessory: created,
                branchId: branchId.isEmpty ? nil : branchId,
                commerce: commerce,
                expectedRevision: nil,
                commandId: commandId
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result, result.success, let productId = result.productId, !productId.isEmpty {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: PPAccessoryVariantServiceError.invalidResponse)
                }
            }
        }
        guard let productId = result.productId else { throw PPAccessoryVariantServiceError.invalidResponse }
        let confirmed: PetAccessory = try await withCheckedThrowingContinuation { continuation in
            PPInventoryCommandService.shared.readBackProduct(
                productId: productId,
                minimumRevision: max(1, result.revision)
            ) { product, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let product {
                    continuation.resume(returning: product)
                } else {
                    continuation.resume(throwing: PPAccessoryVariantServiceError.invalidResponse)
                }
            }
        }
        try await hydrateCost(for: confirmed)
        if let allowedCost, confirmed.costPrice?.doubleValue != allowedCost {
            throw PPAccessoryVariantServiceError.invalidResponse
        }
        return confirmed
    }

    // MARK: - Write

    /// Persists a family through the single authoritative family callable.
    ///
    /// Public-listing ownership for family members is now part of the server
    /// transaction: when the default color changes, `upsertProductVariantFamily`
    /// atomically unlists the outgoing default, lists the incoming default when
    /// the family was public, updates the family, and restamps every member.
    /// The client deliberately performs no visibility preflight/write here; a
    /// multi-call choreography could leave a half-applied public state.
    public func saveFamily(
        _ family: PPAccessoryVariantFamily,
        commandId: String
    ) async throws -> PPAccessoryVariantSaveResult {
        family.autoBindMissingOptionSelections()
        let messages = family.validationMessages()
        if !messages.isEmpty {
            throw PPAccessoryVariantServiceError.validationFailed(messages)
        }

        return try await invokeFamilyCommand(family.commandEnvelope(commandId: commandId))
    }

    /// Dissolves a variant family, reverting the retained product to a standalone
    /// regular item and removing all sibling variants for this family from inventory.
    @objc public func dissolveFamily(
        familyId: String,
        retainedProductId: String,
        deleteOtherVariants: Bool = true
    ) async throws {
        let trimmedFamilyId = familyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFamilyId.isEmpty else {
            throw PPAccessoryVariantServiceError.invalidFamilyIdentifier
        }
        let commandId = "dissolve-\(trimmedFamilyId)-\(UUID().uuidString)"
        let envelope: [String: Any] = [
            "contractVersion": PPAccessoryVariantContract.contractVersionGeneric,
            "action": "dissolve",
            "familyId": trimmedFamilyId,
            "retainedProductId": retainedProductId.trimmingCharacters(in: .whitespacesAndNewlines),
            "deleteOtherVariants": deleteOtherVariants,
            "commandId": commandId
        ]
        _ = try await invokeFamilyCommand(envelope)
    }

    private func invokeFamilyCommand(_ envelope: [String: Any]) async throws -> PPAccessoryVariantSaveResult {
        guard let currentUser = Auth.auth().currentUser else {
            throw PPAccessoryVariantServiceError.notAuthenticated
        }
        // Matches the established inventory callable pattern: refresh the ID
        // token before the call, bound the timeout, and retry once on an
        // unauthenticated failure with a forced refresh.
        _ = try? await currentUser.getIDToken(forcingRefresh: false)

        let boxed = PPVariantSendableDictionary(dict: envelope)
        let callable = functions.httpsCallable(PPAccessoryVariantContract.callableName)
        callable.timeoutInterval = PPAccessoryVariantService.callableTimeout

        do {
            return try parseResult(from: try await callable.call(boxed.dict))
        } catch let error as PPAccessoryVariantServiceError {
            throw error
        } catch {
            let nsError = error as NSError
            let isUnauthenticated = nsError.code == FunctionsErrorCode.unauthenticated.rawValue
            if isUnauthenticated, let currentUser = Auth.auth().currentUser {
                _ = try? await currentUser.getIDToken(forcingRefresh: true)
                do {
                    return try parseResult(from: try await callable.call(boxed.dict))
                } catch let retryError as PPAccessoryVariantServiceError {
                    throw retryError
                } catch {
                    throw PPAccessoryVariantServiceError.server(
                        PPAccessoryVariantError.error(from: error as NSError)
                    )
                }
            }
            // Always surface the typed variant error so the caller gets an
            // explicit recovery intent instead of a raw callable failure.
            throw PPAccessoryVariantServiceError.server(PPAccessoryVariantError.error(from: nsError))
        }
    }

    private func parseResult(from response: HTTPSCallableResult) throws -> PPAccessoryVariantSaveResult {
        guard let payload = response.data as? [String: Any],
              payload["ok"] as? Bool == true,
              let familyId = payload["familyId"] as? String, !familyId.isEmpty else {
            throw PPAccessoryVariantServiceError.invalidResponse
        }
        return PPAccessoryVariantSaveResult(
            familyId: familyId,
            revision: (payload["revision"] as? NSNumber)?.intValue ?? 0,
            idempotent: payload["idempotent"] as? Bool ?? false,
            resultKind: (payload["resultKind"] as? String) ?? "confirmed",
            defaultVariantProductId: (payload["defaultVariantProductId"] as? String) ?? "",
            variantProductIds: (payload["variantProductIds"] as? [String]) ?? []
        )
    }

    private static let callableTimeout: TimeInterval = 30
}

private struct PPVariantSendableDictionary: @unchecked Sendable {
    let dict: [String: Any]
}

// MARK: - Errors

public enum PPAccessoryVariantServiceError: LocalizedError {
    case invalidFamilyIdentifier
    case familyNotFound
    case invalidResponse
    case notAuthenticated
    case validationFailed([String])
    case server(PPAccessoryVariantError)

    public var errorDescription: String? {
        switch self {
        case .invalidFamilyIdentifier:
            return Language.get("Variant_Error_InvalidFamilyId", alter: "معرف مجموعة الألوان غير صالح.")
        case .familyNotFound:
            return Language.get("Variant_Error_FamilyMissingServer", alter: "مجموعة الألوان غير موجودة. أعد تحميل البيانات.")
        case .invalidResponse:
            return Language.get("Variant_Error_InvalidResponse", alter: "تعذر تأكيد استجابة الخادم. أعد التحميل للتحقق.")
        case .notAuthenticated:
            return Language.get("Variant_Error_Unauthenticated", alter: "انتهت الجلسة. أعد تسجيل الدخول.")
        case .validationFailed(let messages):
            return messages.first
        case .server(let error):
            return error.message
        }
    }

    /// Recovery intent for the UI. A local validation failure is always
    /// correctable input; a server failure carries the server's own intent.
    public var recovery: PPAccessoryVariantRecovery {
        switch self {
        case .validationFailed:
            return .correctInput
        case .invalidFamilyIdentifier, .notAuthenticated:
            return .fatal
        case .familyNotFound, .invalidResponse:
            return .reloadAndCompare
        case .server(let error):
            return error.recovery
        }
    }

    /// All local validation messages, so the editor can list every problem at
    /// once rather than revealing them one save at a time.
    public var validationMessages: [String] {
        if case .validationFailed(let messages) = self { return messages }
        return []
    }
}
