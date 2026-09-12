//
//  PPInventoryLot.swift
//  PurePetsAdmin
//
//  Inventory Lot model and service for batch/lot tracking,
//  FEFO allocations, and expiry management.
//

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Inventory Lot Record

public struct PPInventoryLot: Identifiable, Hashable, Sendable {
    public let id: String
    public let lotId: String
    public let lotNumber: String
    public let productId: String
    public let productName: String
    public let branchId: String
    public let initialQuantity: Int
    public let availableQuantity: Int
    public let reservedQuantity: Int
    public let onHandQuantity: Int
    public let costPrice: Double
    public let expiryDate: Date?
    public let status: String
    public let supplier: String
    public let notes: String
    public let createdAt: Date?

    public init(
        id: String,
        lotId: String = "",
        lotNumber: String,
        productId: String,
        productName: String = "",
        branchId: String,
        initialQuantity: Int,
        availableQuantity: Int,
        reservedQuantity: Int = 0,
        onHandQuantity: Int? = nil,
        costPrice: Double = 0.0,
        expiryDate: Date?,
        status: String = "active",
        supplier: String = "",
        notes: String = "",
        createdAt: Date? = nil
    ) {
        self.id = id
        self.lotId = lotId.isEmpty ? id : lotId
        self.lotNumber = lotNumber
        self.productId = productId
        self.productName = productName
        self.branchId = branchId
        self.initialQuantity = initialQuantity
        self.availableQuantity = availableQuantity
        self.reservedQuantity = reservedQuantity
        self.onHandQuantity = onHandQuantity ?? (availableQuantity + reservedQuantity)
        self.costPrice = costPrice
        self.expiryDate = expiryDate
        self.status = status
        self.supplier = supplier
        self.notes = notes
        self.createdAt = createdAt
    }

    public var isExpired: Bool {
        guard let expiryDate else { return false }
        return expiryDate <= Date()
    }

    public var daysUntilExpiry: Int? {
        guard let expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day
    }

    public var isNearExpiry: Bool {
        guard let days = daysUntilExpiry else { return false }
        return days >= 0 && days <= 30
    }

    public var expiryFormatted: String {
        guard let expiryDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: expiryDate)
    }

    public var statusLocalizedKey: String {
        if isExpired { return "inventory_lot_status_expired" }
        switch status.lowercased() {
        case "depleted": return "inventory_lot_status_depleted"
        case "quarantined": return "inventory_lot_status_quarantined"
        default: return "inventory_lot_status_active"
        }
    }

    public var statusColor: Color {
        if isExpired { return .red }
        if isNearExpiry { return .orange }
        switch status.lowercased() {
        case "depleted": return .secondary
        case "quarantined": return .purple
        default: return .green
        }
    }
}

// MARK: - Inventory Lot Service

@MainActor
public final class PPInventoryLotService: ObservableObject {
    public static let shared = PPInventoryLotService()

    @Published public var lotsByProduct: [String: [PPInventoryLot]] = [:]
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private lazy var functions = Functions.functions()

    private init() {}

    /// Fetches branch inventory lots sorted by FEFO (earliest expiry first).
    public func fetchLots(
        branchId: String,
        productId: String,
        includeDepleted: Bool = false,
        includeExpired: Bool = false
    ) async throws -> [PPInventoryLot] {
        isLoading = true
        defer { isLoading = false }

        let resolvedBranch: String
        let trimmed = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "all_branches" && trimmed != "main_store" {
            resolvedBranch = trimmed
        } else if let active = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines), !active.isEmpty && active != "main_store" {
            resolvedBranch = active
        } else {
            throw NSError(
                domain: "PPInventoryLotService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: Language.get("Branch_Required_Error", alter: "يجب تحديد الفرع لعرض التشغيلات")]
            )
        }

        let payload: [String: Any] = [
            "branchId": resolvedBranch,
            "productId": productId,
            "includeDepleted": includeDepleted,
            "includeExpired": includeExpired
        ]

