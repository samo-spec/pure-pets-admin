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
//  This facade owns one behaviour the server cannot: the ordered listing
//  transfer required when the default colour changes. See
//  `saveFamily(_:transferringListingFrom:)`.
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
    public func loadFamily(familyId: String) async throws -> PPAccessoryVariantFamily {
        let trimmed = familyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PPAccessoryVariantServiceError.invalidFamilyIdentifier }

        let snapshot = try await db.collection("ProductFamilies").document(trimmed).getDocument()
        guard snapshot.exists, let data = snapshot.data() else {
            throw PPAccessoryVariantServiceError.familyNotFound
        }

        let productIds = (data["variantProductIds"] as? [Any])?
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        let products = try await loadProducts(ids: productIds)

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
    /// single-variant presentation when the product has never been grouped.
    public func resolveFamily(for accessory: PetAccessory) async throws -> PPAccessoryVariantFamily {
        let familyId = (accessory.productFamilyId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !familyId.isEmpty else {
            return PPAccessoryVariantFamily.legacySingleVariant(from: accessory)
        }
        return try await loadFamily(familyId: familyId)
    }

    /// Chunked `in` fetch. Firestore caps `in` at 30 values per query.
    private func loadProducts(ids: [String]) async throws -> [String: PetAccessory] {
        guard !ids.isEmpty else { return [:] }
        var result: [String: PetAccessory] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 30).map({ Array(ids[$0..<min($0 + 30, ids.count)]) }) {
            let snapshot = try await db.collection("petAccessories")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            for document in snapshot.documents {
                result[document.documentID] = PetAccessory(
                    dictionary: document.data(),
                    documentID: document.documentID
                )
            }
        }
        return result
    }

    // MARK: - Write

    /// Persists a family through the callable.
    ///
    /// `transferringListingFrom` names the colour that currently holds the
    /// public listing when the default is changing. The server refuses a family
    /// whose non-default colour is publicly listed, because released consumer
    /// clients render each product document as its own marketplace card, so the
    /// listing must move **before** the family is re-pointed:
    ///
    ///   1. unlist the outgoing default        (validateInventoryChange)
    ///   2. list the incoming default          (validateInventoryChange)
    ///   3. re-point the family                (upsertProductVariantFamily)
    ///
    /// Doing step 3 first fails with `VARIANT_CONSUMER_VISIBILITY_CONFLICT`.
    /// Steps 1 and 2 are ordered unlist-then-list deliberately: the intermediate
    /// state is "briefly not listed", which is recoverable, rather than "briefly
    /// listed twice", which duplicates the product in the marketplace.
    ///
    /// Each step carries its own derived command id, so a retry of the whole
    /// operation is idempotent per step rather than re-running a partial
    /// sequence under one key.
    public func saveFamily(
        _ family: PPAccessoryVariantFamily,
        commandId: String,
        transferringListingFrom outgoingDefaultProductId: String?
    ) async throws -> PPAccessoryVariantSaveResult {
        let messages = family.validationMessages()
        if !messages.isEmpty {
            throw PPAccessoryVariantServiceError.validationFailed(messages)
        }

        if let outgoing = outgoingDefaultProductId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outgoing.isEmpty,
           outgoing != family.defaultVariantProductId {
            try await transferPublicListing(
                from: outgoing,
                to: family.defaultVariantProductId,
                family: family,
                commandId: commandId
            )
        }

        return try await invokeFamilyCommand(family.commandEnvelope(commandId: commandId))
    }

    /// Steps 1 and 2 of the listing transfer, through the catalog owner.
    /// `showInAppMarket` belongs to `validateInventoryChange`; the family
    /// callable only validates it, so this method must not write it directly.
    private func transferPublicListing(
        from outgoingProductId: String,
        to incomingProductId: String,
        family: PPAccessoryVariantFamily,
        commandId: String
    ) async throws {
        let outgoingWasListed = family.variant(forProductId: outgoingProductId)?.showInAppMarket ?? false
        let incomingIsListed = family.variant(forProductId: incomingProductId)?.showInAppMarket ?? false

        if outgoingWasListed {
            try await setMarketVisibility(
                productId: outgoingProductId,
                visible: false,
                commandId: "\(commandId)-unlist",
                expectedRevision: family.variant(forProductId: outgoingProductId)?.revision
            )
        }
        if !incomingIsListed {
            try await setMarketVisibility(
                productId: incomingProductId,
                visible: true,
                commandId: "\(commandId)-list",
                expectedRevision: family.variant(forProductId: incomingProductId)?.revision
            )
        }
    }

    /// `@MainActor` because `updateCatalogPresentation` is main-actor isolated and
    /// returns a non-`Sendable` dictionary. Isolating the helper keeps that result
    /// from crossing an actor boundary; the response is not needed here, because
    /// the family command that follows re-reads the authoritative state.
    @MainActor
    private func setMarketVisibility(
        productId: String,
        visible: Bool,
        commandId: String,
        expectedRevision: Int?
    ) async throws {
        _ = try await PPLivePetInventoryService.updateCatalogPresentation(
            productID: productId,
            values: ["showInAppMarket": visible],
            commandID: commandId,
            expectedRevision: (expectedRevision ?? 0) > 0 ? expectedRevision : nil
        )
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
