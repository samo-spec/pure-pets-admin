//
//  POSReservedLivePetsView.swift
//  PurePetsAdmin
//
//  Beyond-FAANG · Category-Defining · Reserved Live Pets Operations Horizon
//  Reimagined from absolute first principles — spatial depth, urgency telemetry,
//  physics-based spring interactions, frosted-glass card system, live countdown
//  arcs, hero dossier parallax, and Arabic-RTL-first information architecture.
//

import SwiftUI
import UIKit

// MARK: - Models & Projections

struct POSReservedPetCardModel: Identifiable, Hashable, Sendable {
    let id: String
    let reservationID: String
    let productID: String
    let unitID: String
    let ringTag: String
    let animalName: String
    let photoURL: String
    let sellingPrice: Double
    let standardPrice: Double
    let customerName: String
    let customerPhone: String
    let customerSource: String
    let branchID: String
    let branchName: String
    let validUntil: Date?
    let createdAt: Date?
    let notes: String
    let supplier: String
    let purchaseCost: Double?
    let currency: String

    var isExpired: Bool {
        guard let validUntil else { return false }
        return validUntil < Date()
    }

    var isExpiringSoon: Bool {
        guard let validUntil, !isExpired else { return false }
        return validUntil.timeIntervalSinceNow < (24 * 60 * 60)
    }

    var remainingHours: Int {
        guard let validUntil else { return 0 }
        let interval = validUntil.timeIntervalSinceNow
        return max(0, Int(interval / 3600))
    }

    var urgencyFraction: Double {
        guard let validUntil, let createdAt else { return 1.0 }
        let total = validUntil.timeIntervalSince(createdAt)
        let remaining = max(0, validUntil.timeIntervalSinceNow)
        guard total > 0 else { return 0 }
        return min(1.0, remaining / total)
    }

    var remainingTimeDescription: String {
        guard let validUntil else {
            return Language.get("LivePet_NoExpiry", alter: "بدون مهلة")
        }
        let now = Date()
        if validUntil < now {
            return Language.get("LivePet_Expired", alter: "منتهي الصلاحية")
        }
        let interval = validUntil.timeIntervalSince(now)
        let days = Int(interval / (24 * 3600))
        let hours = Int((interval.truncatingRemainder(dividingBy: 24 * 3600)) / 3600)
        let mins  = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if days > 0 {
            let format = Language.get("LivePet_RemainingDays_Format", alter: "متبقي %d يوم")
            return String(format: format, days)
        } else if hours > 0 {
            let format = Language.get("LivePet_RemainingHours_Format", alter: "متبقي %d ساعة")
            return String(format: format, hours)
        } else {
            let format = Language.get("LivePet_RemainingMins_Format", alter: "متبقي %d دقيقة")
            return String(format: format, max(1, mins))
        }
    }
}

