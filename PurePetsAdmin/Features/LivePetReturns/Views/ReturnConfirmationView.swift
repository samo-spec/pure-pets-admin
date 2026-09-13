//
//  ReturnConfirmationView.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Category-defining, dual-domain Return Confirmation Console.
//  First-principles dedicated native architectures for Live Pets vs Accessories/Food,
//  with adaptive iPadOS Split-Inspector console and ergonomic iPhone sheet.
//

import SwiftUI
import UIKit

// MARK: - Category & Domain Mode

public enum ReturnCategoryMode: String, CaseIterable, Identifiable {
    case livePets = "livePets"
    case accessoriesFood = "accessoriesFood"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .livePets:
            return Language.get("LivePet_Mode_LivePets", alter: "الحيوانات الحية")
        case .accessoriesFood:
            return Language.get("LivePet_Mode_AccessoriesFood", alter: "المستلزمات والأغذية")
        }
    }

    public var systemIcon: String {
        switch self {
        case .livePets:
            return "pawprint.fill"
        case .accessoriesFood:
            return "bag.fill"
        }
    }
}

// MARK: - Merchandise Restock Item Model

public struct ReturnMerchandiseDisplayItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let sku: String
    public let quantity: Int
    public let unitPrice: Double
    public let currency: String
    public let disposition: String
    public let shelfBin: String

    public init(
        id: String,
        name: String,
        sku: String,
        quantity: Int,
        unitPrice: Double,
        currency: String,
        disposition: String,
        shelfBin: String
    ) {
        self.id = id
        self.name = name
        self.sku = sku
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.currency = currency
        self.disposition = disposition
        self.shelfBin = shelfBin
    }
}

// MARK: - Master Return Confirmation View

public struct ReturnConfirmationView: View {
    public let returnCase: LivePetReturnCase
    public let receipt: PPPOSReceipt?
    public let onOpenDossier: () -> Void
    public let onDismiss: () -> Void
    public let onProceedToMerchandiseRefund: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedCategory: ReturnCategoryMode = .livePets
    @State private var hasCopiedCaseNumber: Bool = false
    @State private var showingSlipModal: Bool = false
    @State private var morphicPulse: Bool = false

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    private var hasMixedReceipt: Bool {
        if let receipt = receipt {
            return receipt.hasIndividuallyTrackedLivePets && receipt.hasGenericMerchandise
        }
        return onProceedToMerchandiseRefund != nil
    }

    private var merchandiseItems: [ReturnMerchandiseDisplayItem] {
        if let receipt = receipt, !receipt.genericCartItems.isEmpty {
            return receipt.genericCartItems.enumerated().map { index, item in
                ReturnMerchandiseDisplayItem(
                    id: item.itemID.isEmpty ? "item_\(index)" : item.itemID,
                    name: item.name,
                    sku: item.itemID.isEmpty ? "SKU-\(1000 + index)" : item.itemID,
                    quantity: max(1, item.quantity),
                    unitPrice: item.price,
                    currency: receipt.currency.isEmpty ? returnCase.currency : receipt.currency,
                    disposition: Language.get("LivePet_Disposition_Shelf", alter: "إرجاع للرف (صالح للبيع)"),
                    shelfBin: "BIN-A\(index + 1)"
                )
            }
        } else if onProceedToMerchandiseRefund != nil {
            return [
                ReturnMerchandiseDisplayItem(
                    id: "pending_merchandise_batch",
                    name: Language.get("LivePet_Mode_AccessoriesFood", alter: "المستلزمات والأغذية"),
                    sku: "BATCH-POS",
                    quantity: 1,
                    unitPrice: 0.0,
                    currency: returnCase.currency,
                    disposition: Language.get("LivePet_Disposition_Shelf", alter: "جاهز للتسوية المباشرة"),
                    shelfBin: "POS-DESK"
                )
            ]
        }
        return []
    }

