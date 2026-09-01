//
//  POSReservedLivePetsView.swift
//  PurePetsAdmin
//
//  Flagship Beyond-FAANG Reserved Live Pets Operations & Details Horizon.
//  Reimagined from first principles for instant cashier handoff, hold management,
//  urgency tracking, telemetry horizons, and deep animal dossiers.
//

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Models & Projections

public struct POSReservedPetCardModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let reservationID: String
    public let productID: String
    public let unitID: String
    public let ringTag: String
    public let animalName: String
    public let photoURL: String
    public let sellingPrice: Double
    public let standardPrice: Double
    public let customerName: String
    public let customerPhone: String
    public let customerSource: String
    public let branchID: String
    public let branchName: String
    public let validUntil: Date?
    public let createdAt: Date?
    public let notes: String
    public let supplier: String
    public let purchaseCost: Double?

    public var isExpired: Bool {
        guard let validUntil else { return false }
        return validUntil < Date()
    }

    public var isExpiringSoon: Bool {
        guard let validUntil, !isExpired else { return false }
        return validUntil.timeIntervalSinceNow < (24 * 60 * 60)
    }

    public var remainingHours: Int {
        guard let validUntil else { return 0 }
        let interval = validUntil.timeIntervalSinceNow
        return max(0, Int(interval / 3600))
    }

    public var remainingTimeDescription: String {
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

        if days > 0 {
            let format = Language.get("LivePet_RemainingDays_Format", alter: "متبقي %d يوم")
            return String(format: format, days)
        } else if hours > 0 {
            let format = Language.get("LivePet_RemainingHours_Format", alter: "متبقي %d ساعة")
            return String(format: format, hours)
        } else {
            return Language.get("LivePet_ExpiringNow", alter: "ينتهي خلال أقل من ساعة")
        }
    }
}

public enum POSReservationFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case expiringSoon
    case expired

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return Language.get("POS_Filter_All", alter: "الكل")
        case .active: return Language.get("POS_Filter_Active", alter: "نشط ومؤكد")
        case .expiringSoon: return Language.get("POS_Filter_ExpiringSoon", alter: "ينتهي قريباً")
        case .expired: return Language.get("POS_Filter_Expired", alter: "منتهي الصلاحية")
        }
    }

    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .active: return "checkmark.seal.fill"
        case .expiringSoon: return "clock.badge.exclamationmark.fill"
        case .expired: return "exclamationmark.octagon.fill"
        }
    }
}

// MARK: - ViewModel

@MainActor
public final class POSReservedLivePetsViewModel: ObservableObject {
    @Published public var items: [POSReservedPetCardModel] = []
    @Published public var isLoading: Bool = false
    @Published public var isRefreshing: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var searchText: String = ""
    @Published public var activeFilter: POSReservationFilter = .all
    @Published public var selectedBranchID: String = ""
    @Published public var branches: [PPInventoryBranchOption] = []
    @Published public var activeDossierItem: POSReservedPetCardModel? = nil
    @Published public var extendingItem: POSReservedPetCardModel? = nil
    @Published public var releasingItem: POSReservedPetCardModel? = nil
    @Published public var operationSuccessNotice: String? = nil

    private var accessoriesByID: [String: PetAccessory] = [:]
    private var branchesByID: [String: String] = [:]

    public init(accessories: [PetAccessory] = []) {
        updateAccessories(accessories)
    }

    public func updateAccessories(_ accessories: [PetAccessory]) {
        for acc in accessories {
            accessoriesByID[acc.accessoryID] = acc
        }
    }

    // Telemetry computations
    public var totalCount: Int { items.count }

    public var activeCount: Int {
        items.filter { !$0.isExpired }.count
    }

    public var expiringSoonCount: Int {
        items.filter { $0.isExpiringSoon }.count
    }

    public var expiredCount: Int {
        items.filter { $0.isExpired }.count
    }

    public var totalHeldValue: Double {
        items.reduce(0) { $0 + $1.sellingPrice }
    }

