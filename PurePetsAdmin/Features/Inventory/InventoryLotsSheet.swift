//
//  InventoryLotsSheet.swift
//  PurePetsAdmin
//
//  Sheet for managing inventory lots, batches, and FEFO expiry tracking.
//

import SwiftUI
import UIKit


// MARK: - Filter & Sort Enums

public enum PPLotFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case nearExpiry
    case expired
    case depleted

    public var id: String { rawValue }

    public func title() -> String {
        switch self {
        case .all: return Language.get("Inventory_Filter_All", alter: "الكل")
        case .active: return Language.get("Inventory_Filter_Active", alter: "النشطة")
        case .nearExpiry: return Language.get("Inventory_Filter_Near_Expiry", alter: "وشك الانتهاء")
        case .expired: return Language.get("Inventory_Filter_Expired", alter: "المنتهية")
        case .depleted: return Language.get("Inventory_Filter_Depleted", alter: "النافذة")
        }
    }

    public func systemImage() -> String {
        switch self {
        case .all: return "tray.full.fill"
        case .active: return "checkmark.seal.fill"
        case .nearExpiry: return "clock.badge.exclamationmark.fill"
        case .expired: return "exclamationmark.octagon.fill"
        case .depleted: return "archivebox.fill"
        }
    }
}

public enum PPLotSort: String, CaseIterable, Identifiable {
    case fefo
    case quantity
    case newest

    public var id: String { rawValue }

    public func title() -> String {
        switch self {
        case .fefo: return Language.get("Inventory_Sort_FEFO", alter: "أولوية الصلاحية (FEFO)")
        case .quantity: return Language.get("Inventory_Sort_Quantity", alter: "الأعلى رصيداً")
        case .newest: return Language.get("Inventory_Sort_Newest", alter: "الأحدث إضافة")
        }
    }
}

// MARK: - Category-Defining Inventory Lots Studio

public struct InventoryLotsSheet: View {
    let item: PetAccessory
    let branchId: String
    var onLotsChanged: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var lotService = PPInventoryLotService.shared
    @State private var lots: [PPInventoryLot] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var showingAddLotSheet: Bool = false
    @State private var lotToEdit: PPInventoryLot? = nil
    @State private var isDeletingLot: Bool = false
    @State private var selectedFilter: PPLotFilter = .all
    @State private var selectedSort: PPLotSort = .fefo
    @State private var searchQuery: String = ""
    @State private var copiedLotNumber: String? = nil
    @State private var copiedTask: Task<Void, Never>? = nil

    public init(item: PetAccessory, branchId: String, onLotsChanged: (() -> Void)? = nil) {
        self.item = item
        self.branchId = branchId
        self.onLotsChanged = onLotsChanged
    }

    // MARK: - Computed Telemetry & Radar

