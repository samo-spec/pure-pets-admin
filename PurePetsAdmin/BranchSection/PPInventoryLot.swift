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
    public let costPrice: Double?
    public let validFrom: Date?
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
        costPrice: Double? = nil,
        validFrom: Date? = nil,
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
        self.validFrom = validFrom
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

    /// A lot is considered pristine/unused if no units have been sold or reserved,
    /// available equals initial, and on-hand equals initial.
    public var isPristineUnused: Bool {
        return initialQuantity > 0 &&
               availableQuantity == initialQuantity &&
               reservedQuantity == 0 &&
               onHandQuantity == initialQuantity
    }

    /// Consumed/sold units from this lot that cannot be undone.
    public var consumedQuantity: Int {
        return max(0, initialQuantity - availableQuantity - reservedQuantity)
    }

    /// The minimum allowed new quantity when editing this lot:
    /// cannot be reduced below consumed + reserved units.
    public var minAllowedQuantity: Int {
        return max(0, initialQuantity - availableQuantity)
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
    private var pendingLoads = 0

    private init() {}

    /// Fetches branch inventory lots sorted by FEFO (earliest expiry first).
    public func fetchLots(
        branchId: String,
        productId: String,
        includeDepleted: Bool = false,
        includeExpired: Bool = false
    ) async throws -> [PPInventoryLot] {
        pendingLoads += 1
        isLoading = true
        defer { pendingLoads -= 1; isLoading = pendingLoads > 0 }

        let resolvedBranch: String
        let trimmed = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "all_branches" && trimmed != "main_store" {
            resolvedBranch = trimmed
        } else if let active = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines), !active.isEmpty && active != "main_store" {
            resolvedBranch = active
        } else if let firstAvailable = BranchContextStore.shared.availableBranches.first(where: { !$0.branchID.isEmpty && $0.branchID != "all_branches" && $0.branchID != "main_store" })?.branchID {
            resolvedBranch = firstAvailable
        } else if !trimmed.isEmpty && trimmed != "all_branches" {
            resolvedBranch = trimmed
        } else if let active = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines), !active.isEmpty {
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
                  (dict["ok"] as? Bool == true || (dict["ok"] as? NSNumber)?.boolValue == true),
                  let lotsRaw = dict["lots"] as? [[String: Any]],
                  lotsRaw.allSatisfy({ ($0["id"] as? String)?.isEmpty == false && $0["lotNumber"] is String && $0["branchId"] as? String == resolvedBranch && $0["productId"] as? String == productId }) else {
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

                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                var validFromDate: Date? = nil
                if let validFromString = lotDict["validFrom"] as? String {
                    validFromDate = isoFormatter.date(from: validFromString) ?? ISO8601DateFormatter().date(from: validFromString)
                }

                var expDate: Date? = nil
                if let expStr = lotDict["expiryDate"] as? String {
                    expDate = isoFormatter.date(from: expStr) ?? ISO8601DateFormatter().date(from: expStr)
                }

                return PPInventoryLot(
                    id: id,
                    lotId: (lotDict["lotId"] as? String) ?? id,
                    lotNumber: lotNumber,
                    productId: (lotDict["productId"] as? String) ?? productId,
                    productName: (lotDict["productName"] as? String) ?? "",
                    branchId: (lotDict["branchId"] as? String) ?? resolvedBranch,
                    initialQuantity: (lotDict["initialQuantity"] as? NSNumber)?.intValue ?? (lotDict["initialQuantity"] as? Int) ?? 0,
                    availableQuantity: (lotDict["availableQuantity"] as? NSNumber)?.intValue ?? (lotDict["availableQuantity"] as? Int) ?? 0,
                    reservedQuantity: (lotDict["reservedQuantity"] as? NSNumber)?.intValue ?? (lotDict["reservedQuantity"] as? Int) ?? 0,
                    onHandQuantity: (lotDict["onHandQuantity"] as? NSNumber)?.intValue ?? (lotDict["onHandQuantity"] as? Int),
                    costPrice: (lotDict["costPrice"] as? NSNumber)?.doubleValue,
                    validFrom: validFromDate,
                    expiryDate: expDate,
                    status: (lotDict["status"] as? String) ?? "active",
                    supplier: (lotDict["supplier"] as? String) ?? "",
                    notes: (lotDict["notes"] as? String) ?? ""
                )
            }

            lotsByProduct["\(resolvedBranch)/\(productId)"] = parsedLots
            errorMessage = nil
            return parsedLots
        } catch {
            // Lot records contain cost, supplier and expiry data. A callable
            // failure must not turn into a direct Firestore query that could
            // bypass the server's permission and branch-scope filtering.
            errorMessage = PPBranchInventoryErrorHelper.localizedMessage(for: error)
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
        costPrice: Double? = nil,
        validFrom: Date,
        expiryDate: Date,
        supplier: String = "",
        notes: String = "",
        commandId: String? = nil
    ) async throws -> PPInventoryLot {
        pendingLoads += 1
        isLoading = true
        defer { pendingLoads -= 1; isLoading = pendingLoads > 0 }

        let resolvedBranch: String
        let trimmed = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "all_branches" && trimmed != "main_store" {
            resolvedBranch = trimmed
        } else if let active = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines), !active.isEmpty && active != "main_store" {
            resolvedBranch = active
        } else if let firstAvailable = BranchContextStore.shared.availableBranches.first(where: { !$0.branchID.isEmpty && $0.branchID != "all_branches" && $0.branchID != "main_store" })?.branchID {
            resolvedBranch = firstAvailable
        } else if !trimmed.isEmpty && trimmed != "all_branches" {
            resolvedBranch = trimmed
        } else if let active = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines), !active.isEmpty {
            resolvedBranch = active
        } else {
            throw NSError(
                domain: "PPInventoryLotManager",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: Language.get("Branch_Required_Error_Create_Lot", alter: "يجب تحديد الفرع لإنشاء التشغيلة")]
            )
        }

        let isoFormatter = ISO8601DateFormatter()
        let clampedValidFrom = min(validFrom, Date())
        var payload: [String: Any] = [
            "branchId": resolvedBranch,
            "productId": productId,
            "lotNumber": lotNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            "initialQuantity": initialQuantity,
            "validFrom": isoFormatter.string(from: clampedValidFrom),
            "expiryDate": isoFormatter.string(from: expiryDate),
            "supplier": supplier.trimmingCharacters(in: .whitespacesAndNewlines),
            "notes": notes.trimmingCharacters(in: .whitespacesAndNewlines),
            "commandId": commandId ?? UUID().uuidString
        ]
        if let costPrice { payload["costPrice"] = costPrice }

        do {
            let result = try await functions.httpsCallable("createInventoryLot").call(["payload": payload])

            guard let dict = result.data as? [String: Any],
                  (dict["ok"] as? Bool == true || (dict["ok"] as? NSNumber)?.boolValue == true),
                  let lotData = dict["lot"] as? [String: Any],
                  let lotId = lotData["lotId"] as? String, !lotId.isEmpty,
                  lotData["branchId"] as? String == resolvedBranch,
                  lotData["productId"] as? String == productId,
                  let receivedQuantity = (lotData["initialQuantity"] as? NSNumber)?.intValue ?? (lotData["initialQuantity"] as? Int),
                  let availableQuantity = (lotData["availableQuantity"] as? NSNumber)?.intValue ?? (lotData["availableQuantity"] as? Int) else {
                throw NSError(domain: "PPInventoryLotService", code: -1, userInfo: [NSLocalizedDescriptionKey: Language.get("Inventory_Lot_Invalid_Response", alter: "استجابة غير صالحة من الخادم")])
            }

            let newLot = PPInventoryLot(
                id: lotId,
                lotId: lotId,
                lotNumber: lotNumber,
                productId: productId,
                branchId: resolvedBranch,
                initialQuantity: receivedQuantity,
                availableQuantity: availableQuantity,
                costPrice: (lotData["costPrice"] as? NSNumber)?.doubleValue,
                validFrom: validFrom,
                expiryDate: expiryDate,
                status: "active",
                supplier: supplier,
                notes: notes,
                createdAt: Date()
            )

            let key = "\(resolvedBranch)/\(productId)"
            var current = lotsByProduct[key] ?? []
            current.removeAll { $0.id == lotId }
            current.insert(newLot, at: 0)
            lotsByProduct[key] = current
            errorMessage = nil

            return newLot
        } catch {
            let msg = PPBranchInventoryErrorHelper.localizedMessage(for: error)
            throw NSError(domain: "PPInventoryLotService", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// Deletes an untouched, unused lot and rolls back its stock.
    public func deleteLot(
        branchId: String,
        productId: String,
        lotId: String,
        notes: String = ""
    ) async throws {
        pendingLoads += 1
        isLoading = true
        defer { pendingLoads -= 1; isLoading = pendingLoads > 0 }

        let payload: [String: Any] = [
            "lotId": lotId,
            "notes": notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        do {
            let result = try await functions.httpsCallable("deleteInventoryLot").call(["payload": payload])
            guard let dict = result.data as? [String: Any],
                  (dict["ok"] as? Bool == true || (dict["ok"] as? NSNumber)?.boolValue == true) else {
                throw NSError(
                    domain: "PPInventoryLotService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: Language.get("Inventory_Lot_Invalid_Response", alter: "استجابة غير صالحة من الخادم")]
                )
            }

            let resolvedBranch = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(resolvedBranch)/\(productId)"
            if var current = lotsByProduct[key] {
                current.removeAll { $0.id == lotId || $0.lotId == lotId }
                lotsByProduct[key] = current
            }
            errorMessage = nil
        } catch {
            let msg = PPBranchInventoryErrorHelper.localizedMessage(for: error)
            throw NSError(domain: "PPInventoryLotService", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// Modifies an existing lot's quantity and/or expiry date.
    public func updateLot(
        branchId: String,
        productId: String,
        lotId: String,
        newQuantity: Int? = nil,
        newExpiryDate: Date? = nil,
        notes: String = ""
    ) async throws -> PPInventoryLot {
        pendingLoads += 1
        isLoading = true
        defer { pendingLoads -= 1; isLoading = pendingLoads > 0 }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var payload: [String: Any] = [
            "lotId": lotId,
            "notes": notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if let newQuantity {
            payload["newQuantity"] = newQuantity
        }
        if let newExpiryDate {
            payload["newExpiryDate"] = isoFormatter.string(from: newExpiryDate)
        }

        do {
            let result = try await functions.httpsCallable("updateInventoryLot").call(["payload": payload])
            guard let dict = result.data as? [String: Any],
                  (dict["ok"] as? Bool == true || (dict["ok"] as? NSNumber)?.boolValue == true),
                  let lotData = dict["lot"] as? [String: Any],
                  let returnedLotId = lotData["lotId"] as? String, !returnedLotId.isEmpty else {
                throw NSError(
                    domain: "PPInventoryLotService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: Language.get("Inventory_Lot_Invalid_Response", alter: "استجابة غير صالحة من الخادم")]
                )
            }

            let initialQty = (lotData["initialQuantity"] as? NSNumber)?.intValue ?? (lotData["initialQuantity"] as? Int) ?? 0
            let availableQty = (lotData["availableQuantity"] as? NSNumber)?.intValue ?? (lotData["availableQuantity"] as? Int) ?? 0
            let reservedQty = (lotData["reservedQuantity"] as? NSNumber)?.intValue ?? (lotData["reservedQuantity"] as? Int) ?? 0
            let onHandQty = (lotData["onHandQuantity"] as? NSNumber)?.intValue ?? (lotData["onHandQuantity"] as? Int)

            var parsedExpDate: Date? = newExpiryDate
            if let expStr = lotData["expiryDate"] as? String {
                parsedExpDate = isoFormatter.date(from: expStr) ?? ISO8601DateFormatter().date(from: expStr) ?? newExpiryDate
            }

            let updatedLot = PPInventoryLot(
                id: returnedLotId,
                lotId: returnedLotId,
                lotNumber: (lotData["lotNumber"] as? String) ?? "",
                productId: productId,
                productName: (lotData["productName"] as? String) ?? "",
                branchId: (lotData["branchId"] as? String) ?? branchId,
                initialQuantity: initialQty,
                availableQuantity: availableQty,
                reservedQuantity: reservedQty,
                onHandQuantity: onHandQty,
                costPrice: (lotData["costPrice"] as? NSNumber)?.doubleValue,
                validFrom: nil,
                expiryDate: parsedExpDate,
                status: (lotData["status"] as? String) ?? "active",
                supplier: (lotData["supplier"] as? String) ?? "",
                notes: (lotData["notes"] as? String) ?? notes
            )

            let resolvedBranch = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(resolvedBranch)/\(productId)"
            var current = lotsByProduct[key] ?? []
            if let idx = current.firstIndex(where: { $0.id == returnedLotId || $0.lotId == returnedLotId }) {
                current[idx] = updatedLot
            } else {
                current.insert(updatedLot, at: 0)
            }
            lotsByProduct[key] = current
            errorMessage = nil

            return updatedLot
        } catch {
            let msg = PPBranchInventoryErrorHelper.localizedMessage(for: error)
            throw NSError(domain: "PPInventoryLotService", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