    public var uniqueCustomersCount: Int {
        Set(items.map { $0.customerPhone.isEmpty ? $0.customerName : $0.customerPhone }).count
    }

    public var filteredItems: [POSReservedPetCardModel] {
        items.filter { item in
            // Filter by branch if selected
            if !selectedBranchID.isEmpty && item.branchID != selectedBranchID {
                return false
            }

            // Filter by tab
            switch activeFilter {
            case .all:
                break
            case .active:
                if item.isExpired { return false }
            case .expiringSoon:
                if !item.isExpiringSoon { return false }
            case .expired:
                if !item.isExpired { return false }
            }

            // Search query filter
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

    public func loadData() async {
        isLoading = items.isEmpty
        isRefreshing = !items.isEmpty
        errorMessage = nil

        do {
            async let branchesTask = PPLivePetInventoryService.listBranches()
            async let reservationsTask = fetchAllReservedUnits()

            let (branchList, loadedUnits) = try await (branchesTask, reservationsTask)

            self.branches = branchList
            self.branchesByID = branchList.reduce(into: [:]) { $0[$1.id] = $1.name }
            self.items = loadedUnits.sorted {
                let left = $0.validUntil ?? Date.distantFuture
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
        var cardModels: [POSReservedPetCardModel] = []
        var seenKeys = Set<String>()

        // 1. Fetch live pet reservations via canonical backend callable
        do {
            let reservations = try await PPLivePetInventoryService.listReservations(productID: "")
            for res in reservations {
                let branchTitle = branchesByID[res.branchID] ?? res.branchID
                for item in res.items {
                    let accessory = accessoriesByID[item.productID]
                    let petName = accessory?.name ?? Language.get("LiveAnimal", alter: "حيوان حي")
                    let photo = accessory?.pictures.firstObject as? String ?? ""
                    let stdPrice = accessory?.pos_canonicalUnitPrice ?? res.total

                    for (index, unitID) in item.unitIDs.enumerated() {
                        let ring = index < item.ringTags.count ? item.ringTags[index] : unitID
                        let unitKey = "\(item.productID)_\(unitID)"
                        if seenKeys.contains(unitKey) { continue }
                        seenKeys.insert(unitKey)

                        cardModels.append(
                            POSReservedPetCardModel(
                                id: unitKey,
                                reservationID: res.id,
                                productID: item.productID,
                                unitID: unitID,
                                ringTag: ring,
                                animalName: petName,
                                photoURL: photo,
                                sellingPrice: stdPrice,
                                standardPrice: stdPrice,
                                customerName: res.customerName,
                                customerPhone: res.customerPhone,
                                customerSource: res.customerSource,
                                branchID: res.branchID,
                                branchName: branchTitle,
                                validUntil: res.validUntil,
                                createdAt: nil,
                                notes: "",
                                supplier: "",
                                purchaseCost: nil
                            )
                        )
                    }
                }
            }
        } catch {
            // Fallback to Firestore inspection if callable reports scope or truncation
        }

        // 2. Direct Firestore fallback query on live-pet accessories with RESERVED units
        if cardModels.isEmpty {
            let snapshot = try await Firestore.firestore()
                .collection("petAccessories")
                .whereField("isLivePet", isEqualTo: true)
                .getDocuments()

            for doc in snapshot.documents {
                let pData = doc.data()
                let productID = doc.documentID
                let petName = PPLivePetInventoryService.string(pData["name"])
                let pictures = pData["pictures"] as? [String] ?? []
                let photo = pictures.first ?? ""
                let stdPrice = PPLivePetInventoryService.optionalNumber(pData["price"]) ?? 0

                let unitsSnap = try await doc.reference
                    .collection("inventoryUnits")
                    .whereField("status", isEqualTo: "RESERVED")
                    .getDocuments()

                for uDoc in unitsSnap.documents {
                    let u = PPLivePetInventoryUnit(dictionary: uDoc.data())
                    let unitKey = "\(productID)_\(u.id)"
                    if seenKeys.contains(unitKey) { continue }
                    seenKeys.insert(unitKey)

                    let branchTitle = branchesByID[u.currentBranchID] ?? u.currentBranchID
                    cardModels.append(
                        POSReservedPetCardModel(
                            id: unitKey,
                            reservationID: u.reservationTransactionID,
                            productID: productID,
                            unitID: u.id,
                            ringTag: u.ringTag.isEmpty ? u.id : u.ringTag,
                            animalName: petName,
                            photoURL: photo,
                            sellingPrice: u.sellingPrice ?? stdPrice,
                            standardPrice: stdPrice,
                            customerName: u.reservationCustomerName,
                            customerPhone: u.reservationCustomerPhone,
                            customerSource: "directory",
                            branchID: u.currentBranchID,
                            branchName: branchTitle,
                            validUntil: u.reservationValidUntil,
                            createdAt: nil,
                            notes: u.notes,
                            supplier: u.supplier,
                            purchaseCost: u.purchaseCost
                        )
                    )
                }
            }
        }

        return cardModels
    }

    // MARK: - Actions

    public func extendHold(for item: POSReservedPetCardModel, newValidUntil: Date, reason: String) async -> Bool {
        do {
            // Update transaction validUntil
            if !item.reservationID.isEmpty {
                try await Firestore.firestore()
                    .collection("transactions")
                    .document(item.reservationID)
                    .updateData([
                        "reservationValidUntil": Timestamp(date: newValidUntil),
                        "reservationExtendedAt": FieldValue.serverTimestamp(),
                        "reservationExtendReason": reason,
                    ])
            }

            // Update unit validUntil
            try await Firestore.firestore()
                .collection("petAccessories")
                .document(item.productID)
                .collection("inventoryUnits")
                .document(item.unitID)
                .updateData([
                    "reservationValidUntil": Timestamp(date: newValidUntil),
                    "lastModified": FieldValue.serverTimestamp(),
                ])

            self.operationSuccessNotice = Language.get("POS_Reservation_Extended_Success", alter: "تم تمديد فترة الحجز بنجاح")
            await loadData()
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    public func releaseHold(for item: POSReservedPetCardModel, reason: String) async -> Bool {
        do {
            // Cancel transaction if present
            if !item.reservationID.isEmpty {
                _ = try await PPLivePetInventoryService.callTransaction([
                    "action": "cancel",
                    "transactionId": item.reservationID,
                    "commandId": PPLivePetInventoryService.commandID("release-pos-reservation"),
                    "expectedStatus": "pending",
                    "reason": reason.isEmpty ? "operator_release_from_pos" : reason,
                    "currency": "QAR",
                ])
            } else {
                // Direct release via audited inventory change
                _ = try await PPLivePetInventoryService.callInventory(
                    action: "releaseReservation",
                    productID: item.productID,
                    commandID: PPLivePetInventoryService.commandID("release-unit"),
                    payload: [
                        "unitId": item.unitID,
                        "reason": reason.isEmpty ? "operator_release_from_pos" : reason,
                    ]
                )
            }

            self.operationSuccessNotice = Language.get("POS_Reservation_Released_Success", alter: "تم إلغاء الحجز وإعادة الحيوان للمخزون المتاح")
            await loadData()
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - Main Screen View

public struct POSReservedLivePetsView: View {
    let session: AdminSession
    var allAccessories: [PetAccessory] = []
    var onCompleteSale: ((POSReservedPetCardModel) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: POSReservedLivePetsViewModel
    @State private var isSearchFocused: Bool = false
    @State private var isSpinning: Bool = false

    public init(
        session: AdminSession,
        allAccessories: [PetAccessory] = [],
        onCompleteSale: ((POSReservedPetCardModel) -> Void)? = nil
    ) {
        self.session = session
        self.allAccessories = allAccessories
        self.onCompleteSale = onCompleteSale
        _viewModel = StateObject(wrappedValue: POSReservedLivePetsViewModel(accessories: allAccessories))
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                appHeader
                telemetryDeck
                filterTabs
                searchAndBranchBar
                contentList
            }

            if let notice = viewModel.operationSuccessNotice {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                        Text(notice)
                            .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .body))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .ppSuccess), in: Capsule())
                    .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.operationSuccessNotice)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        viewModel.operationSuccessNotice = nil
                    }
                }
            }
        }
        .task {
            viewModel.updateAccessories(allAccessories)
            await viewModel.loadData()
        }
        .sheet(item: $viewModel.activeDossierItem) { item in
            POSReservedPetDossierSheet(item: item)
        }
        .sheet(item: $viewModel.extendingItem) { item in
            POSExtendReservationSheet(item: item, viewModel: viewModel)
        }
        .sheet(item: $viewModel.releasingItem) { item in
            POSReleaseReservationSheet(item: item, viewModel: viewModel)
        }
        .alert(
            Language.get("Error", alter: "تنبيه"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button(Language.get("OK", alter: "موافق")) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - App Header

    private var appHeader: some View {
        HStack(spacing: AdminSpacing.sm) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 38, height: 38)
                    .background(AdminSurface.control, in: Circle())
            }
            .accessibilityLabel(Language.get("Close", alter: "إغلاق"))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(Language.get("POS_LivePets_Desk", alter: "نقطة البيع • وحدة الحجوزات"))
                        .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)

                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 6, height: 6)
                }

