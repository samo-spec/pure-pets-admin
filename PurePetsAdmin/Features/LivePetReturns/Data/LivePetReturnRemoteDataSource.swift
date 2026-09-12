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
            let alreadyReturned: Bool
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

            var priceByUnitId: [String: Double] = [:]
            for entry in unitPricesRaw {
                if let uId = entry["unitId"] as? String, let uPrice = entry["unitPrice"] as? Double {
                    priceByUnitId[uId] = uPrice
                }
            }

            for (idx, uId) in unitIds.enumerated() {
                let ringTag = idx < unitRingTags.count ? unitRingTags[idx] : uId
                let unitPrice = priceByUnitId[uId] ?? baseItemPrice
                let unitPriceMinor = Int64(round(unitPrice * 100.0))

                let allocatedDiscountMinor: Int64
                if transactionSubtotal > 0 && transactionDiscount > 0 {
                    let proportion = unitPrice / transactionSubtotal
                    allocatedDiscountMinor = Int64(round(proportion * transactionDiscount * 100.0))
                } else {
                    allocatedDiscountMinor = 0
                }

                let existingCaseInfo = returnedUnitIdsWithCase[uId]
                let alreadyReturned = refundedUnitIds.contains(uId) || existingCaseInfo != nil

                pendingLookups.append(UnitPendingLookup(
                    unitId: uId,
                    productId: productId,
                    productName: productName,
                    ringTag: ringTag,
                    unitPriceMinor: unitPriceMinor,
                    allocatedDiscountMinor: allocatedDiscountMinor,
                    alreadyReturned: alreadyReturned,
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
                        return (lookup.unitId, UnitMetadata(species: species, breed: breed, sex: sex, status: status))
                    } else {
                        return (lookup.unitId, UnitMetadata(species: nil, breed: nil, sex: nil, status: nil))
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
            let isPhysicallySold = (meta?.status?.uppercased() == "SOLD")
            // A unit is only considered truly returned if it has an existing return case OR its status is no longer SOLD.
            // If it is still SOLD in inventory, physical intake is required even if a financial refund was recorded.
            let unitAlreadyReturned = isPhysicallySold ? false : lookup.alreadyReturned
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
                currency: (data["currency"] as? String) ?? "QAR",
                conditionAtReturn: .appearsNormal,
                inspectionStatus: .inspectionRequired,
                disposition: .hold,
                previousLifecycleStatus: .sold,
                resultingLifecycleStatus: .returnRequested,
                isAlreadyReturned: unitAlreadyReturned,
                activeReturnCaseId: lookup.existingCaseId,
                activeReturnCaseNumber: lookup.existingCaseNumber
            )
            resultUnits.append(returnUnit)
        }

        return resultUnits
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

    // MARK: - Save Return Case & Events (Server-Authoritative with Local Fallback)

    public func persistReturnCase(_ returnCase: LivePetReturnCase) async throws {
        // 1. First attempt authoritative server callable
        let callable = functions.httpsCallable("createLivePetReturn")
        var requestPayload: [String: Any] = returnCase.toDictionary()
        requestPayload["units"] = returnCase.units.map { $0.toDictionary() }
        requestPayload["events"] = returnCase.events.map { $0.toDictionary() }

        do {
            let result = try await callable.call(requestPayload)
            if let data = result.data as? [String: Any], (data["ok"] as? Bool) == true {
                return
            }
        } catch {
            NSLog("[LivePetReturnRemoteDataSource] createLivePetReturn callable failed, falling back to direct batch write: %@", error.localizedDescription)
        }

        // 2. Fallback to direct batch write (permitted by firestore.rules for authorized staff)
        let caseRef = db.collection("returnCases").document(returnCase.returnCaseId)
        let batch = db.batch()
        batch.setData(returnCase.toDictionary(), forDocument: caseRef, merge: true)

        // Write units to return case subcollection.
        for unit in returnCase.units {
            let unitRef = caseRef.collection("units").document(unit.unitId)
            batch.setData(unit.toDictionary(), forDocument: unitRef, merge: true)
        }

        // Write initial events
        for event in returnCase.events {
            let eventRef = caseRef.collection("events").document(event.eventId)
            batch.setData(event.toDictionary(), forDocument: eventRef, merge: true)
        }

        try await batch.commit()
    }

    // MARK: - Server Authoritative Live Animal Return Acceptance

    public func acceptLiveAnimalReturn(
        productId: String,
        unitId: String,
        ringTag: String,
        transactionId: String,
        refundId: String,
        reason: String,
        notes: String?,
        commandId: String,
        returnCaseId: String? = nil
    ) async throws -> [String: Any] {
        let callable = functions.httpsCallable("validateInventoryChange")
        var payloadDict: [String: Any] = [
            "transactionId": transactionId,
            "refundId": refundId,
            "unitId": unitId,
            "ringTag": ringTag,
            "reason": reason,
            "notes": notes ?? ""
        ]
        if let returnCaseId {
            payloadDict["returnCaseId"] = returnCaseId
        }
        let requestData: [String: Any] = [
            "action": "accept_live_animal_return",
            "productId": productId,
            "commandId": commandId,
            "payload": payloadDict
        ]

        let result = try await callable.call(requestData)
        guard let data = result.data as? [String: Any],
              (data["ok"] as? Bool) == true else {
            throw NSError(
                domain: "LivePetReturn",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to accept live animal return via server."]
            )
        }
        return data
    }

    // MARK: - Server Authoritative Live Animal Quarantine Release

    public func releaseLiveAnimalQuarantine(
        productId: String,
        unitId: String,
        reason: String,
        commandId: String,
        returnCaseId: String? = nil
    ) async throws -> [String: Any] {
        let callable = functions.httpsCallable("validateInventoryChange")
        var payloadDict: [String: Any] = [
            "unitId": unitId,
            "reason": reason
        ]
        if let returnCaseId {
            payloadDict["returnCaseId"] = returnCaseId
        }
        let requestData: [String: Any] = [
            "action": "release_quarantine",
            "productId": productId,
            "commandId": commandId,
            "payload": payloadDict
        ]

        let result = try await callable.call(requestData)
        guard let data = result.data as? [String: Any],
              (data["ok"] as? Bool) == true else {
            throw NSError(
                domain: "LivePetReturn",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to release animal from quarantine via server."]
            )
        }
        return data
    }

    public func updateUnitInspection(
        returnCaseId: String,
        unitId: String,
        newCondition: String,
        newHealthDisposition: String,
        newCommercialDisposition: String,
        actorId: String
    ) async throws {
        let unitRef = db.collection("returnCases").document(returnCaseId).collection("units").document(unitId)
        try await unitRef.setData([
            "conditionAtReturn": newCondition,
            "inspectionStatus": newHealthDisposition,
            "disposition": newCommercialDisposition,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": actorId
        ], merge: true)
    }

    public func recordInspectionProgress(
        returnCaseId: String,
        unitId: String,
        newCondition: String,
        newHealthDisposition: String,
        newCommercialDisposition: String,
        actorId: String,
        event: LivePetReturnEvent
    ) async throws {
        // 1. Attempt authoritative server callable
        let callable = functions.httpsCallable("recordLivePetInspection")
        let requestPayload: [String: Any] = [
            "returnCaseId": returnCaseId,
            "unitId": unitId,
            "newCondition": newCondition,
            "newHealthDisposition": newHealthDisposition,
            "newCommercialDisposition": newCommercialDisposition,
            "actorId": actorId,
            "event": event.toDictionary()
        ]

        do {
            let result = try await callable.call(requestPayload)
            if let data = result.data as? [String: Any], (data["ok"] as? Bool) == true {
                return
            }
        } catch {
            NSLog("[LivePetReturnRemoteDataSource] recordLivePetInspection callable failed, falling back to direct batch write: %@", error.localizedDescription)
        }

        // 2. Fallback to direct batch write (permitted by firestore.rules for authorized staff)
        let batch = db.batch()
        let unitRef = db.collection("returnCases").document(returnCaseId).collection("units").document(unitId)
        batch.setData([
            "conditionAtReturn": newCondition,
            "inspectionStatus": newHealthDisposition,
            "disposition": newCommercialDisposition,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": actorId
        ], forDocument: unitRef, merge: true)

        guard event.returnCaseId == returnCaseId else {
            throw NSError(domain: "LivePetReturn", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Event case id does not match the target return case."
            ])
        }
        let eventRef = db.collection("returnCases").document(returnCaseId).collection("events").document(event.eventId)
        batch.setData(event.toDictionary(), forDocument: eventRef, merge: true)

        try await batch.commit()
    }

    // MARK: - Append Event to Case Timeline

    public func appendEvent(_ event: LivePetReturnEvent) async throws {
        let caseRef = db.collection("returnCases").document(event.returnCaseId)
        let eventRef = caseRef.collection("events").document(event.eventId)
        try await eventRef.setData(event.toDictionary(), merge: true)
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
