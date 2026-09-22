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
        guard products.count == productIds.count,
              ((data["revision"] as? NSNumber)?.intValue ?? 0) >= minimumRevision else {
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
            return PPAccessoryVariantFamily.legacySingleVariant(from: accessory)
        }
        do {
            return try await loadFamily(familyId: familyId)
        } catch PPAccessoryVariantServiceError.familyNotFound,
                PPAccessoryVariantServiceError.invalidFamilyIdentifier {
            print("[PPAccessoryVariantService] Family \(familyId) missing for accessory \(accessory.accessoryID ?? ""). Self-healing to legacy single-variant.")
            accessory.productFamilyId = nil
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
        return result
    }

    /// Loads one exact sellable color product. Used by exact-variant editor
    /// navigation and by Add Color template cloning; never a family projection.
    public func loadProduct(productId: String) async throws -> PetAccessory {
        let trimmed = productId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PPAccessoryVariantServiceError.invalidFamilyIdentifier }
        let snapshot = try await db.collection("petAccessories").document(trimmed).getDocument(source: .server)
        guard snapshot.exists, let data = snapshot.data() else {
            throw PPAccessoryVariantServiceError.familyNotFound
        }
        return PetAccessory(dictionary: data, documentID: trimmed)
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
        quantity: Int = 0,
        commandId: String
    ) async throws -> PetAccessory {
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
        created.costPrice = nil
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
        return try await withCheckedThrowingContinuation { continuation in
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