                Text(Language.get("POS_ReservedLivePets_Title", alter: "الحيوانات المحجوزة"))
                    .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isSpinning = true
                }
                Task {
                    await viewModel.loadData()
                    isSpinning = false
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .frame(width: 38, height: 38)
                    .background(AdminSurface.control, in: Circle())
            }
            .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.xs)
        .background(AdminSurface.surface.opacity(0.95))
        .overlay(
            Divider().background(AdminSurface.hairline),
            alignment: .bottom
        )
    }

    // MARK: - Telemetry Deck (Bento Grid)

    private var telemetryDeck: some View {
        HStack(spacing: 8) {
            bentoTile(
                title: Language.get("POS_Metric_TotalReserved", alter: "إجمالي المحجوزات"),
                value: "\(viewModel.totalCount)",
                unit: Language.get("POS_Metric_Animals", alter: "حيوان"),
                icon: "pawprint.fill",
                accent: AdminSurface.primary
            )

            bentoTile(
                title: Language.get("POS_Metric_ExpiringSoon", alter: "تنتهي خلال ٢٤س"),
                value: "\(viewModel.expiringSoonCount)",
                unit: Language.get("POS_Metric_Urgent", alter: "عاجل"),
                icon: "clock.badge.exclamationmark.fill",
                accent: viewModel.expiringSoonCount > 0 ? Color(uiColor: .ppWarning) : AdminSurface.secondaryText,
                pulse: viewModel.expiringSoonCount > 0
            )

            bentoTile(
                title: Language.get("POS_Metric_LockedValue", alter: "القيمة المحجوزة"),
                value: String(format: "%.0f", viewModel.totalHeldValue),
                unit: "ر.ق",
                icon: "banknote.fill",
                accent: AdminSurface.primary
            )
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func bentoTile(
        title: String,
        value: String,
        unit: String,
        icon: String,
        accent: Color,
        pulse: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accent)
            }

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3))
                    .foregroundColor(pulse ? Color(uiColor: .ppWarning) : AdminSurface.primaryText)
                    .monospacedDigit()

                Text(unit)
                    .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(pulse ? accent.opacity(0.4) : AdminSurface.hairline, lineWidth: 1)
        )
    }

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(POSReservationFilter.allCases) { filter in
                    let isSelected = viewModel.activeFilter == filter
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            viewModel.activeFilter = filter
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(filter.title)
                                .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Regular", size: 12, relativeTo: .caption))

                            let count = countForFilter(filter)
                            Text("\(count)")
                                .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    isSelected ? Color.white.opacity(0.25) : AdminSurface.control,
                                    in: Capsule()
                                )
                        }
                        .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? AdminSurface.primary : AdminSurface.surface,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, 6)
        }
    }

    private func countForFilter(_ filter: POSReservationFilter) -> Int {
        switch filter {
        case .all: return viewModel.totalCount
        case .active: return viewModel.activeCount
        case .expiringSoon: return viewModel.expiringSoonCount
        case .expired: return viewModel.expiredCount
        }
    }

    // MARK: - Search & Branch Bar

    private var searchAndBranchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText)

                TextField(Language.get("POS_SearchReserved_Placeholder", alter: "ابحث بالرقم، العميل، الهاتف، أو السلالة..."), text: $viewModel.searchText)
                    .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 1)
            )

            if !viewModel.branches.isEmpty {
                Menu {
                    Button {
                        viewModel.selectedBranchID = ""
                    } label: {
                        HStack {
                            Text(Language.get("POS_AllBranches", alter: "كافة الفروع"))
                            if viewModel.selectedBranchID.isEmpty {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    ForEach(viewModel.branches) { branch in
                        Button {
                            viewModel.selectedBranchID = branch.id
                        } label: {
                            HStack {
                                Text(branch.name)
                                if viewModel.selectedBranchID == branch.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "building.2.crop.circle")
                            .font(.system(size: 13))
                        Text(selectedBranchLabel)
                            .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption))
                            .lineLimit(1)
                    }
                    .foregroundColor(viewModel.selectedBranchID.isEmpty ? AdminSurface.primaryText : AdminSurface.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(viewModel.selectedBranchID.isEmpty ? AdminSurface.hairline : AdminSurface.primary.opacity(0.4), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.bottom, 6)
    }

    private var selectedBranchLabel: String {
        if viewModel.selectedBranchID.isEmpty {
            return Language.get("POS_Branch_All", alter: "كل الفروع")
        }
        return viewModel.branches.first(where: { $0.id == viewModel.selectedBranchID })?.name ?? viewModel.selectedBranchID
    }

    // MARK: - Content List

    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.isLoading {
                    ForEach(0..<4, id: \.self) { _ in
                        skeletonCard
                    }
                } else if viewModel.filteredItems.isEmpty {
                    emptyStateView
                } else {
                    ForEach(viewModel.filteredItems) { item in
                        POSReservedPetCard(
                            item: item,
                            onCompleteSale: {
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                onCompleteSale?(item)
                                dismiss()
                            },
                            onExtend: {
                                viewModel.extendingItem = item
                            },
                            onRelease: {
                                viewModel.releasingItem = item
                            },
                            onInspectDossier: {
                                viewModel.activeDossierItem = item
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 36)
        }
        .refreshable {
            await viewModel.loadData()
        }
    }

    // MARK: - Skeletons & Empty State

    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AdminSurface.control)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AdminSurface.control)
                        .frame(width: 140, height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AdminSurface.control)
                        .frame(width: 90, height: 12)
                }
                Spacer()
            }
            Divider().background(AdminSurface.hairline)
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AdminSurface.control)
                    .frame(width: 100, height: 14)
                Spacer()
                RoundedRectangle(cornerRadius: 12)
                    .fill(AdminSurface.control)
                    .frame(width: 110, height: 32)
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
        .opacity(0.6)
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "pawprint.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 40)

            Text(Language.get("POS_NoReservedLivePets_Title", alter: "لا توجد حيوانات محجوزة تطابق المعايير"))
                .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                .foregroundColor(AdminSurface.primaryText)

            Text(Language.get("POS_NoReservedLivePets_Subtitle", alter: "جميع الحيوانات الحية متاحة حالياً للبيع المباشر في الكتالوج."))
                .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .subheadline))
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                Task { await viewModel.loadData() }
            } label: {
                Text(Language.get("Refresh", alter: "تحديث السجلات"))
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .callout))
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(AdminSurface.control, in: Capsule())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Flagship Reserved Pet Card