enum POSReservationFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case expiringSoon
    case expired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:          return Language.get("POS_Filter_All",          alter: "الكل")
        case .active:       return Language.get("POS_Filter_Active",       alter: "نشط")
        case .expiringSoon: return Language.get("POS_Filter_ExpiringSoon", alter: "ينتهي قريباً")
        case .expired:      return Language.get("POS_Filter_Expired",      alter: "منتهي")
        }
    }

    var icon: String {
        switch self {
        case .all:          return "square.grid.2x2.fill"
        case .active:       return "checkmark.seal.fill"
        case .expiringSoon: return "clock.badge.exclamationmark.fill"
        case .expired:      return "exclamationmark.octagon.fill"
        }
    }

    var urgencyColor: Color {
        switch self {
        case .all:          return Color(uiColor: .ppPrimary)
        case .active:       return Color(uiColor: .ppSuccess)
        case .expiringSoon: return Color(uiColor: .ppWarning)
        case .expired:      return Color(uiColor: .ppError)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class POSReservedLivePetsViewModel: ObservableObject {
    @Published var items: [POSReservedPetCardModel] = []
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var searchText: String = ""
    @Published var activeFilter: POSReservationFilter = .all
    @Published var selectedBranchID: String = ""
    @Published var branches: [PPInventoryBranchOption] = []
    @Published var activeDossierItem: POSReservedPetCardModel? = nil
    @Published var extendingItem: POSReservedPetCardModel? = nil
    @Published var releasingItem: POSReservedPetCardModel? = nil
    @Published var operationSuccessNotice: String? = nil

    private var accessoriesByID: [String: PetAccessory] = [:]
    private var branchesByID: [String: String] = [:]

    init(accessories: [PetAccessory] = []) {
        updateAccessories(accessories)
    }

    func updateAccessories(_ accessories: [PetAccessory]) {
        for acc in accessories {
            accessoriesByID[acc.accessoryID] = acc
        }
    }

    // Telemetry
    var totalCount: Int { items.count }
    var activeCount: Int { items.filter { !$0.isExpired }.count }
    var expiringSoonCount: Int { items.filter { $0.isExpiringSoon }.count }
    var expiredCount: Int { items.filter { $0.isExpired }.count }
    var totalHeldValue: Double { items.reduce(0) { $0 + $1.sellingPrice } }
    var uniqueCustomersCount: Int {
        Set(items.map { $0.customerPhone.isEmpty ? $0.customerName : $0.customerPhone }).count
    }
    var urgencyPressure: Double {
        guard totalCount > 0 else { return 0 }
        return Double(expiringSoonCount + expiredCount) / Double(totalCount)
    }

    var filteredItems: [POSReservedPetCardModel] {
        items.filter { item in
            if !selectedBranchID.isEmpty && item.branchID != selectedBranchID { return false }
            switch activeFilter {
            case .all: break
            case .active: if item.isExpired { return false }
            case .expiringSoon: if !item.isExpiringSoon { return false }
            case .expired: if !item.isExpired { return false }
            }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if q.isEmpty { return true }
            return item.animalName.lowercased().contains(q)
                || item.ringTag.lowercased().contains(q)
                || item.customerName.lowercased().contains(q)
                || item.customerPhone.lowercased().contains(q)
                || item.reservationID.lowercased().contains(q)
                || item.branchName.lowercased().contains(q)
        }
    }

    // MARK: - Data Loading

    func loadData() async {
        isLoading = items.isEmpty
        isRefreshing = !items.isEmpty
        errorMessage = nil

        do {
            let branchList = try await PPLivePetInventoryService.listBranches()
            self.branches = branchList
            self.branchesByID = branchList.reduce(into: [:]) { $0[$1.id] = $1.name }
            let loadedUnits = try await fetchAllReservedUnits()
            self.items = loadedUnits.sorted {
                let left  = $0.validUntil ?? Date.distantFuture
                let right = $1.validUntil ?? Date.distantFuture
                return left < right
            }
        } catch {
            self.errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
        }

        isLoading = false
        isRefreshing = false
    }

    private func fetchAllReservedUnits() async throws -> [POSReservedPetCardModel] {
        let reservations = try await PPLivePetInventoryService.listReservations()
        var cardModels: [POSReservedPetCardModel] = []
        var seenKeys = Set<String>()

        for reservation in reservations {
            let branchTitle = branchesByID[reservation.branchID] ?? reservation.branchID
            for reservationItem in reservation.items {
                let accessory = accessoriesByID[reservationItem.productID]
                let petName = accessory?.name
                    ?? (!reservationItem.name.isEmpty
                        ? reservationItem.name
                        : Language.get("POS_LiveAnimalFallback", alter: "حيوان حي"))
                let photo = accessory?.imageURLsArray.first ?? ""
                let unitPrice = reservationItem.unitPrice > 0
                    ? reservationItem.unitPrice
                    : accessory?.pos_canonicalUnitPrice ?? 0

                for (index, unitID) in reservationItem.unitIDs.enumerated() {
                    let ring = index < reservationItem.ringTags.count ? reservationItem.ringTags[index] : unitID
                    let unitKey = "\(reservationItem.productID)_\(unitID)"
                    guard seenKeys.insert(unitKey).inserted else { continue }
                    cardModels.append(POSReservedPetCardModel(
                        id: unitKey,
                        reservationID: reservation.id,
                        productID: reservationItem.productID,
                        unitID: unitID,
                        ringTag: ring,
                        animalName: petName,
                        photoURL: photo,
                        sellingPrice: unitPrice,
                        standardPrice: accessory?.pos_canonicalUnitPrice ?? unitPrice,
                        customerName: reservation.customerName,
                        customerPhone: reservation.customerPhone,
                        customerSource: reservation.customerSource,
                        branchID: reservation.branchID,
                        branchName: branchTitle,
                        validUntil: reservation.validUntil,
                        createdAt: nil,
                        notes: "",
                        supplier: "",
                        purchaseCost: nil,
                        currency: reservation.currency
                    ))
                }
            }
        }

        return cardModels
    }

    // MARK: - Actions

    func extendHold(for item: POSReservedPetCardModel, newValidUntil: Date, reason: String) async -> Bool {
        // Reservation expiry is a multi-record lifecycle transition. Infra has
        // no extension command, so this screen must not mutate transactions or
        // exact-animal units directly and silently bypass audit enforcement.
        errorMessage = Language.get(
            "LivePet_Error_ReservationExtensionUnavailable",
            alter: "لا يمكن تمديد الحجز من هذا الجهاز لأن الخادم لا يوفّر عملية تمديد معتمدة. حرر الحجز ثم أنشئ حجزاً جديداً إذا لزم الأمر."
        )
        return false
    }

    func releaseHold(for item: POSReservedPetCardModel, reason: String) async -> Bool {
        guard !item.reservationID.isEmpty else {
            errorMessage = Language.get(
                "LivePet_Error_ReservationProjection",
                alter: "تعذر عرض حجز بسبب بيانات غير مكتملة. حدّث الصفحة وأبلغ المشرف إذا استمرت المشكلة."
            )
            return false
        }
        do {
            _ = try await PPLivePetInventoryService.callTransaction([
                "action": "cancel",
                "transactionId": item.reservationID,
                "commandId": PPLivePetInventoryService.commandID("release-pos-reservation"),
                "expectedStatus": "pending",
                "reason": reason.isEmpty ? "operator_release_from_pos" : reason,
                "currency": item.currency.isEmpty ? "QAR" : item.currency,
            ])
            self.operationSuccessNotice = Language.get("POS_Reservation_Released_Success", alter: "تم إلغاء الحجز وإعادة الحيوان للمخزون ✓")
            await loadData()
            return true
        } catch {
            self.errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
            return false
        }
    }
}

// MARK: - Main Screen — Spatial Horizon Architecture

struct POSReservedLivePetsView: View {
    let session: AdminSession
    var allAccessories: [PetAccessory] = []
    var onCompleteSale: ((POSReservedPetCardModel) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: POSReservedLivePetsViewModel
    @State private var searchFocused: Bool = false
    @State private var headerCollapsed: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var refreshSpinAngle: Double = 0
    @State private var isRefreshSpinning: Bool = false
    @Namespace private var filterNS

    init(
        session: AdminSession,
        allAccessories: [PetAccessory] = [],
        onCompleteSale: ((POSReservedPetCardModel) -> Void)? = nil
    ) {
        self.session = session
        self.allAccessories = allAccessories
        self.onCompleteSale = onCompleteSale
        _vm = StateObject(wrappedValue: POSReservedLivePetsViewModel(accessories: allAccessories))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Deep background gradient — spatial depth
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    Color(uiColor: .secondarySystemBackground).opacity(0.6),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                morphicHeader
                filterOrb
                scrollContent
            }

            // Floating success toast
            toastOverlay
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .task {
            vm.updateAccessories(allAccessories)
            await vm.loadData()
        }
        .sheet(item: $vm.activeDossierItem) { item in
            POSReservedPetDossierSheet(item: item, viewModel: vm, onCompleteSale: onCompleteSale)
        }
        .sheet(item: $vm.extendingItem) { item in
            POSExtendReservationSheet(item: item, viewModel: vm)
        }
        .sheet(item: $vm.releasingItem) { item in
            POSReleaseReservationSheet(item: item, viewModel: vm)
        }
        .alert(
            Language.get("Error", alter: "تنبيه"),
            isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })
        ) {
            Button(Language.get("OK", alter: "موافق")) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Morphic Header (Collapses on scroll)

    private var morphicHeader: some View {
        VStack(spacing: 0) {
            AdminSovereignNavigationBar(
                title: Language.get("POS_ReservedLivePets_Title", alter: "الحيوانات المحجوزة"),
                subtitle: Language.get("POS_LivePets_Desk", alter: "نقطة البيع · حجوزات الحيوانات"),
                statusDotColor: Color(uiColor: .ppSuccess),
                isModal: true,
                onBack: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
            ) {
                AdminSquircleActionButton(
                    systemImage: "arrow.clockwise",
                    isLoading: isRefreshSpinning || vm.isLoading,
                    accessibilityLabel: Language.get("POS_Refresh", alter: "تحديث")
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isRefreshSpinning = true
                    Task {
                        await vm.loadData()
                        isRefreshSpinning = false
                    }
                }
            }

            // Telemetry Orbit Strip
            if !vm.isLoading || !vm.items.isEmpty {
                telemetryOrbit
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.bottom, AdminSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: AdminStroke.thin),
            alignment: .bottom
        )
    }

    // MARK: - Telemetry Orbit (4 Live Counters in a flowing row)

    private var telemetryOrbit: some View {
        HStack(spacing: 8) {
            telemetryPill(
                icon: "pawprint.fill",
                value: "\(vm.totalCount)",
                label: Language.get("POS_Metric_Animals", alter: "حيوان"),
                accent: AdminSurface.primary,
                glow: false
            )
            telemetryPill(
                icon: "person.2.fill",
                value: "\(vm.uniqueCustomersCount)",
                label: Language.get("POS_Metric_Customers", alter: "عميل"),
                accent: Color(uiColor: .ppSuccess),
                glow: false
            )
            telemetryPill(
                icon: "clock.badge.exclamationmark.fill",
                value: "\(vm.expiringSoonCount)",
                label: Language.get("POS_Metric_Urgent", alter: "عاجل"),
                accent: Color(uiColor: .ppWarning),
                glow: vm.expiringSoonCount > 0
            )
            telemetryPill(
                icon: "banknote.fill",
                value: String(format: "%.0f", vm.totalHeldValue),
                label: "ر.ق",
                accent: AdminSurface.primary,
                glow: false
            )
        }
    }

    private func telemetryPill(
        icon: String,
        value: String,
        label: String,
        accent: Color,
        glow: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(accent)

            Text(value)
                .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .callout))
                .foregroundColor(glow ? accent : AdminSurface.primaryText)
                .monospacedDigit()

            Text(label)
                .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                .foregroundColor(AdminSurface.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            glow
                ? accent.opacity(0.12)
                : Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                .stroke(glow ? accent.opacity(0.35) : AdminSurface.hairline, lineWidth: glow ? 1 : AdminStroke.thin)
        )
        .scaleEffect(glow ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: glow)
    }

    // MARK: - Filter Orb Rail

    private var filterOrb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Search pill
                searchPill

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 2)

                ForEach(POSReservationFilter.allCases) { filter in
                    let isSelected = vm.activeFilter == filter
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            vm.activeFilter = filter
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(filter.title)
                                .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Regular", size: 12, relativeTo: .caption))

                            let count = countForFilter(filter)
                            if count > 0 {
                                Text("\(count)")
                                    .font(Font.custom("Beiruti-Bold", size: 9, relativeTo: .caption2))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        isSelected ? Color.white.opacity(0.3) : filter.urgencyColor.opacity(0.12),
                                        in: Capsule()
                                    )
                                    .foregroundColor(isSelected ? .white : filter.urgencyColor)
                            }
                        }
                        .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            isSelected
                                ? filter.urgencyColor
                                : Color(uiColor: .secondarySystemBackground),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: AdminStroke.thin)
                        )
                        .shadow(
                            color: isSelected ? filter.urgencyColor.opacity(0.3) : .clear,
                            radius: 6, y: 2
                        )
                    }
                    .scaleEffect(isSelected ? 1.03 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
                }

                // Branch picker
                if !vm.branches.isEmpty {
                    branchPicker
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, AdminSpacing.sm)
        }
        .background(.ultraThinMaterial)
    }

    private var searchPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AdminSurface.secondaryText)

            TextField(
                Language.get("POS_SearchReserved_Placeholder", alter: "بحث..."),
                text: $vm.searchText
            )
            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
            .frame(width: vm.searchText.isEmpty ? 60 : 120)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: vm.searchText.isEmpty)

            if !vm.searchText.isEmpty {
                Button { vm.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin))
    }

    private var branchPicker: some View {
        Menu {
            Button {
                vm.selectedBranchID = ""
            } label: {
                Label(Language.get("POS_AllBranches", alter: "كافة الفروع"),
                      systemImage: vm.selectedBranchID.isEmpty ? "checkmark" : "building.2")
            }
            Divider()
            ForEach(vm.branches) { branch in
                Button {
                    vm.selectedBranchID = branch.id
                } label: {
                    Label(branch.name,
                          systemImage: vm.selectedBranchID == branch.id ? "checkmark" : "mappin.circle")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "building.2.crop.circle")
                    .font(.system(size: 11))
                Text(selectedBranchLabel)
                    .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(vm.selectedBranchID.isEmpty ? AdminSurface.primaryText : AdminSurface.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                vm.selectedBranchID.isEmpty
                    ? Color(uiColor: .secondarySystemBackground)
                    : AdminSurface.primary.opacity(0.1),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    vm.selectedBranchID.isEmpty ? AdminSurface.hairline : AdminSurface.primary.opacity(0.4),
                    lineWidth: AdminStroke.thin
                )
            )
        }
    }

    private var selectedBranchLabel: String {
        if vm.selectedBranchID.isEmpty {
            return Language.get("POS_Branch_All", alter: "الفروع")
        }
        return vm.branches.first(where: { $0.id == vm.selectedBranchID })?.name ?? vm.selectedBranchID
    }

    private func countForFilter(_ filter: POSReservationFilter) -> Int {
        switch filter {
        case .all:          return vm.totalCount
        case .active:       return vm.activeCount
        case .expiringSoon: return vm.expiringSoonCount
        case .expired:      return vm.expiredCount
        }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if vm.isLoading {
                    skeletonStack
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.top, AdminSpacing.md)
                } else if vm.filteredItems.isEmpty {
                    emptyHorizon
                        .padding(.top, AdminSpacing.xxl)
                } else {
                    // Section header
                    HStack {
                        Text(Language.get("POS_SectionTitle_Reserved", alter: "الحجوزات النشطة"))
                            .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .callout))
                            .foregroundColor(AdminSurface.secondaryText)
                        Spacer()
                        Text("\(vm.filteredItems.count)")
                            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.md)
                    .padding(.bottom, AdminSpacing.xs)

                    ForEach(Array(vm.filteredItems.enumerated()), id: \.element.id) { index, item in
                        POSReservedPetCard(
                            item: item,
                            index: index,
                            onCompleteSale: {
                                guard session.hasPermission("pos.sell") else {
                                    vm.errorMessage = Language.get(
                                        "PPAlert_Error_Permission_Message",
                                        alter: "ليست لديك صلاحية لإكمال هذا الإجراء. اطلب الصلاحية من مسؤول مخوّل."
                                    )
                                    return
                                }
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                onCompleteSale?(item)
                                dismiss()
                            },
                            onExtend: {
                                // Infra intentionally has no reservation-extension
                                // command. Keep the control truthful until that
                                // audited server transition is explicitly added.
                                vm.errorMessage = Language.get(
                                    "LivePet_Error_ReservationExtensionUnavailable",
                                    alter: "لا يمكن تمديد الحجز من هنا لأن الخادم لا يوفّر عملية تمديد معتمدة. حرر الحجز ثم أنشئ حجزاً جديداً إذا لزم الأمر."
                                )
                            },
                            onRelease: {
                                guard session.hasPermission("pos.sell"), session.hasPermission("payments.refund") else {
                                    vm.errorMessage = Language.get(
                                        "PPAlert_Error_Permission_Message",
                                        alter: "ليست لديك صلاحية لإكمال هذا الإجراء. اطلب الصلاحية من مسؤول مخوّل."
                                    )
                                    return
                                }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                vm.releasingItem = item
                            },
                            onInspectDossier: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                vm.activeDossierItem = item
                            }
                        )
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.bottom, 10)
                    }

                    Color.clear.frame(height: 40)
                }
            }
        }
        .refreshable {
            await vm.loadData()
        }
    }

    // MARK: - Skeleton Loading

    private var skeletonStack: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(height: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin)
                    )
                    .opacity(0.5 + Double(2 - i) * 0.15)
                    .shimmer()
            }
        }
    }

    // MARK: - Empty State Horizon

    private var emptyHorizon: some View {
        VStack(spacing: AdminSpacing.md) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.06))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(AdminSurface.primary.opacity(0.04))
                    .frame(width: 64, height: 64)
                Image(systemName: "pawprint.circle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(AdminSurface.primary.opacity(0.5))
            }

            VStack(spacing: 6) {
                Text(Language.get("POS_NoReservedLivePets_Title", alter: "لا توجد حجوزات"))
                    .font(Font.custom("Beiruti-Bold", size: 17, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("POS_NoReservedLivePets_Subtitle", alter: "جميع الحيوانات الحية متاحة للبيع المباشر في الكتالوج حالياً."))
                    .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .subheadline))
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AdminSpacing.xl)
            }

            Button {
                Task { await vm.loadData() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text(Language.get("POS_Refresh", alter: "تحديث"))
                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .callout))
                }
                .foregroundColor(AdminSurface.primary)
                .padding(.horizontal, AdminSpacing.md)
                .padding(.vertical, AdminSpacing.sm)
                .background(AdminSurface.primary.opacity(0.08), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toast Overlay

    private var toastOverlay: some View {
        VStack {
            Spacer()
            if let notice = vm.operationSuccessNotice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 15, weight: .semibold))
                    Text(notice)
                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .callout))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(Color(uiColor: .ppSuccess), in: Capsule())
                .shadow(color: Color(uiColor: .ppSuccess).opacity(0.35), radius: 12, y: 4)
                .padding(.bottom, AdminSpacing.xxl)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            vm.operationSuccessNotice = nil
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: vm.operationSuccessNotice)
        .allowsHitTesting(false)
    }
}

