//
//  ReturnReceiveView.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Custody intake card, return reason, financial resolution, and stock isolation notice.
//

import SwiftUI

public struct ReturnReceiveView: View {
    @ObservedObject var viewModel: ReturnUnitSelectionViewModel

    private let reasonPresets: [String] = [
        Language.get("POS_Refund_Reason_Chip_Customer", alter: "رغبة العميل"),
        Language.get("LivePet_Reason_Behavior", alter: "صعوبة تكيف / سلوك"),
        Language.get("LivePet_Reason_Allergy", alter: "حساسية مفاجئة للأسرة"),
        Language.get("LivePet_Reason_HealthConcern", alter: "ملاحظة صحية تحتاج فحص"),
        Language.get("POS_Refund_Reason_Chip_Error", alter: "خطأ في اختيار الفصيلة")
    ]

    public init(viewModel: ReturnUnitSelectionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Custody Intake Location Card
            custodyDeskCard

            // Controlled Custody Notice (Invariant 2.2)
            controlledCustodyNotice

            // Return Reason Section
            reasonSection

            // Financial Resolution Picker
            financialResolutionSection

            // Refund Calculation Summary
            refundSummaryCard
        }
    }

    // MARK: - Custody Desk Card

    private var custodyDeskCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("LivePet_Custody_IntakeLocationTitle", alter: "موقع استلام الحيوان"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)

                let branchName = BranchContextStore.shared.activeBranch?.localizedName() ?? Language.get("POS_CurrentBranch", alter: "الفرع الحالي")
                Text(String(format: Language.get("LivePet_Custody_DeskFormat", alter: "مكتب المرتجعات • %@"), branchName))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
            }
            Spacer()
        }
        .padding(14)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Controlled Custody Invariant Notice

    private var controlledCustodyNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 20))
                .foregroundColor(Color(uiColor: .systemOrange))

            VStack(alignment: .leading, spacing: 3) {
                Text(Language.get("LivePet_Notice_NoAutoRestockTitle", alter: "بروتوكول سلامة الحيوان المرتجع"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("LivePet_Notice_NoAutoRestockSub", alter: "لن يتم إرجاع الحيوان لمخزون البيع تلقائياً بعد الاسترداد المالي، بل يدخل في عهدة (قيد الفحص) لحين تقييمه واعتماده يدوياً."))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(uiColor: .systemOrange).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(uiColor: .systemOrange).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Reason Section

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("POS_Refund_Reason_Title", alter: "سبب الاسترجاع (مطلوب)"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(reasonPresets, id: \.self) { preset in
                        let isSelected = viewModel.selectedReasonPreset == preset
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.selectedReasonPreset = preset
                            viewModel.customReason = preset
                            viewModel.syncDraft()
                        } label: {
                            Text(preset)
                                .font(AdminType.caption)
                                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    isSelected ? AdminSurface.primary : AdminSurface.backgroundSecondary,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField(Language.get("LivePet_Reason_Placeholder", alter: "اكتب سبب إرجاع العميل بالتفصيل..."), text: $viewModel.customReason)
                .font(AdminType.body)
                .padding(12)
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                )
                .onChange(of: viewModel.customReason) { _ in
                    viewModel.syncDraft()
                }
        }
    }

    // MARK: - Financial Resolution Section

    private var financialResolutionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("LivePet_FinancialResolutionTitle", alter: "طريقة التسوية المالية"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            HStack(spacing: 10) {
                ForEach([FinancialResolution.fullRefund, FinancialResolution.storeCredit, FinancialResolution.manualSettlement]) { res in
                    let isSelected = viewModel.financialResolution == res
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.financialResolution = res
                        viewModel.syncDraft()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: res.iconName)
                                .font(.system(size: 16, weight: .semibold))
                            Text(res.localizedTitle)
                                .font(AdminType.caption2Bold)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .padding(.horizontal, 6)
                        .background(
                            isSelected ? AdminSurface.primary : AdminSurface.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Refund Summary Card

    private var refundSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("LivePet_TotalRefundDue", alter: "المبلغ الإجمالي المستحق"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)

                Text(verbatim: "\(viewModel.selectedUnitIds.count) \(Language.get("LivePet_UnitsCount", alter: "حيوان محدد"))")
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            let scale = LivePetMoney.minorUnitScale(for: viewModel.receipt.currency)
            Text(verbatim: "\(viewModel.calculatedRefundAmountMajor.formatted(.number.precision(.fractionLength(scale)))) \(viewModel.receipt.currency)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AdminSurface.primary)
                .monospacedDigit()
        }
        .padding(16)
        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }
}