        // 1. Attempt Cloud Function callable
        do {
            let result = try await functions.httpsCallable("listBranchInventoryLots").call(["payload": payload])

            guard let dict = result.data as? [String: Any],
                  let lotsRaw = dict["lots"] as? [[String: Any]] else {
                throw NSError(
                    domain: "PPInventoryLotService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: Language.get("Inventory_Lot_Invalid_Response", alter: "استجابة غير صالحة من الخادم")]
                )
            }

            let parsedLots = lotsRaw.compactMap { lotDict -> PPInventoryLot? in
                guard let id = lotDict["id"] as? String,
                      let lotNumber = lotDict["lotNumber"] as? String else {
                    return nil
                }

                var expDate: Date? = nil
                if let expStr = lotDict["expiryDate"] as? String {
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    expDate = isoFormatter.date(from: expStr) ?? ISO8601DateFormatter().date(from: expStr)
                }

                return PPInventoryLot(
                    id: id,
                    lotId: (lotDict["lotId"] as? String) ?? id,
                    lotNumber: lotNumber,
                    productId: (lotDict["productId"] as? String) ?? productId,
                    productName: (lotDict["productName"] as? String) ?? "",
                    branchId: (lotDict["branchId"] as? String) ?? resolvedBranch,
                    initialQuantity: (lotDict["initialQuantity"] as? Int) ?? 0,
                    availableQuantity: (lotDict["availableQuantity"] as? Int) ?? 0,
                    reservedQuantity: (lotDict["reservedQuantity"] as? Int) ?? 0,
                    onHandQuantity: lotDict["onHandQuantity"] as? Int,
                    costPrice: (lotDict["costPrice"] as? Double) ?? 0.0,
                    expiryDate: expDate,
                    status: (lotDict["status"] as? String) ?? "active",
                    supplier: (lotDict["supplier"] as? String) ?? "",
                    notes: (lotDict["notes"] as? String) ?? ""
                )
            }

            lotsByProduct[productId] = parsedLots
            return parsedLots
        } catch {
            // Lot records contain cost, supplier and expiry data. A callable
            // failure must not turn into a direct Firestore query that could
            // bypass the server's permission and branch-scope filtering.
            throw error
        }
    }

    /// Legacy compatibility entry point. It intentionally routes through the
    /// callable instead of retaining a direct Firestore fallback.
    @available(*, deprecated, message: "Use fetchLots(branchId:productId:includeDepleted:includeExpired:)")
    public func fetchLotsFromFirestore(
        branchId: String,
        productId: String,
        includeDepleted: Bool = false,
        includeExpired: Bool = false
    ) async throws -> [PPInventoryLot] {
        try await fetchLots(
            branchId: branchId,
            productId: productId,
            includeDepleted: includeDepleted,
            includeExpired: includeExpired
        )
    }

    /// Creates a new lot record for the branch and product.
    public func createLot(
        branchId: String,
        productId: String,
        lotNumber: String,
        initialQuantity: Int,
        costPrice: Double = 0.0,
        expiryDate: Date,
        supplier: String = "",
        notes: String = ""
    ) async throws -> PPInventoryLot {
        isLoading = true
        defer { isLoading = false }

        let resolvedBranch: String
        let trimmed = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "all_branches" && trimmed != "main_store" {
            resolvedBranch = trimmed
        } else if let active = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines), !active.isEmpty && active != "main_store" {
            resolvedBranch = active
        } else {
            throw NSError(
                domain: "PPInventoryLotManager",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: Language.get("Branch_Required_Error_Create_Lot", alter: "يجب تحديد الفرع لإنشاء التشغيلة")]
            )
        }

        let isoFormatter = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "branchId": resolvedBranch,
            "productId": productId,
            "lotNumber": lotNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            "initialQuantity": initialQuantity,
            "costPrice": costPrice,
            "expiryDate": isoFormatter.string(from: expiryDate),
            "supplier": supplier.trimmingCharacters(in: .whitespacesAndNewlines),
            "notes": notes.trimmingCharacters(in: .whitespacesAndNewlines),
            "commandId": UUID().uuidString
        ]

        do {
            let result = try await functions.httpsCallable("createInventoryLot").call(["payload": payload])

            guard let dict = result.data as? [String: Any],
                  let lotData = dict["lot"] as? [String: Any],
                  let lotId = lotData["lotId"] as? String else {
                throw NSError(domain: "PPInventoryLotService", code: -1, userInfo: [NSLocalizedDescriptionKey: Language.get("Inventory_Lot_Invalid_Response", alter: "استجابة غير صالحة من الخادم")])
            }

            let newLot = PPInventoryLot(
                id: lotId,
                lotId: lotId,
                lotNumber: lotNumber,
                productId: productId,
                branchId: resolvedBranch,
                initialQuantity: initialQuantity,
                availableQuantity: initialQuantity,
                costPrice: costPrice,
                expiryDate: expiryDate,
                status: "active",
                supplier: supplier,
                notes: notes,
                createdAt: Date()
            )

            var current = lotsByProduct[productId] ?? []
            current.insert(newLot, at: 0)
            lotsByProduct[productId] = current

            return newLot
        } catch {
            let msg = PPBranchInventoryErrorHelper.localizedMessage(for: error)
            throw NSError(domain: "PPInventoryLotService", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