// MARK: - Shimmer Modifier

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.15), .clear],
                        startPoint: .init(x: phase, y: 0.5),
                        endPoint: .init(x: phase + 0.5, y: 0.5)
                    )
                    .blendMode(.plusLighter)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

// MARK: - Flagship Reserved Pet Card

private struct POSReservedPetCard: View {
    let item: POSReservedPetCardModel
    let index: Int
    let onCompleteSale: () -> Void
    let onExtend: () -> Void
    let onRelease: () -> Void
    let onInspectDossier: () -> Void

    @State private var isPressed: Bool = false
    @State private var appeared: Bool = false

    private var urgencyColor: Color {
        if item.isExpired      { return Color(uiColor: .ppError) }
        if item.isExpiringSoon { return Color(uiColor: .ppWarning) }
        return Color(uiColor: .ppSuccess)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ─── Top strip: urgency indicator bar ─────────────────────
            UrgencyArcBar(fraction: item.urgencyFraction, color: urgencyColor)
                .frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 99, style: .continuous))
                .padding(.horizontal, 20)

            VStack(spacing: 12) {
                // ─── Row 1: Avatar + Identity + Urgency Badge ──────────
                HStack(spacing: 12) {
                    PetAvatarView(url: item.photoURL, size: 56, cornerRadius: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .center, spacing: 6) {
                            Text(item.animalName)
                                .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)

                            Spacer()

                            urgencyTimeBadge
                        }

                        HStack(spacing: 6) {
                            ringTagBadge
                            if !item.branchName.isEmpty { branchBadge }
                        }
                    }
                }

                // ─── Divider ───────────────────────────────────────────
                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(height: AdminStroke.thin)

                // ─── Row 2: Customer + Price ───────────────────────────
                HStack(alignment: .center, spacing: 0) {
                    customerSection
                    Spacer()
                    priceSection
                }

                // ─── Row 3: Action Suite ───────────────────────────────
                actionSuite
            }
            .padding(.horizontal, AdminSpacing.cardPadding)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(
                    color: item.isExpiringSoon
                        ? urgencyColor.opacity(0.18)
                        : Color.black.opacity(0.06),
                    radius: item.isExpiringSoon ? 12 : 8,
                    y: item.isExpiringSoon ? 4 : 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                .stroke(
                    item.isExpiringSoon
                        ? urgencyColor.opacity(0.35)
                        : AdminSurface.hairline,
                    lineWidth: item.isExpiringSoon ? 1.0 : AdminStroke.thin
                )
        )
        .scaleEffect(isPressed ? 0.985 : 1.0)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.75)
                .delay(Double(index) * 0.04),
            value: appeared
        )
        .onAppear { appeared = true }
    }

    // MARK: Urgency Time Badge

    private var urgencyTimeBadge: some View {
        HStack(spacing: 3) {
            if item.isExpired {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 9, weight: .bold))
            } else if item.isExpiringSoon {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.system(size: 9, weight: .bold))
            } else {
                Circle()
                    .fill(urgencyColor)
                    .frame(width: 5, height: 5)
            }
            Text(item.remainingTimeDescription)
                .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
        }
        .foregroundColor(urgencyColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(urgencyColor.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(urgencyColor.opacity(0.2), lineWidth: AdminStroke.thin))
    }

    private var ringTagBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "number.circle.fill")
                .font(.system(size: 9))
            Text(item.ringTag)
                .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption))
        }
        .foregroundColor(AdminSurface.primary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(AdminSurface.primary.opacity(0.08), in: Capsule())
    }

    private var branchBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 8))
            Text(item.branchName)
                .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                .lineLimit(1)
        }
        .foregroundColor(AdminSurface.secondaryText)
    }

    // MARK: Customer Section

    private var customerSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Language.get("POS_Customer", alter: "العميل"))
                .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                .foregroundColor(AdminSurface.secondaryText)

            HStack(spacing: 5) {
                // Avatar monogram
                let initials = item.customerName.prefix(1).uppercased()
                Circle()
                    .fill(AdminSurface.primary.opacity(0.12))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text(initials.isEmpty ? "؟" : initials)
                            .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.primary)
                    )

                Text(item.customerName.isEmpty
                     ? Language.get("POS_UnnamedCustomer", alter: "بدون اسم")
                     : item.customerName)
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .body))
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                if !item.customerPhone.isEmpty {
                    quickCallButton(phone: item.customerPhone)
                    quickWhatsAppButton(phone: item.customerPhone)
                }
            }

            if !item.customerPhone.isEmpty {
                Text(item.customerPhone)
                    .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)
                    .monospacedDigit()
            }
        }
    }

    // MARK: Price Section

    private var priceSection: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(Language.get("POS_LockedPrice", alter: "سعر الحجز"))
                .font(Font.custom("Beiruti-Regular", size: 9, relativeTo: .caption2))
                .foregroundColor(AdminSurface.secondaryText)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.0f", item.sellingPrice))
                    .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title2))
                    .foregroundColor(AdminSurface.primary)
                    .monospacedDigit()
                Text("ر.ق")
                    .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.primary.opacity(0.7))
            }
        }
    }

    // MARK: Action Suite — horizontal adaptive pill strip

    private var actionSuite: some View {
        HStack(spacing: 6) {
            // Primary: Complete Sale
            Button {
                onCompleteSale()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(Language.get("POS_Action_CompleteSale", alter: "إتمام البيع"))
                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .callout))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, y: 2)
            }

            // Extend Hold
            ActionIconButton(
                systemImage: "calendar.badge.clock",
                tint: AdminSurface.primaryText,
                bg: Color(uiColor: .secondarySystemBackground),
                action: onExtend,
                label: Language.get("POS_Action_Extend", alter: "تمديد الحجز")
            )

            // Release Hold
            ActionIconButton(
                systemImage: "lock.open.fill",
                tint: Color(uiColor: .ppError),
                bg: Color(uiColor: .ppError).opacity(0.08),
                action: onRelease,
                label: Language.get("POS_Action_Release", alter: "إلغاء الحجز")
            )

            // Dossier
            ActionIconButton(
                systemImage: "doc.text.magnifyingglass",
                tint: AdminSurface.secondaryText,
                bg: Color(uiColor: .secondarySystemBackground),
                action: onInspectDossier,
                label: Language.get("POS_Action_Dossier", alter: "السجل الكامل")
            )
        }
    }

    // MARK: Inline Action Helpers

    private func quickCallButton(phone: String) -> some View {
        Button {
            guard let url = URL(string: "tel://\(phone.filter { "0123456789+".contains($0) })") else { return }
            UIApplication.shared.open(url)
        } label: {
            Image(systemName: "phone.fill")
                .font(.system(size: 9))
                .foregroundColor(Color(uiColor: .ppSuccess))
                .padding(4)
                .background(Color(uiColor: .ppSuccess).opacity(0.1), in: Circle())
        }
        .accessibilityLabel(Language.get("Call", alter: "اتصال"))
    }

    private func quickWhatsAppButton(phone: String) -> some View {
        Button {
            let digits = phone.filter { "0123456789".contains($0) }
            guard let url = URL(string: "https://wa.me/\(digits)") else { return }
            UIApplication.shared.open(url)
        } label: {
            Image(systemName: "message.fill")
                .font(.system(size: 9))
                .foregroundColor(Color(uiColor: .ppSuccess))
                .padding(4)
                .background(Color(uiColor: .ppSuccess).opacity(0.1), in: Circle())
        }
        .accessibilityLabel(Language.get("WhatsApp", alter: "واتساب"))
    }
}

