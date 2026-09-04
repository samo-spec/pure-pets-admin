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
            POSReservedPetDossierSheet(item: item)
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
            // Title Bar
            HStack(spacing: AdminSpacing.sm) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 36, height: 36)
                        .background(.thinMaterial, in: Circle())
                        .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin))
                }
                .accessibilityLabel(Language.get("Close", alter: "إغلاق"))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(Language.get("POS_LivePets_Desk", alter: "نقطة البيع · حجوزات الحيوانات"))
                            .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.secondaryText)
                        // Live pulse dot
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 5, height: 5)
                            .scaleEffect(isRefreshSpinning ? 1.6 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRefreshSpinning)
                    }
                    Text(Language.get("POS_ReservedLivePets_Title", alter: "الحيوانات المحجوزة"))
                        .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .headline))
                        .foregroundColor(AdminSurface.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isRefreshSpinning = true
                        refreshSpinAngle += 360
                    }
                    Task {
                        await vm.loadData()
                        isRefreshSpinning = false
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                        .rotationEffect(.degrees(refreshSpinAngle))
                        .animation(.spring(response: 0.6, dampingFraction: 0.5), value: refreshSpinAngle)
                        .frame(width: 36, height: 36)
                        .background(.thinMaterial, in: Circle())
                        .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin))
                }
                .accessibilityLabel(Language.get("POS_Refresh", alter: "تحديث"))
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, AdminSpacing.md)
            .padding(.bottom, AdminSpacing.sm)

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

struct POSReservedPetDossierSheet: View {
    let item: POSReservedPetCardModel
    @Environment(\.dismiss) private var dismiss

    @State private var heroScale: CGFloat = 1.05
    @State private var appeared: Bool = false

