//
//  PPBranchInventory.swift
//  PurePetsAdmin
//
//  Branch-level inventory record and reactive listener service.
//  Binds directly to active branch context via BranchContextStore.
//

import Foundation
import Combine
import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Branch Inventory Record

public struct PPBranchInventory: Identifiable, Hashable, Sendable {
    public let id: String
    public let branchId: String
    public let productId: String
    public let productName: String
    public let sku: String
    public let barcode: String
    public let category: String
    public let quantity: Int
    public let reservedQuantity: Int
    public let availableQuantity: Int
    public let onHandQuantity: Int
    public let damagedQuantity: Int
    public let expiredQuantity: Int
    public let quarantineQuantity: Int
    public let supplierReturnQuantity: Int
    public let minimumStock: Int
    public let maximumStock: Int
    public let shelfLocation: String
    public let costPrice: Double?
    public let sellingPrice: Double?
    public let noStock: Bool
    public let projectionRevision: Int
    public let updatedAt: Date?

    public var needsAttentionQuantity: Int {
        damagedQuantity + expiredQuantity + quarantineQuantity
    }

    public init(
        id: String,
        branchId: String,
        productId: String,
        productName: String = "",
        sku: String = "",
        barcode: String = "",
        category: String = "",
        quantity: Int = 0,
        reservedQuantity: Int = 0,
        availableQuantity: Int = 0,
        onHandQuantity: Int? = nil,
        damagedQuantity: Int = 0,
        expiredQuantity: Int = 0,
        quarantineQuantity: Int = 0,
        supplierReturnQuantity: Int = 0,
        minimumStock: Int = 0,
        maximumStock: Int = 0,
        shelfLocation: String = "",
        costPrice: Double? = nil,
        sellingPrice: Double? = nil,
        noStock: Bool = false,
        projectionRevision: Int = 1,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.branchId = branchId
        self.productId = productId
        self.productName = productName
        self.sku = sku
        self.barcode = barcode
        self.category = category
        self.quantity = quantity
        self.reservedQuantity = reservedQuantity
        self.availableQuantity = availableQuantity
        self.damagedQuantity = damagedQuantity
        self.expiredQuantity = expiredQuantity
        self.quarantineQuantity = quarantineQuantity
        self.supplierReturnQuantity = supplierReturnQuantity
        self.onHandQuantity = onHandQuantity ?? (availableQuantity + reservedQuantity + damagedQuantity + expiredQuantity + quarantineQuantity + supplierReturnQuantity)
        self.minimumStock = minimumStock
        self.maximumStock = maximumStock
        self.shelfLocation = shelfLocation
        self.costPrice = costPrice
        self.sellingPrice = sellingPrice
        self.noStock = noStock
        self.projectionRevision = projectionRevision
        self.updatedAt = updatedAt
    }

