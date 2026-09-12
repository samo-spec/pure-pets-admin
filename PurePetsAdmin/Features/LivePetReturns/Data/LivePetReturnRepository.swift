//
//  LivePetReturnRepository.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Unified repository coordinating remote Firestore, callable endpoints, and local draft store.
//

import Foundation
import FirebaseFirestore

public final class LivePetReturnRepository: @unchecked Sendable {
    public static let shared = LivePetReturnRepository()

    private let remoteDataSource = LivePetReturnRemoteDataSource.shared
    private let draftStore = LivePetReturnDraftStore.shared

    private init() {}

    // MARK: - Fetch Units for Transaction

    public func fetchReturnUnits(for transactionId: String) async throws -> [LivePetReturnUnit] {
        try await remoteDataSource.fetchSoldLivePetUnits(transactionId: transactionId)
    }

    // MARK: - Fetch Return Cases for Transaction

    public func fetchReturnCases(for transactionId: String) async throws -> [LivePetReturnCase] {
        try await remoteDataSource.fetchExistingReturnCases(transactionId: transactionId)
    }

    // MARK: - Submit Return

    public func submitLivePetReturn(
        returnCase: LivePetReturnCase,
        draftId: String? = nil
    ) async throws -> LivePetReturnCase {
        // 1. Persist the return case aggregate in Firestore
        try await remoteDataSource.persistReturnCase(returnCase)

        // 2. Clear any local offline draft once persisted
        if let draftId {
            draftStore.deleteDraft(draftId: draftId)
        } else {
            draftStore.deleteDraftForTransaction(transactionId: returnCase.transactionId)
        }

        return returnCase
    }

    // MARK: - Inspection & Custody Updates

    public func updateReturnCaseInspection(
        returnCaseId: String,
        unitId: String,
        newCondition: ReturnPhysicalCondition,
        newHealthDisposition: HealthDisposition,
        newCommercialDisposition: CommercialDisposition,
        actorId: String,
        actorName: String?,
        branchId: String,
        notes: String?
    ) async throws {
        let event = LivePetReturnEvent(
            eventId: "evt-\(UUID().uuidString)",
            eventType: .inspectionUpdated,
            returnCaseId: returnCaseId,
            unitId: unitId,
            actorId: actorId,
            actorName: actorName,
            branchId: branchId,
            notes: notes ?? "Updated inspection: \(newCondition.localizedTitle)"
        )

        try await remoteDataSource.recordInspectionProgress(
            returnCaseId: returnCaseId,
            unitId: unitId,
            newCondition: newCondition.rawValue,
            newHealthDisposition: newHealthDisposition.rawValue,
            newCommercialDisposition: newCommercialDisposition.rawValue,
            actorId: actorId,
            event: event
        )
    }

    // MARK: - Explicit Clearance for Resale

    public func clearLivePetForResale(
        returnCaseId: String,
        unitId: String,
        productId: String,
        actorId: String,
        actorName: String?,
        branchId: String,
        notes: String?
    ) async throws {
        let db = Firestore.firestore()
        let caseUnitRef = db.collection("returnCases").document(returnCaseId).collection("units").document(unitId)

        let event = LivePetReturnEvent(
            eventId: "evt-\(UUID().uuidString)",
            eventType: .inspectionCleared,
            returnCaseId: returnCaseId,
            unitId: unitId,
            actorId: actorId,
            actorName: actorName,
            branchId: branchId,
            notes: notes ?? "Animal explicitly cleared for resale after veterinarian inspection."
        )
        let eventRef = db.collection("returnCases").document(returnCaseId).collection("events").document(event.eventId)

        // 1. Authoritatively release quarantine via server function validateInventoryChange
        let commandId = "cmd_release_quarantine_\(unitId)_\(UUID().uuidString.prefix(8))"
        _ = try await remoteDataSource.releaseLiveAnimalQuarantine(
            productId: productId,
            unitId: unitId,
            reason: notes ?? "Animal explicitly cleared for resale after veterinarian inspection.",
            commandId: commandId,
            returnCaseId: returnCaseId
        )

        // 2. Update return case unit and record clearance audit event
        let batch = db.batch()
        batch.setData([
            "resultingLifecycleStatus": "cleared",
            "disposition": "eligible_resale",
            "inspectionStatus": "cleared",
            "clearedAt": FieldValue.serverTimestamp(),
            "clearedBy": actorId
        ], forDocument: caseUnitRef, merge: true)

        batch.setData(event.toDictionary(), forDocument: eventRef, merge: true)
        try await batch.commit()
    }

    // MARK: - Single Case Fetch & Real-time Listen

    public func fetchReturnCase(returnCaseId: String) async throws -> LivePetReturnCase? {
        try await remoteDataSource.fetchReturnCase(returnCaseId: returnCaseId)
    }

    public func listenToReturnCase(
        returnCaseId: String,
        onChange: @escaping @Sendable (LivePetReturnCase?) -> Void
    ) -> ListenerRegistration {
        remoteDataSource.listenToReturnCase(returnCaseId: returnCaseId, onChange: onChange)
    }
}