    private var resolvedBranchID: String {
        let trimmed = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "all_branches" {
            return trimmed
        }
        if let active = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines), !active.isEmpty {
            return active
        }
        let resolved = item.resolvedBranchID()
        return !resolved.isEmpty ? resolved : (item.storeID ?? "main_store")
    }

    private var activeLots: [PPInventoryLot] {
        lots.filter { !$0.isExpired && $0.availableQuantity > 0 && $0.status.lowercased() != "depleted" }
    }

    private var earliestExpiringLot: PPInventoryLot? {
        activeLots.sorted { a, b in
            guard let aExp = a.expiryDate else { return false }
            guard let bExp = b.expiryDate else { return true }
            return aExp < bExp
        }.first
    }

    private var totalAvailableUnits: Int {
        lots.reduce(0) { $0 + $1.availableQuantity }
    }

    private var nearExpiryCount: Int {
        lots.filter { $0.isNearExpiry && $0.availableQuantity > 0 }.count
    }

    private var expiredCount: Int {
        lots.filter { $0.isExpired }.count
    }

    private var totalCostValuation: Double? {
        guard lots.allSatisfy({ $0.availableQuantity == 0 || $0.costPrice != nil }) else { return nil }
        return lots.reduce(0.0) { $0 + (Double($1.availableQuantity) * ($1.costPrice ?? 0)) }
    }

    private var totalRetailValuation: Double {
        let unitPrice = item.finalPrice.doubleValue > 0 ? item.finalPrice.doubleValue : item.price.doubleValue
        return Double(totalAvailableUnits) * max(0.0, unitPrice)
    }

    private var filteredLots: [PPInventoryLot] {
        var result = lots

        // Apply Status Filter
        switch selectedFilter {
        case .all:
            break
        case .active:
            result = result.filter { !$0.isExpired && $0.availableQuantity > 0 }
        case .nearExpiry:
            result = result.filter { $0.isNearExpiry && $0.availableQuantity > 0 }
        case .expired:
            result = result.filter { $0.isExpired }
        case .depleted:
            result = result.filter { $0.availableQuantity <= 0 || $0.status.lowercased() == "depleted" }
        }

        // Apply Search
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.lotNumber.lowercased().contains(query) ||
                $0.supplier.lowercased().contains(query) ||
                $0.notes.lowercased().contains(query)
            }
        }

        // Apply Sorting
        switch selectedSort {
        case .fefo:
            result.sort { a, b in
                guard let aExp = a.expiryDate else { return false }
                guard let bExp = b.expiryDate else { return true }
                return aExp < bExp
            }
        case .quantity:
            result.sort { $0.availableQuantity > $1.availableQuantity }
        case .newest:
            result.sort { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
        }

        return result
    }

    // MARK: - Main Body

    public var body: some View {
        GeometryReader { geometry in
            let isRegular = geometry.size.width >= 768

            ZStack {
                AdminSurface.background.ignoresSafeArea()

                if isRegular {
                    ipadCommandStudio(geometry: geometry)
                } else {
                    iphoneHandheldStudio(geometry: geometry)
                }
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .fullScreenCover(isPresented: $showingAddLotSheet) {
                AddLotSheet(item: item, branchId: resolvedBranchID) {
                    onLotsChanged?()
                    loadLots()
                }
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }
            .sheet(item: $lotToEdit) { lot in
                EditLotSheet(item: item, lot: lot, branchId: resolvedBranchID) {
                    onLotsChanged?()
                    loadLots()
                }
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }
            .overlay {
                if isDeletingLot {
                    FEFOMutationActionHUD(
                        title: Language.get("Deleting_Lot", alter: "جاري حذف التشغيلة بأمان..."),
                        subtitle: Language.get("Reverting_Branch_Catalog_Stock", alter: "استرجاع رصيد الوحدات إلى الفرع والكتالوج..."),
                        iconName: "trash.fill",
                        isDestructive: true
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .onAppear {
                loadLots()
            }
        }
    }

    // MARK: - iPhone Handheld Studio (Ergonomic Thumb-Zone)

    @ViewBuilder
    private func iphoneHandheldStudio(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Floating Glassmorphic Apex Bar
            iphoneApexBar

            if isLoading {
                FEFOLoadingHubView(item: item, isRegular: false)
            } else if let errorText = errorMessage, lots.isEmpty {
                errorDiagnosticStateView(errorText: errorText)
            } else if lots.isEmpty {
                emptyLotsSpecimenStage(isRegular: false)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Specimen Identity Runway
                        iphoneSpecimenIdentityCard

                        // Telemetry Radar Ribbon (3-Metrics)
                        telemetryRadarRibbon

                        // FEFO Dispatch Beacon Hero Card
                        if let beaconLot = earliestExpiringLot {
                            fefoDispatchBeaconCard(lot: beaconLot)
                        }

                        // Filter & Search Matrix
                        searchAndFilterToolbar

                        // Tactical Lots Stack
                        if filteredLots.isEmpty {
                            filterEmptyState
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredLots) { lot in
                                    tacticalLotCard(lot: lot, isRegular: false)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 12)
                    .padding(.bottom, 90)
                }
                .refreshable {
                    await refreshLotsAsync()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !isLoading {
                iphoneBottomActionDock
            }
        }
    }

    // MARK: - iPad Spatial Command Studio (Multi-Pane Telemetry Matrix)

    @ViewBuilder
    private func ipadCommandStudio(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // iPad Unified Top Bar
            ipadApexHeaderBar

            HStack(alignment: .top, spacing: 20) {
                // Left Command & Telemetry Tower (Width: 360)
                ipadCommandTower
                    .frame(width: 360)

                // Right Lots Matrix & Chrono-Canvas
                VStack(spacing: 16) {
                    searchAndFilterToolbar

                    if isLoading {
                        FEFOLoadingHubView(item: item, isRegular: true)
                    } else if let errorText = errorMessage, lots.isEmpty {
                        errorDiagnosticStateView(errorText: errorText)
                    } else if lots.isEmpty {
                        emptyLotsSpecimenStage(isRegular: true)
                    } else if filteredLots.isEmpty {
                        filterEmptyState
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 16) {
                                // Prominent FEFO Dispatch Priority Banner
                                if let beaconLot = earliestExpiringLot, selectedFilter == .all || selectedFilter == .active {
                                    fefoDispatchBeaconCard(lot: beaconLot)
                                }

                                // Adaptive Grid of Tactile Specimen Cards
                                let columns = [
                                    GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 14)
                                ]
                                LazyVGrid(columns: columns, spacing: 14) {
                                    ForEach(filteredLots) { lot in
                                        tacticalLotCard(lot: lot, isRegular: true)
                                    }
                                }
                            }
                            .padding(.bottom, 40)
                        }
                        .refreshable {
                            await refreshLotsAsync()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }

    // MARK: - iPad Command Tower Component

    private var ipadCommandTower: some View {
        VStack(spacing: 16) {
            // Hero Specimen Vitrine
            VStack(spacing: 14) {
                if let url = PetAccessory.firstImageURL(for: item) {
                    AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 320, height: 220)) {
                        Color.gray.opacity(0.12)
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(Font.custom("Beiruti-Bold", size: 18))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let sku = item.sku, !sku.isEmpty {
                            Text("SKU: \(sku)".normalizedEnglishDigits)
                                .font(AdminType.caption)
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        Spacer()
                        Text(item.inventoryDisplayPrice)
                            .font(Font.custom("Beiruti-Bold", size: 16))
                            .foregroundStyle(AdminSurface.primary)
                    }
                }
            }
            .padding(16)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))

            // Financial & Margin Intelligence Dossier
            VStack(alignment: .leading, spacing: 12) {
                Text(Language.get("Inventory_Financial_Valuation", alter: "التقييم المالي لتشغيلات الصنف"))
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Inventory_Total_Cost", alter: "تكلفة المخزون"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(totalCostValuation.map { PetAccessory.formatCurrency(NSNumber(value: $0)) } ?? Language.get("Inventory_CostUnavailable", alter: "التكلفة غير متاحة"))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(Language.get("Inventory_Total_Retail", alter: "القيمة البيعية"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(PetAccessory.formatCurrency(NSNumber(value: totalRetailValuation)))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                    }
                }

                if let totalCostValuation, totalCostValuation > 0 && totalRetailValuation > totalCostValuation {
                    let profit = totalRetailValuation - totalCostValuation
                    let margin = (profit / totalCostValuation) * 100.0
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 11, weight: .bold))
                        Text(String(format: Language.get("Inventory_Estimated_Margin", alter: "هامش ربح تقديري: +%@ (%.1f%%)"), PetAccessory.formatCurrency(NSNumber(value: profit)), margin))
                            .font(Font.custom("Beiruti-SemiBold", size: 12))
                    }
                    .foregroundStyle(Color(uiColor: .ppSuccess))
                    .padding(.top, 2)
                }
            }
            .padding(16)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))

            // Primary Intake Trigger
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingAddLotSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(Language.get("Inventory_Add_Lot_CTA", alter: "تسجيل تشغيلة واردة جديدة"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: AdminSurface.primary.opacity(0.25), radius: 10, y: 4)
            }

            Spacer()
        }
    }

    // MARK: - iPhone Apex Navigation Bar

    private var iphoneApexBar: some View {
        HStack(spacing: 12) {
            // Dismiss Button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: 36, height: 36)
                    .background(AdminSurface.control, in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Inventory_Lots_Title", alter: "تشغيلات الصنف وتتبع الصلاحية"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
                Text(verbatim: "\(item.name) • FEFO".normalizedEnglishDigits)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Quick Add Lot Jewel
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingAddLotSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text(Language.get("Add", alter: "إضافة"))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AdminSurface.primary, in: Capsule())
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - iPad Apex Header Bar

    private var ipadApexHeaderBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(Language.get("Inventory_Lots_Title", alter: "تشغيلات الصنف وتتبع الصلاحية (FEFO)"))
                        .font(Font.custom("Beiruti-Bold", size: 22))
                        .foregroundStyle(AdminSurface.primaryText)

                    // Branch Badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 6, height: 6)
                        Text(item.resolvedBranchName())
                            .font(Font.custom("Beiruti-SemiBold", size: 12))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AdminSurface.control, in: Capsule())
                }

                Text(Language.get("Inventory_Lots_Subtitle", alter: "محرك الصرف حسب تاريخ الانتهاء الأقرب أولاً لمنع التلف وحفظ جودة المنتجات"))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer()

            // Refresh & Close Buttons
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    loadLots()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AdminSurface.primaryText)
                        .padding(10)
                        .background(AdminSurface.control, in: Circle())
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                        .padding(10)
                        .background(AdminSurface.control, in: Circle())
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - iPhone Specimen Identity Card

    private var iphoneSpecimenIdentityCard: some View {
        HStack(spacing: 12) {
            if let url = PetAccessory.firstImageURL(for: item) {
                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 140, height: 140)) {
                    Color.gray.opacity(0.1)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let sku = item.sku, !sku.isEmpty {
                        Text("SKU: \(sku)".normalizedEnglishDigits)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                    Spacer()
                    Text(item.inventoryDisplayPrice)
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primary)
                }
            }
        }
        .padding(12)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
    }

    // MARK: - Telemetry Radar Ribbon (3-Metrics Glance)

    private var telemetryRadarRibbon: some View {
        HStack(spacing: 10) {
            // Total Lots
            telemetryPill(
                title: Language.get("Inventory_Lots_Count", alter: "التشغيلات"),
                value: "\(lots.count)".normalizedEnglishDigits,
                systemImage: "shippingbox.fill",
                tint: AdminSurface.primary
            )

            // Total Available Units
            telemetryPill(
                title: Language.get("Available", alter: "المتاح"),
                value: "\(totalAvailableUnits)".normalizedEnglishDigits,
                systemImage: "tray.2.fill",
                tint: Color(uiColor: .ppSuccess)
            )

            // Earliest Expiry / FEFO Urgency
            let urgencyText: String = {
                if let beacon = earliestExpiringLot, let days = beacon.daysUntilExpiry {
                    if days < 0 {
                        return Language.get("Expired", alter: "منتهية")
                    } else if days == 0 {
                        return Language.get("ExpiresToday", alter: "اليوم")
                    } else {
                        return "\(days) " + Language.get("Days_Short", alter: "يوم")
                    }
                }
                return "—"
            }()

            let urgencyColor: Color = {
                if let beacon = earliestExpiringLot {
                    return beacon.isExpired ? .red : (beacon.isNearExpiry ? .orange : Color(uiColor: .ppSuccess))
                }
                return AdminCommandInk.secondary
            }()

            telemetryPill(
                title: Language.get("FEFO_Next_Expiry", alter: "أقرب انتهاء"),
                value: urgencyText.normalizedEnglishDigits,
                systemImage: "hourglass",
                tint: urgencyColor
            )
        }
    }

    private func telemetryPill(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Font.custom("Beiruti-Regular", size: 10))
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(value)
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
    }

    // MARK: - FEFO Dispatch Beacon Hero Card

    private func fefoDispatchBeaconCard(lot: PPInventoryLot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Animated Beacon Pulsing Indicator
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .ppSuccess).opacity(0.20))
                        .frame(width: 24, height: 24)
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 10, height: 10)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("FEFO_Priority_Banner_Title", alter: "أولوية الصرف التلقائي الحالية (FEFO)"))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                    Text(Language.get("FEFO_Priority_Banner_Sub", alter: "يتم البيع والسحب أولاً من هذه التشغيلة نظراً لقرب تاريخ انتهائها"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()

                // Lot Number Pill
                Text(lot.lotNumber)
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                    .foregroundStyle(Color(uiColor: .ppSuccess))
            }

            Divider().background(Color(uiColor: .ppSuccess).opacity(0.20))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Available_Qty", alter: "الرصيد المتبقي بالتشغيلة"))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(verbatim: "\(lot.availableQuantity) / \(lot.initialQuantity)".normalizedEnglishDigits)
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Language.get("Expiry_Date", alter: "تاريخ الانتهاء"))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(verbatim: lot.expiryFormatted.normalizedEnglishDigits)
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(lot.isNearExpiry ? .orange : AdminSurface.primaryText)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .ppSuccess).opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Search & Filter Toolbar

    private var searchAndFilterToolbar: some View {
        VStack(spacing: 10) {
            // Search Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminSurface.secondaryText)
                TextField(Language.get("Search_Lots_Placeholder", alter: "البحث برقم التشغيلة، المورد..."), text: $searchQuery)
                    .font(AdminType.body)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))

            // Filter Chips Carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PPLotFilter.allCases) { filter in
                        let isSelected = selectedFilter == filter
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedFilter = filter
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: filter.systemImage())
                                    .font(.system(size: 11, weight: .bold))
                                Text(filter.title())
                                    .font(Font.custom("Beiruti-Bold", size: 12))
                            }
                            .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? AdminSurface.primary : AdminSurface.control,
                                in: Capsule()
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tactical Lot Specimen Card

    private func tacticalLotCard(lot: PPInventoryLot, isRegular: Bool) -> some View {
        let isCopied = copiedLotNumber == lot.lotNumber

        return VStack(alignment: .leading, spacing: 10) {
            // Header Row: Lot Number & Status Pill
            HStack(spacing: 8) {
                // Monospace Lot Badge with Copy Trigger
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    UIPasteboard.general.string = lot.lotNumber
                    copiedLotNumber = lot.lotNumber
                    copiedTask?.cancel()
                    copiedTask = Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copiedLotNumber = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "barcode.viewfinder")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isCopied ? Color(uiColor: .ppSuccess) : AdminSurface.primary)
                        Text(lot.lotNumber)
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AdminSurface.control, in: Capsule())
                }

                Spacer()

                // Status Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(lot.statusColor)
                        .frame(width: 6, height: 6)
                    Text(Language.get(lot.statusLocalizedKey, alter: lot.status))
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(lot.statusColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(lot.statusColor.opacity(0.10), in: Capsule())
            }

            // Expiry Date & Countdown Ribbon
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Expiry_Date", alter: "تاريخ الصلاحية"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                    HStack(spacing: 4) {
                        if lot.isExpired {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(uiColor: .ppError))
                        } else if lot.isNearExpiry {
                            Image(systemName: "clock.badge.exclamationmark.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(uiColor: .ppWarning))
                        }
                        Text(verbatim: lot.expiryFormatted.normalizedEnglishDigits)
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(lot.isExpired ? Color(uiColor: .ppError) : (lot.isNearExpiry ? Color(uiColor: .ppWarning) : AdminSurface.primaryText))
                    }
                }

                Spacer()

                if let days = lot.daysUntilExpiry {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Language.get("Countdown", alter: "المتبقي"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(verbatim: days < 0 ? String(format: Language.get("Expired_Days_Ago", alter: "منتهي منذ %@ يوم"), "\(-days)".normalizedEnglishDigits) : String(format: Language.get("Days_Left", alter: "%@ يوم متبقي"), "\(days)".normalizedEnglishDigits))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .foregroundStyle(days < 0 ? Color(uiColor: .ppError) : (days <= 30 ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess)))
                    }
                }
            }

            // Available Quantity Meter (Progress Bar)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Language.get("Available_Stock", alter: "الرصيد المتاح"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text(verbatim: "\(lot.availableQuantity) / \(lot.initialQuantity)".normalizedEnglishDigits)
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                GeometryReader { barGeo in
                    let ratio = lot.initialQuantity > 0 ? CGFloat(lot.availableQuantity) / CGFloat(lot.initialQuantity) : 0
                    ZStack(alignment: Language.isRTL() ? .trailing : .leading) {
                        Capsule()
                            .fill(AdminSurface.control)
                            .frame(height: 6)
                        Capsule()
                            .fill(lot.isExpired ? Color(uiColor: .ppError) : (lot.isNearExpiry ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess)))
                            .frame(width: max(0, min(barGeo.size.width, barGeo.size.width * ratio)), height: 6)
                    }
                }
                .frame(height: 6)
            }

            // Footer Metadata (Supplier, Cost Price)
            if !lot.supplier.isEmpty || lot.costPrice != nil {
                Divider().background(AdminSurface.hairline)

                HStack(spacing: 8) {
                    if !lot.supplier.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "building.2")
                                .font(.system(size: 10))
                            Text(lot.supplier)
                                .font(AdminType.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()

                    if let costPrice = lot.costPrice {
                        Text(String(format: Language.get("Cost_Per_Unit", alter: "التكلفة: %@"), PetAccessory.formatCurrency(NSNumber(value: costPrice))))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }

            // Action Buttons Row (Edit & Delete)
            Divider().background(AdminSurface.hairline)

            HStack(spacing: 8) {
                // Edit Lot Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    lotToEdit = lot
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                        Text(Language.get("Edit_Lot", alter: "تعديل التشغيلة"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AdminSurface.control, in: Capsule())
                    .foregroundStyle(AdminSurface.primary)
                }

                Spacer()

                // Delete Lot Button (Only shown if lot is completely untouched/unused)
                if lot.isPristineUnused {
                    Button {
                        promptDeleteConfirmation(for: lot)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(Language.get("Delete_Lot", alter: "حذف التشغيلة"))
                                .font(Font.custom("Beiruti-Bold", size: 12))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .ppError).opacity(0.12), in: Capsule())
                        .foregroundStyle(Color(uiColor: .ppError))
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 10))
                        Text(Language.get("Lot_In_Use", alter: "قيد الاستهلاك"))
                            .font(AdminType.caption2)
                    }
                    .foregroundStyle(AdminSurface.secondaryText)
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(lot.isExpired ? Color(uiColor: .ppError).opacity(0.4) : AdminSurface.hairline, lineWidth: lot.isExpired ? 1.2 : 0.8)
        )
        .contextMenu {
            Button {
                lotToEdit = lot
            } label: {
                Label(Language.get("Edit_Lot_And_Expiry", alter: "تعديل الكمية والصلاحية"), systemImage: "pencil")
            }

            if lot.isPristineUnused {
                Button(role: .destructive) {
                    promptDeleteConfirmation(for: lot)
                } label: {
                    Label(Language.get("Delete_Lot", alter: "حذف التشغيلة"), systemImage: "trash")
                }
            }

            Button {
                UIPasteboard.general.string = lot.lotNumber
            } label: {
                Label(Language.get("Copy_Lot_Number", alter: "نسخ رقم التشغيلة"), systemImage: "doc.on.doc")
            }

            if !lot.notes.isEmpty {
                Button {
                    PPAlertHelper.showInfo(
                        in: nil,
                        title: Language.get("Lot_Notes", alter: "ملاحظات التشغيلة"),
                        subtitle: lot.notes
                    )
                } label: {
                    Label(Language.get("View_Notes", alter: "عرض الملاحظات"), systemImage: "note.text")
                }
            }
        }
    }

    // MARK: - iPhone Bottom Action Dock

    private var iphoneBottomActionDock: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [AdminSurface.background.opacity(0.0), AdminSurface.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingAddLotSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(Language.get("Inventory_Add_Lot_Button", alter: "تسجيل تشغيلة واردة جديدة (FEFO)"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: AdminSurface.primary.opacity(0.3), radius: 12, y: 4)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.bottom, 16)
            .background(AdminSurface.background)
        }
    }

    // MARK: - Empty & Error State Views

    private func emptyLotsSpecimenStage(isRegular: Bool) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.08))
                    .frame(width: isRegular ? 110 : 88, height: isRegular ? 110 : 88)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: isRegular ? 44 : 36))
                    .foregroundStyle(AdminSurface.primary)
            }

            VStack(spacing: 6) {
                Text(Language.get("Inventory_Lots_Empty_Title", alter: "لا توجد تشغيلات مسجلة لهذا الصنف"))
                    .font(Font.custom("Beiruti-Bold", size: isRegular ? 20 : 17))
                    .foregroundStyle(AdminSurface.primaryText)

                Text(Language.get("Inventory_Lots_Empty_Sub", alter: "تتيح لك التشغيلات (FEFO) تتبع تواريخ انتهاء الصلاحية بدقة، وضمان سحب المخزون الأقرب للانتهاء أولاً أثناء عمليات البيع والشحن."))
                    .font(Font.custom("Beiruti-Regular", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingAddLotSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text(Language.get("Inventory_Add_First_Lot", alter: "تسجيل أول تشغيلة"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(AdminSurface.primary, in: Capsule())
                .shadow(color: AdminSurface.primary.opacity(0.25), radius: 8, y: 3)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filterEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(AdminSurface.secondaryText)
            Text(Language.get("No_Matching_Lots", alter: "لا توجد تشغيلات مطابقة للبحث أو التصفية"))
                .font(AdminType.subheadline)
                .foregroundStyle(AdminSurface.secondaryText)
            Button(Language.get("Clear_Filters", alter: "إعادة ضبط التصفية")) {
                searchQuery = ""
                selectedFilter = .all
            }
            .font(AdminType.captionBold)
            .foregroundStyle(AdminSurface.primary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    private func errorDiagnosticStateView(errorText: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .ppWarning).opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(uiColor: .ppWarning))
            }

            VStack(spacing: 6) {
                Text(Language.get("Inventory_Lots_Sync_Notice", alter: "تعذر تحميل التشغيلات"))
                    .font(Font.custom("Beiruti-Bold", size: 17))
                    .foregroundStyle(AdminSurface.primaryText)

                Text(Language.get("Inventory_Lots_Sync_Notice_Sub", alter: "تعذر الوصول إلى خدمة التشغيلات الآمنة. لم تتأثر بيانات المخزون؛ أعد المحاولة، وإذا استمرت المشكلة فتحقق من الاتصال والصلاحيات."))
                    .font(Font.custom("Beiruti-Regular", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                #if DEBUG
                if !errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(errorText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .frame(maxWidth: 420)
                }
                #endif
            }

            HStack(spacing: 12) {
                Button {
                    loadLots()
                } label: {
                    Label(Language.get("Retry", alter: "إعادة المحاولة"), systemImage: "arrow.clockwise")
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AdminSurface.control, in: Capsule())
                }

                Button {
                    showingAddLotSheet = true
                } label: {
                    Label(Language.get("Add_Lot", alter: "إضافة تشغيلة"), systemImage: "plus")
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AdminSurface.primary, in: Capsule())
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Category-Defining PPAlert Confirmation

    private func promptDeleteConfirmation(for lot: PPInventoryLot) {
        guard lot.isPristineUnused else {
            PPAlertHelper.showError(
                in: nil,
                title: Language.get("Cannot_Delete_Lot", alter: "لا يمكن حذف التشغيلة"),
                subtitle: Language.get("Lot_Already_Used_Error", alter: "تم استخدام جزء من هذه التشغيلة بالفعل، لا يمكن حذفها ولكن يمكنك تعديل رصيدها.")
            )
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let title = Language.get("Delete_Lot_Title", alter: "حذف التشغيلة")
        let rawFormat = Language.get("Delete_Lot_Confirmation", alter: "هل أنت متأكد من حذف التشغيلة '%@'؟\nسيتم استرجاع رصيدها بالكامل (%@ وحدة) من رصيد الفرع والكتالوج.")
        let message = String(format: rawFormat, lot.lotNumber, "\(lot.initialQuantity)".normalizedEnglishDigits)

        PPAlertHelper.showDestructiveConfirmation(
            in: nil,
            title: title,
            subtitle: message,
            confirmButton: Language.get("Delete", alter: "حذف"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "trash.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                executeLotDeletion(lot: lot)
            },
            cancelBlock: nil
        )
    }

    // MARK: - Data Operations

    private func loadLots() {
        isLoading = true
        errorMessage = nil

        Task {
            await refreshLotsAsync()
        }
    }

    private func refreshLotsAsync() async {
        do {
            let fetched = try await lotService.fetchLots(
                branchId: resolvedBranchID,
                productId: item.accessoryID,
                includeDepleted: true,
                includeExpired: true
            )
            await MainActor.run {
                self.lots = fetched
                self.isLoading = false
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func executeLotDeletion(lot: PPInventoryLot) {
        guard lot.isPristineUnused else {
            PPAlertHelper.showError(
                in: nil,
                title: Language.get("Cannot_Delete_Lot", alter: "لا يمكن حذف التشغيلة"),
                subtitle: Language.get("Lot_Already_Used_Error", alter: "تم استخدام جزء من هذه التشغيلة بالفعل، لا يمكن حذفها ولكن يمكنك تعديل رصيدها.")
            )
            return
        }

        isDeletingLot = true
        Task {
            do {
                try await lotService.deleteLot(
                    branchId: resolvedBranchID,
                    productId: item.accessoryID,
                    lotId: lot.lotId,
                    notes: "Deleted from Admin app"
                )
                await MainActor.run {
                    isDeletingLot = false
                    lots.removeAll { $0.id == lot.id || $0.lotId == lot.lotId }
                    onLotsChanged?()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    PPAlertHelper.showSuccess(
                        in: nil,
                        title: Language.get("Lot_Deleted_Success", alter: "تم حذف التشغيلة بنجاح"),
                        subtitle: String(format: Language.get("Lot_Deleted_Subtitle", alter: "تم خصم %@ وحدة من رصيد الفرع والكتالوج."), "\(lot.initialQuantity)".normalizedEnglishDigits)
                    )
                }
            } catch {
                await MainActor.run {
                    isDeletingLot = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    PPAlertHelper.showError(
                        in: nil,
                        title: Language.get("Error", alter: "خطأ"),
                        subtitle: PPBranchInventoryErrorHelper.localizedMessage(for: error)
                    )
                }
            }
}

// MARK: - Category-Defining FEFO Telemetry Loading Hub View

private struct FEFOLoadingHubView: View {
    let item: PetAccessory
    var isRegular: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phaseIndex: Int = 0
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var shimmerOffset: CGFloat = -1.2
    @State private var tickerTask: Task<Void, Never>? = nil

    private var statusPhases: [(title: String, icon: String)] {
        [
            (Language.get("Loading_Scanning_Lots", alter: "جاري فحص تشغيلات الصنف ومصفوفة الصلاحية..."), "calendar.badge.clock"),
            (Language.get("Loading_Calculating_FEFO", alter: "ترتيب أولويات الصرف التلقائي الذكي (FEFO)..."), "arrow.triangle.swap"),
            (Language.get("Loading_Syncing_Inventory", alter: "مزامنة أرصدة الكتالوج وقيود الفرع..."), "shippingbox.and.arrow.backward.fill")
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            // 1. Specimen Identity Scaffold
            identitySkeletonBar

            // 2. Central Orbital Chrono-Radar Hub
            orbitalChronoRadarCore

            // 3. Shimmering Telemetry & Lots Wireframe
            telemetryAndLotsWireframe
        }
        .padding(.horizontal, isRegular ? 0 : AdminSpacing.screenMargin)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            startAnimationPipelines()
        }
        .onDisappear {
            tickerTask?.cancel()
        }
    }

    // MARK: - Specimen Identity Skeleton Bar
    private var identitySkeletonBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AdminSurface.surface)
                    .frame(width: 44, height: 44)

                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary.opacity(0.4))
            }

            VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AdminSurface.surface)
                    .frame(width: 140, height: 14)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(AdminSurface.surface.opacity(0.6))
                    .frame(width: 90, height: 10)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AdminSurface.surface.opacity(0.7))
                .frame(width: 72, height: 28)
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
        .shimmerEffect(offset: shimmerOffset)
    }

    // MARK: - Central Orbital Chrono-Radar Hub
    private var orbitalChronoRadarCore: some View {
        VStack(spacing: 14) {
            ZStack {
                // Expanding Ambient Aura
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AdminSurface.primary.opacity(0.18),
                                Color(uiColor: .ppWarning).opacity(0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 75
                        )
                    )
                    .frame(width: 150, height: 150)
                    .scaleEffect(reduceMotion ? 1.0 : pulseScale)

                // Concentric Pulse Rings
                ForEach(0..<2, id: \.self) { ring in
                    Circle()
                        .strokeBorder(
                            AdminSurface.primary.opacity(0.12 - Double(ring) * 0.05),
                            lineWidth: 1.2
                        )
                        .frame(width: CGFloat(90 + ring * 30), height: CGFloat(90 + ring * 30))
                        .scaleEffect(reduceMotion ? 1.0 : (pulseScale + CGFloat(ring) * 0.05))
                }

                // Dynamic Kinetic Orbital Track
                Circle()
                    .trim(from: 0.08, to: 0.82)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                AdminSurface.primary,
                                Color(uiColor: .ppWarning),
                                AdminSurface.primary.opacity(0.15)
                            ]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round, dash: [8, 4])
                    )
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(reduceMotion ? 45 : rotationAngle))

                // Inner Glass Core Sphere
                ZStack {
                    Circle()
                        .fill(AdminSurface.surface)
                        .frame(width: 58, height: 58)
                        .shadow(color: AdminSurface.primary.opacity(0.18), radius: 12, x: 0, y: 4)

                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.4), AdminSurface.primary.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                        .frame(width: 58, height: 58)

                    // Core Symbol: FEFO Chrono Icon
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AdminSurface.primary, Color(uiColor: .ppWarning)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(reduceMotion ? 0 : -rotationAngle * 0.5))
                }
            }
            .frame(height: 120)

            // Dynamic Live Operational Ticker
            VStack(spacing: 8) {
                let currentPhase = phaseIndex < statusPhases.count ? statusPhases[phaseIndex] : statusPhases[0]
                HStack(spacing: 6) {
                    Image(systemName: currentPhase.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)

                    Text(currentPhase.title)
                        .font(Font.custom("Beiruti-Bold", size: 13.5))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.3), value: phaseIndex)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(AdminSurface.surface, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(AdminSurface.primary.opacity(0.2), lineWidth: 0.8)
                )

                // Micro Phase Stepper Dots
                HStack(spacing: 5) {
                    ForEach(0..<statusPhases.count, id: \.self) { idx in
                        Capsule()
                            .fill(idx == phaseIndex ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.25))
                            .frame(width: idx == phaseIndex ? 16 : 5, height: 4)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phaseIndex)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AdminSurface.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Shimmering Telemetry & Lots Wireframe
    private var telemetryAndLotsWireframe: some View {
        VStack(spacing: 12) {
            // 3-Metric Telemetry Ribbon Placeholder
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AdminSurface.surface.opacity(0.7))
                            .frame(width: 48, height: 9)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(AdminSurface.surface)
                            .frame(width: 32, height: 16)
                    }
                    .frame(maxWidth: .infinity, alignment: Language.isRTL() ? .trailing : .leading)
                    .padding(12)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.6)
                    )
                }
            }
            .shimmerEffect(offset: shimmerOffset)

            // Tactical Lot Card Skeletons
            ForEach(0..<2, id: \.self) { cardIdx in
                VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 10) {
                    HStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(AdminSurface.surface.opacity(0.8))
                            .frame(width: 120, height: 14)
                        Spacer()
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AdminSurface.surface.opacity(0.6))
                            .frame(width: 55, height: 20)
                    }

                    HStack(spacing: 14) {
                        VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(AdminSurface.surface.opacity(0.6))
                                .frame(width: 60, height: 8)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(AdminSurface.surface)
                                .frame(width: 80, height: 12)
                        }
                        Spacer()
                        VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(AdminSurface.surface.opacity(0.6))
                                .frame(width: 50, height: 8)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(AdminSurface.surface)
                                .frame(width: 40, height: 12)
                        }
                    }

                    // Progress bar placeholder
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(AdminSurface.surface.opacity(0.5))
                        .frame(height: 6)

                    HStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AdminSurface.surface.opacity(0.7))
                            .frame(width: 80, height: 24)
                        Spacer()
                        if cardIdx == 0 {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AdminSurface.surface.opacity(0.7))
                                .frame(width: 70, height: 24)
                        }
                    }
                }
                .padding(14)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                )
                .shimmerEffect(offset: shimmerOffset)
            }
        }
    }

    private func startAnimationPipelines() {
        guard !reduceMotion else { return }

        withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }

        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulseScale = 1.08
        }

        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            shimmerOffset = 1.8
        }

        tickerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                if !Task.isCancelled {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        phaseIndex = (phaseIndex + 1) % max(1, statusPhases.count)
                    }
                }
            }
        }
    }
}

