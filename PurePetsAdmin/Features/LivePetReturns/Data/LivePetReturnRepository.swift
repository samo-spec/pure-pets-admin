//
//  LivePetReturnRepository.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Unified repository coordinating remote Firestore, callable endpoints, and local draft store.
//

import Foundation
import CryptoKit
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
        _ = productId
        _ = actorId
        _ = actorName
        _ = branchId
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedNotes = trimmedNotes.isEmpty
            ? "Animal explicitly cleared for resale after veterinarian inspection."
            : trimmedNotes

        // A returned animal has two authoritative server transitions:
        // inspection clearance (still non-sellable), then stock release. Keep
        // both audited callables and reconcile after every response so a lost
        // network acknowledgement cannot cause a duplicate or false failure.
        for attempt in 0..<5 {
            let (currentCase, currentUnit) = try await authoritativeUnit(
                returnCaseId: returnCaseId,
                unitId: unitId
            )

            switch currentUnit.resultingLifecycleStatus {
            case .available:
                return

            case .underInspection, .quarantined:
                let commandId = stableCommandId(
                    action: "inspect-clear",
                    returnCaseId: returnCaseId,
                    unitId: unitId,
                    caseVersion: currentCase.version,
                    unitVersion: currentUnit.inventoryVersion,
                    notes: resolvedNotes
                )
                do {
                    _ = try await remoteDataSource.recordInspectionProgress(
                        returnCaseId: returnCaseId,
                        unitId: unitId,
                        expectedCaseVersion: currentCase.version,
                        expectedUnitVersion: currentUnit.inventoryVersion,
                        newCondition: currentUnit.conditionAtReturn.rawValue,
                        newHealthDisposition: HealthDisposition.cleared.rawValue,
                        newCommercialDisposition: CommercialDisposition.eligibleForResale.rawValue,
                        notes: resolvedNotes,
                        commandId: commandId
                    )
                } catch {
                    guard attempt < 4,
                          let reconciled = try? await authoritativeUnit(returnCaseId: returnCaseId, unitId: unitId),
                          reconciled.0.version != currentCase.version ||
                            reconciled.1.inventoryVersion != currentUnit.inventoryVersion ||
                            reconciled.1.resultingLifecycleStatus != currentUnit.resultingLifecycleStatus else {
                        throw error
                    }
                }

            case .cleared:
                let commandId = stableCommandId(
                    action: "release-resale",
                    returnCaseId: returnCaseId,
                    unitId: unitId,
                    caseVersion: currentCase.version,
                    unitVersion: currentUnit.inventoryVersion,
                    notes: resolvedNotes
                )
                do {
                    _ = try await remoteDataSource.clearLivePetForResale(
                        returnCaseId: returnCaseId,
                        unitId: unitId,
                        expectedCaseVersion: currentCase.version,
                        expectedUnitVersion: currentUnit.inventoryVersion,
                        notes: resolvedNotes,
                        commandId: commandId
                    )
                } catch {
                    guard attempt < 4,
                          let reconciled = try? await authoritativeUnit(returnCaseId: returnCaseId, unitId: unitId),
                          reconciled.0.version != currentCase.version ||
                            reconciled.1.inventoryVersion != currentUnit.inventoryVersion ||
                            reconciled.1.resultingLifecycleStatus != currentUnit.resultingLifecycleStatus else {
                        throw error
                    }
                }

            default:
                throw NSError(domain: "LivePetReturn", code: 409, userInfo: [
                    NSLocalizedDescriptionKey: Language.get(
                        "LivePet_Error_ResaleLifecycle",
                        alter: "لا يمكن إتاحة الحيوان للبيع من حالته الحالية. حدّث ملف الاسترجاع وراجع قرار الرعاية البيطرية."
                    )
                ])
            }
        }

        throw NSError(domain: "LivePetReturn", code: 409, userInfo: [
            NSLocalizedDescriptionKey: Language.get(
                "LivePet_Error_ResaleReadback",
                alter: "تم إرسال أمر الإتاحة، لكن تعذر تأكيد الحالة النهائية. حدّث ملف الاسترجاع قبل إعادة المحاولة."
            )
        ])
    }

    private func authoritativeUnit(
        returnCaseId: String,
        unitId: String
    ) async throws -> (LivePetReturnCase, LivePetReturnUnit) {
        guard let currentCase = try await remoteDataSource.fetchReturnCase(returnCaseId: returnCaseId),
              let currentUnit = currentCase.units.first(where: { $0.unitId == unitId }) else {
            throw NSError(domain: "LivePetReturn", code: 404, userInfo: [
                NSLocalizedDescriptionKey: Language.get(
                    "LivePet_Error_ReturnUnitMissing",
                    alter: "لم يعد ملف الاسترجاع أو الحيوان المحدد متاحاً. حدّث البيانات وحاول مرة أخرى."
                )
            ])
        }
        return (currentCase, currentUnit)
    }

    private func stableCommandId(
        action: String,
        returnCaseId: String,
        unitId: String,
        caseVersion: Int,
        unitVersion: Int,
        notes: String
    ) -> String {
        let intent = [
            action,
            returnCaseId,
            unitId,
            String(caseVersion),
            String(unitVersion),
            notes
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(intent.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "admin-ios-\(action)-\(digest.prefix(40))"
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