    public init?(dictionary: [String: Any], documentId: String) {
        let branchId = (dictionary["branchId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let productId = (dictionary["productId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !branchId.isEmpty, !productId.isEmpty else { return nil }

        self.id = documentId
        self.branchId = branchId
        self.productId = productId
        self.productName = (dictionary["productName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.sku = (dictionary["sku"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.barcode = (dictionary["barcode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.category = (dictionary["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        func count(_ key: String, default fallback: Int = 0) -> Int? {
            guard let value = dictionary[key] else { return fallback }
            guard let number = value as? NSNumber, number.doubleValue.isFinite,
                  number.doubleValue >= 0, number.doubleValue <= 9_007_199_254_740_991,
                  number.doubleValue.rounded(.towardZero) == number.doubleValue else { return nil }
            return number.intValue
        }
        guard let rawQty = count("quantity"), let rawReserved = count("reservedQuantity"),
              let rawDamaged = count("damagedQuantity"), let rawExpired = count("expiredQuantity"),
              let rawQuarantine = count("quarantineQuantity"), let rawSupplierReturn = count("supplierReturnQuantity") else { return nil }
        let nonSellable = rawReserved + rawDamaged + rawExpired + rawQuarantine + rawSupplierReturn
        guard let rawAvailable = count("availableQuantity", default: max(0, rawQty - nonSellable)),
              let rawOnHand = count("onHandQuantity", default: rawQty),
              rawOnHand == rawAvailable + nonSellable,
              let revision = count("projectionRevision", default: 1),
              let minimum = count("minimumStock"), let maximum = count("maximumStock") else { return nil }

        self.quantity = max(0, rawQty)
        self.reservedQuantity = max(0, rawReserved)
        self.damagedQuantity = max(0, rawDamaged)
        self.expiredQuantity = max(0, rawExpired)
        self.quarantineQuantity = max(0, rawQuarantine)
        self.supplierReturnQuantity = max(0, rawSupplierReturn)
        self.availableQuantity = rawAvailable
        self.onHandQuantity = rawOnHand
        self.projectionRevision = revision
        self.minimumStock = minimum
        self.maximumStock = maximum
        self.shelfLocation = (dictionary["shelfLocation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if let cost = dictionary["costPrice"] as? NSNumber, cost.doubleValue.isFinite, cost.doubleValue >= 0 {
            self.costPrice = cost.doubleValue
        } else {
            self.costPrice = nil
        }
        
        if let price = dictionary["sellingPrice"] as? NSNumber, price.doubleValue.isFinite, price.doubleValue >= 0 {
            self.sellingPrice = price.doubleValue
        } else {
            self.sellingPrice = nil
        }
        
        self.noStock = (dictionary["noStock"] as? Bool) ?? (self.availableQuantity <= 0)
        
        if let ts = dictionary["updatedAt"] as? Timestamp {
            self.updatedAt = ts.dateValue()
        } else if let date = dictionary["updatedAt"] as? Date {
            self.updatedAt = date
        } else {
            self.updatedAt = nil
        }
    }
}

// MARK: - Branch Product Settings Record

public struct PPBranchProductSettings: Identifiable, Hashable, Sendable {
    public let id: String
    public let branchId: String
    public let productId: String
    public let sellingPrice: Double?
    public let discountPercentage: Double?
    public let discountAmount: Double?
    public let taxRate: Double?
    public let isTaxExempt: Bool
    public let isActive: Bool

    public init(
        id: String,
        branchId: String,
        productId: String,
        sellingPrice: Double? = nil,
        discountPercentage: Double? = nil,
        discountAmount: Double? = nil,
        taxRate: Double? = nil,
        isTaxExempt: Bool = false,
        isActive: Bool = true
    ) {
        self.id = id
        self.branchId = branchId
        self.productId = productId
        self.sellingPrice = sellingPrice
        self.discountPercentage = discountPercentage
        self.discountAmount = discountAmount
        self.taxRate = taxRate
        self.isTaxExempt = isTaxExempt
        self.isActive = isActive
    }

    public init?(dictionary: [String: Any], documentId: String) {
        let branchId = (dictionary["branchId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let productId = (dictionary["productId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !branchId.isEmpty, !productId.isEmpty else { return nil }

        self.id = documentId
        self.branchId = branchId
        self.productId = productId
        self.sellingPrice = (dictionary["sellingPrice"] as? NSNumber)?.doubleValue

        if let discRules = dictionary["discountRules"] as? [String: Any] {
            self.discountPercentage = (discRules["percentage"] as? NSNumber)?.doubleValue
            self.discountAmount = (discRules["amount"] as? NSNumber)?.doubleValue
        } else {
            self.discountPercentage = nil
            self.discountAmount = nil
        }

        if let taxRules = dictionary["taxRules"] as? [String: Any] {
            self.taxRate = (taxRules["taxRate"] as? NSNumber)?.doubleValue
            self.isTaxExempt = (taxRules["isTaxExempt"] as? Bool) ?? false
        } else {
            self.taxRate = nil
            self.isTaxExempt = false
        }

        self.isActive = (dictionary["isActive"] as? Bool) ?? true
    }
}

// MARK: - Canonical Branch Commerce Projection

/// Client-safe projection written by `upsertBranchProductCommerce` from the
/// SAME resolver used by POS/checkout. This deliberately replaces the legacy
/// `branchProductSettings.sellingPrice` and `branchInventory.sellingPrice`
/// shortcuts, which could disagree with ProductCommerce/BranchProductCommerce.
public struct PPBranchCommercePriceProjection: Identifiable, Hashable, Sendable {
    public let id: String
    public let branchId: String
    public let productId: String
    public let pricingRevision: Int
    public let defaultRetailQuantityGroupId: String
    public let effectiveDefaultRetailPriceMinor: Int
    public let currency: String

    public var effectiveDefaultRetailPrice: Double {
        Double(effectiveDefaultRetailPriceMinor) / 100.0
    }

    public init?(dictionary: [String: Any], documentId: String) {
        let branchId = (dictionary["branchId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let productId = (dictionary["productId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let groupId = (dictionary["defaultRetailQuantityGroupId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !branchId.isEmpty, !productId.isEmpty, !groupId.isEmpty,
              let minor = dictionary["effectiveDefaultRetailPriceMinor"] as? NSNumber,
              minor.doubleValue.isFinite,
              minor.doubleValue >= 0,
              minor.doubleValue.rounded(.towardZero) == minor.doubleValue else { return nil }

        self.id = documentId
        self.branchId = branchId
        self.productId = productId
        self.pricingRevision = max(1, (dictionary["pricingRevision"] as? NSNumber)?.intValue ?? 1)
        self.defaultRetailQuantityGroupId = groupId
        self.effectiveDefaultRetailPriceMinor = minor.intValue
        self.currency = ((dictionary["currency"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "QAR"
    }
}

// MARK: - Reactive Branch Inventory Service

@MainActor
public final class PPBranchInventoryService: ObservableObject {
    public static let shared = PPBranchInventoryService()

    /// Real-time map of branch inventory keyed by productId: [productId: PPBranchInventory]
    @Published public private(set) var inventoryMap: [String: PPBranchInventory] = [:]

    /// Canonical branch retail projection keyed by productId. The legacy name
    /// `settingsMap` is retained for source compatibility with observers; its
    /// authority is now BranchProductCommerce, not branchProductSettings.
    @Published public private(set) var settingsMap: [String: PPBranchCommercePriceProjection] = [:]
    @Published public private(set) var unresolvedCommerceProductIds: Set<String> = []

    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var currentBranchId: String? = nil
    @Published public private(set) var lastSyncDate: Date? = nil
    @Published public private(set) var inventoryError: String? = nil
    @Published public private(set) var settingsError: String? = nil
    @Published public private(set) var isServerConfirmed = false

    private var listenerRegistration: ListenerRegistration?
    private var settingsListenerRegistration: ListenerRegistration?
    private var bindingGeneration = UUID()
    private var cancellables = Set<AnyCancellable>()

    public init() {
        // Observe BranchContextStore to switch branch inventory dynamically
        BranchContextStore.shared.$activeBranch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] branch in
                guard let self = self else { return }
                let newBranchId = branch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines)
                if newBranchId != self.currentBranchId {
                    self.bindToBranch(newBranchId)
                }
            }
            .store(in: &cancellables)

        // Initial bind
        if let initialBranchId = BranchContextStore.shared.activeBranch?.branchID {
            bindToBranch(initialBranchId)
        }
    }

    deinit {
        // In Swift 6 strict concurrency, nonisolated deinit cannot touch MainActor non-Sendable listeners.
        // Singleton lifecycle persists for the lifetime of the application.
    }

    public func startListeningIfNeeded() {
        if listenerRegistration == nil, let branchId = BranchContextStore.shared.activeBranch?.branchID {
            bindToBranch(branchId)
        }
    }

    /// Subscribes to `branchInventory` plus canonical `BranchProductCommerce` for the specified branch.
    /// Every branch change invalidates the previous generation and clears its projection before the new listeners attach.
    public func bindToBranch(_ branchId: String?) {
        listenerRegistration?.remove()
        listenerRegistration = nil
        settingsListenerRegistration?.remove()
        settingsListenerRegistration = nil

        let generation = UUID()
        bindingGeneration = generation
        inventoryMap = [:]
        settingsMap = [:]
        unresolvedCommerceProductIds = []
        lastSyncDate = nil
        inventoryError = nil
        settingsError = nil
        isServerConfirmed = false

        guard let branchId = branchId?.trimmingCharacters(in: .whitespacesAndNewlines), !branchId.isEmpty else {
            currentBranchId = nil
            isLoading = false
            return
        }

        currentBranchId = branchId
        isLoading = true

        let query = Firestore.firestore()
            .collection("branchInventory")
            .whereField("branchId", isEqualTo: branchId)

        listenerRegistration = query.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self,
                      self.bindingGeneration == generation,
                      self.currentBranchId == branchId else { return }
                self.isLoading = false

                if let error {
                    self.inventoryError = error.localizedDescription
                    self.isServerConfirmed = false
                    return
                }

                guard let documents = snapshot?.documents else { return }
                var newMap: [String: PPBranchInventory] = [:]
                for doc in documents {
                    guard let record = PPBranchInventory(dictionary: doc.data(), documentId: doc.documentID),
                          record.branchId == branchId, newMap[record.productId] == nil else {
                        self.inventoryError = Language.get("Inventory_ProjectionUnavailable", alter: "تعذر التحقق من رصيد الفرع. أعد تحميل المخزون.")
                        self.isServerConfirmed = false
                        return
                    }
                    newMap[record.productId] = record
                }
                self.inventoryMap = newMap
                self.inventoryError = nil
                self.isServerConfirmed = snapshot?.metadata.isFromCache == false && snapshot?.metadata.hasPendingWrites == false
                if self.isServerConfirmed { self.lastSyncDate = Date() }
            }
        }

        let settingsQuery = Firestore.firestore()
            .collection("BranchProductCommerce")
            .whereField("branchId", isEqualTo: branchId)

        settingsListenerRegistration = settingsQuery.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self,
                      self.bindingGeneration == generation,
                      self.currentBranchId == branchId else { return }
                if let error {
                    self.settingsError = error.localizedDescription
                    return
                }

                guard let documents = snapshot?.documents else { return }
                var newSettings: [String: PPBranchCommercePriceProjection] = [:]
                var unresolved: Set<String> = []
                for doc in documents {
                    let productId = (doc.data()["productId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard let projection = PPBranchCommercePriceProjection(dictionary: doc.data(), documentId: doc.documentID),
                          projection.branchId == branchId,
                          newSettings[projection.productId] == nil else {
                        if !productId.isEmpty { unresolved.insert(productId) }
                        continue
                    }
                    newSettings[projection.productId] = projection
                }
                self.settingsMap = newSettings
                self.unresolvedCommerceProductIds = unresolved
                self.settingsError = unresolved.isEmpty
                    ? nil
                    : Language.get(
                        "BranchCommerce_ProjectionMissing",
                        alter: "تعذر تأكيد سعر الفرع لبعض الأصناف. أعد حفظ تسعير الفرع قبل البيع."
                    )
            }
        }
    }

    /// Returns the branch inventory record for a given product ID
    public func inventory(for productId: String) -> PPBranchInventory? {
        inventoryMap[productId]
    }

    /// Returns available stock from the active branch projection.
    /// If an explicit branch record exists in `inventoryMap`, its available quantity is authoritative.
    /// If no branch-specific record exists, falls back to the catalog quantity for unsegmented stock
    /// in `main_store` or global view, returning 0 for unstocked secondary branches.
    public func availableStock(for productId: String, fallback: Int = 0) -> Int {
        guard let currentBranchId = currentBranchId?.trimmingCharacters(in: .whitespacesAndNewlines), !currentBranchId.isEmpty else {
            return fallback
        }
        if currentBranchId == "all_branches" {
            return fallback
        }
        if let record = inventoryMap[productId] {
            return record.availableQuantity
        }
        if currentBranchId == "main_store" {
            return max(0, fallback)
        }
        return 0
    }

    /// Resolves the effective DEFAULT RETAIL price from the same branch commerce
    /// authority the backend transaction engine uses. If an override document
    /// exists without the new projection, return 0 to fail closed rather than
    /// silently submit a catalog fallback the server will reject as stale/wrong.
    public func effectiveSellingPrice(for productId: String, fallbackPrice: Double) -> Double {
        if let projection = settingsMap[productId] {
            return projection.effectiveDefaultRetailPrice
        }
        if unresolvedCommerceProductIds.contains(productId) {
            return 0
        }
        return fallbackPrice
    }

    public func hasConfirmedCommercePrice(for productId: String) -> Bool {
        !unresolvedCommerceProductIds.contains(productId)
    }

    /// Refreshes the authoritative record after a confirmed command. Never
    /// invent quantities/revisions or reapply deltas to an already-new listener.
    public func refreshInventory(
        for productId: String,
        branchId: String,
        minimumRevision: Int = 0,
        completion: ((Result<PPBranchInventory, Error>) -> Void)? = nil
    ) {
        let cleanBranch = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBranch.isEmpty, currentBranchId == cleanBranch else {
            completion?(.failure(CancellationError()))
            return
        }
        let generation = bindingGeneration
        Task { @MainActor [weak self] in
            do {
                let snapshot = try await Firestore.firestore().collection("branchInventory")
                    .document("\(cleanBranch)_\(productId)").getDocument(source: .server)
                guard let self, self.bindingGeneration == generation, self.currentBranchId == cleanBranch else {
                    completion?(.failure(CancellationError()))
                    return
                }
                guard let data = snapshot.data(), let record = PPBranchInventory(dictionary: data, documentId: snapshot.documentID),
                      record.branchId == cleanBranch, record.productId == productId,
                      record.projectionRevision >= minimumRevision else {
                    let message = Language.get("Inventory_ProjectionUnavailable", alter: "تعذر التحقق من رصيد الفرع. أعد تحميل المخزون.")
                    self.inventoryError = message
                    self.isServerConfirmed = false
                    completion?(.failure(NSError(domain: "pp.inventory.projection", code: 409, userInfo: [NSLocalizedDescriptionKey: message])))
                    return
                }
                if (self.inventoryMap[productId]?.projectionRevision ?? 0) <= record.projectionRevision {
                    self.inventoryMap[productId] = record
                }
                completion?(.success(record))
            } catch {
                guard let self, self.bindingGeneration == generation else {
                    completion?(.failure(CancellationError()))
                    return
                }
                self.inventoryError = error.localizedDescription
                self.isServerConfirmed = false
                completion?(.failure(error))
            }
        }
    }

    /// Records damaged stock via backend Cloud Function `recordInventoryDamage`
    public func recordDamage(
        productId: String,
        branchId: String,
        quantity: Int,
        reasonCode: String = "packaging_damage",
        notes: String = "",
        commandId: String? = nil,
        completion: ((Result<[String: Any], Error>) -> Void)? = nil
    ) {
        let resolvedBranch: String
        let trimmed = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "all_branches" {
            resolvedBranch = trimmed
        } else if let active = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines), !active.isEmpty {
            resolvedBranch = active
        } else {
            completion?(.failure(NSError(
                domain: "PPBranchInventory",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: Language.get("Branch_Required_Error_Damage", alter: "يجب تحديد الفرع لتسجيل التلفيات")]
            )))
            return
        }

        let cleanCommandId = commandId ?? "dmg_\(UUID().uuidString)"
        let payload: [String: Any] = [
            "branchId": resolvedBranch,
            "productId": productId,
            "quantity": quantity,
            "reasonCode": reasonCode,
            "notes": notes,
            "commandId": cleanCommandId,
            "sessionId": BranchContextStore.shared.currentSessionId
        ]

        let callable = Functions.functions().httpsCallable("recordInventoryDamage")
        callable.call(["payload": payload]) { [weak self] result, error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            let data = (result?.data as? [String: Any]) ?? [:]
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion?(.success(data))
                    return
                }
                self.refreshInventory(for: productId, branchId: resolvedBranch)
                completion?(.success(data))
            }
        }
    }

    /// Resolves an inventory disposition (quarantine release, damaged, expired, supplierReturn, or write-off)
    /// via backend Cloud Function `resolveInventoryDisposition`.
    public func resolveDisposition(
        productId: String,
        branchId: String,
        quantity: Int,
        action: String = "move",
        fromBucket: String = "quarantine",
        toBucket: String? = nil,
        dispositionId: String? = nil,
        reasonCode: String? = nil,
        notes: String = "",
        commandId: String? = nil,
        completion: ((Result<[String: Any], Error>) -> Void)? = nil
    ) {
        let resolvedBranch: String
        let trimmed = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "all_branches" {
            resolvedBranch = trimmed
        } else if let active = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines), !active.isEmpty {
            resolvedBranch = active
        } else {
            completion?(.failure(NSError(
                domain: "PPBranchInventory",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: Language.get("Branch_Required_Error_Disposition", alter: "يجب تحديد الفرع لمعالجة حالة المخزون")]
            )))
            return
        }

        let cleanCommandId = commandId ?? "disp_res_\(UUID().uuidString)"
        var payload: [String: Any] = [
            "branchId": resolvedBranch,
            "productId": productId,
            "quantity": quantity,
            "action": action,
            "fromBucket": fromBucket,
            "notes": notes,
            "commandId": cleanCommandId,
            "sessionId": BranchContextStore.shared.currentSessionId
        ]
        if let toBucket = toBucket {
            payload["toBucket"] = toBucket
        }
        if let dispositionId = dispositionId {
            payload["dispositionId"] = dispositionId
        }
        if let reasonCode = reasonCode {
            payload["reasonCode"] = reasonCode
        }

        let callable = Functions.functions().httpsCallable("resolveInventoryDisposition")
        callable.call(["payload": payload]) { [weak self] result, error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            let data = (result?.data as? [String: Any]) ?? [:]
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion?(.success(data))
                    return
                }
                self.refreshInventory(for: productId, branchId: resolvedBranch)
                completion?(.success(data))
            }
        }
    }

    /// Lists inventory dispositions from backend Cloud Function `listInventoryDispositions`
    public func fetchDispositions(
        branchId: String? = nil,
        status: String? = nil,
        condition: String? = nil,
        limit: Int = 50,
        completion: @escaping (Result<[[String: Any]], Error>) -> Void
    ) {
        var payload: [String: Any] = ["limit": limit]
        if let branchId = branchId { payload["branchId"] = branchId }
        if let status = status { payload["status"] = status }
        if let condition = condition { payload["condition"] = condition }

        let callable = Functions.functions().httpsCallable("listInventoryDispositions")
        callable.call(["payload": payload]) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let data = (result?.data as? [String: Any]) ?? [:]
            let items = (data["items"] as? [[String: Any]]) ?? []
            completion(.success(items))
        }
    }

    /// Adjust stock callable via backend Cloud Function
    public func adjustStock(
        productId: String,
        branchId: String,
        newQuantity: Int? = nil,
        delta: Int? = nil,
        type: String = "adjustment",
        referenceId: String = "",
        reason: String = "manual_adjustment",
        notes: String = "",
        commandId suppliedCommandId: String? = nil,
        expectedRevision: Int? = nil,
        completion: ((Result<[String: Any], Error>) -> Void)? = nil
    ) {
        let normalizedCommandId = suppliedCommandId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let commandId = normalizedCommandId.isEmpty
            ? "admin-ios-branch-adjust-\(productId)-\(UUID().uuidString.lowercased())"
            : normalizedCommandId
        var payload: [String: Any] = [
            "productId": productId,
            "branchId": branchId,
            "type": type,
            "referenceId": referenceId,
            "sessionId": BranchContextStore.shared.currentSessionId,
            "reason": reason,
            "notes": notes,
            "commandId": commandId
        ]
        if let newQty = newQuantity {
            payload["newQuantity"] = newQty
        }
        if let d = delta {
            payload["delta"] = d
        }
        if let expectedRevision { payload["expectedRevision"] = expectedRevision }

        let callable = Functions.functions().httpsCallable("adjustBranchStock")
        callable.call(["contractVersion": 2, "payload": payload]) { [weak self] result, error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            let data = (result?.data as? [String: Any]) ?? [:]
            guard data["ok"] as? Bool == true,
                  data["commandId"] as? String == commandId else {
                let responseError = NSError(
                    domain: "pp.branch.inventory",
                    code: 502,
                    userInfo: [NSLocalizedDescriptionKey: Language.get(
                        "Inventory_InvalidAdjustmentResponse",
                        alter: "تعذر التحقق من نتيجة تعديل المخزون."
                    )]
                )
                completion?(.failure(responseError))
                return
            }
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion?(.success(data))
                    return
                }
                self.refreshInventory(for: productId, branchId: branchId)
                completion?(.success(data))
            }
        }
    }

    /// Transfer stock callable via backend Cloud Function
    public func transferStock(
        productId: String,
        sourceBranchId: String,
        destinationBranchId: String,
        quantity: Int,
        reason: String = "branch_transfer",
        notes: String = "",
        commandId suppliedCommandId: String? = nil,
        expectedSourceRevision: Int? = nil,
        expectedDestinationRevision: Int? = nil,
        completion: ((Result<[String: Any], Error>) -> Void)? = nil
    ) {
        let normalizedCommandId = suppliedCommandId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let commandId = normalizedCommandId.isEmpty
            ? "admin-ios-branch-transfer-\(productId)-\(UUID().uuidString.lowercased())"
            : normalizedCommandId
        var payload: [String: Any] = [
            "productId": productId,
            "sourceBranchId": sourceBranchId,
            "destinationBranchId": destinationBranchId,
            "quantity": quantity,
            "sessionId": BranchContextStore.shared.currentSessionId,
            "reason": reason,
            "notes": notes,
            "commandId": commandId
        ]
        if let expectedSourceRevision { payload["expectedSourceRevision"] = expectedSourceRevision }
        if let expectedDestinationRevision { payload["expectedDestinationRevision"] = expectedDestinationRevision }

        let callable = Functions.functions().httpsCallable("transferBranchStock")
        callable.call(["contractVersion": 2, "payload": payload]) { [weak self] result, error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            let data = (result?.data as? [String: Any]) ?? [:]
            guard data["ok"] as? Bool == true,
                  data["commandId"] as? String == commandId else {
                let responseError = NSError(
                    domain: "pp.branch.inventory",
                    code: 502,
                    userInfo: [NSLocalizedDescriptionKey: Language.get(
                        "Inventory_InvalidTransferResponse",
                        alter: "تعذر التحقق من نتيجة نقل المخزون."
                    )]
                )
                completion?(.failure(responseError))
                return
            }
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion?(.success(data))
                    return
                }
                self.refreshInventory(for: productId, branchId: sourceBranchId)
                self.refreshInventory(for: productId, branchId: destinationBranchId)
                completion?(.success(data))
            }
        }
    }

    // MARK: - Cycle Counting & Stock Reconciliation (Phase 5)

    /// Creates a cycle count session snapshotting current branch stock
    public func createCycleCountSession(
        branchId: String,
        scope: String = "all",
        category: String? = nil,
        shelfLocation: String? = nil,
        varianceThreshold: Int = 2,
        productIds: [String]? = nil,
        commandId: String? = nil,
        completion: @escaping (Result<PPCycleCountSession, Error>) -> Void
    ) {
        var payload: [String: Any] = [
            "branchId": branchId,
            "scope": scope,
            "varianceThreshold": varianceThreshold
        ]
        if let cat = category, !cat.isEmpty { payload["category"] = cat }
        if let shelf = shelfLocation, !shelf.isEmpty { payload["shelfLocation"] = shelf }
        if let pids = productIds, !pids.isEmpty { payload["productIds"] = pids }
        if let commandId { payload["commandId"] = commandId }

        let callable = Functions.functions().httpsCallable("createCycleCountSession")
        callable.call(["payload": payload]) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = result?.data as? [String: Any], data["ok"] as? Bool == true,
                  let auditId = data["auditId"] as? String, !auditId.isEmpty,
                  data["items"] is [[String: Any]] else {
                completion(.failure(Self.invalidCycleCountResponse()))
                return
            }
            let session = PPCycleCountSession(id: auditId, branchId: branchId, data: data)
            completion(.success(session))
        }
    }

    /// Submits physical counts from staff and calculates variances
    public func submitCycleCount(
        auditId: String,
        branchId: String,
        counts: [[String: any Sendable]],
        completion: @escaping (Result<PPCycleCountSession, Error>) -> Void
    ) {
        let payload: [String: any Sendable] = [
            "auditId": auditId,
            "branchId": branchId,
            "counts": counts
        ]

        let callable = Functions.functions().httpsCallable("submitCycleCount")
        let requestPayload: [String: any Sendable] = ["payload": payload]
        callable.call(requestPayload) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = result?.data as? [String: Any], data["ok"] as? Bool == true,
                  data["auditId"] as? String == auditId,
                  data["items"] is [[String: Any]], data["status"] is String else {
                completion(.failure(Self.invalidCycleCountResponse()))
                return
            }
            let session = PPCycleCountSession(id: auditId, branchId: branchId, data: data)
            completion(.success(session))
        }
    }

    /// Reconciles stock discrepancies transactionally, updates branch stock & catalog
    public func reconcileCycleCount(
        auditId: String,
        branchId: String,
        resolutionNotes: String = "",
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let payload: [String: any Sendable] = [
            "auditId": auditId,
            "branchId": branchId,
            "resolutionNotes": resolutionNotes
        ]

        let callable = Functions.functions().httpsCallable("reconcileCycleCount")
        let requestPayload: [String: any Sendable] = ["payload": payload]
        callable.call(requestPayload) { [weak self] result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = result?.data as? [String: Any], data["ok"] as? Bool == true,
                  data["auditId"] as? String == auditId else {
                completion(.failure(Self.invalidCycleCountResponse()))
                return
            }
            Task { @MainActor [weak self] in
                // Refresh local snapshot after reconciliation
                self?.startListeningIfNeeded()
                completion(.success(data))
            }
        }
    }

    /// Fetches past cycle count sessions
    public func fetchCycleCounts(
        branchId: String? = nil,
        status: String? = nil,
        limit: Int = 50,
        completion: @escaping (Result<[PPCycleCountSession], Error>) -> Void
    ) {
        var payload: [String: Any] = ["limit": limit]
        if let branchId = branchId { payload["branchId"] = branchId }
        if let status = status { payload["status"] = status }

        let callable = Functions.functions().httpsCallable("listCycleCounts")
        callable.call(["payload": payload]) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = result?.data as? [String: Any], data["ok"] as? Bool == true,
                  let items = data["items"] as? [[String: Any]],
                  items.allSatisfy({ !((($0["id"] ?? $0["auditId"]) as? String) ?? "").isEmpty }) else {
                completion(.failure(Self.invalidCycleCountResponse()))
                return
            }
            let sessions = items.map { dict in
                let id = (dict["id"] as? String) ?? (dict["auditId"] as? String) ?? ""
                let bId = (dict["branchId"] as? String) ?? (branchId ?? "")
                return PPCycleCountSession(id: id, branchId: bId, data: dict)
            }
            completion(.success(sessions))
        }
    }

    /// Fetches single cycle count session detail
    public func fetchCycleCountDetails(
        auditId: String,
        branchId: String,
        completion: @escaping (Result<PPCycleCountSession, Error>) -> Void
    ) {
        let payload: [String: Any] = [
            "auditId": auditId,
            "branchId": branchId
        ]

        let callable = Functions.functions().httpsCallable("getCycleCountSession")
        callable.call(["payload": payload]) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = result?.data as? [String: Any], data["ok"] as? Bool == true,
                  let sessionData = data["session"] as? [String: Any],
                  sessionData["branchId"] as? String == branchId else {
                completion(.failure(Self.invalidCycleCountResponse()))
                return
            }
            let session = PPCycleCountSession(id: auditId, branchId: branchId, data: sessionData)
            completion(.success(session))
        }
    }

    private nonisolated static func invalidCycleCountResponse() -> NSError {
        NSError(domain: "PPInventory", code: -1, userInfo: [NSLocalizedDescriptionKey:
            Language.get("Inventory_InvalidCommandResponse", alter: "تعذر التحقق من استجابة خدمة المخزون.")])
    }
}