// MARK: - Category-Defining Kinetic Mutation Action HUD

private struct FEFOMutationActionHUD: View {
    let title: String
    let subtitle: String?
    let iconName: String
    var isDestructive: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Tactile Ambient Blur Dimming
            Color.black.opacity(0.38)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            // Continuous Elevated Capsule
            VStack(spacing: 16) {
                // Kinetic Dual-Ring Core
                ZStack {
                    // Outer Translucent Guide Ring
                    Circle()
                        .strokeBorder(
                            (isDestructive ? Color(uiColor: .ppError) : AdminSurface.primary).opacity(0.15),
                            lineWidth: 3.5
                        )
                        .frame(width: 58, height: 58)

                    // Kinetic Rotating Light Particle Segment
                    Circle()
                        .trim(from: 0.1, to: 0.75)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    isDestructive ? Color(uiColor: .ppError) : AdminSurface.primary,
                                    (isDestructive ? Color(uiColor: .ppError) : AdminSurface.primary).opacity(0.1)
                                ]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .frame(width: 58, height: 58)
                        .rotationEffect(.degrees(reduceMotion ? 0 : rotation))

                    // Center Animated Glyph
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isDestructive ? Color(uiColor: .ppError) : AdminSurface.primary)
                        .scaleEffect(reduceMotion ? 1.0 : pulse)
                }
                .frame(width: 64, height: 64)

                // Contextual Typography
                VStack(spacing: 4) {
                    Text(title)
                        .font(Font.custom("Beiruti-Bold", size: 17))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.center)

                    if let sub = subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(Font.custom("Beiruti-Regular", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AdminSurface.surface)
                    .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                (isDestructive ? Color(uiColor: .ppError) : AdminSurface.primary).opacity(0.35),
                                AdminSurface.hairline
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .padding(.horizontal, 36)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = 1.14
            }
        }
    }
}