// MARK: - Urgency Arc Bar

private struct UrgencyArcBar: View {
    let fraction: Double
    let color: Color
    @State private var animFraction: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * animFraction)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animFraction)
            }
        }
        .onAppear { animFraction = max(0.02, fraction) }
        .onChange(of: fraction) { animFraction = max(0.02, $0) }
    }
}

// MARK: - Pet Avatar View

private struct PetAvatarView: View {
    let url: String
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let imageURL = URL(string: url), !url.isEmpty {
                AdminRemoteImage(url: imageURL, contentMode: .fill, targetSize: CGSize(width: size, height: size)) {
                    placeholderView
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin)
        )
    }

    private var placeholderView: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * 0.35))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.4))
        }
    }
}

// MARK: - Action Icon Button

private struct ActionIconButton: View {
    let systemImage: String
    let tint: Color
    let bg: Color
    let action: () -> Void
    let label: String

    @State private var pressed = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 40, height: 40)
                .background(bg, in: RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin)
                )
                .scaleEffect(pressed ? 0.92 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.65), value: pressed)
        }
        .buttonStyle(PressButtonStyle(pressed: $pressed))
        .accessibilityLabel(label)
    }
}

private struct PressButtonStyle: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { pressed = $0 }
    }
}

// MARK: - Deep Animal Dossier Sheet (Full-Bleed Hero)