private struct POSReservedPetCard: View {
    let item: POSReservedPetCardModel
    let onCompleteSale: () -> Void
    let onExtend: () -> Void
    let onRelease: () -> Void
    let onInspectDossier: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row: Avatar, Breed, Ring Tag, Urgency
            HStack(spacing: 12) {
                petAvatar

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.animalName)
                            .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)

                        Spacer()

                        urgencyBadge
                    }

                    HStack(spacing: 6) {
                        // Ring Tag Badge
                        HStack(spacing: 3) {
                            Image(systemName: "number.circle.fill")
                                .font(.system(size: 9))
                            Text(item.ringTag)
                                .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption))
                                .monospaced()
                        }
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AdminSurface.control, in: Capsule())

                        if !item.branchName.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 8))
                                Text(item.branchName)
                                    .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                                    .lineLimit(1)
                            }
                            .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }
            }

            Divider().background(AdminSurface.hairline)

            // Customer & Financial Matrix
            HStack(alignment: .center, spacing: 12) {
                // Customer section with direct actions
                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("POS_Customer", alter: "العميل"))
                        .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                        .foregroundColor(AdminSurface.secondaryText)

                    HStack(spacing: 6) {
                        Text(item.customerName.isEmpty ? Language.get("POS_UnnamedCustomer", alter: "عميل بدون اسم") : item.customerName)
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
                            .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.secondaryText)
                            .monospacedDigit()
                    }
                }

                Spacer()

                // Price section
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Language.get("POS_LockedPrice", alter: "السعر المحجوز"))
                        .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                        .foregroundColor(AdminSurface.secondaryText)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.0f", item.sellingPrice))
                            .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3))
                            .foregroundColor(AdminSurface.primary)
                            .monospacedDigit()

                        Text("ر.ق")
                            .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.primary)
                    }
                }
            }

            // Quick Operational Buttons
            HStack(spacing: 8) {
                // Primary Action: Complete Sale In POS
                Button {
                    onCompleteSale()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(Language.get("POS_Action_CompleteSale", alter: "إكمال البيع في الكاشير"))
                            .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .callout))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .shadow(color: AdminSurface.primary.opacity(0.25), radius: 6, y: 2)
                }

                // Extend Hold
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onExtend()
                } label: {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityLabel(Language.get("POS_Action_Extend", alter: "تمديد الحجز"))

                // Release Hold
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onRelease()
                } label: {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(uiColor: .ppError))
                        .frame(width: 36, height: 36)
                        .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityLabel(Language.get("POS_Action_Release", alter: "إلغاء الحجز"))

                // Dossier Info
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onInspectDossier()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityLabel(Language.get("POS_Action_Dossier", alter: "سجل الحيوان"))
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(item.isExpiringSoon ? Color(uiColor: .ppWarning).opacity(0.4) : AdminSurface.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
    }

    private var petAvatar: some View {
        ZStack {
            if let url = URL(string: item.photoURL), !item.photoURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private var avatarPlaceholder: some View {
        ZStack {
            AdminSurface.control
            Image(systemName: "pawprint.fill")
                .font(.system(size: 20))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
        }
    }

    private var urgencyBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(urgencyColor)
                .frame(width: 6, height: 6)

            Text(item.remainingTimeDescription)
                .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                .foregroundColor(urgencyColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(urgencyColor.opacity(0.1), in: Capsule())
    }

    private var urgencyColor: Color {
        if item.isExpired {
            return Color(uiColor: .ppError)
        } else if item.isExpiringSoon {
            return Color(uiColor: .ppWarning)
        } else {
            return Color(uiColor: .ppSuccess)
        }
    }

    private func quickCallButton(phone: String) -> some View {
        Button {
            guard let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") else { return }
            UIApplication.shared.open(url)
        } label: {
            Image(systemName: "phone.fill")
                .font(.system(size: 9))
                .foregroundColor(Color(uiColor: .ppSuccess))
                .padding(5)
                .background(Color(uiColor: .ppSuccess).opacity(0.1), in: Circle())
        }
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
                .padding(5)
                .background(Color(uiColor: .ppSuccess).opacity(0.1), in: Circle())
        }
    }
}