// MARK: - Shimmer View Modifier

private struct PPShimmerModifier: ViewModifier {
    var offset: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.18),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.7)
                    .offset(x: geo.size.width * offset)
                }
                .mask(content)
            )
    }
}

extension View {
    fileprivate func shimmerEffect(offset: CGFloat) -> some View {
        self.modifier(PPShimmerModifier(offset: offset))
    }
}

// MARK: - Add Lot Sheet (NextGen V6 Dual-Architecture Studio)

private struct AddLotSheet: View {
    let item: PetAccessory
    let branchId: String
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var lotNumber: String = ""
    @State private var quantity: Int = 10
    @State private var costPrice: String = ""
    @State private var receiptCommandId = UUID().uuidString
    @State private var receiptFingerprint = ""
    @State private var validFromDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var expiryDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date().addingTimeInterval(86400 * 180)
    @State private var supplier: String = ""
    @State private var notes: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    @State private var selectedHorizon: ExpiryHorizon? = .sixMonths
    @State private var isValidFromCalendarExpanded: Bool = false
    @State private var isCustomCalendarExpanded: Bool = false
    @State private var isManualQuantityEditing: Bool = false
    @State private var manualQuantityInput: String = "10"
    @State private var showTactileQuantityPad: Bool = false
    @State private var showTactileCostPad: Bool = false