    public init(
        returnCase: LivePetReturnCase,
        receipt: PPPOSReceipt? = nil,
        onOpenDossier: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onProceedToMerchandiseRefund: (() -> Void)? = nil
    ) {
        self.returnCase = returnCase
        self.receipt = receipt
        self.onOpenDossier = onOpenDossier
        self.onDismiss = onDismiss
        self.onProceedToMerchandiseRefund = onProceedToMerchandiseRefund
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            if isIPad {
                iPadConfirmationLayout
            } else {
                iPhoneConfirmationLayout
            }
        }
        .accessibilityIdentifier("return_confirmation_root")
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showingSlipModal) {
            ReturnIntakeSlipModal(
                returnCase: returnCase,
                categoryMode: selectedCategory,
                merchandiseItems: merchandiseItems,
                onDismiss: { showingSlipModal = false }
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                morphicPulse = true
            }
        }
    }

    // MARK: - iPad Dedicated 2-Column Inspector Architecture

    private var iPadConfirmationLayout: some View {
        VStack(spacing: 0) {
            // iPad Top Navigation Bar
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(uiColor: .systemGreen))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("LivePet_Confirm_SuccessTitle", alter: "تم تسجيل استرجاع الحيوان بنجاح"))
                            .font(AdminType.title3Bold)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("LivePet_KeyShortcuts_Hint", alter: "اختصارات iPad: ⌘D للمتابعة • ⌘P للطباعة • ⌘C للنسخ • Esc للإغلاق"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                // Thermal Slip Generator Trigger
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingSlipModal = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "printer.fill")
                        Text(selectedCategory == .livePets ? Language.get("LivePet_PrintSlipAction", alter: "طباعة بطاقة القفص") : Language.get("LivePet_PrintRestockSlipAction", alter: "طباعة ملصق الرف"))
                    }
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("p", modifiers: .command)
                .accessibilityLabel(Language.get("LivePet_PrintSlipAction", alter: "طباعة القسيمة"))

                AdminSquircleCloseButton {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .background(AdminSurface.card.overlay(Divider(), alignment: .bottom))

            // iPad Split Inspector Console
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 24) {
                    // Left Column: Authority, Credentials, Financials & Actions (380pt fixed)
                    VStack(spacing: 18) {
                        morphicVerificationSeal
                        caseCredentialCard
                        telemetryDualGrid
                        physicalCustodyCard
                        iPadPrimaryActionRail
                    }
                    .frame(width: 380)

                    // Right Column: Domain Manifest & Detailed Inventory Routing
                    VStack(spacing: 20) {
                        if hasMixedReceipt {
                            categorySegmentPicker
                        }

                        if selectedCategory == .livePets {
                            livePetIntakeManifest
                        } else {
                            merchandiseRestockManifest
                        }

                        quickSlipBannerCard
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(28)
            }
        }
    }

    // MARK: - iPhone Dedicated Ergonomic Sheet Architecture

    private var iPhoneConfirmationLayout: some View {
        VStack(spacing: 0) {
            // iPhone Minimal Header
            HStack {
                Text(selectedCategory == .livePets ? Language.get("LivePet_Confirm_SuccessTitle", alter: "تم استرجاع الحيوان") : Language.get("LivePet_Confirm_MerchandiseTitle", alter: "استرجاع المنتجات"))
                    .font(AdminType.headlineBold)
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                Button {
                    showingSlipModal = true
                } label: {
                    Image(systemName: "printer.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.primary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("LivePet_PrintSlipAction", alter: "طباعة"))

                AdminSquircleCloseButton {
                    onDismiss()
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(AdminSurface.card)
            .overlay(Divider().background(AdminSurface.hairline), alignment: .bottom)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    morphicVerificationSeal
                    caseCredentialCard

                    if hasMixedReceipt {
                        categorySegmentPicker
                    }

                    telemetryDualGrid

                    if selectedCategory == .livePets {
                        livePetIntakeManifest
                    } else {
                        merchandiseRestockManifest
                    }

                    physicalCustodyCard
                    quickSlipBannerCard
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }

            // Fixed Bottom Action Dock
            iPhoneBottomActionDock
        }
    }

    // MARK: - Morphic Verification Seal

    private var morphicVerificationSeal: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemGreen).opacity(0.08))
                    .frame(width: isIPad ? 96 : 80, height: isIPad ? 96 : 80)
                    .scaleEffect(morphicPulse ? 1.08 : 0.94)

                Circle()
                    .stroke(Color(uiColor: .systemGreen).opacity(0.25), lineWidth: 1.5)
                    .frame(width: isIPad ? 82 : 68, height: isIPad ? 82 : 68)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: isIPad ? 44 : 36, weight: .semibold))
                    .foregroundColor(Color(uiColor: .systemGreen))
                    .shadow(color: Color(uiColor: .systemGreen).opacity(0.3), radius: 8, x: 0, y: 4)
            }

            VStack(spacing: 4) {
                Text(selectedCategory == .livePets ? Language.get("LivePet_Confirm_SuccessTitle", alter: "تم تسجيل استرجاع الحيوان بنجاح") : Language.get("LivePet_Confirm_MerchandiseTitle", alter: "تم تسجيل استرجاع المنتجات بنجاح"))
                    .font(isIPad ? AdminType.headlineBold : AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)

                Text(selectedCategory == .livePets ? Language.get("LivePet_Confirm_SuccessSub", alter: "تم فتح ملف الاسترجاع ونقل الحيوان للعهدة المخصصة") : Language.get("LivePet_Confirm_MerchandiseSub", alter: "تم تحديث سجل المخزون وتوجيه الأصناف للرفوف"))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Case Credential Card

    private var caseCredentialCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Language.get("LivePet_CaseNumberLabel", alter: "رقم ملف الاسترجاع"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)

                Text(returnCase.caseNumber)
                    .font(.system(size: isIPad ? 19 : 17, weight: .bold, design: .monospaced))
                    .foregroundColor(AdminSurface.primaryText)
            }

            Spacer()

            Button {
                UIPasteboard.general.string = returnCase.caseNumber
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                hasCopiedCaseNumber = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    hasCopiedCaseNumber = false
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: hasCopiedCaseNumber ? "checkmark" : "doc.on.doc")
                    Text(hasCopiedCaseNumber ? Language.get("Copied", alter: "تم النسخ") : Language.get("Copy", alter: "نسخ"))
                }
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: .command)
            .accessibilityIdentifier("case_number_copy_button")
        }
        .padding(14)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
    }

    // MARK: - Category Segment Switcher

    private var categorySegmentPicker: some View {
        HStack(spacing: 6) {
            ForEach(ReturnCategoryMode.allCases) { mode in
                let isSelected = selectedCategory == mode
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedCategory = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemIcon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(mode.localizedTitle)
                            .font(AdminType.subheadlineBold)
                    }
                    .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        isSelected ? AdminSurface.primary : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Telemetry Dual Grid (Workflow & Financial)

    private var telemetryDualGrid: some View {
        HStack(spacing: 12) {
            // Case Workflow Status Card
            VStack(alignment: .leading, spacing: 6) {
                Label(Language.get("LivePet_WorkflowStateLabel", alter: "حالة الملف"), systemImage: "doc.text.fill")
                    .font(AdminType.caption2Medium)
                    .foregroundColor(AdminSurface.secondaryText)

                Text(returnCase.status.localizedTitle)
                    .font(AdminType.headline)
                    .foregroundColor(returnCase.status.badgeColor)

                Text(Language.get("LivePet_UnderInspection_Notice", alter: "في عهدة مكتب الاستلام"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )

            // Financial Refund State Card
            VStack(alignment: .leading, spacing: 6) {
                Label(Language.get("LivePet_RefundStateLabel", alter: "حالة الاسترداد"), systemImage: "creditcard.fill")
                    .font(AdminType.caption2Medium)
                    .foregroundColor(AdminSurface.secondaryText)

                Text(returnCase.refundStatus.localizedTitle)
                    .font(AdminType.headline)
                    .foregroundColor(returnCase.refundStatus.badgeColor)

                let scale = LivePetMoney.minorUnitScale(for: returnCase.currency)
                Text(verbatim: "\(returnCase.totalRefundAmountMajor.formatted(.number.precision(.fractionLength(scale)))) \(returnCase.currency)")
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
    }

    // MARK: - Domain Manifest: Live Pets

    private var livePetIntakeManifest: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(Language.get("LivePet_ReturnedUnitsHeader", alter: "سجل الحيوانات المسترجعة"), systemImage: "pawprint.fill")
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                Text("\(returnCase.units.count)")
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
            }

            VStack(spacing: 8) {
                ForEach(returnCase.units) { unit in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.primary.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: "tag.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AdminSurface.primary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(unit.displayIdentification)
                                .font(AdminType.bodyBold)
                                .foregroundColor(AdminSurface.primaryText)

                            HStack(spacing: 6) {
                                Text("ID: \(unit.unitId)")
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .monospacedDigit()

                                if let breed = unit.breedName, !breed.isEmpty {
                                    Text("• \(breed)")
                                        .font(AdminType.caption2)
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(unit.conditionAtReturn.localizedTitle)
                                .font(AdminType.captionBold)
                                .foregroundColor(unit.conditionAtReturn.tintColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(unit.conditionAtReturn.tintColor.opacity(0.12), in: Capsule())

                            Text(Language.get("LivePet_Tag_CageSlip", alter: "بطاقة القفص جاهزة"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                    .padding(12)
                    .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 0.8)
                    )
                }
            }
        }
    }

    // MARK: - Domain Manifest: Merchandise & Food

    private var merchandiseRestockManifest: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(Language.get("LivePet_Mode_AccessoriesFood", alter: "سجل مستلزمات وأغذية الفاتورة"), systemImage: "shippingbox.fill")
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(uiColor: .systemGreen))
                        .frame(width: 7, height: 7)
                    Text(Language.get("LivePet_InventorySynced", alter: "تم تحديث الرصيد فورياً"))
                        .font(AdminType.caption2)
                        .foregroundColor(Color(uiColor: .systemGreen))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(uiColor: .systemGreen).opacity(0.10), in: Capsule())
            }

            VStack(spacing: 8) {
                if merchandiseItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 28))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                        Text(Language.get("LivePet_Confirm_MerchandiseSub", alter: "لا توجد مستلزمات إضافية مسجلة بهذه الفاتورة"))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(merchandiseItems) { item in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(uiColor: .systemOrange).opacity(0.12))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "cube.box.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(uiColor: .systemOrange))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(AdminType.bodyBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                    .lineLimit(1)

                                HStack(spacing: 8) {
                                    Text("SKU: \(item.sku)")
                                        .font(AdminType.caption2)
                                        .foregroundColor(AdminSurface.secondaryText)
                                        .monospacedDigit()

                                    Text("• \(item.shelfBin)")
                                        .font(AdminType.caption2Bold)
                                        .foregroundColor(AdminSurface.primary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(item.quantity) \(Language.get("LivePet_ItemQuantityUnit", alter: "قطعة"))")
                                    .font(AdminType.captionBold)
                                    .foregroundColor(AdminSurface.primaryText)

                                Text(item.disposition)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color(uiColor: .systemGreen))
                            }
                        }
                        .padding(12)
                        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 0.8)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Physical Custody & Receiving Desk Card

    private var physicalCustodyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 18))
                .foregroundColor(AdminSurface.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("LivePet_CustodyLocationLabel", alter: "موقع العهدة الفيزيائية"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)

                Text(returnCase.receivingBranchId.isEmpty ? Language.get("LivePet_UnderInspection_Notice", alter: "مكتب استلام الفرع الرئيسي") : "الفرع: \(returnCase.receivingBranchId)")
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)
            }

            Spacer()

            if let receiver = returnCase.receivedBy, !receiver.isEmpty {
                Text(receiver)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.cardElevated, in: Capsule())
            }
        }
        .padding(12)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Quick Slip Action Banner

    private var quickSlipBannerCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingSlipModal = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedCategory == .livePets ? Language.get("LivePet_Tag_CageSlip", alter: "بطاقة القفص وقسيمة الاستلام") : Language.get("LivePet_Tag_RestockSlip", alter: "ملصق توجيه المخزون والرف"))
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)

                    Text(Language.get("LivePet_ThermalPrintReady", alter: "جاهز للمعاينة والإرسال للطابعة الحرارية فورياً"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(12)
            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AdminSurface.primary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - iPad Primary Action Rail

    private var iPadPrimaryActionRail: some View {
        VStack(spacing: 10) {
            if let onProceed = onProceedToMerchandiseRefund {
                Button(action: onProceed) {
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox.and.arrow.backward.fill")
                        Text(Language.get("LivePet_ProceedToMerchandiseRefund", alter: "استكمال استرداد المنتجات والأكسسوارات"))
                            .font(AdminType.headlineBold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(uiColor: .systemOrange), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityIdentifier("proceed_merchandise_button")
            }

            Button(action: onOpenDossier) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                    Text(Language.get("LivePet_OpenDossierButton", alter: "فتح ملف الاسترجاع والمتابعة"))
                        .font(onProceedToMerchandiseRefund != nil ? AdminType.subheadlineBold : AdminType.headlineBold)
                }
                .foregroundColor(onProceedToMerchandiseRefund != nil ? AdminSurface.primary : .white)
                .frame(maxWidth: .infinity)
                .frame(height: onProceedToMerchandiseRefund != nil ? 46 : 50)
                .background(
                    onProceedToMerchandiseRefund != nil ? AdminSurface.primary.opacity(0.12) : AdminSurface.primary,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: .command)
            .accessibilityIdentifier("open_dossier_button")

            Button(action: onDismiss) {
                Text(Language.get("Done", alter: "تم الإغلاق"))
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - iPhone Bottom Action Dock

    private var iPhoneBottomActionDock: some View {
        VStack(spacing: 8) {
            if let onProceed = onProceedToMerchandiseRefund {
                Button(action: onProceed) {
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox.and.arrow.backward.fill")
                        Text(Language.get("LivePet_ProceedToMerchandiseRefund", alter: "استكمال استرداد المنتجات والأكسسوارات"))
                            .font(AdminType.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(uiColor: .systemOrange), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("proceed_merchandise_button")
            }

            Button(action: onOpenDossier) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                    Text(Language.get("LivePet_OpenDossierButton", alter: "فتح ملف الاسترجاع والمتابعة"))
                        .font(onProceedToMerchandiseRefund != nil ? AdminType.subheadlineBold : AdminType.headline)
                }
                .foregroundColor(onProceedToMerchandiseRefund != nil ? AdminSurface.primary : .white)
                .frame(maxWidth: .infinity)
                .frame(height: onProceedToMerchandiseRefund != nil ? 44 : 48)
                .background(
                    onProceedToMerchandiseRefund != nil ? AdminSurface.primary.opacity(0.12) : AdminSurface.primary,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("open_dossier_button")

            Button(action: onDismiss) {
                Text(Language.get("Done", alter: "تم الإغلاق"))
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            AdminSurface.card
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(Divider().background(AdminSurface.hairline), alignment: .top)
    }
}

// MARK: - Thermal Intake Slip & Cage Tag Generator Modal

private struct ReturnIntakeSlipModal: View {
    let returnCase: LivePetReturnCase
    let categoryMode: ReturnCategoryMode
    let merchandiseItems: [ReturnMerchandiseDisplayItem]
    let onDismiss: () -> Void

    @State private var hasCopied: Bool = false

    private var slipContentFormatted: String {
        let isArabic = Language.isRTL()
        var str = "================================\n"
        str += isArabic ? "         بيور بتس - الإدارة       \n" : "        PURE PETS ADMIN         \n"
        str += "================================\n"
        str += "\(isArabic ? "الملف:" : "CASE:") \(returnCase.caseNumber)\n"
        str += "\(isArabic ? "المعاملة:" : "TXN: ") \(returnCase.transactionId)\n"
        str += "\(isArabic ? "التاريخ:" : "DATE:") \(Date().formatted(date: .numeric, time: .shortened))\n"
        str += "--------------------------------\n"
        if categoryMode == .livePets {
            str += isArabic ? "استلام العهدة: حيوانات حية\n" : "INTAKE: LIVE PET CUSTODY\n"
            for u in returnCase.units {
                str += "\(isArabic ? "الحجل:" : "TAG:") \(u.ringTag) | ID: \(u.unitId)\n"
                str += "\(isArabic ? "النوع:" : "SPEC:") \(u.productName)\n"
                str += "\(isArabic ? "الحالة:" : "COND:") \(u.conditionAtReturn.localizedTitle)\n"
            }
        } else {
            str += isArabic ? "إعادة للمخزون: منتجات وأغذية\n" : "RESTOCK: MERCHANDISE & FOOD\n"
            for m in merchandiseItems {
                str += "SKU: \(m.sku) | QTY: \(m.quantity)\n"
                str += "\(isArabic ? "الرف:" : "BIN:") \(m.shelfBin) | \(m.disposition)\n"
            }
        }
        str += "--------------------------------\n"
        str += "\(isArabic ? "الاسترداد:" : "REFUND:") \(returnCase.totalRefundAmountMajor) \(returnCase.currency)\n"
        str += "\(isArabic ? "العهدة:" : "CUSTODY:") \(returnCase.receivingBranchId.isEmpty ? (isArabic ? "الفرع الرئيسي" : "MAIN_BRANCH") : returnCase.receivingBranchId)\n"
        str += "================================\n"
        return str
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Thermal Slip Paper Simulation
                VStack(spacing: 12) {
                    VStack(spacing: 4) {
                        Text(Language.isRTL() ? "بيور بتس" : "PURE PETS")
                            .font(AdminType.headlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .multilineTextAlignment(.center)
                        Text(categoryMode == .livePets ? Language.get("LivePet_CageSlip_ModalTitle", alter: "قسيمة استلام العهدة وبطاقة القفص") : Language.get("LivePet_RestockSlip_ModalTitle", alter: "ملصق توجيه رفوف المخزون"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    Divider()

                    // Visual Barcode Simulation
                    VStack(spacing: 4) {
                        HStack(spacing: 3) {
                            ForEach(0..<26, id: \.self) { i in
                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(width: (i % 3 == 0) ? 3 : (i % 2 == 0 ? 1.5 : 2), height: 42)
                            }
                        }
                        Text(returnCase.caseNumber)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .padding(.vertical, 4)

                    Divider()

                    // Plain Details
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Text(Language.get("LivePet_Slip_TxnLabel", alter: "المعاملة:"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.primaryText)
                            Text(returnCase.transactionId)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 6) {
                            Text(Language.get("LivePet_Slip_CustodyLabel", alter: "موقع الاستلام:"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.primaryText)
                            Text(returnCase.receivingBranchId.isEmpty ? Language.get("LivePet_MainBranch", alter: "الفرع الرئيسي") : returnCase.receivingBranchId)
                                .font(returnCase.receivingBranchId.isEmpty ? AdminType.caption2 : .system(size: 11, design: .monospaced))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if categoryMode == .livePets {
                            ForEach(returnCase.units) { unit in
                                HStack(alignment: .center, spacing: 8) {
                                    HStack(spacing: 4) {
                                        Text(Language.get("LivePet_Slip_TagLabel", alter: "الحجل:"))
                                            .font(AdminType.caption2Bold)
                                            .foregroundColor(AdminSurface.secondaryText)
                                        Text(unit.ringTag)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(AdminSurface.primaryText)
                                    }

                                    Spacer(minLength: 8)

                                    Text(unit.conditionAtReturn.localizedTitle)
                                        .font(AdminType.caption2)
                                        .foregroundColor(AdminSurface.secondaryText)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            ForEach(merchandiseItems) { item in
                                HStack(alignment: .center, spacing: 8) {
                                    Text("\(item.name) (x\(item.quantity))")
                                        .font(AdminType.caption1Bold)
                                        .foregroundColor(AdminSurface.primaryText)
                                        .lineLimit(1)

                                    Spacer(minLength: 8)

                                    HStack(spacing: 4) {
                                        Text(Language.get("LivePet_Slip_BinLabel", alter: "الرف:"))
                                            .font(AdminType.caption2)
                                            .foregroundColor(AdminSurface.secondaryText)
                                        Text(item.shelfBin)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundColor(AdminSurface.hairline)
                )
                .padding(.horizontal, 24)

                Spacer()

                // Actions: Print via UIPrintInteractionController & Copy Plain
                HStack(spacing: 12) {
                    if Language.isRTL() {
                        printActionButton
                        copyActionButton
                    } else {
                        copyActionButton
                        printActionButton
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle(categoryMode == .livePets ? Language.get("LivePet_Tag_CageSlip", alter: "بطاقة القفص وقسيمة الاستلام") : Language.get("LivePet_Tag_RestockSlip", alter: "ملصق توجيه المخزون والرف"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        onDismiss()
                    }
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primary)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var printActionButton: some View {
        Button {
            triggerAirPrint()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "printer.fill")
                Text(categoryMode == .livePets ? Language.get("LivePet_PrintSlipAction", alter: "طباعة بطاقة القفص") : Language.get("LivePet_PrintRestockSlipAction", alter: "طباعة ملصق الرف"))
            }
            .font(AdminType.subheadlineBold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var copyActionButton: some View {
        Button {
            UIPasteboard.general.string = slipContentFormatted
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            hasCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                hasCopied = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                Text(hasCopied ? Language.get("Copied", alter: "تم النسخ") : Language.get("Copy", alter: "نسخ"))
            }
            .font(AdminType.subheadlineBold)
            .foregroundColor(AdminSurface.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func triggerAirPrint() {
        guard UIPrintInteractionController.isPrintingAvailable else { return }
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "ReturnSlip_\(returnCase.caseNumber)"
        printController.printInfo = printInfo

        let formatter = UIMarkupTextPrintFormatter(markupText: "<pre style='font-family: monospace; font-size: 14px;'>\(slipContentFormatted)</pre>")
        printController.printFormatter = formatter
        printController.present(animated: true, completionHandler: nil)
    }
}