// MARK: - Cycle Count Models

public struct PPCycleCountSession: Identifiable, Sendable {
    public let id: String
    public let branchId: String
    public let status: String // in_progress, pending_review, reconciled, cancelled
    public let scope: String // all, category, shelf, spot_check
    public let category: String?
    public let shelfLocation: String?
    public let varianceThreshold: Int
    public let itemCount: Int
    public let totalPhysicalCount: Int
    public let totalVariance: Int
    public let totalShrinkageUnits: Int
    public let totalSurplusUnits: Int
    public let totalShrinkageValue: Double?
    public let totalSurplusValue: Double?
    public let discrepancyCount: Int
    public let accuracyRate: Double
    public let createdBy: String
    public let createdByName: String
    public let createdAt: Date?
    public let submittedBy: String?
    public let submittedByName: String?
    public let submittedAt: Date?
    public let reconciledBy: String?
    public let reconciledByName: String?
    public let reconciledAt: Date?
    public let resolutionNotes: String?
    public let items: [PPCycleCountItem]

    public init(id: String, branchId: String, data: [String: Any]) {
        self.id = id
        self.branchId = branchId
        self.status = data["status"] as? String ?? "in_progress"
        self.scope = data["scope"] as? String ?? "all"
        self.category = data["category"] as? String
        self.shelfLocation = data["shelfLocation"] as? String
        self.varianceThreshold = (data["varianceThreshold"] as? NSNumber)?.intValue ?? 2
        self.itemCount = (data["itemCount"] as? NSNumber)?.intValue ?? 0
        self.totalPhysicalCount = (data["totalPhysicalCount"] as? NSNumber)?.intValue ?? 0
        self.totalVariance = (data["totalVariance"] as? NSNumber)?.intValue ?? 0
        self.totalShrinkageUnits = (data["totalShrinkageUnits"] as? NSNumber)?.intValue ?? 0
        self.totalSurplusUnits = (data["totalSurplusUnits"] as? NSNumber)?.intValue ?? 0
        self.totalShrinkageValue = (data["totalShrinkageValue"] as? NSNumber)?.doubleValue
        self.totalSurplusValue = (data["totalSurplusValue"] as? NSNumber)?.doubleValue
        self.discrepancyCount = (data["discrepancyCount"] as? NSNumber)?.intValue ?? 0
        self.accuracyRate = (data["accuracyRate"] as? NSNumber)?.doubleValue ?? 100.0
        self.createdBy = data["createdBy"] as? String ?? ""
        self.createdByName = data["createdByName"] as? String ?? ""
        self.submittedBy = data["submittedBy"] as? String
        self.submittedByName = data["submittedByName"] as? String
        self.reconciledBy = data["reconciledBy"] as? String
        self.reconciledByName = data["reconciledByName"] as? String
        self.resolutionNotes = data["resolutionNotes"] as? String

        let tsCreated = data["createdAt"] as? Timestamp
        self.createdAt = tsCreated?.dateValue() ?? Self.callableDate(data["createdAt"])
        let tsSubmitted = data["submittedAt"] as? Timestamp
        self.submittedAt = tsSubmitted?.dateValue() ?? Self.callableDate(data["submittedAt"])
        let tsReconciled = data["reconciledAt"] as? Timestamp
        self.reconciledAt = tsReconciled?.dateValue() ?? Self.callableDate(data["reconciledAt"])

        let rawItems = (data["items"] as? [[String: Any]]) ?? (data["snapshot"] as? [[String: Any]]) ?? []
        self.items = rawItems.map { PPCycleCountItem(data: $0) }
    }