    private var urgencyColor: Color {
        if item.isExpired      { return Color(uiColor: .ppError) }
        if item.isExpiringSoon { return Color(uiColor: .ppWarning) }
        return Color(uiColor: .ppSuccess)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Full-bleed hero
                    ZStack(alignment: .bottom) {
                        heroImage
                            .frame(height: 260)
                            .clipped()

                        // Gradient scrim
                        LinearGradient(
                            colors: [.clear, Color(uiColor: .systemBackground).opacity(0.9)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 120)

                        // Hero identity overlay
                        VStack(spacing: 6) {
                            Text(item.animalName)
                                .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title2))
                                .foregroundColor(AdminSurface.primaryText)

                            HStack(spacing: 8) {
                                Label("#\(item.ringTag)", systemImage: "number.circle.fill")
                                    .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.thinMaterial, in: Capsule())

                                Text(item.remainingTimeDescription)
                                    .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                                    .foregroundColor(urgencyColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(urgencyColor.opacity(0.1), in: Capsule())
                                    .overlay(Capsule().stroke(urgencyColor.opacity(0.25), lineWidth: 1))
                            }
                        }
                        .padding(.bottom, 18)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: appeared)
                    }

                    // Urgency bar
                    UrgencyArcBar(fraction: item.urgencyFraction, color: urgencyColor)
                        .frame(height: 4)
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.vertical, AdminSpacing.sm)

                    // Dossier Matrix
                    VStack(spacing: AdminSpacing.xs) {
                        dossierSection(title: Language.get("POS_Section_Reservation", alter: "بيانات الحجز")) {
                            dossierRow(icon: "number.circle", title: Language.get("POS_TransactionRef", alter: "رقم المعاملة"), value: POSReceiptFormat.receiptID(item.reservationID), mono: true)
                            if let valid = item.validUntil {
                                dossierRow(icon: "clock.fill", title: Language.get("POS_ValidUntil", alter: "صالح حتى"), value: {
                                    let fmt = DateFormatter()
                                    fmt.dateStyle = .medium
                                    fmt.timeStyle = .short
                                    fmt.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
                                    return fmt.string(from: valid)
                                }())
                            }
                            dossierRow(icon: "tag.fill", title: Language.get("POS_UnitID", alter: "معرف الوحدة"), value: item.unitID, mono: true)
                        }

                        dossierSection(title: Language.get("POS_Section_Customer", alter: "بيانات العميل")) {
                            dossierRow(icon: "person.fill", title: Language.get("POS_Customer", alter: "الاسم"), value: item.customerName.isEmpty ? "—" : item.customerName)
                            if !item.customerPhone.isEmpty {
                                dossierRowWithActions(
                                    icon: "phone.fill",
                                    title: Language.get("POS_Phone", alter: "الهاتف"),
                                    value: item.customerPhone,
                                    phone: item.customerPhone
                                )
                            }
                            if !item.branchName.isEmpty {
                                dossierRow(icon: "building.2.fill", title: Language.get("POS_Branch", alter: "الفرع"), value: item.branchName)
                            }
                        }

                        dossierSection(title: Language.get("POS_Section_Financial", alter: "البيانات المالية")) {
                            dossierRow(icon: "banknote.fill", title: Language.get("POS_LockedPrice", alter: "سعر الحجز المعتمد"), value: "\(String(format: "%.2f", item.sellingPrice)) ر.ق")
                            if let cost = item.purchaseCost, cost > 0 {
                                dossierRow(icon: "cart.fill", title: Language.get("LivePet_PurchaseCost", alter: "تكلفة الشراء"), value: "\(String(format: "%.2f", cost)) ر.ق")
                            }
                        }

                        if !item.supplier.isEmpty || !item.notes.isEmpty {
                            dossierSection(title: Language.get("POS_Section_Notes", alter: "ملاحظات إضافية")) {
                                if !item.supplier.isEmpty {
                                    dossierRow(icon: "shippingbox.fill", title: Language.get("LivePet_Supplier", alter: "المورد"), value: item.supplier)
                                }
                                if !item.notes.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label(Language.get("POS_Notes", alter: "ملاحظات"), systemImage: "note.text")
                                            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                                            .foregroundColor(AdminSurface.secondaryText)
                                        Text(item.notes)
                                            .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                                            .foregroundColor(AdminSurface.primaryText)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.bottom, AdminSpacing.xxl)
                }
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Language.get("POS_AnimalDossier_Title", alter: "ملف الحيوان المحجوز"))
                        .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                        .foregroundColor(AdminSurface.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Done", alter: "تم")) { dismiss() }
                        .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .body))
                        .foregroundColor(AdminSurface.primary)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { appeared = true }
    }

    private var heroImage: some View {
        ZStack {
            if let url = URL(string: item.photoURL), !item.photoURL.isEmpty {
                AdminRemoteImage(url: url, contentMode: .fill) {
                    heroPlaeholder
                }
                .scaleEffect(heroScale)
                .onAppear {
                    withAnimation(.easeOut(duration: 1.2)) { heroScale = 1.0 }
                }
            } else {
                heroPlaeholder
            }
        }
    }

    private var heroPlaeholder: some View {
        ZStack {
            LinearGradient(
                colors: [AdminSurface.primary.opacity(0.15), AdminSurface.primary.opacity(0.04)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "pawprint.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(AdminSurface.primary.opacity(0.25))
        }
    }

    private func dossierSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.leading, 4)
                .padding(.top, AdminSpacing.md)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin)
            )
        }
    }

    private func dossierRow(icon: String, title: String, value: String, mono: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(AdminSurface.primary.opacity(0.6))
                .frame(width: 22)

            Text(title)
                .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                .foregroundColor(AdminSurface.secondaryText)
            Spacer()
            Text(value)
                .font(mono
                      ? Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption)
                      : Font.custom("Beiruti-Bold", size: 13, relativeTo: .body))
                .foregroundColor(AdminSurface.primaryText)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, AdminSpacing.md)
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(AdminSurface.hairline).frame(height: AdminStroke.thin), alignment: .bottom)
    }

    private func dossierRowWithActions(icon: String, title: String, value: String, phone: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(AdminSurface.primary.opacity(0.6))
                .frame(width: 22)

            Text(title)
                .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                .foregroundColor(AdminSurface.secondaryText)
            Spacer()
            HStack(spacing: 6) {
                Text(value)
                    .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                    .foregroundColor(AdminSurface.primaryText)

                // Call
                Button {
                    guard let url = URL(string: "tel://\(phone.filter { "0123456789+".contains($0) })") else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(uiColor: .ppSuccess))
                        .padding(5)
                        .background(Color(uiColor: .ppSuccess).opacity(0.1), in: Circle())
                }

                // WhatsApp
                Button {
                    let digits = phone.filter { "0123456789".contains($0) }
                    guard let url = URL(string: "https://wa.me/\(digits)") else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Image(systemName: "message.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(uiColor: .ppSuccess))
                        .padding(5)
                        .background(Color(uiColor: .ppSuccess).opacity(0.1), in: Circle())
                }
            }
        }
        .padding(.horizontal, AdminSpacing.md)
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(AdminSurface.hairline).frame(height: AdminStroke.thin), alignment: .bottom)
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