// MARK: - Category-Defining Deep Animal Dossier Sheet — Spatial Flight Deck

struct POSReservedPetDossierSheet: View {
    let item: POSReservedPetCardModel
    var viewModel: POSReservedLivePetsViewModel? = nil
    var onCompleteSale: ((POSReservedPetCardModel) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var copiedNotice: String? = nil
    @State private var appeared: Bool = false
    @State private var pulsePill: Bool = false

    private var urgencyColor: Color {
        if item.isExpired      { return Color(uiColor: .ppError) }
        if item.isExpiringSoon { return Color(uiColor: .ppWarning) }
        return Color(uiColor: .ppSuccess)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Spatial Sheet Drag Handle & Navigation Header
            sheetHeader

            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 18) {
                        // Hero Studio Identity Showcase
                        heroShowcaseCard

                        // Quick Operational Action Horizon
                        if viewModel != nil {
                            quickActionHorizon
                        }

                        // Customer & Direct Communication Flight Deck
                        customerFlightDeckSection

                        // Reservation & Forensic Transaction Data
                        reservationTelemetrySection

                        // Financial & Margin Analysis
                        financialPricingSection

                        // Additional Notes & Sourcing
                        if !item.supplier.isEmpty || !item.notes.isEmpty {
                            notesAndSourcingSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 580)
                    .frame(maxWidth: .infinity)
                }

                // Floating Copy Feedback Toast
                if let notice = copiedNotice {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(uiColor: .ppSuccess))

                        Text(notice)
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AdminSurface.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                    .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulsePill = true
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    // MARK: - Subviews

    private var sheetHeader: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 38, height: 4.5)
                .padding(.top, 8)

            HStack(alignment: .center) {
                AdminSquircleCloseButton {
                    dismiss()
                }

                Spacer()

                // Live Hold Status Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(urgencyColor)
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulsePill ? 1.25 : 0.85)