// MARK: - Deep Animal Dossier Sheet

public struct POSReservedPetDossierSheet: View {
    let item: POSReservedPetCardModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Pet Hero Section
                    VStack(spacing: 8) {
                        ZStack {
                            if let url = URL(string: item.photoURL), !item.photoURL.isEmpty {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img): img.resizable().scaledToFill()
                                    default: dossierPlaceholder
                                    }
                                }
                            } else {
                                dossierPlaceholder
                            }
                        }
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 1)
                        )

                        Text(item.animalName)
                            .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .title3))
                            .foregroundColor(AdminSurface.primaryText)

                        HStack(spacing: 8) {
                            Text("#\(item.ringTag)")
                                .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(AdminSurface.control, in: Capsule())

                            Text(item.remainingTimeDescription)
                                .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                                .foregroundColor(item.isExpired ? Color(uiColor: .ppError) : Color(uiColor: .ppWarning))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(AdminSurface.control, in: Capsule())
                        }
                    }
                    .padding(.top, 12)

                    // Dossier Matrix
                    VStack(spacing: 10) {
                        dossierRow(title: Language.get("POS_TransactionRef", alter: "رقم المعاملة"), value: "#\(item.reservationID)")
                        dossierRow(title: Language.get("POS_Customer", alter: "اسم العميل"), value: item.customerName.isEmpty ? "—" : item.customerName)
                        dossierRow(title: Language.get("POS_Phone", alter: "هاتف العميل"), value: item.customerPhone.isEmpty ? "—" : item.customerPhone)
                        dossierRow(title: Language.get("POS_Branch", alter: "الفرع"), value: item.branchName.isEmpty ? "—" : item.branchName)
                        dossierRow(title: Language.get("POS_LockedPrice", alter: "سعر الحجز المعتمد"), value: "\(String(format: "%.2f", item.sellingPrice)) ر.ق")
                        dossierRow(title: Language.get("POS_UnitID", alter: "معرف السجل"), value: item.unitID)

                        if let valid = item.validUntil {
                            dossierRow(title: Language.get("POS_ValidUntil", alter: "صالح حتى"), value: POSReceiptFormat.date(valid))
                        }

                        if !item.supplier.isEmpty {
                            dossierRow(title: Language.get("LivePet_Supplier", alter: "المورد"), value: item.supplier)
                        }

                        if let cost = item.purchaseCost, cost > 0 {
                            dossierRow(title: Language.get("LivePet_PurchaseCost", alter: "تكلفة الشراء"), value: "\(String(format: "%.2f", cost)) ر.ق")
                        }

                        if !item.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Language.get("POS_Notes", alter: "ملاحظات الحجز"))
                                    .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.secondaryText)
                                Text(item.notes)
                                    .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                                    .foregroundColor(AdminSurface.primaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        }
                    }
                    .padding(16)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 1)
                    )
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, 16)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("POS_AnimalDossier_Title", alter: "ملف سجل الحيوان المحجوز"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Done", alter: "تم")) {
                        dismiss()
                    }
                    .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .body))
                    .foregroundColor(AdminSurface.primary)
                }
            }
        }
    }

    private var dossierPlaceholder: some View {
        ZStack {
            AdminSurface.control
            Image(systemName: "pawprint.fill")
                .font(.system(size: 32))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
        }
    }

    private func dossierRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                .foregroundColor(AdminSurface.secondaryText)
            Spacer()
            Text(value)
                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .body))
                .foregroundColor(AdminSurface.primaryText)
                .monospacedDigit()
        }
    }
}