    private var isIPadLayout: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }

    private var daysUntilExpiry: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
    }

    private var fefoLevel: FEFOSafetyLevel {
        FEFOSafetyLevel.resolve(days: daysUntilExpiry)
    }

    private var validFromDateFormatted: String {
        formattedDate(validFromDate)
    }

    private var expiryDateFormatted: String {
        formattedDate(expiryDate)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var latestValidFromDate: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var minimumExpiryDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let validityStart = calendar.startOfDay(for: validFromDate)
        let baseline = max(today, validityStart)
        return calendar.date(byAdding: .day, value: 1, to: baseline) ?? baseline.addingTimeInterval(86_400)
    }

    private var unitCostDouble: Double {
        Double(costPrice.normalizedEnglishDigits.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "٫", with: ".")) ?? 0.0
    }

    private var totalBatchCost: Double {
        Double(quantity) * unitCostDouble
    }

    private var retailPriceDouble: Double {
        let price = item.price.doubleValue > 0 ? item.price.doubleValue : item.finalPrice.doubleValue
        return max(0.0, price)
    }

    private var projectedMarginPercent: Double? {
        guard retailPriceDouble > 0, unitCostDouble > 0 else { return nil }
        let margin = (retailPriceDouble - unitCostDouble) / retailPriceDouble * 100.0
        return max(0, margin)
    }

    private var canSubmit: Bool {
        !lotNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        quantity > 0 &&
        unitCostDouble.isFinite && unitCostDouble >= 0 &&
        (costPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(costPrice.normalizedEnglishDigits.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "٫", with: ".")) != nil) &&
        validFromDate <= Date() &&
        expiryDate >= minimumExpiryDate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                if isIPadLayout {
                    // iPad 2-Column Split Studio
                    HStack(alignment: .top, spacing: AdminSpacing.lg) {
                        // Left Column (42%): Telemetry & Holographic Pass Cockpit
                        ScrollView {
                            IPadBatchLaboratoryCockpit(
                                item: item,
                                lotNumber: lotNumber,
                                quantity: quantity,
                                unitCost: unitCostDouble,
                                totalCost: totalBatchCost,
                                retailPrice: retailPriceDouble,
                                margin: projectedMarginPercent,
                                expiryFormatted: expiryDateFormatted,
                                daysRemaining: daysUntilExpiry,
                                fefoLevel: fefoLevel,
                                onGenerateCode: { generateSmartLotCode() }
                            )
                            .padding(.top, AdminSpacing.md)
                            .padding(.bottom, AdminSpacing.xl)
                        }
                        .frame(maxWidth: .infinity)

                        // Vertical Divider
                        Rectangle()
                            .fill(AdminSurface.hairline)
                            .frame(width: 1)
                            .ignoresSafeArea(edges: .vertical)

                        // Right Column (58%): Precision Intake Deck
                        ScrollView {
                            VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                                intakeFormFields
                                submitButton
                                    .padding(.top, AdminSpacing.sm)
                            }
                            .padding(AdminSpacing.lg)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, AdminSpacing.md)
                } else {
                    // iPhone Fluid Tactical Flow
                    ScrollView {
                        VStack(alignment: .leading, spacing: AdminSpacing.base) {
                            // Hero Batch Passport Card
                            BatchPassportCard(
                                item: item,
                                lotNumber: lotNumber,
                                quantity: quantity,
                                unitCost: unitCostDouble,
                                totalCost: totalBatchCost,
                                expiryFormatted: expiryDateFormatted,
                                daysRemaining: daysUntilExpiry,
                                fefoLevel: fefoLevel,
                                onGenerateCode: { generateSmartLotCode() }
                            )
                            .padding(.top, AdminSpacing.xs)

                            intakeFormFields
                        }
                        .padding(AdminSpacing.screenMargin)
                        .padding(.bottom, 90) // Room for sticky bottom bar
                    }
                    .safeAreaInset(edge: .bottom) {
                        iphoneFloatingActionBar
                    }
                }
            }
            .navigationTitle(Language.get("Inventory_Add_Lot_Title", alter: "إضافة تشغيلة جديدة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .foregroundColor(AdminSurface.primary)
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        generateSmartLotCode()
                    } label: {
                        Label(Language.get("Auto_Generate", alter: "توليد ذكي"), systemImage: "sparkles")
                            .font(AdminType.caption1Bold)
                            .foregroundColor(AdminSurface.primary)
                    }
                    .keyboardShortcut("g", modifiers: .command)
                }
            }
        }
        .onAppear {
            if let defaultCost = item.costPrice?.doubleValue, defaultCost > 0, costPrice.isEmpty {
                costPrice = String(format: "%.2f", defaultCost)
            }
            if lotNumber.isEmpty {
                generateSmartLotCode()
            }
        }
        .tactileQuantityPad(
            isPresented: $showTactileQuantityPad,
            title: Language.get("Inventory_Lot_Initial_Qty", alter: "كمية الدفعة الواردة"),
            currentQuantity: quantity,
            referenceQuantity: quantity,
            specimen: PPTactileSpecimenInfo(
                title: item.name,
                imageURL: PetAccessory.firstImageURL(for: item),
                sku: item.sku,
                unitCost: unitCostDouble
            )
        ) { newQty in
            quantity = max(1, newQty)
            manualQuantityInput = "\(quantity)"
        }
        .tactilePricePad(
            isPresented: $showTactileCostPad,
            title: Language.get("Cost_Price", alter: "سعر التكلفة للوحدة"),
            currentPrice: unitCostDouble,
            referencePrice: item.costPrice?.doubleValue,
            specimen: PPTactileSpecimenInfo(
                title: item.name,
                imageURL: PetAccessory.firstImageURL(for: item),
                sku: item.sku
            )
        ) { newCost in
            costPrice = String(format: "%.2f", newCost)
        }
    }

    // MARK: - Subviews & Form Fields

    @ViewBuilder
    private var intakeFormFields: some View {
        // Section 1: Lot Number & Smart Generator
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Language.get("Inventory_Lot_Number", alter: "رقم التشغيلة / الدفعة *"))
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Button {
                    generateSmartLotCode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12))
                        Text(Language.get("Auto_Generate_Short", alter: "توليد تلقائي"))
                            .font(AdminType.caption1Bold)
                    }
                    .foregroundColor(AdminSurface.primary)
                }
            }

            HStack(spacing: 8) {
                TextField("e.g. LOT-2026-A1", text: $lotNumber)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)

                if !lotNumber.isEmpty {
                    Button {
                        lotNumber = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                    }
                }
            }
            .padding(AdminSpacing.md)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
        }

        // Section 2: Intake Quantity & Case Multipliers
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Language.get("Quantity", alter: "الكمية الواردة *"))
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Text(Language.isRTL() ? "المخزون الحالي: \(item.pos_branchStock(activeBranch: branchId)) وحدة" : "Current Stock: \(item.pos_branchStock(activeBranch: branchId)) units")
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            // Primary Tactile Stepper
            HStack(spacing: AdminSpacing.md) {
                Button {
                    if quantity > 1 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        quantity -= 1
                        manualQuantityInput = "\(quantity)"
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(quantity > 1 ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.25))
                }
                .disabled(quantity <= 1)

                Spacer()

                if isManualQuantityEditing {
                    TextField("10", text: $manualQuantityInput)
                        .keyboardType(.numberPad)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(width: 80)
                        .onSubmit {
                            if let parsed = Int(manualQuantityInput), parsed > 0 {
                                quantity = parsed
                            }
                            isManualQuantityEditing = false
                        }
                } else {
                    VStack(spacing: 2) {
                        Text(verbatim: "\(quantity)".normalizedEnglishDigits)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("Tap_To_Type", alter: "انقر للإدخال الرقمي"))
                            .font(.system(size: 10))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.8))
                    }
                    .frame(minWidth: 70)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showTactileQuantityPad = true
                    }
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    quantity += 1
                    manualQuantityInput = "\(quantity)"
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(AdminSurface.primary)
                }
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, 10)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

            // Case Multipliers Bar
            HStack(spacing: 6) {
                ForEach([6, 12, 24, 50, 100], id: \.self) { addAmount in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        quantity += addAmount
                        manualQuantityInput = "\(quantity)"
                    } label: {
                        Text("+\(addAmount)")
                            .font(AdminType.caption1Bold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AdminSurface.control, in: Capsule())
                            .foregroundColor(AdminSurface.primaryText)
                    }
                }
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    quantity = 10
                    manualQuantityInput = "10"
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(6)
                        .background(AdminSurface.control, in: Circle())
                }
            }
        }

        // Section 3: Validity Start
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("Inventory_Lot_Valid_From", alter: "صالح من *"))
                .font(AdminType.subheadlineBold)
                .foregroundColor(AdminSurface.primaryText)

            // Target Date Display Strip (Identical font & styling to Expiry Date)
            HStack {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 15))
                    .foregroundColor(AdminSurface.primary)
                Text(verbatim: validFromDateFormatted.normalizedEnglishDigits)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Image(systemName: isValidFromCalendarExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(AdminSpacing.md)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(AdminAnimation.standard) {
                    isValidFromCalendarExpanded.toggle()
                }
            }

            // Expandable Graphical Calendar
            if isValidFromCalendarExpanded {
                VStack {
                    DatePicker(
                        "",
                        selection: $validFromDate,
                        in: ...latestValidFromDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding(AdminSpacing.sm)
                    .accentColor(AdminSurface.primary)
                }
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: validFromDate) { _, newValue in
            guard selectedHorizon != .custom, let selectedHorizon else { return }
            if let recalculatedExpiry = selectedHorizon.calculateDate(from: newValue) {
                expiryDate = max(recalculatedExpiry, minimumExpiryDate)
            }
        }

        // Section 4: Shelf-Life Horizon & Expiry Date
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Language.get("Expiry_Date", alter: "تاريخ انتهاء الصلاحية *"))
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                // Days countdown chip
                HStack(spacing: 4) {
                    Circle()
                        .fill(fefoLevel.color)
                        .frame(width: 6, height: 6)
                    Text(fefoLevel.titleArabic)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(fefoLevel.color)
                }
            }

            // Quick Horizon Selector Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ExpiryHorizon.allCases) { horizon in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedHorizon = horizon
                            if horizon == .custom {
                                withAnimation(AdminAnimation.standard) {
                                    isCustomCalendarExpanded = true
                                }
                            } else if let newDate = horizon.calculateDate(from: validFromDate) {
                                withAnimation(AdminAnimation.standard) {
                                    expiryDate = newDate
                                    isCustomCalendarExpanded = false
                                }
                            }
                        } label: {
                            Text(horizon.title)
                                .font(AdminType.caption1Bold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    selectedHorizon == horizon
                                        ? AdminSurface.primary
                                        : AdminSurface.control,
                                    in: Capsule()
                                )
                                .foregroundColor(
                                    selectedHorizon == horizon
                                        ? .white
                                        : AdminSurface.primaryText
                                )
                        }
                    }
                }
            }

            // Target Date Display Strip
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 15))
                    .foregroundColor(AdminSurface.primary)
                Text(verbatim: expiryDateFormatted.normalizedEnglishDigits)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                if daysUntilExpiry > 0 {
                    Text(String(format: Language.get("Inventory_Lot_Days_Remaining", alter: "متبقي %d يوم"), daysUntilExpiry))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                } else {
                    Text(Language.get("Inventory_Lot_Expires_Today", alter: "تاريخ غير مسموح!"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.crimson)
                }
            }
            .padding(AdminSpacing.md)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
            .onTapGesture {
                withAnimation(AdminAnimation.standard) {
                    isCustomCalendarExpanded.toggle()
                    if isCustomCalendarExpanded {
                        selectedHorizon = .custom
                    }
                }
            }

            // Expandable Graphical Calendar
            if isCustomCalendarExpanded {
                VStack {
                    DatePicker(
                        "",
                        selection: $expiryDate,
                        in: minimumExpiryDate...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding(AdminSpacing.sm)
                    .accentColor(AdminSurface.primary)
                }
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }

        // Section 5: Cost Valuation & Supplier
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            // Cost Price
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Language.get("Cost_Price", alter: "سعر التكلفة للوحدة (ر.ق)"))
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showTactileCostPad = true
                    } label: {
                        Image(systemName: "circle.grid.3x3.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AdminSurface.primary)
                    }

                    Spacer()
                    if let defaultCost = item.costPrice?.doubleValue, defaultCost > 0 {
                        Button {
                            costPrice = String(format: "%.2f", defaultCost)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text("السعر السابق: \(String(format: "%.2f", defaultCost)) ر.ق")
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.primary)
                        }
                    }
                }

                HStack {
                    TextField("0.00", text: $costPrice)
                        .font(AdminType.body)
                        .keyboardType(.decimalPad)

                    if unitCostDouble > 0 {
                        Text(String(format: "إجمالي الدفعة: %.2f ر.ق", totalBatchCost))
                            .font(AdminType.caption1Bold)
                            .foregroundColor(AdminSurface.emerald)
                    }
                }
                .padding(AdminSpacing.md)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
            }

            // Supplier
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Supplier", alter: "المورّد"))
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                TextField(Language.get("Supplier_Placeholder", alter: "اسم المورد أو الشركة"), text: $supplier)
                    .font(AdminType.body)
                    .padding(AdminSpacing.md)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                    .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
            }

            // Internal Notes
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Inventory_Lot_Notes", alter: "ملاحظات إضافية"))
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                TextField(Language.get("Inventory_Lot_Enter_Notes", alter: "ملاحظات التشغيلة أو الشحنة..."), text: $notes)
                    .font(AdminType.body)
                    .padding(AdminSpacing.md)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                    .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
            }
        }

        if let error = errorMessage {
            AdminErrorBanner(message: error, retry: nil)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var submitButton: some View {
        Button {
            submitLot()
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView().tint(.white).padding(.trailing, 4)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(Language.get("Inventory_Save_Lot", alter: "اعتماد التشغيلة وتحديث المخزون"))
                    .font(AdminType.calloutBold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                canSubmit
                    ? AdminSurface.primary
                    : AdminSurface.primary.opacity(0.35),
                in: RoundedRectangle(cornerRadius: AdminRadius.card)
            )
            .foregroundColor(.white)
        }
        .disabled(!canSubmit || isSubmitting)
        .keyboardShortcut("s", modifiers: .command)
    }

    @ViewBuilder
    private var iphoneFloatingActionBar: some View {
        VStack(spacing: 8) {
            submitButton
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            AdminSurface.background.opacity(0.88)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    // MARK: - Actions

    private func generateSmartLotCode() {
        let year = Calendar.current.component(.year, from: Date())
        let pool = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let suffix = String((0..<3).compactMap { _ in pool.randomElement() })
        lotNumber = "LOT-\(year)-\(suffix)"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func submitLot() {
        guard canSubmit, !isSubmitting else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isSubmitting = true
        errorMessage = nil

        let cost = costPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Optional(unitCostDouble)
        let clampedValidFrom = min(validFromDate, Date())
        let fingerprint = [branchId, item.accessoryID, lotNumber, String(quantity), cost.map { String($0) } ?? "unknown", String(clampedValidFrom.timeIntervalSince1970), String(expiryDate.timeIntervalSince1970), supplier, notes].joined(separator: "\u{0}")
        if receiptFingerprint != fingerprint {
            receiptCommandId = UUID().uuidString
            receiptFingerprint = fingerprint
        }

        Task { @MainActor in
            do {
                _ = try await PPInventoryLotService.shared.createLot(
                    branchId: branchId,
                    productId: item.accessoryID,
                    lotNumber: lotNumber,
                    initialQuantity: quantity,
                    costPrice: cost,
                    validFrom: clampedValidFrom,
                    expiryDate: expiryDate,
                    supplier: supplier,
                    notes: notes,
                    commandId: receiptCommandId
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isSubmitting = false
                onAdded()
                dismiss()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                let errorMsg = error.localizedDescription
                self.errorMessage = errorMsg
                self.isSubmitting = false
            }
        }
    }
}

// MARK: - Expiry Horizon Presets

private enum ExpiryHorizon: String, CaseIterable, Identifiable {
    case threeMonths
    case sixMonths
    case oneYear
    case twoYears
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threeMonths: return "+3 أشهر"
        case .sixMonths: return "+6 أشهر"
        case .oneYear: return "+1 سنة"
        case .twoYears: return "+2 سنة"
        case .custom: return "📅 مخصص"
        }
    }

    func calculateDate(from startDate: Date = Date()) -> Date? {
        let cal = Calendar.current
        switch self {
        case .threeMonths: return cal.date(byAdding: .month, value: 3, to: startDate)
        case .sixMonths: return cal.date(byAdding: .month, value: 6, to: startDate)
        case .oneYear: return cal.date(byAdding: .year, value: 1, to: startDate)
        case .twoYears: return cal.date(byAdding: .year, value: 2, to: startDate)
        case .custom: return nil
        }
    }
}

// MARK: - FEFO Safety Level

private enum FEFOSafetyLevel {
    case optimal
    case moderate
    case critical
    case expired

    static func resolve(days: Int) -> FEFOSafetyLevel {
        if days <= 0 { return .expired }
        if days < 90 { return .critical }
        if days <= 180 { return .moderate }
        return .optimal
    }

    var titleArabic: String {
        switch self {
        case .optimal: return "صلاحية ممتدة (FEFO آمن)"
        case .moderate: return "صلاحية معتدلة (90-180 يوم)"
        case .critical: return "صلاحية قصيرة (أولوية صرف)"
        case .expired: return "منتهي الصلاحية (مرفوض)"
        }
    }

    var color: Color {
        switch self {
        case .optimal: return AdminSurface.emerald
        case .moderate: return AdminSurface.amber
        case .critical: return .orange
        case .expired: return AdminSurface.crimson
        }
    }
}

// MARK: - Simulated Barcode Graphic

private struct SimulatedBatchBarcode: View {
    let code: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<24, id: \.self) { index in
                let isThick = (index * 5 + code.count) % 3 == 0
                Rectangle()
                    .fill(AdminSurface.primaryText.opacity(index % 4 == 0 ? 0.75 : (isThick ? 0.6 : 0.22)))
                    .frame(width: isThick ? 2.2 : 1.1, height: 18)
            }
        }
    }
}

