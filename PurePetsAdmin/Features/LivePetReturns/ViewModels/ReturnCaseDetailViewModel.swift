//
//  ReturnCaseDetailViewModel.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  ViewModel powering the authoritative ReturnCase dossier and post-intake operations.
//

import Foundation
import SwiftUI
import FirebaseFirestore

@MainActor
public final class ReturnCaseDetailViewModel: ObservableObject {
    public let returnCaseId: String

    @Published public private(set) var returnCase: LivePetReturnCase?
    @Published public private(set) var isLoading: Bool = false
    @Published public var actionErrorMessage: String?
    @Published public var actionSuccessMessage: String?
    @Published public var isPerformingAction: Bool = false

    private final class ListenerHolder: @unchecked Sendable {
        var registration: (any ListenerRegistration)?
        func remove() {
            registration?.remove()
            registration = nil
        }
    }

    private let listenerHolder = ListenerHolder()
    private let repository = LivePetReturnRepository.shared
    private let service = LivePetReturnService.shared

    public init(returnCaseId: String, initialCase: LivePetReturnCase? = nil) {
        self.returnCaseId = returnCaseId
        self.returnCase = initialCase
        startListening()
    }

    deinit {
        listenerHolder.remove()
    }

    public func startListening() {
        isLoading = returnCase == nil
        listenerHolder.remove()
        listenerHolder.registration = repository.listenToReturnCase(returnCaseId: returnCaseId) { [weak self] updatedCase in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let updatedCase {
                    self.returnCase = updatedCase
                } else {
                    self.returnCase = nil
                    self.actionErrorMessage = Language.get("LivePet_CaseNotFound", alter: "لم يتم العثور على ملف الاسترجاع.")
                }
            }
        }
    }

    // MARK: - Staff Clearance Action

    public func clearUnitForResale(unit: LivePetReturnUnit, notes: String?) async -> Bool {
        guard service.canInspectOrClear() else {
            actionErrorMessage = Language.get("LivePet_Error_NoClearancePerm", alter: "ليس لديك صلاحية لاعتماد الحيوانات للبيع (returns.live_pet.inspect).")
            return false
        }

        isPerformingAction = true
        actionErrorMessage = nil

        let currentStaff = PPStaffAuth.shared().cachedCurrentStaff
        let actorId = currentStaff?.uid ?? "unknown"
        let actorName = currentStaff?.displayName ?? currentStaff?.email ?? "Staff"
        let branchId = returnCase?.receivingBranchId ?? ""

        do {
            try await repository.clearLivePetForResale(
                returnCaseId: returnCaseId,
                unitId: unit.unitId,
                productId: unit.productId,
                actorId: actorId,
                actorName: actorName,
                branchId: branchId,
                notes: notes
            )
            isPerformingAction = false
            actionSuccessMessage = Language.get("LivePet_Clearance_Success", alter: "تم اعتماد الحيوان بنجاح وأصبح متاحاً للبيع في المتجر.")
            return true
        } catch {
            isPerformingAction = false
            actionErrorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Quarantine Action

    public func quarantineUnit(unit: LivePetReturnUnit, notes: String?) async -> Bool {
        guard service.canInspectOrClear() else {
            actionErrorMessage = Language.get("LivePet_Error_NoInspectPerm", alter: "ليس لديك صلاحية لتحديث حالة الفحص (returns.live_pet.inspect).")
            return false
        }

        isPerformingAction = true
        actionErrorMessage = nil

        let currentStaff = PPStaffAuth.shared().cachedCurrentStaff
        let actorId = currentStaff?.uid ?? "unknown"
        let actorName = currentStaff?.displayName ?? currentStaff?.email ?? "Staff"
        let branchId = returnCase?.receivingBranchId ?? ""

        do {
            try await repository.updateReturnCaseInspection(
                returnCaseId: returnCaseId,
                unitId: unit.unitId,
                newCondition: .illnessSuspected,
                newHealthDisposition: .quarantine,
                newCommercialDisposition: .hold,
                actorId: actorId,
                actorName: actorName,
                branchId: branchId,
                notes: notes ?? "Animal transferred to quarantine."
            )
            isPerformingAction = false
            actionSuccessMessage = Language.get("LivePet_Quarantine_Success", alter: "تم نقل الحيوان إلى وحدة الحجر الصحي بنجاح.")
            return true
        } catch {
            isPerformingAction = false
            actionErrorMessage = error.localizedDescription
            return false
        }
    }
}