struct POSReleaseReservationSheet: View {
    let item: POSReservedPetCardModel
    @ObservedObject var viewModel: POSReservedLivePetsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String = ""
    @State private var isSubmitting: Bool = false
    @State private var confirmed: Bool = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AdminSpacing.lg) {
                    // Warning illustration
                    VStack(spacing: AdminSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color(uiColor: .ppError).opacity(0.1))
                                .frame(width: 80, height: 80)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 36, weight: .light))
                                .foregroundColor(Color(uiColor: .ppError))
                        }
                        .padding(.top, AdminSpacing.lg)

                        Text(Language.get("POS_Release_Title", alter: "إلغاء الحجز"))
                            .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3))
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("POS_Release_Warning",
                                          alter: "سيتم إلغاء الحجز فوراً وإعادة الحيوان إلى المخزون المتاح لجميع العملاء."))
                            .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                            .foregroundColor(AdminSurface.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AdminSpacing.xl)
                    }

                    // Pet identity reminder
                    HStack(spacing: AdminSpacing.sm) {
                        PetAvatarView(url: item.photoURL, size: 44, cornerRadius: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.animalName)
                                .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                                .foregroundColor(AdminSurface.primaryText)
                            Text("#\(item.ringTag) · \(item.customerName.isEmpty ? Language.get("POS_UnnamedCustomer", alter: "بدون اسم") : item.customerName)")
                                .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        Spacer()
                        Text("\(String(format: "%.0f", item.sellingPrice)) ر.ق")
                            .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .callout))
                            .foregroundColor(Color(uiColor: .ppError))
                    }
                    .padding(AdminSpacing.md)
                    .background(Color(uiColor: .ppError).opacity(0.05), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .stroke(Color(uiColor: .ppError).opacity(0.15), lineWidth: AdminStroke.thin)
                    )
                    .padding(.horizontal, AdminSpacing.screenMargin)

                    // Reason
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(Language.get("POS_Release_Reason", alter: "سبب الإلغاء"))
                            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, AdminSpacing.xs)

                        TextField(
                            Language.get("POS_Release_Reason_Placeholder", alter: "عدم حضور العميل، طلب الإلغاء..."),
                            text: $reason
                        )
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                        .padding(AdminSpacing.md)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)

                    // Confirmation toggle
                    HStack(spacing: AdminSpacing.sm) {
                        Toggle("", isOn: $confirmed)
                            .labelsHidden()
                            .tint(Color(uiColor: .ppError))
                        Text(Language.get("POS_Release_Confirm_Label", alter: "أتحمل مسؤولية إلغاء هذا الحجز نيابةً عن إدارة المتجر"))
                            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isSubmitting = true
                    Task {
                        let ok = await viewModel.releaseHold(for: item, reason: reason)
                        isSubmitting = false
                        if ok { dismiss() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSubmitting { ProgressView().tint(.white) }
                        else { Image(systemName: "lock.open.fill") }
                        Text(Language.get("POS_Confirm_Release", alter: "تأكيد إلغاء الحجز"))
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        confirmed ? Color(uiColor: .ppError) : Color(uiColor: .ppError).opacity(0.4),
                        in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                    )
                    .shadow(color: confirmed ? Color(uiColor: .ppError).opacity(0.3) : .clear, radius: 10, y: 4)
                }
                .disabled(isSubmitting || !confirmed)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: confirmed)
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, AdminSpacing.md)
                .background(.thinMaterial)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "تراجع")) { dismiss() }
                        .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                }
            }
        }
    }
}
