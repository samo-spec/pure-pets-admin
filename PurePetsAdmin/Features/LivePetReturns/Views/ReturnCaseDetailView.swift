//
//  ReturnCaseDetailView.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Operational source-of-truth dossier with real-time sync, timeline, and clearance actions.
//

import SwiftUI

public struct ReturnCaseDetailView: View {
    @StateObject private var viewModel: ReturnCaseDetailViewModel
    @ObservedObject private var branchStore = BranchContextStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedUnitForAction: LivePetReturnUnit?
    @State private var showingClearanceConfirmation: Bool = false
    @State private var showingQuarantineConfirmation: Bool = false
    @State private var actionNotes: String = ""

    public init(returnCaseId: String, initialCase: LivePetReturnCase? = nil) {
        _viewModel = StateObject(wrappedValue: ReturnCaseDetailViewModel(returnCaseId: returnCaseId, initialCase: initialCase))
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.returnCase == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(Language.get("Loading", alter: "جاري التحميل..."))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            } else if let rCase = viewModel.returnCase {
                VStack(spacing: 0) {
                    // Top Navigation Header
                    headerBar(for: rCase)

                    Divider().background(AdminSurface.hairline)

                    // Scrollable Dossier Content
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Feedback Banners
                            if let error = viewModel.actionErrorMessage {
                                AdminErrorBanner(message: error)
                            }
                            if let success = viewModel.actionSuccessMessage {
                                successBanner(message: success)
                            }

                            // Independent State Cards (Animal Custody vs Financial Settlement)
                            stateSummarySection(for: rCase)

                            // Returned Animal Units Details Card
                            unitsSection(for: rCase)

                            // Timeline & Event History
                            timelineSection(for: rCase)
                        }
                        .padding(AdminSpacing.screenMargin)
                    }
                }
            } else {
                notFoundView
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .alert(Language.get("LivePet_ConfirmClearanceTitle", alter: "تأكيد اعتماد الحيوان للبيع"), isPresented: $showingClearanceConfirmation) {
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
            Button(Language.get("Confirm", alter: "تأكيد الاعتماد")) {
                if let unit = selectedUnitForAction {
                    let trimmed = actionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let notes = trimmed.isEmpty ? nil : trimmed
                    Task {
                        _ = await viewModel.clearUnitForResale(unit: unit, notes: notes)
                    }
                }
            }
        } message: {
            Text(Language.get("LivePet_ConfirmClearanceMsg", alter: "هل أنت متأكد من اجتياز الحيوان لكافة الفحوصات البيطرية وأنه مؤهل للإتاحة في المتجر مجدداً؟"))
        }
        .alert(Language.get("LivePet_ConfirmQuarantineTitle", alter: "نقل الحيوان للحجر الصحي"), isPresented: $showingQuarantineConfirmation) {
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
            Button(Language.get("Confirm", alter: "تأكيد العزل"), role: .destructive) {
                if let unit = selectedUnitForAction {
                    let trimmed = actionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let notes = trimmed.isEmpty ? nil : trimmed
                    Task {
                        _ = await viewModel.quarantineUnit(unit: unit, notes: notes)
                    }
                }
            }
        } message: {
            Text(Language.get("LivePet_ConfirmQuarantineMsg", alter: "سيتم عزل الحيوان في وحدة الحجر ونقله من عهدة مكتب الاستلام لحين التقييم الطبي."))
        }
    }

    // MARK: - Header Bar

    private func headerBar(for rCase: LivePetReturnCase) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(rCase.caseNumber)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .monospacedDigit()

                    Text(rCase.status.localizedTitle)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(rCase.status.badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(rCase.status.badgeColor.opacity(0.12), in: Capsule())
                }

                Text(verbatim: "\(Language.get("POS_TransactionID", alter: "رقم الفاتورة")): #\(rCase.transactionId)")
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            AdminSquircleCloseButton {
                dismiss()
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.md)
    }

    // MARK: - State Summary Section

    private func stateSummarySection(for rCase: LivePetReturnCase) -> some View {
        HStack(spacing: 12) {
            // Animal Custody Card
            VStack(alignment: .leading, spacing: 6) {
                Label(Language.get("LivePet_AnimalCustody", alter: "العهدة والموقع"), systemImage: "tray.and.arrow.down.fill")
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)

                Text(rCase.status.localizedTitle)
                    .font(AdminType.headline)
                    .foregroundColor(rCase.status.badgeColor)

                Text(verbatim: "\(Language.get("Branch", alter: "الفرع")): \(branchDisplayName(for: rCase.receivingBranchId))")
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Financial Settlement Card
            VStack(alignment: .leading, spacing: 6) {
                Label(Language.get("LivePet_FinancialSettlement", alter: "التسوية المالية"), systemImage: "creditcard.fill")
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)

                Text(rCase.refundStatus.localizedTitle)
                    .font(AdminType.headline)
                    .foregroundColor(rCase.refundStatus.badgeColor)

                let scale = LivePetMoney.minorUnitScale(for: rCase.currency)
                Text(verbatim: "\(rCase.totalRefundAmountMajor.formatted(.number.precision(.fractionLength(scale)))) \(rCase.currency)")
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Units Details & Action Section

    private func unitsSection(for rCase: LivePetReturnCase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("LivePet_ReturnedAnimalsHeader", alter: "سجل الحيوانات والإجراءات البيطرية"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            ForEach(rCase.units) { unit in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(unit.displayIdentification)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)

                            if let sp = unit.speciesName {
                                Text(sp)
                                    .font(AdminType.caption)
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                        }

                        Spacer()

                        Text(unit.conditionAtReturn.localizedTitle)
                            .font(AdminType.caption2Bold)
                            .foregroundColor(unit.conditionAtReturn.tintColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(unit.conditionAtReturn.tintColor.opacity(0.12), in: Capsule())
                    }

                    // Staff Inspection Action Buttons
                    HStack(spacing: 8) {
                        Button {
                            selectedUnitForAction = unit
                            showingClearanceConfirmation = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                Text(Language.get("LivePet_ActionClearResale", alter: "اعتماد للبيع"))
                            }
                            .font(AdminType.caption2Bold)
                            .foregroundColor(Color(uiColor: .systemGreen))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .systemGreen).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            selectedUnitForAction = unit
                            showingQuarantineConfirmation = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                                Text(Language.get("LivePet_ActionQuarantine", alter: "نقل للحجر"))
                            }
                            .font(AdminType.caption2Bold)
                            .foregroundColor(Color(uiColor: .systemPurple))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .systemPurple).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Timeline Section

    private func timelineSection(for rCase: LivePetReturnCase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("LivePet_TimelineHeader", alter: "سجل العمليات والتدقيق التاريخي"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            if rCase.events.isEmpty {
                Text(Language.get("LivePet_NoEventsYet", alter: "لا توجد سجلات بعد."))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rCase.events.enumerated()), id: \.element.eventId) { idx, event in
                        HStack(alignment: .top, spacing: 12) {
                            // Dot & Vertical Line
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(event.eventType.tintColor)
                                    .frame(width: 12, height: 12)

                                if idx < rCase.events.count - 1 {
                                    Rectangle()
                                        .fill(AdminSurface.hairline)
                                        .frame(width: 2)
                                        .frame(minHeight: 34)
                                }
                            }

                            // Event Content
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(event.eventType.localizedTitle)
                                        .font(AdminType.bodyBold)
                                        .foregroundColor(AdminSurface.primaryText)

                                    Spacer()

                                    Text(formattedTime(event.occurredAt))
                                        .font(AdminType.caption2)
                                        .foregroundColor(AdminSurface.secondaryText)
                                }

                                if let actorName = event.actorName, !actorName.isEmpty {
                                    Text(verbatim: "\(Language.get("Staff", alter: "الموظف")): \(actorName)")
                                        .font(AdminType.caption2)
                                        .foregroundColor(AdminSurface.secondaryText)
                                }

                                if let notes = event.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(AdminType.caption)
                                        .foregroundColor(AdminSurface.primaryText)
                                        .padding(.top, 2)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(14)
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func successBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(uiColor: .systemGreen))
            Text(message)
                .font(AdminType.caption)
                .foregroundColor(AdminSurface.primaryText)
            Spacer()
        }
        .padding(12)
        .background(Color(uiColor: .systemGreen).opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var notFoundView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark.fill")
                .font(.system(size: 38))
                .foregroundColor(AdminSurface.secondaryText)
            Text(Language.get("LivePet_CaseNotFound", alter: "لم يتم العثور على ملف الاسترجاع."))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.secondaryText)
            Button(Language.get("Close", alter: "إغلاق")) {
                dismiss()
            }
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_US")
        return formatter.string(from: date)
    }

    private func branchDisplayName(for branchId: String) -> String {
        let trimmed = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Language.get("MainStore", alter: "المتجر الرئيسي")
        }
        if trimmed == "main_store" || trimmed.lowercased() == "main_store" || trimmed.lowercased() == "main store" {
            return Language.get("MainStore", alter: "المتجر الرئيسي")
        }
        let localized = branchStore.localizedBranchName(for: trimmed)
        if localized != trimmed && !localized.isEmpty {
            return localized
        }
        if let canonical = PPLivePetInventoryService.canonicalBranch(for: trimmed, in: PPLivePetInventoryService.cachedBranches) {
            return canonical.fullMeaningfulTitle
        }
        if let cached = PPLivePetInventoryService.branch(for: trimmed) {
            return cached.fullMeaningfulTitle
        }
        return localized
    }
}