// MARK: - Edit Lot Sheet (Studio-Grade Quantity & Expiry Editor)

private struct EditLotSheet: View {
    let item: PetAccessory
    let lot: PPInventoryLot
    let branchId: String
    let onUpdated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var quantity: Int
    @State private var manualQuantityInput: String
    @State private var expiryDate: Date
    @State private var notes: String
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isCustomCalendarExpanded: Bool = false

    private var isIPadLayout: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }

    init(item: PetAccessory, lot: PPInventoryLot, branchId: String, onUpdated: @escaping () -> Void) {
        self.item = item
        self.lot = lot
        self.branchId = branchId
        self.onUpdated = onUpdated
        _quantity = State(initialValue: lot.initialQuantity)
        _manualQuantityInput = State(initialValue: "\(lot.initialQuantity)".normalizedEnglishDigits)
        _expiryDate = State(initialValue: lot.expiryDate ?? Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date())
        _notes = State(initialValue: "")
    }

    private var minAllowedQuantity: Int {
        lot.minAllowedQuantity
    }

    private var consumedQuantity: Int {
        lot.consumedQuantity
    }

    private var delta: Int {
        quantity - lot.initialQuantity
    }

    private var resultingAvailable: Int {
        lot.availableQuantity + delta
    }

    private var daysUntilExpiry: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
    }

    private var fefoLevel: FEFOSafetyLevel {
        FEFOSafetyLevel.resolve(days: daysUntilExpiry)
    }

    private var formattedExpiryDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: expiryDate)
    }

    private var minimumExpiryDate: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date().addingTimeInterval(86400)
        return tomorrow
    }

    private var isQuantityValid: Bool {
        quantity >= minAllowedQuantity && quantity > 0
    }

    private var isExpiryValid: Bool {
        expiryDate >= minimumExpiryDate
    }

    private var hasChanges: Bool {
        let dateChanged: Bool
        if let originalDate = lot.expiryDate {
            dateChanged = Calendar.current.startOfDay(for: expiryDate) != Calendar.current.startOfDay(for: originalDate)
        } else {
            dateChanged = true
        }
        let qtyChanged = quantity != lot.initialQuantity
        let notesChanged = !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return qtyChanged || dateChanged || notesChanged
    }

    private var canSubmit: Bool {
        hasChanges && isQuantityValid && isExpiryValid && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AdminSpacing.lg) {
                        // Lot Identity Banner
                        lotHeaderBanner

                        // Consumption & Remaining Stock Radar
                        consumptionTelemetryCard

                        // Quantity Modification Chamber
                        quantityModificationCard

                        // Expiry Date Modification Chamber
                        expiryModificationCard

                        // Notes / Reason Field
                        notesSectionCard

                        if let errorMessage {
                            errorBanner(text: errorMessage)
                        }
                    }
                    .padding(.horizontal, isIPadLayout ? 32 : AdminSpacing.screenMargin)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(Language.get("Edit_Lot_Title", alter: "تعديل بيانات التشغيلة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submitUpdate()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .tint(AdminSurface.primary)
                        } else {
                            Text(Language.get("Save_Changes", alter: "حفظ التعديلات"))
                                .font(AdminType.subheadlineBold)
                                .foregroundColor(canSubmit ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.5))
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    // MARK: - Subcomponents

    private var lotHeaderBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AdminSurface.primary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(AdminType.headlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                        Text(lot.lotNumber)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AdminSurface.control, in: Capsule())

                    if let sku = item.sku, !sku.isEmpty {
                        Text("SKU: \(sku)".normalizedEnglishDigits)
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }

            Spacer()

            // Status Badge
            HStack(spacing: 4) {
                Circle()
                    .fill(lot.statusColor)
                    .frame(width: 6, height: 6)
                Text(Language.get(lot.statusLocalizedKey, alter: lot.status))
                    .font(Font.custom("Beiruti-Bold", size: 11))
                    .foregroundStyle(lot.statusColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(lot.statusColor.opacity(0.10), in: Capsule())
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    private var consumptionTelemetryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Language.get("Stock_Consumption_Radar", alter: "رادار الاستهلاك والرصيد المتاح"), systemImage: "chart.bar.xaxis")
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
            }

            Divider().background(AdminSurface.hairline)

            HStack(spacing: 10) {
                // Registered initial
                telemetryCell(
                    title: Language.get("Initial_Stock", alter: "الكمية المسجلة"),
                    value: "\(lot.initialQuantity)".normalizedEnglishDigits,
                    color: AdminSurface.primaryText
                )

                // Consumed
                telemetryCell(
                    title: Language.get("Consumed_Stock", alter: "المستهلك / المباع"),
                    value: "\(consumedQuantity)".normalizedEnglishDigits,
                    color: consumedQuantity > 0 ? AdminSurface.amber : AdminSurface.secondaryText
                )

                // Available
                telemetryCell(
                    title: Language.get("Available_Stock", alter: "المتاح حالياً"),
                    value: "\(lot.availableQuantity)".normalizedEnglishDigits,
                    color: lot.availableQuantity > 0 ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError)
                )
            }

            if consumedQuantity > 0 {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 13))
                        .foregroundColor(AdminSurface.amber)
                    Text(String(format: Language.get("Lot_Consumed_Warning", alter: "تم استهلاك أو حجز %@ وحدة من هذه التشغيلة مسبقاً. لا يمكن تقليل الكمية الإجمالية إلى أقل من %@ وحدة."), "\(consumedQuantity)".normalizedEnglishDigits, "\(minAllowedQuantity)".normalizedEnglishDigits))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.amber)
                        .lineSpacing(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    private func telemetryCell(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
                .lineLimit(1)
            Text(value)
                .font(Font.custom("Beiruti-Bold", size: 16))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
    }

    private var quantityModificationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(Language.get("New_Lot_Quantity", alter: "كمية التشغيلة الإجمالية"), systemImage: "number")
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()

                Text(String(format: Language.get("Min_Allowed_Lot_Quantity", alter: "الحد الأدنى: %@"), "\(minAllowedQuantity)".normalizedEnglishDigits))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            // Interactive Stepper & Numeric Input
            HStack(spacing: 12) {
                // Decrement Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if quantity > minAllowedQuantity {
                        quantity -= 1
                        manualQuantityInput = "\(quantity)".normalizedEnglishDigits
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(quantity > minAllowedQuantity ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.4))
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.control, in: Circle())
                }
                .disabled(quantity <= minAllowedQuantity)

                // TextField for Quantity
                TextField("", text: $manualQuantityInput)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(isQuantityValid ? AdminSurface.primaryText : AdminSurface.crimson)
                    .padding(.vertical, 8)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: manualQuantityInput) { newValue in
                        let cleaned = newValue.normalizedEnglishDigits.filter { "0123456789".contains($0) }
                        if let parsed = Int(cleaned) {
                            quantity = parsed
                        } else if cleaned.isEmpty {
                            quantity = 0
                        }
                    }

                // Increment Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    quantity += 1
                    manualQuantityInput = "\(quantity)".normalizedEnglishDigits
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.control, in: Circle())
                }
            }

            // Quick Step Presets
            HStack(spacing: 8) {
                quickStepChip(deltaValue: -10, title: "-10")
                quickStepChip(deltaValue: -5, title: "-5")
                quickStepChip(deltaValue: 5, title: "+5")
                quickStepChip(deltaValue: 10, title: "+10")
                quickStepChip(deltaValue: 50, title: "+50")
            }

            Divider().background(AdminSurface.hairline)

            // Live Delta Radar
            if delta != 0 {
                HStack(spacing: 8) {
                    Image(systemName: delta > 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(delta > 0 ? AdminSurface.emerald : AdminSurface.amber)

                    Text(delta > 0
                         ? String(format: Language.get("Lot_Stock_Increase_Preview", alter: "إضافة +%@ وحدة إلى المخزون (الرصيد المتاح سيصبح: %@)"), "\(delta)".normalizedEnglishDigits, "\(resultingAvailable)".normalizedEnglishDigits)
                         : String(format: Language.get("Lot_Stock_Decrease_Preview", alter: "خصم %@ وحدة من المخزون (الرصيد المتاح سيصبح: %@)"), "\(-delta)".normalizedEnglishDigits, "\(resultingAvailable)".normalizedEnglishDigits))
                        .font(AdminType.caption1Bold)
                        .foregroundColor(delta > 0 ? AdminSurface.emerald : AdminSurface.amber)

                    Spacer()
                }
                .padding(10)
                .background((delta > 0 ? AdminSurface.emerald : AdminSurface.amber).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack {
                    Text(Language.get("No_Quantity_Change", alter: "الكمية مطابقة للرصيد المسجل حالياً (لا تغيير)"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                }
            }

            if quantity < minAllowedQuantity {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundColor(AdminSurface.crimson)
                    Text(String(format: Language.get("Quantity_Below_Min_Error", alter: "الكمية لا يمكن أن تقل عن %@ وحدة."), "\(minAllowedQuantity)".normalizedEnglishDigits))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.crimson)
                }
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    private func quickStepChip(deltaValue: Int, title: String) -> some View {
        let isEnabled = (quantity + deltaValue) >= minAllowedQuantity

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            quantity = max(minAllowedQuantity, quantity + deltaValue)
            manualQuantityInput = "\(quantity)".normalizedEnglishDigits
        } label: {
            Text(title.normalizedEnglishDigits)
                .font(Font.custom("Beiruti-Bold", size: 12))
                .foregroundColor(isEnabled ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8))
        }
        .disabled(!isEnabled)
    }

    private var expiryModificationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(Language.get("New_Expiry_Date", alter: "تاريخ الصلاحية الجديد"), systemImage: "calendar")
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()

                // Days Remaining Pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(fefoLevel.color)
                        .frame(width: 6, height: 6)
                    Text(daysUntilExpiry > 0 ? "\(daysUntilExpiry) يوم متبقي".normalizedEnglishDigits : "منتهي الصلاحية")
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundColor(fefoLevel.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(fefoLevel.color.opacity(0.12), in: Capsule())
            }

            // Expiry Date Selector Button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isCustomCalendarExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 15))
                        .foregroundColor(AdminSurface.primary)

                    Text(formattedExpiryDate.normalizedEnglishDigits)
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundColor(AdminSurface.primaryText)

                    Spacer()

                    Image(systemName: isCustomCalendarExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
            }

            if isCustomCalendarExpanded {
                DatePicker(
                    "",
                    selection: $expiryDate,
                    in: minimumExpiryDate...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .accentColor(AdminSurface.primary)
                .padding(8)
                .background(AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    private var notesSectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Update_Reason_Notes", alter: "سبب التعديل أو ملاحظات إضافية"), systemImage: "note.text")
                .font(AdminType.subheadlineBold)
                .foregroundColor(AdminSurface.primaryText)

            TextField(Language.get("Lot_Notes_Placeholder", alter: "مثال: تصحيح خطأ إدخال الكمية أو تعديل تاريخ الصلاحية الفعلي"), text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .font(AdminType.footnote)
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    private func errorBanner(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(AdminSurface.crimson)
            Text(text)
                .font(AdminType.footnote)
                .foregroundColor(AdminSurface.crimson)
                .lineSpacing(2)
            Spacer()
        }
        .padding(12)
        .background(AdminSurface.crimson.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func submitUpdate() {
        guard canSubmit else { return }

        isSubmitting = true
        errorMessage = nil

        let updatedQty = quantity != lot.initialQuantity ? quantity : nil
        let dateChanged: Bool
        if let originalDate = lot.expiryDate {
            dateChanged = Calendar.current.startOfDay(for: expiryDate) != Calendar.current.startOfDay(for: originalDate)
        } else {
            dateChanged = true
        }
        let updatedExp = dateChanged ? expiryDate : nil

        Task {
            do {
                _ = try await PPInventoryLotService.shared.updateLot(
                    branchId: branchId,
                    productId: lot.productId,
                    lotId: lot.lotId,
                    newQuantity: updatedQty,
                    newExpiryDate: updatedExp,
                    notes: notes
                )
                await MainActor.run {
                    isSubmitting = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    PPAlertHelper.showSuccess(
                        in: nil,
                        title: Language.get("Lot_Updated_Success", alter: "تم تحديث التشغيلة بنجاح"),
                        subtitle: nil
                    )
                    onUpdated()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Batch Passport Card

private struct BatchPassportCard: View {
    let item: PetAccessory
    let lotNumber: String
    let quantity: Int
    let unitCost: Double
    let totalCost: Double
    let expiryFormatted: String
    let daysRemaining: Int
    let fefoLevel: FEFOSafetyLevel
    var onGenerateCode: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Row: Product Identity & Security Badge
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(AdminType.headlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let sku = item.sku, !sku.isEmpty {
                            Text("SKU: \(sku)")
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        if let barcode = item.barcode, !barcode.isEmpty {
                            Text("• \(barcode)")
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }

                Spacer()

                // Security hologram badge
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundColor(AdminSurface.emerald)
                    Text("FEFO CERTIFIED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AdminSurface.control, in: Capsule())
            }

            Divider().background(AdminSurface.hairline)

            // Center: Lot Number and Simulated Barcode
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("Inventory_Lot_Number", alter: "رقم التشغيلة").replacingOccurrences(of: " *", with: ""))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)

                    Text(lotNumber.isEmpty ? "LOT-2026-...." : lotNumber)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundColor(lotNumber.isEmpty ? AdminSurface.secondaryText.opacity(0.5) : AdminSurface.primary)
                }

                Spacer()

                SimulatedBatchBarcode(code: lotNumber)
            }

            // Telemetry Pills
            HStack(spacing: 8) {
                // FEFO Expiry Status Capsule
                HStack(spacing: 5) {
                    Circle()
                        .fill(fefoLevel.color)
                        .frame(width: 7, height: 7)
                    Text(daysRemaining > 0 ? "\(daysRemaining) يوم متبقي" : "منتهي الصلاحية")
                        .font(AdminType.caption1Bold)
                        .foregroundColor(fefoLevel.color)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(fefoLevel.color.opacity(0.12), in: Capsule())

                Spacer()

                // Total Value Capsule
                if totalCost > 0 {
                    HStack(spacing: 4) {
                        Text("إجمالي القيمة:")
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(String(format: "%.2f ر.ق", totalCost))
                            .font(AdminType.caption1Bold)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AdminSurface.control, in: Capsule())
                }
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
    }
}

// MARK: - iPad Laboratory Cockpit

private struct IPadBatchLaboratoryCockpit: View {
    let item: PetAccessory
    let lotNumber: String
    let quantity: Int
    let unitCost: Double
    let totalCost: Double
    let retailPrice: Double
    let margin: Double?
    let expiryFormatted: String
    let daysRemaining: Int
    let fefoLevel: FEFOSafetyLevel
    let onGenerateCode: () -> Void

    var body: some View {
        VStack(spacing: AdminSpacing.md) {
            // Master Holographic Batch Passport
            BatchPassportCard(
                item: item,
                lotNumber: lotNumber,
                quantity: quantity,
                unitCost: unitCost,
                totalCost: totalCost,
                expiryFormatted: expiryFormatted,
                daysRemaining: daysRemaining,
                fefoLevel: fefoLevel,
                onGenerateCode: onGenerateCode
            )

            // Financial Telemetry Radar
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("التحليل المالي للتشغيلة", systemImage: "chart.line.uptrend.xyaxis")
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Spacer()
                    Text("\(quantity) وحدة")
                        .font(AdminType.caption1Bold)
                        .foregroundColor(AdminSurface.primary)
                }

                Divider().background(AdminSurface.hairline)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("إجمالي الاستثمار")
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(String(format: "%.2f ر.ق", totalCost))
                            .font(AdminType.title3Bold)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    Spacer()
                    if let margin {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("هامش الربح المتوقع")
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                            Text(String(format: "%.1f%%", margin))
                                .font(AdminType.title3Bold)
                                .foregroundColor(AdminSurface.emerald)
                        }
                    }
                }

                if retailPrice > 0 {
                    HStack {
                        Text("سعر البيع المعتمد بالفرع: \(String(format: "%.2f ر.ق", retailPrice))")
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                        Spacer()
                    }
                }
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

            // FEFO Protocol & Dispatch Simulation
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("بروتوكول صرف المخزون FEFO", systemImage: "arrow.triangle.2.circlepath")
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Spacer()
                }

                Text(daysRemaining > 0
                     ? "سيتم تصنيف هذه التشغيلة وفق تاريخ الصلاحية (\(expiryFormatted)). يضمن نظام FEFO بيع التشغيلات الأقرب انتهاءً أولاً تلقائياً لمنع أي هدر دوائي أو غذائي."
                     : "تنبيه: لا يمكن استقبال أي تشغيلة بتاريخ منتهٍ حرصاً على سلامة الحيوانات الأليفة.")
                    .font(AdminType.footnote)
                    .foregroundColor(daysRemaining > 0 ? AdminSurface.secondaryText : AdminSurface.crimson)
                    .lineSpacing(3)
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

            Spacer()
        }
    }
}
