//
//  LivePetReturnCoordinatorView.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Master workflow coordinator handling unit selection, custody intake, review, and confirmation.
//

import SwiftUI

public struct LivePetReturnCoordinatorView: View {
    public let receipt: PPPOSReceipt
    public let onComplete: (LivePetReturnCase) -> Void
    public let onProceedToMerchandiseRefund: ((PPPOSReceipt) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: ReturnUnitSelectionViewModel

    private enum Step {
        case selectUnits
        case receiveAndResolve
        case confirmed(LivePetReturnCase)
    }

    @State private var currentStep: Step = .selectUnits
    @State private var isSubmitting: Bool = false
    @State private var submissionError: String?
    @State private var showingDossierCaseId: String?
    @State private var hasCompleted: Bool = false

    private var isConfirmedStep: Bool {
        if case .confirmed = currentStep { return true }
        return false
    }

    private func handleDismiss() {
        guard !isSubmitting else { return }
        if case .confirmed(let returnCase) = currentStep {
            if !hasCompleted {
                hasCompleted = true
                onComplete(returnCase)
            }
        }
        dismiss()
    }

    public init(
        receipt: PPPOSReceipt,
        onProceedToMerchandiseRefund: ((PPPOSReceipt) -> Void)? = nil,
        onComplete: @escaping (LivePetReturnCase) -> Void
    ) {
        self.receipt = receipt
        self.onProceedToMerchandiseRefund = onProceedToMerchandiseRefund
        self.onComplete = onComplete
        _viewModel = StateObject(wrappedValue: ReturnUnitSelectionViewModel(receipt: receipt))
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header (only for wizard steps)
                if case .confirmed = currentStep {
                    // Confirmation view has its own header
                } else {
                    wizardHeader
                    Divider().background(AdminSurface.hairline)
                }

                // Step Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        if let error = submissionError {
                            AdminErrorBanner(message: error)
                        }

                        switch currentStep {
                        case .selectUnits:
                            ReturnUnitSelectionView(viewModel: viewModel)
                        case .receiveAndResolve:
                            ReturnReceiveView(viewModel: viewModel)
                        case .confirmed(let returnCase):
                            ReturnConfirmationView(
                                returnCase: returnCase,
                                onOpenDossier: {
                                    showingDossierCaseId = returnCase.returnCaseId
                                },
                                onDismiss: {
                                    handleDismiss()
                                },
                                onProceedToMerchandiseRefund: (receipt.hasGenericMerchandise && onProceedToMerchandiseRefund != nil) ? {
                                    if !hasCompleted {
                                        hasCompleted = true
                                        onComplete(returnCase)
                                    }
                                    dismiss()
                                    onProceedToMerchandiseRefund?(receipt)
                                } : nil
                            )
                        }
                    }
                    .padding(AdminSpacing.screenMargin)
                }

                // Bottom Action Bar (for wizard steps)
                if case .confirmed = currentStep {
                    // Empty bottom bar on confirmation
                } else {
                    bottomActionBar
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .interactiveDismissDisabled(isSubmitting || isConfirmedStep)
        .sheet(item: Binding<DossierIdentifier?>(
            get: { showingDossierCaseId.map { DossierIdentifier(id: $0) } },
            set: { showingDossierCaseId = $0?.id }
        )) { ident in
            ReturnCaseDetailView(returnCaseId: ident.id)
        }
    }

    // MARK: - Wizard Header

    private var wizardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("LivePet_Return_CoordinatorTitle", alter: "استرجاع حيوان أليف (حجل محدد)"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)

                Text(verbatim: "\(Language.get("POS_TransactionID", alter: "فاتورة")): #\(receipt.receiptID)")
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            AdminSquircleCloseButton {
                handleDismiss()
            }
            .disabled(isSubmitting)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.md)
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 8) {
            Divider().background(AdminSurface.hairline)

            HStack(spacing: 12) {
                if case .receiveAndResolve = currentStep {
                    Button {
                        withAnimation {
                            currentStep = .selectUnits
                        }
                    } label: {
                        Text(Language.get("Back", alter: "السابق"))
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(width: 80, height: 50)
                            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }

                Button(action: handlePrimaryAction) {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: primaryActionIcon)
                                .font(.system(size: 16, weight: .bold))
                        }

                        Text(primaryActionTitle)
                            .font(AdminType.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        canProceedWithPrimary ? AdminSurface.primary : Color.gray.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canProceedWithPrimary || isSubmitting)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.bottom, 16)
        }
        .background(AdminSurface.surface)
    }

    private var primaryActionIcon: String {
        switch currentStep {
        case .selectUnits: return "arrow.right"
        case .receiveAndResolve: return "checkmark.seal.fill"
        case .confirmed: return "checkmark"
        }
    }

    private var primaryActionTitle: String {
        switch currentStep {
        case .selectUnits:
            let count = viewModel.selectedUnitIds.count
            return String(format: Language.get("LivePet_NextCustodyIntake", alter: "متابعة الاستلام (%d حيوان)"), count)
        case .receiveAndResolve:
            let currency = viewModel.receipt.currency
            let scale = LivePetMoney.minorUnitScale(for: currency)
            let amountStr = viewModel.calculatedRefundAmountMajor.formatted(.number.precision(.fractionLength(scale))) + " " + currency
            return String(format: Language.get("LivePet_ConfirmReturnAction", alter: "تأكيد الاسترجاع (%@)"), amountStr)
        case .confirmed:
            return Language.get("Done", alter: "تم")
        }
    }

    private var canProceedWithPrimary: Bool {
        switch currentStep {
        case .selectUnits:
            return !viewModel.selectedUnitIds.isEmpty
        case .receiveAndResolve:
            return viewModel.canProceed
        case .confirmed:
            return true
        }
    }

    private func handlePrimaryAction() {
        switch currentStep {
        case .selectUnits:
            withAnimation {
                currentStep = .receiveAndResolve
            }
        case .receiveAndResolve:
            executeLivePetReturn()
        case .confirmed:
            dismiss()
        }
    }

    private func executeLivePetReturn() {
        isSubmitting = true
        submissionError = nil

        let branchCandidate = [
            BranchContextStore.shared.activeBranch?.branchID,
            receipt.branchID
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }

        guard let receivingBranch = branchCandidate else {
            isSubmitting = false
            submissionError = Language.get(
                "LivePet_MissingReceivingBranch",
                alter: "تعذر تحديد فرع الاستلام المعتمد."
            )
            return
        }
        let selectedUnits = viewModel.selectedUnitsForSubmission
        let reason = viewModel.effectiveReason
        let resolution = viewModel.financialResolution
        let adjustmentReason = viewModel.refundAdjustmentReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftId = viewModel.activeDraftId

        Task {
            do {
                let returnCase = try await LivePetReturnService.shared.processLivePetReturn(
                    transaction: receipt,
                    selectedUnits: selectedUnits,
                    receivingBranchId: receivingBranch,
                    reason: reason,
                    financialResolution: resolution,
                    refundAdjustmentReason: resolution == .partialRefund ? adjustmentReason : nil,
                    draftId: draftId
                )

                await MainActor.run {
                    self.isSubmitting = false
                    self.viewModel.clearDraft()
                    withAnimation {
                        self.currentStep = .confirmed(returnCase)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSubmitting = false
                    self.submissionError = error.localizedDescription
                }
            }
        }
    }
}

private struct DossierIdentifier: Identifiable {
    let id: String
}
