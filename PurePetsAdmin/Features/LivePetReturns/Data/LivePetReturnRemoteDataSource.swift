//
//  LivePetReturnRemoteDataSource.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Server-authoritative remote data source interfacing with Firestore and Firebase Functions.
//

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

public final class LivePetReturnRemoteDataSource: @unchecked Sendable {
    public static let shared = LivePetReturnRemoteDataSource()

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private init() {}

    private func call(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        let result = try await functions.httpsCallable(name).call(payload)
        guard let data = result.data as? [String: Any], data["ok"] as? Bool == true else {
            throw NSError(
                domain: "LivePetReturn",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "The server did not acknowledge the live-pet return command."]
            )
        }
        return data
    }

    // MARK: - Fetch Sold Live Pet Units from Transaction

    public func fetchSoldLivePetUnits(transactionId: String) async throws -> [LivePetReturnUnit] {
        let trimmedId = transactionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            throw NSError(domain: "LivePetReturn", code: 400, userInfo: [NSLocalizedDescriptionKey: "Transaction ID is required."])
        }

        let docRef = db.collection("transactions").document(trimmedId)
        let snapshot = try await docRef.getDocument()
        guard snapshot.exists, let data = snapshot.data() else {
            throw NSError(domain: "LivePetReturn", code: 404, userInfo: [NSLocalizedDescriptionKey: "Transaction \(trimmedId) not found."])
        }

        let rawItems = (data["items"] as? [[String: Any]]) ?? []
        let transactionDiscount = (data["discount"] as? Double) ?? 0.0
        let transactionSubtotal = (data["subtotal"] as? Double) ?? 0.0
        let isConvertedProforma = !((data["proformaInvoiceId"] as? String) ?? "").isEmpty

        // Also check if any existing return cases exist for this transaction to mark already-returned units
        let existingCases = try await fetchExistingReturnCases(transactionId: trimmedId)
        var returnedUnitIdsWithCase: [String: (caseId: String, caseNumber: String)] = [:]
        for rCase in existingCases {
            for unit in rCase.units {
                returnedUnitIdsWithCase[unit.unitId] = (rCase.returnCaseId, rCase.caseNumber)
            }
        }

        // Collect all target units and their lookups to fetch concurrently
        struct UnitPendingLookup {
            let unitId: String
            let productId: String
            let productName: String
            let ringTag: String
            let unitPriceMinor: Int64
            let allocatedDiscountMinor: Int64
            let netPaidMinor: Int64
            let alreadyReturned: Bool
            let isFinanciallyRefunded: Bool
            let existingCaseId: String?
            let existingCaseNumber: String?
        }

        var pendingLookups: [UnitPendingLookup] = []

        for rawItem in rawItems {
            let productId = (rawItem["productId"] as? String) ?? (rawItem["itemId"] as? String) ?? ""
            let invMode = (rawItem["inventoryMode"] as? String) ?? ""
            let unitIds = (rawItem["unitIds"] as? [String]) ?? []
            let unitRingTags = (rawItem["unitRingTags"] as? [String]) ?? []
            let unitPricesRaw = (rawItem["unitPrices"] as? [[String: Any]]) ?? []
            let refundedUnitIds = (rawItem["refundedUnitIds"] as? [String]) ?? []

            let isLivePet = invMode.uppercased() == "INDIVIDUAL_TRACKED" || !unitIds.isEmpty
            guard isLivePet, !productId.isEmpty else { continue }

            let productName = (rawItem["name"] as? String) ?? ""
            let baseItemPrice = (rawItem["unitPrice"] as? Double) ?? (rawItem["price"] as? Double) ?? 0.0
            let capturedAllocations = isConvertedProforma
                ? try Self.capturedProformaUnitAllocations(rawItem, unitIds: unitIds)
                : [:]

            var priceByUnitId: [String: Double] = [:]
            for entry in unitPricesRaw {
                if let uId = entry["unitId"] as? String, let uPrice = entry["unitPrice"] as? Double {
                    priceByUnitId[uId] = uPrice
                }
            }

            for (idx, uId) in unitIds.enumerated() {
                let ringTag = idx < unitRingTags.count ? unitRingTags[idx] : uId
                let unitPrice = priceByUnitId[uId] ?? baseItemPrice
                let captured = capturedAllocations[uId]
                let unitPriceMinor = captured?.grossMinor ?? Int64(round(unitPrice * 100.0))

                let allocatedDiscountMinor: Int64
                if let captured {
                    allocatedDiscountMinor = captured.discountMinor
                } else if transactionSubtotal > 0 && transactionDiscount > 0 {
                    let proportion = unitPrice / transactionSubtotal
                    allocatedDiscountMinor = Int64(round(proportion * transactionDiscount * 100.0))
                } else {
                    allocatedDiscountMinor = 0
                }

                let existingCaseInfo = returnedUnitIdsWithCase[uId]
                let alreadyReturned = existingCaseInfo != nil
                let isFinanciallyRefunded = refundedUnitIds.contains(uId)

                pendingLookups.append(UnitPendingLookup(
                    unitId: uId,
                    productId: productId,
                    productName: productName,
                    ringTag: ringTag,
                    unitPriceMinor: unitPriceMinor,
                    allocatedDiscountMinor: allocatedDiscountMinor,
                    netPaidMinor: captured?.paidMinor ?? max(0, unitPriceMinor - allocatedDiscountMinor),
                    alreadyReturned: alreadyReturned,
                    isFinanciallyRefunded: isFinanciallyRefunded,
                    existingCaseId: existingCaseInfo?.caseId,
                    existingCaseNumber: existingCaseInfo?.caseNumber
                ))
            }
        }

        // Fetch unit metadata concurrently
        struct UnitMetadata {
            let species: String?
            let breed: String?
            let sex: String?
            let status: String?
            let saleTransactionId: String?
            let version: Int
            /// Raw inventory-unit reads are intentionally denied to POS-only
            /// staff because the document contains purchase cost and private
            /// intake/medical fields. Keep that denial distinguishable from a
            /// successful read of a unit that is no longer sold.
            let readSucceeded: Bool
        }

        let metadataByUnitId: [String: UnitMetadata] = try await withThrowingTaskGroup(of: (String, UnitMetadata).self) { group in
            for lookup in pendingLookups {
                group.addTask {
                    let unitRef = self.db.collection("petAccessories").document(lookup.productId).collection("inventoryUnits").document(lookup.unitId)
                    if let unitSnap = try? await unitRef.getDocument(), unitSnap.exists, let uData = unitSnap.data() {
                        let species = (uData["subSubKindNameAr"] as? String) ?? (uData["subSubKindNameEn"] as? String) ?? (uData["species"] as? String)
                        let breed = (uData["subSubKindItemNameAr"] as? String) ?? (uData["subSubKindItemNameEn"] as? String) ?? (uData["breed"] as? String)
                        let sex = uData["sex"] as? String
                        let status = (uData["status"] as? String) ?? ""
                        let saleTransactionId = uData["saleTransactionId"] as? String
                        let version = (uData["version"] as? Int) ?? 1
                        return (lookup.unitId, UnitMetadata(species: species, breed: breed, sex: sex, status: status, saleTransactionId: saleTransactionId, version: version, readSucceeded: true))
                    } else {
                        return (lookup.unitId, UnitMetadata(species: nil, breed: nil, sex: nil, status: nil, saleTransactionId: nil, version: 1, readSucceeded: false))
                    }
                }
            }

            var results: [String: UnitMetadata] = [:]
            for try await (uId, meta) in group {
                results[uId] = meta
            }
            return results
        }

        var resultUnits: [LivePetReturnUnit] = []
        for lookup in pendingLookups {
            let meta = metadataByUnitId[lookup.unitId]
            // A denied raw-unit read is not evidence that custody changed. The
            // canonical create/receive callables re-check SOLD, sale binding,
            // active return state, and the expected version transactionally.
            // Only a successful read may mark a unit unavailable here.
            let isStillOriginalSale = meta?.readSucceeded != true ||
                ((meta?.status?.uppercased() == "SOLD") && meta?.saleTransactionId == trimmedId)
            // Financial reversal never proves physical receipt. Only canonical custody/state does.
            let unitAlreadyReturned = lookup.alreadyReturned || !isStillOriginalSale
            let netPaidMinor = lookup.netPaidMinor
            let returnUnit = LivePetReturnUnit(
                unitId: lookup.unitId,
                productId: lookup.productId,
                productName: lookup.productName,
                ringTag: lookup.ringTag,
                speciesName: meta?.species,
                breedName: meta?.breed,
                sex: meta?.sex,
                originalSaleTransactionId: trimmedId,
                originalSalePriceMinor: lookup.unitPriceMinor,
                allocatedDiscountMinor: lookup.allocatedDiscountMinor,
                netPaidMinor: netPaidMinor,
                refundableRemainingMinor: lookup.isFinanciallyRefunded ? 0 : netPaidMinor,
                refundAmountMinor: lookup.isFinanciallyRefunded ? 0 : netPaidMinor,
                currency: (data["currency"] as? String) ?? "QAR",
                conditionAtReturn: .appearsNormal,
                inspectionStatus: .inspectionRequired,
                disposition: .hold,
                previousLifecycleStatus: .sold,
                resultingLifecycleStatus: .returnRequested,
                inventoryVersion: meta?.version ?? 1,
                isAlreadyReturned: unitAlreadyReturned,
                activeReturnCaseId: lookup.existingCaseId,
                activeReturnCaseNumber: lookup.existingCaseNumber
            )
            resultUnits.append(returnUnit)
        }

        return resultUnits
    }

    // MARK: - Captured Proforma Exact-Unit Refund Projection

    private struct CapturedUnitAllocation {
        let grossMinor: Int64
        let discountMinor: Int64
        let paidMinor: Int64
    }

    /// Mirrors Infra proformaCalculations.refundAllocation. Net and tax are
    /// allocated independently; stable unit-ID order owns remainder cents.
    /// These preview values never replace the callable's financial authority.
    private static func capturedProformaUnitAllocations(
        _ item: [String: Any], unitIds: [String]
    ) throws -> [String: CapturedUnitAllocation] {
        let rawPrices = (item["unitPrices"] as? [[String: Any]]) ?? []
        guard !unitIds.isEmpty, Set(unitIds).count == unitIds.count, rawPrices.count == unitIds.count else {
            throw capturedAllocationError()
        }
        var prices: [(id: String, minor: Int64)] = []
        for raw in rawPrices {
            guard let id = raw["unitId"] as? String, unitIds.contains(id),
                  let price = capturedMinor(raw["unitPrice"], scale: 2) else {
                throw capturedAllocationError()
            }
            prices.append((id, price))
        }
        // Infra validates these IDs as ASCII and uses code-unit lexical order.
        prices.sort { $0.id < $1.id }
        guard Set(prices.map { $0.id }).count == unitIds.count,
              let gross = capturedMinor(item["lineSubtotalMinor"]),
              let taxable = capturedMinor(item["taxableMinor"]),
              let tax = capturedMinor(item["taxMinor"]),
              let total = capturedMinor(item["totalMinor"]),
              prices.reduce(Decimal.zero, { $0 + Decimal($1.minor) }) == Decimal(gross),
              taxable <= gross, taxable + tax == total else {
            throw capturedAllocationError()
        }
        let weights = prices.map { $0.minor }
        let nets = try capturedShares(taxable, weights: weights)
        let taxes = try capturedShares(tax, weights: weights)
        return Dictionary(uniqueKeysWithValues: prices.indices.map { index in
            (prices[index].id, CapturedUnitAllocation(
                grossMinor: prices[index].minor,
                discountMinor: prices[index].minor - nets[index],
                paidMinor: nets[index] + taxes[index]
            ))
        })
    }

    /// Decimal intermediates avoid Int64 multiplication overflow and binary
    /// price rounding. Captured amounts fit Infra's 99,999,999,999 minor limit.
    private static func capturedMinor(_ raw: Any?, scale: Int = 0) -> Int64? {
        let text: String
        if let value = raw as? NSNumber { text = value.stringValue }
        else if let value = raw as? String { text = value }
        else { return nil }
        guard let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return nil }
        var scaled = amount * (scale == 2 ? Decimal(100) : Decimal(1))
        var integral = Decimal.zero
        NSDecimalRound(&integral, &scaled, 0, .down)
        guard scaled == integral, integral >= 0, integral <= Decimal(99_999_999_999 as Int64) else { return nil }
        return NSDecimalNumber(decimal: integral).int64Value
    }

    private static func capturedShares(_ amount: Int64, weights: [Int64]) throws -> [Int64] {
        let total = weights.reduce(Decimal.zero) { $0 + Decimal($1) }
        guard total > 0 else {
            guard amount == 0 else { throw capturedAllocationError() }
            return weights.map { _ in 0 }
        }
        var shares: [Int64] = []
        var remainders: [Decimal] = []
        for weight in weights {
            let numerator = Decimal(amount) * Decimal(weight)
            var quotient = numerator / total
            var integral = Decimal.zero
            NSDecimalRound(&integral, &quotient, 0, .down)
            shares.append(NSDecimalNumber(decimal: integral).int64Value)
            remainders.append(numerator - integral * total)
        }
        let missing = amount - shares.reduce(0, +)
        guard missing >= 0, missing <= Int64(weights.count) else { throw capturedAllocationError() }
        let ranked = weights.indices.sorted {
            remainders[$0] == remainders[$1] ? $0 < $1 : remainders[$0] > remainders[$1]
        }
        for index in ranked.prefix(Int(missing)) { shares[index] += 1 }
        return shares
    }

    private static func capturedAllocationError() -> NSError {
        NSError(domain: "LivePetReturn", code: 422, userInfo: [
            NSLocalizedDescriptionKey: Language.get("Proforma_ReturnAllocationUnavailable", alter: nil)
        ])
    }

    // MARK: - Existing Return Cases for Transaction

    public func fetchExistingReturnCases(transactionId: String) async throws -> [LivePetReturnCase] {
        let trimmedId = transactionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return [] }

        let query = db.collection("returnCases").whereField("transactionId", isEqualTo: trimmedId)
        let snapshot = try await query.getDocuments()

        return try await withThrowingTaskGroup(of: LivePetReturnCase?.self) { group in
            for doc in snapshot.documents {
                group.addTask {
                    let unitsSnap = try await self.db.collection("returnCases").document(doc.documentID).collection("units").getDocuments()
                    let units = unitsSnap.documents.compactMap { uDoc in
                        LivePetReturnUnit.fromDictionary(uDoc.data())
                    }
                    return LivePetReturnCase.fromDictionary(doc.data(), returnCaseId: doc.documentID, units: units)
                }
            }
            var cases: [LivePetReturnCase] = []
            for try await rCase in group {
                if let rCase {
                    cases.append(rCase)
                }
            }
            return cases
        }
    }

    // MARK: - Return command callables

    /// Creates the server-owned return aggregate. Only immutable sale identity,
    /// expected inventory versions, and the requested financial amount cross the
    /// client/server boundary; case fields and events are authored by Infra.
    @discardableResult
    public func persistReturnCase(_ returnCase: LivePetReturnCase, commandId: String? = nil) async throws -> [String: Any] {
        let resolvedCommandId = commandId
            ?? returnCase.events.compactMap(\.commandId).first
            ?? "cmd-\(returnCase.returnCaseId)"
        let requestPayload: [String: Any] = [
            "commandId": resolvedCommandId,
            "transactionId": returnCase.transactionId,
            "returnCaseId": returnCase.returnCaseId,
            "receivingBranchId": returnCase.receivingBranchId,
            "reasonCode": returnCase.reasonCode,
            "reasonNotes": returnCase.reasonNotes,
            "financialResolution": returnCase.financialResolution.rawValue,
            "units": returnCase.units.map { unit in
                [
                    "unitId": unit.unitId,
                    "expectedVersion": unit.inventoryVersion,
                    "refundAmountMinor": unit.refundAmountMinor,
                    "conditionAtReturn": unit.conditionAtReturn.rawValue
                ]
            }
        ]
        return try await call("createLivePetReturn", payload: requestPayload)
    }

    @discardableResult
    public func receiveLivePetReturn(
        returnCaseId: String,
        unitId: String,
        expectedCaseVersion: Int,
        expectedUnitVersion: Int,
        conditionAtReturn: String,
        notes: String?,
        commandId: String
    ) async throws -> [String: Any] {
        try await call("receiveLivePetReturn", payload: [
            "commandId": commandId,
            "returnCaseId": returnCaseId,
            "unitId": unitId,
            "expectedCaseVersion": expectedCaseVersion,
            "expectedUnitVersion": expectedUnitVersion,
            "conditionAtReturn": conditionAtReturn,
            "notes": notes ?? ""
        ])
    }

    @discardableResult
    public func requestReturnRefund(
        returnCaseId: String,
        expectedCaseVersion: Int,
        refundItems: [[String: Any]],
        refundAmount: Double,
        reason: String,
        currency: String,
        refundMode: String,
        refundAdjustmentReason: String?,
        commandId: String
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "commandId": commandId,
            "returnCaseId": returnCaseId,
            "expectedCaseVersion": expectedCaseVersion,
            "refundItems": refundItems,
            "refundAmount": refundAmount,
            "reason": reason,
            "currency": currency,
            "refundMode": refundMode
        ]
        if let refundAdjustmentReason, !refundAdjustmentReason.isEmpty {
            payload["refundAdjustmentReason"] = refundAdjustmentReason
        }
        return try await call("requestReturnRefund", payload: payload)
    }

    public func recordInspectionProgress(
        returnCaseId: String,
        unitId: String,
        expectedCaseVersion: Int,
        expectedUnitVersion: Int,
        newCondition: String,
        newHealthDisposition: String,
        newCommercialDisposition: String,
        notes: String?,
        commandId: String
    ) async throws -> [String: Any] {
        let requestPayload: [String: Any] = [
            "commandId": commandId,
            "returnCaseId": returnCaseId,
            "unitId": unitId,
            "expectedCaseVersion": expectedCaseVersion,
            "expectedUnitVersion": expectedUnitVersion,
            "newCondition": newCondition,
            "newHealthDisposition": newHealthDisposition,
            "newCommercialDisposition": newCommercialDisposition,
            "notes": notes ?? ""
        ]
        return try await call("recordLivePetInspection", payload: requestPayload)
    }

    @discardableResult
    public func clearLivePetForResale(
        returnCaseId: String,
        unitId: String,
        expectedCaseVersion: Int,
        expectedUnitVersion: Int,
        notes: String?,
        commandId: String
    ) async throws -> [String: Any] {
        try await call("clearLivePetForResale", payload: [
            "commandId": commandId,
            "returnCaseId": returnCaseId,
            "unitId": unitId,
            "expectedCaseVersion": expectedCaseVersion,
            "expectedUnitVersion": expectedUnitVersion,
            "notes": notes ?? ""
        ])
    }

    // MARK: - Fetch Single Return Case with Units & Events

    public func fetchReturnCase(returnCaseId: String) async throws -> LivePetReturnCase? {
        let caseRef = db.collection("returnCases").document(returnCaseId)
        let snap = try await caseRef.getDocument()
        guard snap.exists, let data = snap.data() else { return nil }

        // Fetch units
        let unitsSnap = try await caseRef.collection("units").getDocuments()
        var units: [LivePetReturnUnit] = []
        for uDoc in unitsSnap.documents {
            if let unit = LivePetReturnUnit.fromDictionary(uDoc.data()) {
                units.append(unit)
            }
        }

        // Fetch events ordered by time
        let eventsSnap = try await caseRef.collection("events").order(by: "occurredAt", descending: false).getDocuments()
        var events: [LivePetReturnEvent] = []
        for eDoc in eventsSnap.documents {
            if let evt = LivePetReturnEvent.fromDictionary(eDoc.data(), eventId: eDoc.documentID) {
                events.append(evt)
            }
        }

        return LivePetReturnCase.fromDictionary(data, returnCaseId: returnCaseId, units: units, events: events)
    }

    // MARK: - Real-time Listener for Return Case Dossier

    public func listenToReturnCase(
        returnCaseId: String,
        onChange: @escaping @Sendable (LivePetReturnCase?) -> Void
    ) -> ListenerRegistration {
        let caseRef = db.collection("returnCases").document(returnCaseId)
        return caseRef.addSnapshotListener { [weak self] snapshot, error in
            if let error {
                NSLog("[LivePetReturnRemoteDataSource] Snapshot listener error: %@", error.localizedDescription)
                return
            }

            guard let self, let snapshot else { return }

            Task { @MainActor in
                if !snapshot.exists {
                    onChange(nil)
                    return
                }

                guard let data = snapshot.data() else { return }

                do {
                    let fullCase = try await self.fetchReturnCase(returnCaseId: returnCaseId)
                    onChange(fullCase)
                } catch {
                    let baseCase = LivePetReturnCase.fromDictionary(data, returnCaseId: returnCaseId)
                    onChange(baseCase)
                }
            }
        }
    }

    // MARK: - Fetch Latest Refund ID for Transaction

    public func fetchLatestRefundId(for transactionId: String) async -> String? {
        let trimmedId = transactionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return nil }

        // 1. Check parent transaction document for refunds array
        if let snap = try? await db.collection("transactions").document(trimmedId).getDocument(),
           let data = snap.data() {
            if let refunds = data["refunds"] as? [[String: Any]],
               let last = refunds.last,
               let rId = (last["id"] as? String) ?? (last["commandId"] as? String),
               !rId.isEmpty {
                return rId
            }
        }

        // 2. Check refunds subcollection
        if let querySnap = try? await db.collection("transactions").document(trimmedId).collection("refunds")
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments(),
           let doc = querySnap.documents.first {
            return doc.documentID
        }

        return nil
    }
}