                    Text(item.isExpired ? Language.get("LivePet_Expired", alter: "منتهي الصلاحية") : Language.get("POS_Dossier_Status_ActiveHold", alter: "حجز نشط • معلق"))
                        .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                        .foregroundColor(urgencyColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(urgencyColor.opacity(0.09), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(urgencyColor.opacity(0.2), lineWidth: 0.75)
                )

                Spacer()

                // Share / Copy All Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copyDossierSummary()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AdminSurface.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                            )
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var heroShowcaseCard: some View {
        VStack(spacing: 16) {
            ZStack {
                // Soft Ambient Radial Glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [urgencyColor.opacity(0.18), urgencyColor.opacity(0.02), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 55
                        )
                    )
                    .frame(width: 110, height: 110)

                PetAvatarView(url: item.photoURL, size: 84, cornerRadius: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(urgencyColor.opacity(0.3), lineWidth: 1.5)
                    )
                    .shadow(color: urgencyColor.opacity(0.2), radius: 14, y: 5)
                    .scaleEffect(appeared ? 1.0 : 0.8)
            }

            VStack(spacing: 6) {
                Text(item.animalName)
                    .font(Font.custom("Beiruti-Bold", size: 24, relativeTo: .title2))
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)

                // Identity Pill Horizon
                HStack(spacing: 8) {
                    // Ring Tag (Tap to copy)
                    Button {
                        copyText(item.ringTag, label: Language.get("POS_UnitID", alter: "معرف الوحدة"))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .font(.system(size: 10, weight: .bold))
                            Text(item.ringTag.isEmpty ? "—" : item.ringTag)
                                .font(Font.custom("Beiruti-Bold", size: 12))
                        }
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AdminSurface.primary.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(AdminSurface.primary.opacity(0.2), lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)

                    // Remaining countdown
                    HStack(spacing: 5) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10))
                        Text(item.remainingTimeDescription)
                            .font(Font.custom("Beiruti-Bold", size: 12))
                    }
                    .foregroundColor(urgencyColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(urgencyColor.opacity(0.09), in: Capsule())
                    .overlay(Capsule().strokeBorder(urgencyColor.opacity(0.25), lineWidth: 0.75))

                    // Price lock badge
                    HStack(spacing: 3) {
                        Text(String(format: "%.0f", item.sellingPrice))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                        Text(item.currency.isEmpty ? "ر.ق" : item.currency)
                            .font(Font.custom("Beiruti-Bold", size: 10))
                    }
                    .foregroundColor(Color(uiColor: .ppError))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .ppError).opacity(0.08), in: Capsule())
                }
            }

            // Sleek Urgency Progress Track
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: Language.isRTL() ? .trailing : .leading) {
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .frame(height: 5)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [urgencyColor, urgencyColor.opacity(0.75)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * CGFloat(min(1.0, max(0.05, item.urgencyFraction)))), height: 5)
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }

    private var quickActionHorizon: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
                Text(Language.get("POS_Dossier_QuickActions", alter: "الإجراءات التشغيلية السريعة"))
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 4)

            // Primary Checkout Action
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                dismiss()
                onCompleteSale?(item)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text(Language.get("POS_Dossier_CompleteCheckout", alter: "إتمام البيع في الكاشير"))
                        .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                    Spacer()
                    Text(String(format: "%.0f %@", item.sellingPrice, item.currency.isEmpty ? "ر.ق" : item.currency))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.2), in: Capsule())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: [Color(uiColor: .ppSuccess), Color(uiColor: .ppSuccess).opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: Color(uiColor: .ppSuccess).opacity(0.25), radius: 10, y: 4)
            }
            .buttonStyle(.plain)

            // Secondary Actions: Extend & Release
            HStack(spacing: 10) {
                // Extend Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                    viewModel?.extendingItem = item
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 13, weight: .semibold))
                        Text(Language.get("POS_Action_Extend", alter: "تمديد الحجز"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                    }
                    .foregroundColor(AdminSurface.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)

                // Release Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                    viewModel?.releasingItem = item
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(Language.get("POS_Action_Release", alter: "إلغاء الحجز"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                    }
                    .foregroundColor(Color(uiColor: .ppError))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppError).opacity(0.25), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customerFlightDeckSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
                Text(Language.get("POS_Section_Customer", alter: "بيانات العميل والتواصل"))
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 12) {
                // Customer Name & Source Row
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.1))
                            .frame(width: 38, height: 38)
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AdminSurface.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.customerName.isEmpty ? Language.get("POS_UnnamedCustomer", alter: "عميل بدون اسم") : item.customerName)
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline))
                            .foregroundColor(AdminSurface.primaryText)

                        Text(item.customerSource == "directory" ? "سجل منصة معتمد" : "حساب نقطة البيع")
                            .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    if !item.branchName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 11))
                            Text(item.branchName)
                                .font(Font.custom("Beiruti-Regular", size: 12))
                        }
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    }
                }

                if !item.customerPhone.isEmpty {
                    Divider()
                        .overlay(AdminSurface.hairline)

                    // Phone & Direct Comms Row
                    HStack(spacing: 10) {
                        Button {
                            copyText(item.customerPhone, label: Language.get("POS_Phone", alter: "الهاتف"))
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(AdminSurface.secondaryText)
                                Text(item.customerPhone)
                                    .font(Font.custom("Beiruti-Bold", size: 14))
                                    .foregroundColor(AdminSurface.primaryText)
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // WhatsApp Action
                        Button {
                            let digits = item.customerPhone.filter { "0123456789".contains($0) }
                            guard let url = URL(string: "https://wa.me/\(digits)") else { return }
                            UIApplication.shared.open(url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(Language.get("POS_Dossier_WhatsApp", alter: "واتساب"))
                                    .font(Font.custom("Beiruti-Bold", size: 12))
                            }
                            .foregroundColor(Color(uiColor: .ppSuccess))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        // Call Action
                        Button {
                            guard let url = URL(string: "tel://\(item.customerPhone.filter { "0123456789+".contains($0) })") else { return }
                            UIApplication.shared.open(url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(Language.get("POS_Dossier_CallCustomer", alter: "اتصال"))
                                    .font(Font.custom("Beiruti-Bold", size: 12))
                            }
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
    }

    private var reservationTelemetrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "doc.plaintext.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
                Text(Language.get("POS_Section_Reservation", alter: "بيانات الحجز والمعاملة"))
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                // Receipt Ref Row
                copyableTelemetryRow(
                    icon: "number.circle.fill",
                    title: Language.get("POS_TransactionRef", alter: "رقم المعاملة"),
                    value: POSReceiptFormat.receiptID(item.reservationID),
                    copyPayload: item.reservationID
                )

                Divider().overlay(AdminSurface.hairline)

                // Valid Until Row
                if let valid = item.validUntil {
                    telemetryRow(
                        icon: "calendar.badge.clock",
                        title: Language.get("POS_ValidUntil", alter: "صالح حتى"),
                        value: {
                            let fmt = DateFormatter()
                            fmt.dateStyle = .medium
                            fmt.timeStyle = .short
                            fmt.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
                            return fmt.string(from: valid)
                        }()
                    )
                    Divider().overlay(AdminSurface.hairline)
                }

                // Unit ID Row
                copyableTelemetryRow(
                    icon: "tag.fill",
                    title: Language.get("POS_UnitID", alter: "معرف الوحدة"),
                    value: item.unitID,
                    copyPayload: item.unitID
                )
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
    }

    private var financialPricingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
                Text(Language.get("POS_Section_Financial", alter: "البيانات المالية والتسعير"))
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                // Locked Price
                telemetryRow(
                    icon: "lock.fill",
                    title: Language.get("POS_LockedPrice", alter: "سعر الحجز المعتمد"),
                    value: String(format: "%.2f %@", item.sellingPrice, item.currency.isEmpty ? "ر.ق" : item.currency),
                    highlightColor: Color(uiColor: .ppError)
                )

                // Purchase Cost & Margin (if available)
                if let cost = item.purchaseCost, cost > 0 {
                    Divider().overlay(AdminSurface.hairline)

                    telemetryRow(
                        icon: "cart.fill",
                        title: Language.get("LivePet_PurchaseCost", alter: "تكلفة الشراء"),
                        value: String(format: "%.2f %@", cost, item.currency.isEmpty ? "ر.ق" : item.currency)
                    )

                    Divider().overlay(AdminSurface.hairline)

                    let margin = item.sellingPrice - cost
                    let marginPct = cost > 0 ? (margin / item.sellingPrice) * 100 : 0
                    telemetryRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: Language.get("POS_Dossier_Margin", alter: "هامش الربح التقديري"),
                        value: String(format: "+%.2f (%d%%)", margin, Int(marginPct)),
                        highlightColor: Color(uiColor: .ppSuccess)
                    )
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
    }

    private var notesAndSourcingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
                Text(Language.get("POS_Section_Notes", alter: "ملاحظات إضافية ومصدر التوريد"))
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if !item.supplier.isEmpty {
                    telemetryRow(
                        icon: "building.columns.fill",
                        title: Language.get("LivePet_Supplier", alter: "المورد"),
                        value: item.supplier
                    )
                }

                if !item.notes.isEmpty {
                    if !item.supplier.isEmpty { Divider().overlay(AdminSurface.hairline) }

                    VStack(alignment: .leading, spacing: 4) {
                        Label(Language.get("POS_Notes", alter: "ملاحظات"), systemImage: "note.text")
                            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(item.notes)
                            .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
    }

    // MARK: - Telemetry Row Helpers

    private func telemetryRow(icon: String, title: String, value: String, highlightColor: Color? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(AdminSurface.primary.opacity(0.7))
                .frame(width: 22)

            Text(title)
                .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                .foregroundColor(AdminSurface.secondaryText)

            Spacer()

            Text(value)
                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .body))
                .foregroundColor(highlightColor ?? AdminSurface.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func copyableTelemetryRow(icon: String, title: String, value: String, copyPayload: String) -> some View {
        Button {
            copyText(copyPayload, label: title)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(AdminSurface.primary.opacity(0.7))
                    .frame(width: 22)

                Text(title)
                    .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                    .foregroundColor(AdminSurface.secondaryText)

                Spacer()

                HStack(spacing: 6) {
                    Text(value)
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func copyText(_ text: String, label: String) {
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            copiedNotice = "\(Language.get("POS_Dossier_Copied", alter: "تم النسخ للحافظة")): \(text)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.25)) {
                if copiedNotice?.contains(text) == true {
                    copiedNotice = nil
                }
            }
        }
    }

    private func copyDossierSummary() {
        let summary = """
        \(item.animalName) (#\(item.ringTag))
        \(Language.get("POS_TransactionRef", alter: "رقم المعاملة")): \(item.reservationID)
        \(Language.get("POS_Customer", alter: "العميل")): \(item.customerName) (\(item.customerPhone))
        \(Language.get("POS_LockedPrice", alter: "السعر")): \(String(format: "%.2f %@", item.sellingPrice, item.currency))
        \(Language.get("POS_Branch", alter: "الفرع")): \(item.branchName)
        """
        copyText(summary, label: item.animalName)
    }
}


// MARK: - Extend Hold Sheet

struct POSExtendReservationSheet: View {
    let item: POSReservedPetCardModel
    @ObservedObject var viewModel: POSReservedLivePetsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedHours: Int = 24
    @State private var customDate: Date = Date().addingTimeInterval(24 * 3600)
    @State private var reason: String = ""
    @State private var isSubmitting: Bool = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AdminSpacing.lg) {
                    // Illustration header
                    VStack(spacing: AdminSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.primary.opacity(0.08))
                                .frame(width: 80, height: 80)
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 36, weight: .light))
                                .foregroundColor(AdminSurface.primary)
                        }
                        .padding(.top, AdminSpacing.lg)

                        Text(Language.get("POS_Extend_Title", alter: "تمديد مهلة الحجز"))
                            .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3))
                            .foregroundColor(AdminSurface.primaryText)

                        Text("\(item.animalName) · #\(item.ringTag)")
                            .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    // Quick presets
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(Language.get("POS_QuickExtend", alter: "تمديد سريع"))
                            .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, AdminSpacing.xs)

                        HStack(spacing: 8) {
                            presetChip(title: "+٢٤ ساعة", hours: 24)
                            presetChip(title: "+٤٨ ساعة", hours: 48)
                            presetChip(title: "+٧ أيام", hours: 168)
                            presetChip(title: "+٣٠ يوم", hours: 720)
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)

                    // Date Picker
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(Language.get("POS_NewExpiryDate", alter: "تاريخ وساعة الانتهاء الجديدة"))
                            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, AdminSpacing.xs)

                        DatePicker("", selection: $customDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .padding(AdminSpacing.md)
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)

                    // Reason
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(Language.get("POS_ExtendReason", alter: "سبب التمديد (اختياري)"))
                            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, AdminSpacing.xs)

                        TextField(
                            Language.get("POS_ExtendReason_Placeholder", alter: "طلب العميل، تأكيد موعد الاستلام..."),
                            text: $reason
                        )
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                        .padding(AdminSpacing.md)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isSubmitting = true
                    Task {
                        let ok = await viewModel.extendHold(for: item, newValidUntil: customDate, reason: reason)
                        isSubmitting = false
                        if ok { dismiss() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSubmitting { ProgressView().tint(.white) }
                        else { Image(systemName: "checkmark.circle.fill") }
                        Text(Language.get("POS_Confirm_Extend", alter: "تأكيد تمديد الحجز"))
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
                    .shadow(color: AdminSurface.primary.opacity(0.3), radius: 10, y: 4)
                }
                .disabled(isSubmitting)
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, AdminSpacing.md)
                .background(.thinMaterial)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                        .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                }
            }
        }
    }

    private func presetChip(title: String, hours: Int) -> some View {
        let isSelected = selectedHours == hours
        return Button {
            selectedHours = hours
            customDate = Date().addingTimeInterval(TimeInterval(hours * 3600))
        } label: {
            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AdminSpacing.sm)
                .background(
                    isSelected ? AdminSurface.primary : Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                        .stroke(isSelected ? .clear : AdminSurface.hairline, lineWidth: AdminStroke.thin)
                )
                .shadow(color: isSelected ? AdminSurface.primary.opacity(0.25) : .clear, radius: 5, y: 2)
        }
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Release Hold Sheet