    private static func callableDate(_ value: Any?) -> Date? {
        guard let fields = value as? [String: Any],
              let seconds = (fields["_seconds"] ?? fields["seconds"]) as? NSNumber,
              seconds.doubleValue.isFinite else { return nil }
        return Date(timeIntervalSince1970: seconds.doubleValue)
    }
}

public struct PPCycleCountItem: Identifiable, Sendable {
    public var id: String { productId }
    public let productId: String
    public let productName: String
    public let sku: String
    public let barcode: String
    public let category: String
    public let shelfLocation: String
    public let costPrice: Double?
    public let sellingPrice: Double
    public let expectedOnHand: Int?
    public let expectedAvailable: Int?
    public var countedQuantity: Int
    public let variance: Int?
    public let varianceCost: Double?
    public let varianceRetail: Double?
    public let status: String // matched, shrinkage, surplus, uncounted
    public var notes: String

    public init(data: [String: Any]) {
        self.productId = data["productId"] as? String ?? ""
        self.productName = data["productName"] as? String ?? ""
        self.sku = data["sku"] as? String ?? ""
        self.barcode = data["barcode"] as? String ?? ""
        self.category = data["category"] as? String ?? ""
        self.shelfLocation = data["shelfLocation"] as? String ?? ""
        self.costPrice = (data["costPrice"] as? NSNumber)?.doubleValue
        self.sellingPrice = (data["sellingPrice"] as? NSNumber)?.doubleValue ?? 0.0
        self.expectedOnHand = (data["expectedOnHand"] as? NSNumber)?.intValue
        self.expectedAvailable = (data["expectedAvailable"] as? NSNumber)?.intValue
        self.countedQuantity = (data["countedQuantity"] as? NSNumber)?.intValue ?? 0
        self.variance = (data["variance"] as? NSNumber)?.intValue
        self.varianceCost = (data["varianceCost"] as? NSNumber)?.doubleValue
        self.varianceRetail = (data["varianceRetail"] as? NSNumber)?.doubleValue
        self.status = data["status"] as? String ?? "uncounted"
        self.notes = data["notes"] as? String ?? ""
    }
}

