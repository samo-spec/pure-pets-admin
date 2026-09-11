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
        
        let rawQty = (dictionary["quantity"] as? NSNumber)?.intValue ?? 0
        let rawReserved = (dictionary["reservedQuantity"] as? NSNumber)?.intValue ?? 0
        let rawAvailable = (dictionary["availableQuantity"] as? NSNumber)?.intValue
        let rawDamaged = (dictionary["damagedQuantity"] as? NSNumber)?.intValue ?? 0
        let rawExpired = (dictionary["expiredQuantity"] as? NSNumber)?.intValue ?? 0
        let rawQuarantine = (dictionary["quarantineQuantity"] as? NSNumber)?.intValue ?? 0
        let rawSupplierReturn = (dictionary["supplierReturnQuantity"] as? NSNumber)?.intValue ?? 0
        let rawOnHand = (dictionary["onHandQuantity"] as? NSNumber)?.intValue

        self.quantity = max(0, rawQty)
        self.reservedQuantity = max(0, rawReserved)
        self.damagedQuantity = max(0, rawDamaged)
        self.expiredQuantity = max(0, rawExpired)
        self.quarantineQuantity = max(0, rawQuarantine)
        self.supplierReturnQuantity = max(0, rawSupplierReturn)
        self.availableQuantity = max(0, rawAvailable ?? (rawQty - rawReserved))
        self.onHandQuantity = max(
            0,
            rawOnHand ?? (self.availableQuantity + self.reservedQuantity + self.damagedQuantity + self.expiredQuantity + self.quarantineQuantity + self.supplierReturnQuantity)
        )
        self.projectionRevision = (dictionary["projectionRevision"] as? NSNumber)?.intValue ?? 1
        self.minimumStock = max(0, (dictionary["minimumStock"] as? NSNumber)?.intValue ?? 0)
        self.maximumStock = max(0, (dictionary["maximumStock"] as? NSNumber)?.intValue ?? 0)
        self.shelfLocation = (dictionary["shelfLocation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if let cost = dictionary["costPrice"] as? NSNumber {
            self.costPrice = cost.doubleValue
        } else {
            self.costPrice = nil
        }
        
        if let price = dictionary["sellingPrice"] as? NSNumber {
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

// MARK: - Reactive Branch Inventory Service

@MainActor
public final class PPBranchInventoryService: ObservableObject {
    public static let shared = PPBranchInventoryService()

    /// Real-time map of branch inventory keyed by productId: [productId: PPBranchInventory]
    @Published public private(set) var inventoryMap: [String: PPBranchInventory] = [:]

    /// Real-time map of branch product settings overrides: [productId: PPBranchProductSettings]
    @Published public private(set) var settingsMap: [String: PPBranchProductSettings] = [:]

    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var currentBranchId: String? = nil
    @Published public private(set) var lastSyncDate: Date? = nil

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

    /// Subscribes to Firestore collection `branchInventory` and `branchProductSettings` for the specified branch.
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
        lastSyncDate = nil

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

        listenerRegistration = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self,
                      self.bindingGeneration == generation,
                      self.currentBranchId == branchId else { return }
                self.isLoading = false

                if let error {
                    print("❌ [PPBranchInventoryService] Firestore inventory listener error: \(error.localizedDescription)")
                    return
                }

                guard let documents = snapshot?.documents else { return }
                var newMap: [String: PPBranchInventory] = [:]
                for doc in documents {
                    if let record = PPBranchInventory(dictionary: doc.data(), documentId: doc.documentID) {
                        newMap[record.productId] = record
                    }
                }
                self.inventoryMap = newMap
                self.lastSyncDate = Date()
            }
        }

        let settingsQuery = Firestore.firestore()
            .collection("branchProductSettings")
            .whereField("branchId", isEqualTo: branchId)

        settingsListenerRegistration = settingsQuery.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self,
                      self.bindingGeneration == generation,
                      self.currentBranchId == branchId else { return }
                if let error {
                    print("❌ [PPBranchInventoryService] Firestore settings listener error: \(error.localizedDescription)")
                    return
                }

                guard let documents = snapshot?.documents else { return }
                var newSettings: [String: PPBranchProductSettings] = [:]
                for doc in documents {
                    if let setting = PPBranchProductSettings(dictionary: doc.data(), documentId: doc.documentID) {
                        newSettings[setting.productId] = setting
                    }
                }
                self.settingsMap = newSettings
            }
        }
    }

    /// Returns the branch inventory record for a given product ID
    public func inventory(for productId: String) -> PPBranchInventory? {
        inventoryMap[productId]
    }

    /// Returns available stock from the active branch projection.
    /// If an explicit branch record exists in `inventoryMap`, its available quantity is authoritative.
    /// If no branch-specific record exists, falls back to the catalog quantity for unsegmented stock.
    public func availableStock(for productId: String, fallback: Int = 0) -> Int {
        guard let currentBranchId = currentBranchId?.trimmingCharacters(in: .whitespacesAndNewlines), !currentBranchId.isEmpty else {
            return fallback
        }
        if let record = inventoryMap[productId] {
            return record.availableQuantity
        }
        return max(0, fallback)
    }

    /// Resolves the effective selling price for a product, honoring branch overrides when present
    public func effectiveSellingPrice(for productId: String, fallbackPrice: Double) -> Double {
        if let settings = settingsMap[productId], let customPrice = settings.sellingPrice, customPrice > 0 {
            return customPrice
        }
        if let record = inventoryMap[productId], let recordPrice = record.sellingPrice, recordPrice > 0 {
            return recordPrice
        }
        return fallbackPrice
    }

    /// Updates or inserts a local in-memory branch inventory record for immediate UI reactivity.
    public func updateAvailableStockLocally(for productId: String, branchId: String, newQuantity: Int) {
        let cleanBranch = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBranch.isEmpty, currentBranchId == cleanBranch else { return }
        let clamped = max(0, newQuantity)
        if let existing = inventoryMap[productId] {
            let nextAvailable = max(0, clamped - existing.reservedQuantity)
            let updated = PPBranchInventory(
                id: existing.id,
                branchId: existing.branchId,
                productId: existing.productId,
                productName: existing.productName,
                sku: existing.sku,
                barcode: existing.barcode,
                category: existing.category,
                quantity: clamped,
                reservedQuantity: existing.reservedQuantity,
                availableQuantity: nextAvailable,
                onHandQuantity: nextAvailable + existing.reservedQuantity + existing.damagedQuantity + existing.expiredQuantity + existing.quarantineQuantity + existing.supplierReturnQuantity,
                damagedQuantity: existing.damagedQuantity,
                expiredQuantity: existing.expiredQuantity,
                quarantineQuantity: existing.quarantineQuantity,
                supplierReturnQuantity: existing.supplierReturnQuantity,
                minimumStock: existing.minimumStock,
                maximumStock: existing.maximumStock,
                shelfLocation: existing.shelfLocation,
                costPrice: existing.costPrice,
                sellingPrice: existing.sellingPrice,
                noStock: nextAvailable <= 0,
                projectionRevision: existing.projectionRevision + 1,
                updatedAt: Date()
            )
            inventoryMap[productId] = updated
        } else {
            let newRecord = PPBranchInventory(
                id: "\(cleanBranch)_\(productId)",
                branchId: cleanBranch,
                productId: productId,
                quantity: clamped,
                reservedQuantity: 0,
                availableQuantity: clamped,
                onHandQuantity: clamped,
                damagedQuantity: 0,
                expiredQuantity: 0,
                quarantineQuantity: 0,
                supplierReturnQuantity: 0,
                noStock: clamped <= 0,
                projectionRevision: 1,
                updatedAt: Date()
            )
            inventoryMap[productId] = newRecord
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
                if let branchData = data["branchInventory"] as? [String: Any] {
                    let docId = (data["branchInventoryId"] as? String) ?? "\(resolvedBranch)_\(productId)"
                    if let record = PPBranchInventory(dictionary: branchData, documentId: docId) {
                        self.inventoryMap[productId] = record
                    }
                } else if let existing = self.inventoryMap[productId] {
                    let newAvail = max(0, existing.availableQuantity - quantity)
                    let newDamaged = existing.damagedQuantity + quantity
                    let updated = PPBranchInventory(
                        id: existing.id,
                        branchId: existing.branchId,
                        productId: existing.productId,
                        productName: existing.productName,
                        sku: existing.sku,
                        barcode: existing.barcode,
                        category: existing.category,
                        quantity: existing.quantity,
                        reservedQuantity: existing.reservedQuantity,
                        availableQuantity: newAvail,
                        onHandQuantity: existing.onHandQuantity,
                        damagedQuantity: newDamaged,
                        expiredQuantity: existing.expiredQuantity,
                        quarantineQuantity: existing.quarantineQuantity,
                        supplierReturnQuantity: existing.supplierReturnQuantity,
                        minimumStock: existing.minimumStock,
                        maximumStock: existing.maximumStock,
                        shelfLocation: existing.shelfLocation,
                        costPrice: existing.costPrice,
                        sellingPrice: existing.sellingPrice,
                        noStock: newAvail <= 0,
                        projectionRevision: existing.projectionRevision + 1,
                        updatedAt: Date()
                    )
                    self.inventoryMap[productId] = updated
                }
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
                // Refresh local cache if record is available in map
                if let existing = self.inventoryMap[productId] {
                    var avail = existing.availableQuantity
                    let res = existing.reservedQuantity
                    var quar = existing.quarantineQuantity
                    var dam = existing.damagedQuantity
                    var exp = existing.expiredQuantity
                    var ret = existing.supplierReturnQuantity
                    var onHand = existing.onHandQuantity

                    if action == "write_off" {
                        onHand = max(0, onHand - quantity)
                        switch fromBucket {
                        case "available": avail = max(0, avail - quantity)
                        case "quarantine": quar = max(0, quar - quantity)
                        case "damaged": dam = max(0, dam - quantity)
                        case "expired": exp = max(0, exp - quantity)
                        case "supplierReturn": ret = max(0, ret - quantity)
                        default: break
                        }
                    } else if action == "move", let to = toBucket {
                        switch fromBucket {
                        case "available": avail = max(0, avail - quantity)
                        case "quarantine": quar = max(0, quar - quantity)
                        case "damaged": dam = max(0, dam - quantity)
                        case "expired": exp = max(0, exp - quantity)
                        case "supplierReturn": ret = max(0, ret - quantity)
                        default: break
                        }
                        switch to {
                        case "available": avail += quantity
                        case "quarantine": quar += quantity
                        case "damaged": dam += quantity
                        case "expired": exp += quantity
                        case "supplierReturn": ret += quantity
                        default: break
                        }
                    }

                    let updated = PPBranchInventory(
                        id: existing.id,
                        branchId: existing.branchId,
                        productId: existing.productId,
                        productName: existing.productName,
                        sku: existing.sku,
                        barcode: existing.barcode,
                        category: existing.category,
                        quantity: existing.quantity,
                        reservedQuantity: res,
                        availableQuantity: avail,
                        onHandQuantity: onHand,
                        damagedQuantity: dam,
                        expiredQuantity: exp,
                        quarantineQuantity: quar,
                        supplierReturnQuantity: ret,
                        minimumStock: existing.minimumStock,
                        maximumStock: existing.maximumStock,
                        shelfLocation: existing.shelfLocation,
                        costPrice: existing.costPrice,
                        sellingPrice: existing.sellingPrice,
                        noStock: avail <= 0,
                        projectionRevision: existing.projectionRevision + 1,
                        updatedAt: Date()
                    )
                    self.inventoryMap[productId] = updated
                }
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
        completion: ((Result<[String: Any], Error>) -> Void)? = nil
    ) {
        var payload: [String: Any] = [
            "productId": productId,
            "branchId": branchId,
            "type": type,
            "referenceId": referenceId,
            "sessionId": BranchContextStore.shared.currentSessionId,
            "reason": reason,
            "notes": notes
        ]
        if let newQty = newQuantity {
            payload["newQuantity"] = newQty
        }
        if let d = delta {
            payload["delta"] = d
        }

        let callable = Functions.functions().httpsCallable("adjustBranchStock")
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
                if let newQtyNum = (data["newQuantity"] as? NSNumber) ?? (data["targetBranchQty"] as? NSNumber) {
                    self.updateAvailableStockLocally(
                        for: productId,
                        branchId: branchId,
                        newQuantity: newQtyNum.intValue
                    )
                }
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
        completion: ((Result<[String: Any], Error>) -> Void)? = nil
    ) {
        let payload: [String: Any] = [
            "productId": productId,
            "sourceBranchId": sourceBranchId,
            "destinationBranchId": destinationBranchId,
            "quantity": quantity,
            "sessionId": BranchContextStore.shared.currentSessionId,
            "reason": reason,
            "notes": notes
        ]

        let callable = Functions.functions().httpsCallable("transferBranchStock")
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
                if let sourceNewQtyNum = data["sourceNewQuantity"] as? NSNumber {
                    self.updateAvailableStockLocally(
                        for: productId,
                        branchId: sourceBranchId,
                        newQuantity: sourceNewQtyNum.intValue
                    )
                }
                if let destNewQtyNum = data["destNewQuantity"] as? NSNumber {
                    self.updateAvailableStockLocally(
                        for: productId,
                        branchId: destinationBranchId,
                        newQuantity: destNewQtyNum.intValue
                    )
                }
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

        let callable = Functions.functions().httpsCallable("createCycleCountSession")
        callable.call(["payload": payload]) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let data = (result?.data as? [String: Any]) ?? [:]
            let auditId = data["auditId"] as? String ?? ""
            let session = PPCycleCountSession(id: auditId, branchId: branchId, data: data)
            completion(.success(session))
        }
    }

    /// Submits physical counts from staff and calculates variances
    public func submitCycleCount(
        auditId: String,
        branchId: String,
        counts: [[String: Any]],
        completion: @escaping (Result<PPCycleCountSession, Error>) -> Void
    ) {
        let payload: [String: Any] = [
            "auditId": auditId,
            "branchId": branchId,
            "counts": counts
        ]

        let callable = Functions.functions().httpsCallable("submitCycleCount")
        callable.call(["payload": payload]) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let data = (result?.data as? [String: Any]) ?? [:]
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
        let payload: [String: Any] = [
            "auditId": auditId,
            "branchId": branchId,
            "resolutionNotes": resolutionNotes
        ]

        let callable = Functions.functions().httpsCallable("reconcileCycleCount")
        callable.call(["payload": payload]) { [weak self] result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let data = (result?.data as? [String: Any]) ?? [:]
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
            let data = (result?.data as? [String: Any]) ?? [:]
            let items = (data["items"] as? [[String: Any]]) ?? []
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
            let data = (result?.data as? [String: Any]) ?? [:]
            let sessionData = (data["session"] as? [String: Any]) ?? data
            let session = PPCycleCountSession(id: auditId, branchId: branchId, data: sessionData)
            completion(.success(session))
        }
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
    public let totalShrinkageValue: Double
    public let totalSurplusValue: Double
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
        self.totalShrinkageValue = (data["totalShrinkageValue"] as? NSNumber)?.doubleValue ?? 0.0
        self.totalSurplusValue = (data["totalSurplusValue"] as? NSNumber)?.doubleValue ?? 0.0
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
        self.createdAt = tsCreated?.dateValue()
        let tsSubmitted = data["submittedAt"] as? Timestamp
        self.submittedAt = tsSubmitted?.dateValue()
        let tsReconciled = data["reconciledAt"] as? Timestamp
        self.reconciledAt = tsReconciled?.dateValue()

        let rawItems = (data["items"] as? [[String: Any]]) ?? (data["snapshot"] as? [[String: Any]]) ?? []
        self.items = rawItems.map { PPCycleCountItem(data: $0) }
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
    public let costPrice: Double
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
        self.costPrice = (data["costPrice"] as? NSNumber)?.doubleValue ?? 0.0
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