// MARK: - Category-Defining Release Hold Sheet — Spatial Operational Horizon

struct POSReleaseReservationSheet: View {
    let item: POSReservedPetCardModel
    @ObservedObject var viewModel: POSReservedLivePetsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String = ""
    @State private var selectedChip: String? = nil
    @State private var isSubmitting: Bool = false
    @State private var confirmed: Bool = false
    @State private var pulseWarning: Bool = false
    @State private var hasAppeared: Bool = false

    private struct QuickReasonOption: Identifiable {
        let id: String
        let key: String
        let fallback: String
        let icon: String
    }

    private let quickReasons: [QuickReasonOption] = [
        .init(id: "no_show", key: "POS_Release_Chip_NoShow", fallback: "عدم حضور العميل", icon: "person.fill.xmark"),
        .init(id: "customer_request", key: "POS_Release_Chip_CustomerRequest", fallback: "طلب العميل الإلغاء", icon: "phone.down.fill"),
        .init(id: "expired", key: "POS_Release_Chip_Expired", fallback: "انتهاء مهلة الحجز", icon: "clock.badge.xmark.fill"),
        .init(id: "swapped", key: "POS_Release_Chip_Swapped", fallback: "استبدال بحيوان آخر", icon: "arrow.triangle.2.circlepath"),
        .init(id: "clerical_error", key: "POS_Release_Chip_ClericalError", fallback: "خطأ في تسجيل الحجز", icon: "pencil.and.outline")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Spatial Sheet Drag Handle & Navigation Header
            sheetNavigationHeader

            ScrollView {
                VStack(spacing: 20) {
                    // Hero Spatial Warning Shield
                    heroWarningSection

                    // Live Animal & Customer Dossier Card
                    liveAnimalIdentityCard

                    // 3-Pillar Consequence Blueprint
                    consequenceHorizonSection

                    // Quick-Tap Reasons & Custom Text Input
                    reasonSelectorSection

                    // Operator Governance & Responsibility Card
                    responsibilityAgreementCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: 580)
                .frame(maxWidth: .infinity)
            }

            // Flagship Sticky Bottom Dock
            stickyActionDock
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseWarning = true
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Subviews

    private var sheetNavigationHeader: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 38, height: 4.5)
                .padding(.top, 8)

            HStack(alignment: .center) {
                AdminSquircleCloseButton {
                    dismiss()
                }

                Spacer()

                // Sensitive Operational Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(uiColor: .ppError))
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulseWarning ? 1.3 : 0.85)