// MARK: - Branch Inventory Error Helper

public enum PPBranchInventoryErrorHelper {
    public static func localizedMessage(for error: Error) -> String {
        let nsError = error as NSError

        // 1. Extract details dictionary or string from userInfo
        var detailMessage: String?
        if let detailsDict = (nsError.userInfo["details"] as? [String: Any]) ?? (nsError.userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any]) {
            if let domainCode = detailsDict["domainCode"] as? String {
                switch domainCode {
                case "CYCLE_COUNT_INCOMPLETE", "CYCLE_COUNT_INVALID_COUNTS":
                    return Language.get("Inventory_CountIncomplete", alter: "عدّ كل صنف أو أكد أن رصيده صفر قبل إرسال الجرد.")
                case "CYCLE_COUNT_SCOPE_TOO_LARGE":
                    return Language.get("Inventory_CountScopeTooLarge", alter: "اختر رفاً أو فئة أو جرداً انتقائياً لا يتجاوز 100 صنف.")
                case "CYCLE_COUNT_EMPTY":
                    return Language.get("Inventory_CountScopeEmpty", alter: "لا توجد أصناف مخزون في نطاق الجرد المحدد.")
                case "TRACKED_INVENTORY_OPERATION_REQUIRED":
                    return Language.get("Inventory_TrackedOperationRequired", alter: "استخدم مسار الحيوان المحدد أو التشغيلة لتعديل هذا المخزون.")
                case "INVENTORY_AGGREGATE_CONFLICT", "INVENTORY_IDENTITY_CONFLICT":
                    return Language.get("Inventory_AggregateConflict", alter: "أرصدة المخزون غير متطابقة. حدّث البيانات وسوّها قبل إعادة المحاولة.")
                case "STALE_REVISION":
                    return Language.get("Inventory_StaleCount", alter: "تغير المخزون بعد بدء الجرد. ابدأ جرداً جديداً قبل تطبيق التسوية.")
                case "INSUFFICIENT_BRANCH_STOCK":
                    return Language.get("Branch_Stock_Insufficient", alter: "الكمية المتوفرة في الفرع غير كافية لإتمام التحويل.")
                case "BRANCH_NOT_FOUND", "SOURCE_BRANCH_NOT_FOUND":
                    return Language.get("Branch_Stock_SourceBranchNotFound", alter: "لم يتم العثور على فرع المصدر في النظام.")
                case "DEST_BRANCH_NOT_FOUND":
                    return Language.get("Branch_Stock_DestBranchNotFound", alter: "لم يتم العثور على فرع الاستلام في النظام.")
                case "BRANCH_INACTIVE":
                    return Language.get("Branch_Stock_Inactive", alter: "الفرع المحدد غير نشط حالياً.")
                case "PRODUCT_NOT_FOUND":
                    return Language.get("Branch_Stock_ProductNotFound", alter: "لم يتم العثور على المنتج في قاعدة البيانات.")
                case "SAME_SOURCE_DESTINATION_BRANCH":
                    return Language.get("Branch_Stock_SameBranch", alter: "لا يمكن التحويل من وإلى نفس الفرع.")
                case "INVALID_ADJUSTMENT_QUANTITY", "NEGATIVE_QUANTITY_NOT_ALLOWED":
                    return Language.get("Branch_Stock_InvalidQuantity", alter: "يرجى تحديد كمية صالحة للتعديل.")
                case "INVALID_BUCKET_TRANSITION":
                    return Language.get("Branch_Stock_InvalidBucketTransition", alter: "حركة المخزون بين الحالات المحددة غير مسموح بها.")
                case "INVALID_REASON_CODE":
                    return Language.get("Branch_Stock_InvalidReasonCode", alter: "سبب التعديل أو الإتلاف المحدد غير صالح.")
                case "CYCLE_COUNT_SESSION_NOT_FOUND":
                    return Language.get("CycleCount_Error_NotFound", alter: "لم يتم العثور على جلسة الجرد في النظام.")
                case "CYCLE_COUNT_ALREADY_COMPLETED":
                    return Language.get("CycleCount_Error_AlreadyCompleted", alter: "تمت تسوية واعتماد جلسة الجرد هذه مسبقاً.")
                case "CYCLE_COUNT_INVALID_STATUS":
                    return Language.get("CycleCount_Error_InvalidStatus", alter: "حالة جلسة الجرد الحالية لا تسمح بهذا الإجراء.")
                case "VARIANCE_EXCEEDS_THRESHOLD":
                    return Language.get("CycleCount_Error_ExceedsThreshold", alter: "تجاوزت الفروقات الحد المسموح به وتتطلب اعتماد المدير.")
                case "UNAUTHORIZED_RECONCILIATION":
                    return Language.get("CycleCount_Error_Unauthorized", alter: "ليس لديك صلاحية لاعتماد وتسوية فروقات الجرد.")
                case "INVENTORY_LOT_MIGRATION_REQUIRED":
                    return Language.get("Inventory_Lot_MigrationRequired", alter: "يجب استهلاك أو تسوية المخزون الحالي قبل تفعيل تتبع التشغيلات.")
                case "PRODUCT_EXPIRED":
                    return Language.get("Inventory_Lot_ExpiredError", alter: "تاريخ انتهاء الصلاحية غير صالح أو أن التشغيلة منتهية الصلاحية.")
                case "LOT_ALREADY_EXISTS":
                    return Language.get("Inventory_Lot_AlreadyExists", alter: "رقم التشغيلة مسجل مسبقاً لهذا الصنف في هذا الفرع.")
                case "VALID_FROM_IN_FUTURE":
                    return Language.get("Inventory_Lot_ValidFromFuture", alter: "تاريخ بدء الصلاحية لا يمكن أن يكون في المستقبل.")
                case "INVALID_TRACKING_POLICY":
                    return Language.get("Inventory_Lot_InvalidPolicy", alter: "لا يمكن إنشاء تشغيلات لأصناف تتبع الوحدات الفردية.")
                case "LOT_UNAVAILABLE":
                    return Language.get("Inventory_Lot_Unavailable", alter: "التشغيلة المحددة غير متوفرة أو غير صالحة.")
                default:
                    break
                }
            }
            detailMessage = (detailsDict["message"] as? String) ?? (detailsDict["error"] as? String)
        } else if let detailsStr = nsError.userInfo["details"] as? String, !detailsStr.isEmpty {
            detailMessage = detailsStr
        }

