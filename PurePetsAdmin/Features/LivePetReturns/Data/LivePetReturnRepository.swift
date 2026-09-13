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
        draftId: String? = nil,
        commandId: String? = nil
    ) async throws -> LivePetReturnCase {
        // The callable is the only write path. Read back the server-authored
        // aggregate so versions/statuses never come from the local draft.
        _ = try await remoteDataSource.persistReturnCase(returnCase, commandId: commandId)

        // 2. Clear any local offline draft once persisted
        if let draftId {
            draftStore.deleteDraft(draftId: draftId)
        } else {
            draftStore.deleteDraftForTransaction(transactionId: returnCase.transactionId)
        }

        return (try? await remoteDataSource.fetchReturnCase(returnCaseId: returnCase.returnCaseId)) ?? returnCase
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
        guard let currentCase = try await remoteDataSource.fetchReturnCase(returnCaseId: returnCaseId),
              let currentUnit = currentCase.units.first(where: { $0.unitId == unitId }) else {
            throw NSError(domain: "LivePetReturn", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "The return case or exact unit is no longer available."
            ])
        }

        _ = actorId
        _ = actorName
        _ = branchId
        let commandId = "inspect-\(returnCaseId)-\(unitId)-\(UUID().uuidString)"
        _ = try await remoteDataSource.recordInspectionProgress(
            returnCaseId: returnCaseId,
            unitId: unitId,
            expectedCaseVersion: currentCase.version,
            expectedUnitVersion: currentUnit.inventoryVersion,
            newCondition: newCondition.rawValue,
            newHealthDisposition: newHealthDisposition.rawValue,
            newCommercialDisposition: newCommercialDisposition.rawValue,
            notes: notes ?? "Updated inspection: \(newCondition.localizedTitle)",
            commandId: commandId
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
        guard let currentCase = try await remoteDataSource.fetchReturnCase(returnCaseId: returnCaseId),
              let currentUnit = currentCase.units.first(where: { $0.unitId == unitId }) else {
            throw NSError(domain: "LivePetReturn", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "The return case or exact unit is no longer available."
            ])
        }

        _ = productId
        _ = actorId
        _ = actorName
        _ = branchId
        let commandId = "clear-\(returnCaseId)-\(unitId)-\(UUID().uuidString)"
        _ = try await remoteDataSource.clearLivePetForResale(
            returnCaseId: returnCaseId,
            unitId: unitId,
            expectedCaseVersion: currentCase.version,
            expectedUnitVersion: currentUnit.inventoryVersion,
            notes: notes ?? "Animal explicitly cleared for resale after veterinarian inspection.",
            commandId: commandId
        )
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