                    Text(Language.get("POS_Release_Sensitive_Action", alter: "إجراء تشغيلي حساس"))
                        .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                        .foregroundColor(Color(uiColor: .ppError))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(uiColor: .ppError).opacity(0.08), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color(uiColor: .ppError).opacity(0.18), lineWidth: 0.75)
                )

                Spacer()

                // Balance Box
                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var heroWarningSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(uiColor: .ppError).opacity(0.20), Color(uiColor: .ppError).opacity(0.03), .clear],
                            center: .center,
                            startRadius: 15,
                            endRadius: 54
                        )
                    )
                    .frame(width: 108, height: 108)

                Circle()
                    .strokeBorder(Color(uiColor: .ppError).opacity(0.20), lineWidth: 1)
                    .frame(width: 84, height: 84)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(uiColor: .ppError).opacity(0.15), Color(uiColor: .ppError).opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                    )
                    .shadow(color: Color(uiColor: .ppError).opacity(0.25), radius: 14, y: 5)

                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(uiColor: .ppError), Color(uiColor: .ppError).opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(hasAppeared ? 1.0 : 0.75)
            }

            VStack(spacing: 6) {
                Text(Language.get("POS_Release_Title", alter: "إلغاء حجز الحيوان"))
                    .font(Font.custom("Beiruti-Bold", size: 23, relativeTo: .title2))
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("POS_Release_Warning", alter: "سيتم تحرير الحيوان فوراً من عهدة الحجز وإعادته للمخزون المتاح للبيع في المتجر."))
                    .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .subheadline))
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 4)
    }

    private var liveAnimalIdentityCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                PetAvatarView(url: item.photoURL, size: 60, cornerRadius: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppError).opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.animalName)
                            .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)

                        Spacer()

                        // Locked Price Pill
                        HStack(spacing: 3) {
                            Text(String(format: "%.0f", item.sellingPrice))
                                .font(Font.custom("Beiruti-Bold", size: 17, relativeTo: .callout))
                            Text(item.currency.isEmpty ? "ر.ق" : item.currency)
                                .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption2))
                        }
                        .foregroundColor(Color(uiColor: .ppError))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color(uiColor: .ppError).opacity(0.09), in: Capsule())
                    }

                    HStack(spacing: 8) {
                        // Ring Tag Pill
                        HStack(spacing: 3) {
                            Image(systemName: "number")
                                .font(.system(size: 10, weight: .bold))
                            Text(item.ringTag.isEmpty ? "—" : item.ringTag)
                                .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                        }
                        .foregroundColor(AdminSurface.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())

                        if !item.branchName.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 10))
                                Text(item.branchName)
                                    .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                                    .lineLimit(1)
                            }
                            .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }
            }

            Divider()
                .overlay(AdminSurface.hairline)

            // Customer & Expiry Sub-Row
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AdminSurface.secondaryText)

                    Text(item.customerName.isEmpty ? Language.get("POS_UnnamedCustomer", alter: "بدون اسم") : item.customerName)
                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .subheadline))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    if !item.customerPhone.isEmpty {
                        Text("· \(item.customerPhone)")
                            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Expiry Countdown Badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(item.isExpired ? Color(uiColor: .ppError) : (item.isExpiringSoon ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess)))
                        .frame(width: 6, height: 6)

                    Text(item.remainingTimeDescription)
                        .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                        .foregroundColor(item.isExpired ? Color(uiColor: .ppError) : (item.isExpiringSoon ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess)))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    (item.isExpired ? Color(uiColor: .ppError) : (item.isExpiringSoon ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess))).opacity(0.1),
                    in: Capsule()
                )
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppError).opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private var consequenceHorizonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)

                Text(Language.get("POS_Release_Consequence_Title", alter: "الأثر التشغيلي للإلغاء الفوري"))
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 8) {
                consequenceRow(
                    icon: "arrow.uturn.backward.circle.fill",
                    color: Color(uiColor: .ppSuccess),
                    text: Language.get("POS_Release_Consequence_Stock", alter: "إعادة فورية للحيوان إلى المخزون المتاح للبيع")
                )
                consequenceRow(
                    icon: "creditcard.trianglebadge.exclamationmark.fill",
                    color: Color(uiColor: .ppWarning),
                    text: Language.get("POS_Release_Consequence_Hold", alter: "فك الحجز المالي وتحرير رقم حلقة التعريف")
                )
                consequenceRow(
                    icon: "shield.checkered",
                    color: Color(uiColor: .ppInfo),
                    text: Language.get("POS_Release_Consequence_Audit", alter: "توثيق حركة الإلغاء في سجل التدقيق باسم الموظف")
                )
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
    }

    private func consequenceRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)

            Text(text)
                .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .subheadline))
                .foregroundColor(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var reasonSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("POS_Release_Reason", alter: "سبب الإلغاء والتحرير"))
                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.horizontal, 4)

            // Dynamic Preset Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickReasons) { chip in
                        let isSelected = selectedChip == chip.id
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                if isSelected {
                                    selectedChip = nil
                                    reason = ""
                                } else {
                                    selectedChip = chip.id
                                    reason = Language.get(chip.key, alter: chip.fallback)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: chip.icon)
                                    .font(.system(size: 11, weight: .bold))
                                Text(Language.get(chip.key, alter: chip.fallback))
                                    .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Regular", size: 13))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? Color(uiColor: .ppError) : AdminSurface.surface,
                                in: Capsule()
                            )
                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        isSelected ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.8),
                                        lineWidth: 0.8
                                    )
                            )
                            .shadow(color: isSelected ? Color(uiColor: .ppError).opacity(0.25) : Color.black.opacity(0.02), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }

            // Custom Text Field with Clear Action
            HStack(spacing: 10) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 14))
                    .foregroundColor(AdminSurface.secondaryText)

                TextField(
                    Language.get("POS_Release_Reason_Placeholder", alter: "اختر سبباً سريعاً أو اكتب توضيحاً مخصصاً..."),
                    text: $reason
                )
                .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                .foregroundColor(AdminSurface.primaryText)

                if !reason.isEmpty {
                    Button {
                        reason = ""
                        selectedChip = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(reason.isEmpty ? AdminSurface.hairline : Color(uiColor: .ppError).opacity(0.4), lineWidth: 1)
            )
        }
    }

    private var responsibilityAgreementCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                confirmed.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(confirmed ? Color(uiColor: .ppError) : Color(uiColor: .secondarySystemBackground))
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(confirmed ? Color.clear : AdminSurface.secondaryText.opacity(0.35), lineWidth: 1)
                        )

                    if confirmed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("POS_Release_Confirm_Label", alter: "أقر بمسؤوليتي التشغيلية عن تحرير هذا الحيوان وإعادته للمخزون نيابةً عن إدارة المتجر"))
                        .font(Font.custom(confirmed ? "Beiruti-Bold" : "Beiruti-Regular", size: 13, relativeTo: .subheadline))
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                confirmed ? Color(uiColor: .ppError).opacity(0.07) : AdminSurface.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        confirmed ? Color(uiColor: .ppError).opacity(0.4) : AdminSurface.hairline,
                        lineWidth: confirmed ? 1.25 : 0.75
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var stickyActionDock: some View {
        VStack(spacing: 8) {
            Button {
                guard confirmed, !isSubmitting else {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    return
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isSubmitting = true
                Task {
                    let ok = await viewModel.releaseHold(for: item, reason: reason)
                    isSubmitting = false
                    if ok { dismiss() }
                }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView().tint(.white)
                        Text(Language.get("POS_Release_Submitting", alter: "جارٍ تحرير الحجز وتحديث المخزون..."))
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                    } else {
                        Image(systemName: confirmed ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text(confirmed ? Language.get("POS_Confirm_Release", alter: "تأكيد إلغاء الحجز والتحرير") : Language.get("POS_Release_Acknowledge_Required", alter: "يلزم تفعيل إقرار المسؤولية أولاً للمتابعة"))
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    confirmed
                        ? LinearGradient(colors: [Color(uiColor: .ppError), Color(uiColor: .ppError).opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color(uiColor: .ppError).opacity(0.4), Color(uiColor: .ppError).opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .shadow(color: confirmed ? Color(uiColor: .ppError).opacity(0.35) : .clear, radius: 12, y: 5)
            }
            .disabled(isSubmitting || !confirmed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: confirmed)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Text(Language.get("POS_Release_KeepReservation", alter: "الاحتفاظ بالحجز والرجوع"))
                    .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .subheadline))
                    .foregroundColor(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(
            AdminSurface.surface
                .opacity(0.95)
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(AdminSurface.hairline)
                        .frame(height: 0.75),
                    alignment: .top
                )
        )
    }
}