        if let msg = detailMessage, !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return msg
        }

        // 2. Extract standard localized description
        let localizedDesc = (nsError.userInfo[NSLocalizedDescriptionKey] as? String) ?? error.localizedDescription
        let trimmed = localizedDesc.trimmingCharacters(in: .whitespacesAndNewlines)

        // 3. Map Firebase Functions standard codes into clear Arabic
        let isFunctionsDomain = nsError.domain == "com.firebase.functions" || nsError.domain == FunctionsErrorDomain
        if isFunctionsDomain {
            switch nsError.code {
            case 7, FunctionsErrorCode.permissionDenied.rawValue:
                return Language.get("Branch_Stock_PermissionDenied", alter: "ليس لديك صلاحية لإجراء تعديلات المخزون أو الوصول لهذا الفرع.")
            case 16, FunctionsErrorCode.unauthenticated.rawValue:
                return Language.get("Branch_Stock_Unauthenticated", alter: "انتهت صلاحية الجلسة، يرجى إعادة تسجيل الدخول.")
            case 5, FunctionsErrorCode.notFound.rawValue:
                if trimmed.lowercased().contains("branch") {
                    return Language.get("Branch_Stock_BranchNotFound", alter: "الفرع المحدد غير مسجل أو غير موجود.")
                }
                if trimmed.lowercased().contains("product") {
                    return Language.get("Branch_Stock_ProductNotFound", alter: "الصنف غير موجود في المخزون.")
                }
                return Language.get("Branch_Stock_NotFound", alter: "البيانات المطلوبة غير موجودة في النظام.")
            case 9, FunctionsErrorCode.failedPrecondition.rawValue:
                if trimmed.lowercased().contains("insufficient") {
                    return Language.get("Branch_Stock_Insufficient", alter: "الكمية المتوفرة في الفرع غير كافية لإتمام التحويل.")
                }
                if trimmed.lowercased().contains("inactive") {
                    return Language.get("Branch_Stock_Inactive", alter: "أحد الفروع المحددة غير نشط حالياً.")
                }
                if trimmed.lowercased().contains("validfrom") || trimmed.lowercased().contains("future") {
                    return Language.get("Inventory_Lot_ValidFromFuture", alter: "تاريخ بدء الصلاحية لا يمكن أن يكون في المستقبل.")
                }
                if trimmed.lowercased().contains("expired") {
                    return Language.get("Inventory_Lot_ExpiredError", alter: "تاريخ انتهاء الصلاحية غير صالح أو أن التشغيلة منتهية الصلاحية.")
                }
                if trimmed.lowercased().contains("migration") || trimmed.lowercased().contains("allocated") {
                    return Language.get("Inventory_Lot_MigrationRequired", alter: "يجب استهلاك أو تسوية المخزون الحالي قبل تفعيل تتبع التشغيلات.")
                }
                if !trimmed.isEmpty && !trimmed.contains("com.firebase.functions") && !trimmed.lowercased().contains("the operation couldn") {
                    return trimmed
                }
                return Language.get("Branch_Stock_PreconditionFailed", alter: "تعذر تنفيذ العملية بسبب عدم استيفاء شروط المخزون.")
            case 3, FunctionsErrorCode.invalidArgument.rawValue:
                if trimmed.lowercased().contains("same") {
                    return Language.get("Branch_Stock_SameBranch", alter: "لا يمكن التحويل من وإلى نفس الفرع.")
                }
                return Language.get("Branch_Stock_InvalidArgument", alter: "بيانات العملية غير صحيحة، يرجى مراجعة المدخلات.")
            case 13, FunctionsErrorCode.internal.rawValue:
                return Language.get("Branch_Stock_InternalError", alter: "حدث خطأ في الخادم أثناء معالجة المخزون. يرجى مراجعة سجل الحركات أو المحاولة لاحقاً.")
            default:
                break
            }
        }

        // 4. Return trimmed description if it's descriptive and not a raw token
        if !trimmed.isEmpty && trimmed != "INTERNAL" && !trimmed.contains("com.firebase.functions") && !trimmed.lowercased().contains("the operation couldn") {
            return trimmed
        }

        return Language.get("Branch_Stock_GeneralError", alter: "حدث خطأ أثناء تعديل المخزون. يرجى المحاولة مرة أخرى.")
    }
}