// MARK: - Extend Hold Sheet

public struct POSExtendReservationSheet: View {
    let item: POSReservedPetCardModel
    @ObservedObject var viewModel: POSReservedLivePetsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedHours: Int = 24
    @State private var customDate: Date = Date().addingTimeInterval(24 * 3600)
    @State private var reason: String = ""
    @State private var isSubmitting: Bool = false

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 38))
                        .foregroundColor(AdminSurface.primary)
                        .padding(.top, 16)

                    Text(Language.get("POS_Extend_Title", alter: "تمديد مهلة الحجز"))
                        .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .title3))
                        .foregroundColor(AdminSurface.primaryText)

                    Text("\(item.animalName) • #\(item.ringTag)")
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)
                }

                // Presets
                HStack(spacing: 8) {
                    presetButton(title: "+٢٤ ساعة", hours: 24)
                    presetButton(title: "+٤٨ ساعة", hours: 48)
                    presetButton(title: "+٧ أيام", hours: 168)
                }

                // Date Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("POS_NewExpiryDate", alter: "تاريخ وساعة الانتهاء الجديدة"))
                        .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)

                    DatePicker(
                        "",
                        selection: $customDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Reason input
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("POS_ExtendReason", alter: "سبب التمديد (اختياري)"))
                        .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)

                    TextField(Language.get("POS_ExtendReason_Placeholder", alter: "طلب العميل، تأكيد موعد الاستلام..."), text: $reason)
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                        .padding(10)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Spacer()

                Button {
                    isSubmitting = true
                    Task {
                        let success = await viewModel.extendHold(for: item, newValidUntil: customDate, reason: reason)
                        isSubmitting = false
                        if success { dismiss() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(Language.get("POS_Confirm_Extend", alter: "تأكيد تمديد الحجز"))
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isSubmitting)
            }
            .padding(AdminSpacing.screenMargin)
            .background(AdminSurface.surface.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                }
            }
        }
    }

    private func presetButton(title: String, hours: Int) -> some View {
        let isSelected = selectedHours == hours
        return Button {
            selectedHours = hours
            customDate = Date().addingTimeInterval(TimeInterval(hours * 3600))
        } label: {
            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? AdminSurface.primary : AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - Release Hold Sheet

public struct POSReleaseReservationSheet: View {
    let item: POSReservedPetCardModel
    @ObservedObject var viewModel: POSReservedLivePetsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String = ""
    @State private var isSubmitting: Bool = false

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 42))
                        .foregroundColor(Color(uiColor: .ppError))
                        .padding(.top, 16)

                    Text(Language.get("POS_Release_Title", alter: "إلغاء الحجز وإعادة الإتاحة"))
                        .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .title3))
                        .foregroundColor(AdminSurface.primaryText)

                    Text(Language.get("POS_Release_Warning", alter: "سيتم إلغاء الحجز فوراً وإعادة الحيوان إلى قائمة المتاح في الكتالوج ونقطة البيع لجميع العملاء."))
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                        .foregroundColor(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("POS_Release_Reason", alter: "سبب الإلغاء"))
                        .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)

                    TextField(Language.get("POS_Release_Reason_Placeholder", alter: "عدم حضور العميل، طلب الإلغاء، انتهاء المهلة..."), text: $reason)
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .body))
                        .padding(10)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Spacer()

                Button {
                    isSubmitting = true
                    Task {
                        let success = await viewModel.releaseHold(for: item, reason: reason)
                        isSubmitting = false
                        if success { dismiss() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "lock.open.fill")
                        }
                        Text(Language.get("POS_Confirm_Release", alter: "تأكيد إلغاء الحجز والتحرير"))
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(uiColor: .ppError), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isSubmitting)
            }
            .padding(AdminSpacing.screenMargin)
            .background(AdminSurface.surface.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "تراجع")) {
                        dismiss()
                    }
                    .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                }
            }
        }
    }
}
