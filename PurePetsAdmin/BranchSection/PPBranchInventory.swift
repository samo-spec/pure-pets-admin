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
    public let minimumStock: Int
    public let maximumStock: Int
    public let shelfLocation: String
    public let costPrice: Double?
    public let sellingPrice: Double?
    public let noStock: Bool
    public let updatedAt: Date?

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
        minimumStock: Int = 0,
        maximumStock: Int = 0,
        shelfLocation: String = "",
        costPrice: Double? = nil,
        sellingPrice: Double? = nil,
        noStock: Bool = false,
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
        self.minimumStock = minimumStock
        self.maximumStock = maximumStock
        self.shelfLocation = shelfLocation
        self.costPrice = costPrice
        self.sellingPrice = sellingPrice
        self.noStock = noStock
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
        self.quantity = max(0, rawQty)
        self.reservedQuantity = max(0, rawReserved)
        self.availableQuantity = max(0, rawQty - rawReserved)
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
        
        self.noStock = (dictionary["noStock"] as? Bool) ?? (self.quantity <= 0)
        
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

    /// Returns available stock only from the active branch projection.
    /// Missing branch inventory is unavailable, never a fallback to the company-wide catalog quantity.
    public func availableStock(for productId: String, fallback: Int = 0) -> Int {
        guard currentBranchId?.isEmpty == false else { return 0 }
        return inventoryMap[productId]?.availableQuantity ?? 0
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
        completion: @escaping (Result<[String: Any], Error>) -> Void
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
        callable.call(["payload": payload]) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let data = (result?.data as? [String: Any]) ?? [:]
            completion(.success(data))
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
        completion: @escaping (Result<[String: Any], Error>) -> Void
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
        callable.call(["payload": payload]) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let data = (result?.data as? [String: Any]) ?? [:]
            completion(.success(data))
        }
    }
}
