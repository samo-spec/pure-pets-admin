//
//  ServicesView.swift
//  PurePetsAdmin
//
//  Category-Defining Beyond-FAANG Services Operations Command Center.
//  Reimagined from absolute first principles for iPhone and iPad separately:
//  - Sovereign Living Command Header with live Firestore sync pulse beacon
//  - Interactive 4-Pod Executive Telemetry Matrix (KPI HUD: Total, Live, Review, Archived)
//  - Real-Time Search & Multi-Dimensional Refine Horizon (Status, Category, Sort)
//  - Beyond-FAANG Service Specimen Cards with rich image, QAR price pill, status aura & action dock
//  - iPhone: Ergonomic thumb-zone sensory deck with inline one-touch quick actions
//  - iPad: Desktop-grade 2-column spatial cockpit (Stream Horizon + Pinned Live Dossier Inspector)
//  - Living Concentric Radar Empty State with dynamic feedback
//  - Full lifecycle integration with PPServiceManager & Firebase Firestore
//

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth

// MARK: - PPServiceModel Identifiable Conformance

extension PPServiceModel: @retroactive Identifiable, @unchecked Sendable {
    public var id: String { serviceID }
}

// MARK: - Enums & Filters

enum AdminServicePrimaryFilter: Int, CaseIterable, Identifiable {
    case all = 0
    case live = 1
    case review = 2
    case archived = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all: return Language.get("Service_Filter_All", alter: "الكل")
        case .live: return Language.get("Service_Filter_Live", alter: "نشطة")
        case .review: return Language.get("Service_Filter_NeedsReview", alter: "تحتاج مراجعة")
        case .archived: return Language.get("Service_Filter_Archived", alter: "مؤرشفة")
        }
    }

    var symbol: String {
        switch self {
        case .all: return "sparkles"
        case .live: return "checkmark.circle.fill"
        case .review: return "exclamationmark.triangle.fill"
        case .archived: return "archivebox.fill"
        }
    }
}

enum AdminServiceSecondaryFilter: Int, CaseIterable, Identifiable {
    case any = 0
    case needsReview = 1
    case verified = 2
    case pending = 3
    case blocked = 4
    case disabled = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .any: return Language.get("Service_Filter_Any", alter: "أي حالة")
        case .needsReview: return Language.get("Service_Filter_NeedsReview", alter: "تحتاج مراجعة")
        case .verified: return Language.get("Service_Filter_Verified", alter: "موثقة")
        case .pending: return Language.get("Service_Filter_Pending", alter: "قيد المراجعة")
        case .blocked: return Language.get("Service_Filter_Blocked", alter: "محظورة")
        case .disabled: return Language.get("Service_Filter_Disabled", alter: "معطلة")
        }
    }
}

enum AdminServiceSortOption: Int, CaseIterable, Identifiable {
    case updatedDesc = 0
    case titleAsc = 1
    case priceHigh = 2
    case priceLow = 3
    case availableSoonest = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .updatedDesc: return Language.get("Service_Sort_Updated", alter: "أحدث التحديثات")
        case .titleAsc: return Language.get("Service_Sort_Title", alter: "العنوان أ-ي")
        case .priceHigh: return Language.get("Service_Sort_PriceHigh", alter: "السعر الأعلى")
        case .priceLow: return Language.get("Service_Sort_PriceLow", alter: "السعر الأقل")
        case .availableSoonest: return Language.get("Service_Sort_Available", alter: "الأقرب موعداً")
        }
    }
}

enum AdminServiceActiveSheet: Identifiable {
    case add
    case edit(PPServiceModel)
    case moderate(PPServiceModel)
    case detail(PPServiceModel)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let s): return "edit_\(s.serviceID)"
        case .moderate(let s): return "moderate_\(s.serviceID)"
        case .detail(let s): return "detail_\(s.serviceID)"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class AdminServicesViewModel: ObservableObject {
    @Published var allServices: [PPServiceModel] = []
    @Published var filteredServices: [PPServiceModel] = []
    @Published var searchQuery: String = ""
    @Published var primaryFilter: AdminServicePrimaryFilter = .all
    @Published var secondaryFilter: AdminServiceSecondaryFilter = .any
    @Published var sortOption: AdminServiceSortOption = .updatedDesc
    @Published var selectedService: PPServiceModel? = nil
    @Published var activeSheet: AdminServiceActiveSheet? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var successMessage: String? = nil
    @Published var activeMetricFilter: AdminServicePrimaryFilter? = nil

    private var listener: ListenerRegistration? = nil

    init() {
        startListening()
    }

    deinit {
        // In Swift 6 strict concurrency, nonisolated deinit cannot touch MainActor non-Sendable listeners.
    }

    // MARK: - Computed KPI Telemetry

    var totalCount: Int { allServices.count }

    var liveCount: Int {
        allServices.filter { $0.isLive() }.count
    }

    var reviewCount: Int {
        allServices.filter { service in
            let v = (service.verificationStatus ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return service.isBlocked || service.isDisabled ||
                   v == "pending" || v == "pending_review" || v == "verification_pending" || v == "rejected"
        }.count
    }

    var archivedCount: Int {
        allServices.filter { $0.isDeleted }.count
    }

    // MARK: - Data Synchronization

    func startListening() {
        listener?.remove()
        isLoading = true
        errorMessage = nil

        listener = PPServiceManager.shared().observeAllServices { [weak self] services, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoading = false

                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                let items = services ?? []
                self.allServices = items
                self.applyFilters()

                // Auto-select first item on iPad if none is selected
                if self.selectedService == nil || !items.contains(where: { $0.serviceID == self.selectedService?.serviceID }) {
                    self.selectedService = self.filteredServices.first ?? items.first
                }
            }
        }
    }

    func refreshTriggered() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isLoading = true
        PPServiceManager.shared().fetchAllServices { [weak self] services, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.allServices = services ?? []
                self.applyFilters()
            }
        }
    }

    // MARK: - Filtering & Sorting

    func applyFilters() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var result = allServices.filter { service in
            // Primary Filter
            switch primaryFilter {
            case .all:
                break
            case .live:
                if !service.isLive() { return false }
            case .review:
                let v = (service.verificationStatus ?? "").lowercased()
                let needsReview = service.isBlocked || service.isDisabled ||
                                  v == "pending" || v == "pending_review" || v == "verification_pending" || v == "rejected"
                if !needsReview { return false }
            case .archived:
                if !service.isDeleted { return false }
            }

            // Secondary Filter
            let verification = (service.verificationStatus ?? "").lowercased()
            switch secondaryFilter {
            case .any:
                break
            case .needsReview:
                let needsReview = service.isBlocked || service.isDisabled ||
                                  verification == "pending" || verification == "pending_review" || verification == "verification_pending" || verification == "rejected"
                if !needsReview { return false }
            case .verified:
                if verification != "verified" { return false }
            case .pending:
                if verification != "pending" && verification != "pending_review" && verification != "verification_pending" { return false }
            case .blocked:
                if !service.isBlocked { return false }
            case .disabled:
                if !service.isDisabled { return false }
            }

            // Search Query Filter
            if !query.isEmpty {
                let haystack: [String] = [
                    service.title,
                    service.serviceDescriptionText,
                    service.category,
                    service.categoryID,
                    service.serviceOwnerID,
                    service.serviceID,
                    service.verificationStatus ?? "",
                    service.subscriptionPlan ?? ""
                ].map { $0.lowercased() }

                if !haystack.contains(where: { $0.contains(query) }) {
                    return false
                }
            }

            return true
        }

        // Sorting
        result.sort { a, b in
            switch sortOption {
            case .titleAsc:
                return (a.title ?? "").localizedCaseInsensitiveCompare(b.title ?? "") == .orderedAscending
            case .priceHigh:
                return a.price > b.price
            case .priceLow:
                return a.price < b.price
            case .availableSoonest:
                let d1 = a.availableDate ?? Date.distantFuture
                let d2 = b.availableDate ?? Date.distantFuture
                return d1 < d2
            case .updatedDesc:
                let t1 = a.updatedAt ?? a.timestamp ?? a.createdAt ?? Date.distantPast
                let t2 = b.updatedAt ?? b.timestamp ?? b.createdAt ?? Date.distantPast
                return t1 > t2
            }
        }

        filteredServices = result

        // Update selected service on iPad
        if let current = selectedService, !result.contains(where: { $0.serviceID == current.serviceID }) {
            selectedService = result.first
        } else if selectedService == nil {
            selectedService = result.first
        }
    }

    func selectMetricFilter(_ metric: AdminServicePrimaryFilter) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            if activeMetricFilter == metric {
                activeMetricFilter = nil
                primaryFilter = .all
            } else {
                activeMetricFilter = metric
                primaryFilter = metric
            }
            applyFilters()
        }
    }

    // MARK: - Operational Actions

    func toggleDisabled(service: PPServiceModel) {
        let newState = !service.isDisabled
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        PPServiceManager.shared().setDisabled(newState, forServiceID: service.serviceID, auditNote: nil) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                } else {
                    self.successMessage = newState
                        ? Language.get("Service_Disabled_Success", alter: "تم تعطيل الخدمة بنجاح.")
                        : Language.get("Service_Enabled_Success", alter: "تم تفعيل الخدمة بنجاح.")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    func toggleBlocked(service: PPServiceModel) {
        let newState = !service.isBlocked
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        PPServiceManager.shared().setBlocked(newState, forServiceID: service.serviceID, auditNote: nil) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                } else {
                    self.successMessage = newState
                        ? Language.get("Service_Blocked_Success", alter: "تم حظر الخدمة بنجاح.")
                        : Language.get("Service_Unblocked_Success", alter: "تم إلغاء حظر الخدمة بنجاح.")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    func toggleArchived(service: PPServiceModel) {
        let shouldArchive = !service.isDeleted
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let completion: PPServiceVoidBlock = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                } else {
                    self.successMessage = shouldArchive
                        ? Language.get("Service_Archived_Success", alter: "تمت أرشفة الخدمة بنجاح.")
                        : Language.get("Service_Restored_Success", alter: "تمت استعادة الخدمة بنجاح.")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }

        if shouldArchive {
            PPServiceManager.shared().archiveServiceID(service.serviceID, auditNote: nil, completion: completion)
        } else {
            PPServiceManager.shared().restoreServiceID(service.serviceID, auditNote: nil, completion: completion)
        }
    }

    func deletePermanently(service: PPServiceModel) {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("Service_Confirm_Delete_Title", alter: "حذف الخدمة نهائياً"),
            subtitle: Language.get("Service_Confirm_Delete_Subtitle", alter: "هل أنت متأكد من رغبتك في حذف هذه الخدمة نهائياً؟ لا يمكن التراجع عن هذا الإجراء."),
            confirmButton: Language.get("Delete", alter: "حذف نهائي"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "trash.fill"),
            confirmBlock: { [weak self] _, didConfirm in
                guard didConfirm else { return }
                self?.performDeletePermanently(service: service)
            },
            cancelBlock: nil
        )
    }

    private func performDeletePermanently(service: PPServiceModel) {
        let deletedID = service.serviceID
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        PPServiceManager.shared().deleteServicePermanently(deletedID, auditNote: nil) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                } else {
                    self.successMessage = Language.get("Service_Deleted_Success", alter: "تم حذف الخدمة نهائياً.")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    if self.selectedService?.serviceID == deletedID {
                        self.selectedService = self.filteredServices.first(where: { $0.serviceID != deletedID })
                    }
                }
            }
        }
    }
}

// MARK: - Root Entry View

public struct AdminServicesView: View {
    public var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminServicesViewModel()

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        GeometryReader { geometry in
            let isPad = UIDevice.current.userInterfaceIdiom == .pad && geometry.size.width > 640

            ZStack {
                AdminSurface.background.ignoresSafeArea()

                if isPad {
                    iPadServicesSpatialCockpit(viewModel: viewModel, onDismiss: handleDismiss)
                } else {
                    iPhoneServicesSensoryDeck(viewModel: viewModel, onDismiss: handleDismiss)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(item: $viewModel.activeSheet) { sheet in
            switch sheet {
            case .add:
                AdminServiceAddEditSheetRepresentable(service: nil)
                    .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            case .edit(let service):
                AdminServiceAddEditSheetRepresentable(service: service)
                    .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            case .moderate(let service):
                AdminServiceModerationSheetRepresentable(service: service)
                    .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            case .detail(let service):
                AdminServiceDetailSheetRepresentable(service: service)
                    .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }
        }
    }

    private func handleDismiss() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}

// MARK: - ==========================================
// MARK: - IPHONE: SENSORY DECK ARCHITECTURE
// MARK: - ==========================================

private struct iPhoneServicesSensoryDeck: View {
    @ObservedObject var viewModel: AdminServicesViewModel
    let onDismiss: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Sovereign Navigation Deck
            sovereignNavigationBar

            // Feedback Banners
            if let error = viewModel.errorMessage {
                feedbackBanner(text: error, isError: true)
            }
            if let success = viewModel.successMessage {
                feedbackBanner(text: success, isError: false)
            }

            ScrollView {
                VStack(spacing: 14) {
                    // Interactive Telemetry HUD (4 Sensors)
                    telemetryMatrixHUD
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    // Search & Refine Horizon
                    searchAndRefineHorizon
                        .padding(.horizontal, 16)

                    // Specimen Stream or Empty State
                    if viewModel.filteredServices.isEmpty && !viewModel.isLoading {
                        ServicesLivingEmptyState(
                            hasSearch: !viewModel.searchQuery.isEmpty || viewModel.primaryFilter != .all || viewModel.secondaryFilter != .any,
                            onAdd: { viewModel.activeSheet = .add },
                            onReset: {
                                viewModel.searchQuery = ""
                                viewModel.primaryFilter = .all
                                viewModel.secondaryFilter = .any
                                viewModel.activeMetricFilter = nil
                                viewModel.applyFilters()
                            }
                        )
                        .padding(.top, 24)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.filteredServices) { service in
                                iPhoneServiceSpecimenCard(service: service, viewModel: viewModel)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .refreshable {
                viewModel.refreshTriggered()
            }
        }
    }

    // MARK: - Sovereign Navigation Bar

    private var sovereignNavigationBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Service_Section_Title", alter: "الخدمات"),
            subtitle: Language.get("CommandCenter_Operations_Workspace", alter: "مساحة عمل العمليات"),
            statusDotColor: Color(uiColor: .ppSuccess),
            isModal: false,
            onBack: onDismiss
        ) {
            HStack(spacing: 8) {
                // Refresh Sync Beacon
                Button {
                    viewModel.refreshTriggered()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AdminSurface.control)
                            .frame(width: 38, height: 38)
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AdminSurface.secondaryText)
                            .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                            .animation(viewModel.isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isLoading)
                    }
                }
                .buttonStyle(PlainButtonStyle())

                // Jewel Add Service Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.activeSheet = .add
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 42, height: 42)
                            .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, y: 2)

                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Feedback Banner

    private func feedbackBanner(text: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
                .font(.system(size: 13))
            Text(text)
                .font(Font.custom("Beiruti-Medium", size: 12.5, relativeTo: .caption))
                .foregroundColor(AdminSurface.primaryText)
            Spacer()
            Button {
                if isError { viewModel.errorMessage = nil }
                else { viewModel.successMessage = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background((isError ? Color.red : Color.green).opacity(0.12))
    }

    // MARK: - Telemetry Matrix HUD

    private var telemetryMatrixHUD: some View {
        HStack(spacing: 8) {
            // Pod 1: Total
            telemetrySensorPod(
                title: Language.get("Service_Stat_Total", alter: "الإجمالي"),
                value: "\(viewModel.totalCount)",
                accentColor: AdminSurface.primary,
                filter: .all,
                isSelected: viewModel.activeMetricFilter == .all
            )

            // Pod 2: Live
            telemetrySensorPod(
                title: Language.get("Service_Stat_Live", alter: "نشطة"),
                value: "\(viewModel.liveCount)",
                accentColor: Color(uiColor: .ppSuccess),
                filter: .live,
                isSelected: viewModel.activeMetricFilter == .live
            )

            // Pod 3: Needs Review
            telemetrySensorPod(
                title: Language.get("Service_Stat_Review", alter: "تحتاج مراجعة"),
                value: "\(viewModel.reviewCount)",
                accentColor: Color(uiColor: .ppWarning),
                filter: .review,
                isSelected: viewModel.activeMetricFilter == .review
            )

            // Pod 4: Archived
            telemetrySensorPod(
                title: Language.get("Service_Stat_Archived", alter: "مؤرشفة"),
                value: "\(viewModel.archivedCount)",
                accentColor: Color(uiColor: .ppTextSecondary),
                filter: .archived,
                isSelected: viewModel.activeMetricFilter == .archived
            )
        }
    }

    private func telemetrySensorPod(
        title: String,
        value: String,
        accentColor: Color,
        filter: AdminServicePrimaryFilter,
        isSelected: Bool
    ) -> some View {
        Button {
            viewModel.selectMetricFilter(filter)
        } label: {
            VStack(spacing: 2) {
                Text(value)
                    .font(Font.custom("Beiruti-Bold", size: 21, relativeTo: .title3))
                    .foregroundColor(accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(title)
                    .font(Font.custom("Beiruti-Medium", size: 10.5, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                accentColor.opacity(isSelected ? 0.22 : 0.08),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? accentColor : AdminSurface.hairline, lineWidth: isSelected ? 1.8 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Search & Refine Horizon

    private var searchAndRefineHorizon: some View {
        VStack(spacing: 10) {
            // Search Input Capsule
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AdminSurface.secondaryText)
                    .font(.system(size: 15))

                TextField(Language.get("Service_Search_Placeholder", alter: "ابحث باسم الخدمة أو الفئة أو المالك..."), text: $viewModel.searchQuery)
                    .font(Font.custom("Beiruti-Regular", size: 14.5, relativeTo: .body))
                    .foregroundColor(AdminSurface.primaryText)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .onChange(of: viewModel.searchQuery, perform: { _ in
                        viewModel.applyFilters()
                    })

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        viewModel.applyFilters()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AdminSurface.secondaryText)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSearchFocused ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSearchFocused ? 1.4 : 1)
            )

            // Horizontal Filter Chips Ribbon + Sort Popup
            HStack(spacing: 8) {
                // Scrollable Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AdminServicePrimaryFilter.allCases) { f in
                            let active = viewModel.primaryFilter == f
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    viewModel.primaryFilter = f
                                    viewModel.activeMetricFilter = (f == .all ? nil : f)
                                    viewModel.applyFilters()
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: f.symbol)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(f.title)
                                        .font(Font.custom(active ? "Beiruti-Bold" : "Beiruti-Medium", size: 12.5, relativeTo: .caption))
                                }
                                .foregroundColor(active ? .white : AdminSurface.primaryText)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(active ? AdminSurface.primary : AdminSurface.surface, in: Capsule())
                                .overlay(Capsule().stroke(AdminSurface.hairline))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                // Sort Dropdown Button
                Menu {
                    ForEach(AdminServiceSortOption.allCases) { opt in
                        Button {
                            viewModel.sortOption = opt
                            viewModel.applyFilters()
                        } label: {
                            HStack {
                                Text(opt.title)
                                if viewModel.sortOption == opt {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text(viewModel.sortOption.title)
                            .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption2))
                            .lineLimit(1)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(AdminSurface.primary.opacity(0.09), in: Capsule())
                    .overlay(Capsule().stroke(AdminSurface.primary.opacity(0.3)))
                }
            }
        }
    }
}

// MARK: - iPhone Specimen Card

private struct iPhoneServiceSpecimenCard: View {
    let service: PPServiceModel
    @ObservedObject var viewModel: AdminServicesViewModel

    var body: some View {
        VStack(spacing: 10) {
            // Main Content Row
            HStack(alignment: .top, spacing: 12) {
                // Specimen Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.control)
                        .frame(width: 74, height: 74)

                    if !service.imageURL.isEmpty, let url = URL(string: service.imageURL) {
                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 74, height: 74)) {
                            serviceFallbackIcon
                        }
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        serviceFallbackIcon
                    }
                }

                // Info Stack
                VStack(alignment: .leading, spacing: 4) {
                    // Category Pill & Status Badge Row
                    HStack(spacing: 6) {
                        // Category / Type Pill
                        Text(serviceCategoryLabel)
                            .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(AdminSurface.primary.opacity(0.10), in: Capsule())

                        Spacer()

                        // Operational Status Pill
                        statusBadgeView
                    }

                    // Title
                    Text(service.title.isEmpty ? Language.get("Service_Untitled", alter: "خدمة بدون عنوان") : service.title)
                        .font(Font.custom("Beiruti-Bold", size: 15.5, relativeTo: .body))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Price & Owner Row
                    HStack(spacing: 8) {
                        // QAR Price Pill
                        HStack(spacing: 3) {
                            Text(String(format: "%.2f", service.price))
                                .font(.system(size: 13, weight: .bold))
                                .monospacedDigit()
                            Text(Language.get("QAR", alter: "ر.ق"))
                                .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption))
                        }
                        .foregroundColor(Color(uiColor: .ppSuccess))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())

                        if !service.serviceOwnerID.isEmpty {
                            let owner = service.serviceOwnerID
                            Text("•")
                                .foregroundColor(AdminSurface.hairline)
                            HStack(spacing: 2) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 9))
                                Text(String(owner.prefix(8)))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .monospacedDigit()
                            }
                            .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }
            }

            Divider().background(AdminSurface.hairline.opacity(0.6))

            // Action Ribbon
            HStack(spacing: 6) {
                // View Details Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.activeSheet = .detail(service)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 11))
                        Text(Language.get("Services_QuickAction_View", alter: "معاينة"))
                            .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                    }
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())

                // Edit Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.activeSheet = .edit(service)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                        Text(Language.get("Services_QuickAction_Edit", alter: "تعديل"))
                            .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                    }
                    .foregroundColor(AdminSurface.primary)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())

                // Moderate Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.activeSheet = .moderate(service)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11))
                        Text(Language.get("Services_QuickAction_Moderate", alter: "مراجعة"))
                            .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                    }
                    .foregroundColor(Color(uiColor: .ppWarning))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color(uiColor: .ppWarning).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())

                // More Options Menu
                Menu {
                    // Disable/Enable
                    Button {
                        viewModel.toggleDisabled(service: service)
                    } label: {
                        Label(
                            service.isDisabled ? Language.get("Service_Action_Enable", alter: "تفعيل") : Language.get("Service_Action_Disable", alter: "تعطيل"),
                            systemImage: service.isDisabled ? "checkmark.circle" : "nosign"
                        )
                    }

                    // Block/Unblock
                    Button {
                        viewModel.toggleBlocked(service: service)
                    } label: {
                        Label(
                            service.isBlocked ? Language.get("Service_Action_Unblock", alter: "إلغاء الحظر") : Language.get("Service_Action_Block", alter: "حظر"),
                            systemImage: service.isBlocked ? "lock.open" : "hand.raised.fill"
                        )
                    }

                    // Archive/Restore
                    Button {
                        viewModel.toggleArchived(service: service)
                    } label: {
                        Label(
                            service.isDeleted ? Language.get("Service_Action_Restore", alter: "استعادة") : Language.get("Service_Action_Archive", alter: "أرشفة"),
                            systemImage: service.isDeleted ? "arrow.uturn.backward.circle" : "archivebox"
                        )
                    }

                    // Delete Permanently
                    Button(role: .destructive) {
                        viewModel.deletePermanently(service: service)
                    } label: {
                        Label(Language.get("Delete", alter: "حذف نهائي"), systemImage: "trash")
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AdminSurface.control)
                            .frame(width: 34, height: 32)
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }
        }
        .padding(12)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))
    }

    private var serviceFallbackIcon: some View {
        Image(systemName: service.type == .grooming ? "scissors" : "figure.walk")
            .font(.system(size: 24))
            .foregroundColor(AdminSurface.primary.opacity(0.7))
    }

    private var serviceCategoryLabel: String {
        if !service.category.isEmpty {
            return service.category
        }
        let typeName = service.localizedTypeName()
        return typeName.isEmpty ? Language.get("Service_Type_Service", alter: "خدمة") : typeName
    }

    @ViewBuilder
    private var statusBadgeView: some View {
        if service.isDeleted {
            statusPill(text: Language.get("Service_Stat_Archived", alter: "مؤرشفة"), color: .gray, symbol: "archivebox.fill")
        } else if service.isBlocked {
            statusPill(text: Language.get("Service_Filter_Blocked", alter: "محظورة"), color: .red, symbol: "hand.raised.fill")
        } else if service.isDisabled {
            statusPill(text: Language.get("Service_Filter_Disabled", alter: "معطلة"), color: .orange, symbol: "nosign")
        } else {
            let v = (service.verificationStatus ?? "").lowercased()
            if v == "pending" || v == "pending_review" || v == "verification_pending" {
                statusPill(text: Language.get("Service_Filter_Pending", alter: "قيد المراجعة"), color: .yellow, symbol: "clock.fill")
            } else if v == "rejected" {
                statusPill(text: Language.get("Rejected", alter: "مرفوضة"), color: .red, symbol: "xmark.circle.fill")
            } else {
                statusPill(text: Language.get("Service_Stat_Live", alter: "نشطة"), color: .green, symbol: "checkmark.circle.fill")
            }
        }
    }

    private func statusPill(text: String, color: Color, symbol: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8.5))
            Text(text)
                .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - ==========================================
// MARK: - IPAD: SPATIAL COCKPIT ARCHITECTURE
// MARK: - ==========================================

private struct iPadServicesSpatialCockpit: View {
    @ObservedObject var viewModel: AdminServicesViewModel
    let onDismiss: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Apex Command Bar
            iPadApexCommandBar

            Divider().background(AdminSurface.hairline)

            // Feedback Banners
            if let error = viewModel.errorMessage {
                iPadFeedbackBanner(text: error, isError: true)
            }
            if let success = viewModel.successMessage {
                iPadFeedbackBanner(text: success, isError: false)
            }

            // 2-Column Spatial Engine
            HStack(spacing: 0) {
                // Left Column: Stream Horizon (56% width)
                iPadLeftCatalogColumn
                    .frame(maxWidth: .infinity)

                // Separation Hairline
                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(width: 1)

                // Right Column: Live Dossier Inspector & Administrative Command Dock (44% width)
                iPadRightDossierColumn
                    .frame(width: 390)
            }
        }
    }

    // MARK: - Apex Command Bar

    private var iPadApexCommandBar: some View {
        HStack(spacing: 12) {
            // Back Button
            Button(action: onDismiss) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.control)
                        .frame(width: 38, height: 38)
                    Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AdminSurface.primaryText)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Title & Breadcrumb Stack
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(Language.get("Service_Section_Title", alter: "الخدمات"))
                        .font(Font.custom("Beiruti-Bold", size: 21, relativeTo: .title3))
                        .foregroundColor(AdminSurface.primaryText)

                    // Live Beacon Pulse
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text(Language.get("Services_LiveBeacon", alter: "متصل لحظياً بقاعدة البيانات"))
                            .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.control, in: Capsule())
                }

                Text(Language.get("CommandCenter_Operations_Workspace", alter: "مساحة عمل العمليات / الخدمات"))
                    .font(Font.custom("Beiruti-Regular", size: 12.5, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            // Trailing Actions Cluster
            HStack(spacing: 10) {
                // Refresh Sync Beacon
                Button {
                    viewModel.refreshTriggered()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                            .animation(viewModel.isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isLoading)
                        Text(Language.get("Refresh", alter: "تحديث"))
                            .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                    }
                    .foregroundColor(AdminSurface.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())

                // Add Service Jewel Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.activeSheet = .add
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text(Language.get("Service_Add_Title", alter: "إضافة خدمة"))
                            .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(color: AdminSurface.primary.opacity(0.24), radius: 6, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AdminSurface.surface)
    }

    private func iPadFeedbackBanner(text: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
                .font(.system(size: 13))
            Text(text)
                .font(Font.custom("Beiruti-Medium", size: 13, relativeTo: .caption))
                .foregroundColor(AdminSurface.primaryText)
            Spacer()
            Button {
                if isError { viewModel.errorMessage = nil }
                else { viewModel.successMessage = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background((isError ? Color.red : Color.green).opacity(0.12))
    }

    // MARK: - Left Column: Stream Horizon

    private var iPadLeftCatalogColumn: some View {
        VStack(spacing: 12) {
            // Interactive 4-Pod KPI HUD
            HStack(spacing: 8) {
                iPadTelemetryPod(title: Language.get("Service_Stat_Total", alter: "الإجمالي"), value: "\(viewModel.totalCount)", color: AdminSurface.primary, filter: .all, isSelected: viewModel.activeMetricFilter == .all, action: { viewModel.selectMetricFilter(.all) })
                iPadTelemetryPod(title: Language.get("Service_Stat_Live", alter: "نشطة"), value: "\(viewModel.liveCount)", color: Color(uiColor: .ppSuccess), filter: .live, isSelected: viewModel.activeMetricFilter == .live, action: { viewModel.selectMetricFilter(.live) })
                iPadTelemetryPod(title: Language.get("Service_Stat_Review", alter: "تحتاج مراجعة"), value: "\(viewModel.reviewCount)", color: Color(uiColor: .ppWarning), filter: .review, isSelected: viewModel.activeMetricFilter == .review, action: { viewModel.selectMetricFilter(.review) })
                iPadTelemetryPod(title: Language.get("Service_Stat_Archived", alter: "مؤرشفة"), value: "\(viewModel.archivedCount)", color: Color(uiColor: .ppTextSecondary), filter: .archived, isSelected: viewModel.activeMetricFilter == .archived, action: { viewModel.selectMetricFilter(.archived) })
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Search Bar & Filter Strip
            HStack(spacing: 8) {
                // Search Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AdminSurface.secondaryText)
                        .font(.system(size: 14))

                    TextField(Language.get("Service_Search_Placeholder", alter: "ابحث بالعنوان أو الفئة أو المالك..."), text: $viewModel.searchQuery)
                        .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                        .focused($isSearchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onChange(of: viewModel.searchQuery, perform: { _ in
                            viewModel.applyFilters()
                        })

                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                            viewModel.applyFilters()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AdminSurface.secondaryText)
                                .font(.system(size: 13))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSearchFocused ? AdminSurface.primary : AdminSurface.hairline)
                )

                // Sort Menu Button
                Menu {
                    ForEach(AdminServiceSortOption.allCases) { opt in
                        Button {
                            viewModel.sortOption = opt
                            viewModel.applyFilters()
                        } label: {
                            HStack {
                                Text(opt.title)
                                if viewModel.sortOption == opt { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 10, weight: .bold))
                        Text(viewModel.sortOption.title)
                            .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                    }
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 16)

            // Filter Chips Horizon
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AdminServicePrimaryFilter.allCases) { f in
                        let active = viewModel.primaryFilter == f
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                viewModel.primaryFilter = f
                                viewModel.activeMetricFilter = (f == .all ? nil : f)
                                viewModel.applyFilters()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: f.symbol).font(.system(size: 10))
                                Text(f.title)
                                    .font(Font.custom(active ? "Beiruti-Bold" : "Beiruti-Medium", size: 12.5, relativeTo: .caption))
                            }
                            .foregroundColor(active ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(active ? AdminSurface.primary : AdminSurface.surface, in: Capsule())
                            .overlay(Capsule().stroke(AdminSurface.hairline))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }

            // Stream List
            if viewModel.filteredServices.isEmpty && !viewModel.isLoading {
                ServicesLivingEmptyState(
                    hasSearch: !viewModel.searchQuery.isEmpty || viewModel.primaryFilter != .all,
                    onAdd: { viewModel.activeSheet = .add },
                    onReset: {
                        viewModel.searchQuery = ""
                        viewModel.primaryFilter = .all
                        viewModel.activeMetricFilter = nil
                        viewModel.applyFilters()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.filteredServices) { service in
                            iPadServiceRowCard(
                                service: service,
                                isSelected: viewModel.selectedService?.serviceID == service.serviceID,
                                onSelect: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        viewModel.selectedService = service
                                    }
                                },
                                onEdit: { viewModel.activeSheet = .edit(service) },
                                onModerate: { viewModel.activeSheet = .moderate(service) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func iPadTelemetryPod(title: String, value: String, color: Color, filter: AdminServicePrimaryFilter, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(value)
                    .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .headline))
                    .foregroundColor(color)
                Text(title)
                    .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(color.opacity(isSelected ? 0.22 : 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? color : AdminSurface.hairline, lineWidth: isSelected ? 1.8 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Right Column: Live Dossier Inspector

    private var iPadRightDossierColumn: some View {
        VStack(spacing: 0) {
            if let service = viewModel.selectedService {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Hero Image Section
                        ZStack(alignment: .bottomLeading) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AdminSurface.control)
                                .frame(height: 180)

                            if !service.imageURL.isEmpty, let url = URL(string: service.imageURL) {
                                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 358, height: 180)) {
                                    Image(systemName: "photo").font(.system(size: 32)).foregroundColor(.secondary)
                                }
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                VStack {
                                    Image(systemName: service.type == .grooming ? "scissors" : "figure.walk")
                                        .font(.system(size: 40))
                                        .foregroundColor(AdminSurface.primary.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }

                            // Category Pill Overlay
                            HStack {
                                let categoryName = !service.category.isEmpty ? service.category : service.localizedTypeName()
                                Text(categoryName.isEmpty ? Language.get("Service_Type_Service", alter: "خدمة") : categoryName)
                                    .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.65), in: Capsule())

                                Spacer()

                                // QAR Price Tag
                                HStack(spacing: 3) {
                                    Text(String(format: "%.2f", service.price))
                                        .font(.system(size: 15, weight: .bold))
                                        .monospacedDigit()
                                    Text(Language.get("QAR", alter: "ر.ق"))
                                        .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(uiColor: .ppSuccess), in: Capsule())
                            }
                            .padding(12)
                        }

                        // Title & Identifiers
                        VStack(alignment: .leading, spacing: 4) {
                            Text(service.title.isEmpty ? Language.get("Service_Untitled", alter: "خدمة بدون عنوان") : service.title)
                                .font(Font.custom("Beiruti-Bold", size: 19, relativeTo: .title3))
                                .foregroundColor(AdminSurface.primaryText)

                            Text("ID: \(service.serviceID)")
                                .font(.system(size: 11, weight: .regular))
                                .monospacedDigit()
                                .foregroundColor(AdminSurface.secondaryText)
                        }

                        // Status Telemetry Horizontal Strip
                        HStack(spacing: 8) {
                            iPadStatusTag(
                                title: service.isDeleted ? Language.get("Service_Stat_Archived", alter: "مؤرشفة") :
                                       (service.isBlocked ? Language.get("Service_Filter_Blocked", alter: "محظورة") :
                                       (service.isDisabled ? Language.get("Service_Filter_Disabled", alter: "معطلة") : Language.get("Service_Stat_Live", alter: "نشطة"))),
                                color: service.isDeleted ? .gray : (service.isBlocked ? .red : (service.isDisabled ? .orange : .green))
                            )

                            let verification = (service.verificationStatus ?? "").lowercased()
                            iPadStatusTag(
                                title: verification == "verified" ? Language.get("Verified", alter: "موثقة") :
                                       (verification == "rejected" ? Language.get("Rejected", alter: "مرفوضة") : Language.get("Pending", alter: "قيد المراجعة")),
                                color: verification == "verified" ? .green : (verification == "rejected" ? .red : .yellow)
                            )
                        }

                        // Provider Dossier Card
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Language.get("Services_Dossier_ProviderSection", alter: "بيانات المزوّد والاعتماد"))
                                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                .foregroundColor(AdminSurface.secondaryText)

                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(AdminSurface.primary)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(service.serviceOwnerID.isEmpty ? "—" : service.serviceOwnerID)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundColor(AdminSurface.primaryText)
                                    Text(Language.get("Service_Owner_Label", alter: "معرّف مالك الخدمة"))
                                        .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                                        .foregroundColor(AdminSurface.secondaryText)
                                }

                                Spacer()

                                Button {
                                    UIPasteboard.general.string = service.serviceOwnerID
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12))
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                            }
                            .padding(10)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
                        }

                        // Full Description Box
                        if !service.serviceDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let desc = service.serviceDescriptionText
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Language.get("Description", alter: "الوصف التفصيلي"))
                                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.secondaryText)

                                Text(desc)
                                    .font(Font.custom("Beiruti-Regular", size: 13.5, relativeTo: .body))
                                    .foregroundColor(AdminSurface.primaryText)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
                            }
                        }
                    }
                    .padding(16)
                }

                Divider().background(AdminSurface.hairline)

                // Administrative Command Dock
                VStack(spacing: 8) {
                    // Twin Launchers
                    HStack(spacing: 8) {
                        Button {
                            viewModel.activeSheet = .edit(service)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                Text(Language.get("Service_Action_Edit", alter: "تعديل الخدمة"))
                                    .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .callout))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button {
                            viewModel.activeSheet = .moderate(service)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                Text(Language.get("Service_Action_Moderate", alter: "مراجعة واعتماد"))
                                    .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .callout))
                            }
                            .foregroundColor(Color(uiColor: .ppWarning))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Color(uiColor: .ppWarning).opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Administrative Toggles Strip
                    HStack(spacing: 6) {
                        // Toggle Disabled
                        Button {
                            viewModel.toggleDisabled(service: service)
                        } label: {
                            Text(service.isDisabled ? Language.get("Service_Action_Enable", alter: "تفعيل") : Language.get("Service_Action_Disable", alter: "تعطيل"))
                                .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption))
                                .foregroundColor(service.isDisabled ? Color(uiColor: .ppSuccess) : .orange)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Toggle Blocked
                        Button {
                            viewModel.toggleBlocked(service: service)
                        } label: {
                            Text(service.isBlocked ? Language.get("Service_Action_Unblock", alter: "فك الحظر") : Language.get("Service_Action_Block", alter: "حظر"))
                                .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption))
                                .foregroundColor(service.isBlocked ? Color(uiColor: .ppSuccess) : .red)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Toggle Archive
                        Button {
                            viewModel.toggleArchived(service: service)
                        } label: {
                            Text(service.isDeleted ? Language.get("Service_Action_Restore", alter: "استعادة") : Language.get("Service_Action_Archive", alter: "أرشفة"))
                                .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Permanent Delete
                        Button {
                            viewModel.deletePermanently(service: service)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                                .frame(width: 32, height: 32)
                                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(14)
                .background(AdminSurface.surface)

            } else {
                // Empty Inspector Placeholder
                VStack(spacing: 14) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 54, weight: .light))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.4))

                    Text(Language.get("Services_Dossier_InspectorTitle", alter: "ملف الخدمة الشامل"))
                        .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .headline))
                        .foregroundColor(AdminSurface.primaryText)

                    Text(Language.get("Services_Dossier_EmptyHint", alter: "اختر عرض خدمة من القائمة لمعاينة التفاصيل الكاملة وتفعيل إجراءات الرقابة والإدارة."))
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AdminSurface.surface.opacity(0.4))
    }

    private func iPadStatusTag(title: String, color: Color) -> some View {
        Text(title)
            .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - iPad Specimen Row Card

private struct iPadServiceRowCard: View {
    let service: PPServiceModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onModerate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Main Touch Target
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    // Thumbnail
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AdminSurface.control)
                            .frame(width: 58, height: 58)

                        if !service.imageURL.isEmpty, let url = URL(string: service.imageURL) {
                            AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 58, height: 58)) {
                                Image(systemName: "photo").font(.system(size: 16))
                            }
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            Image(systemName: service.type == .grooming ? "scissors" : "figure.walk")
                                .font(.system(size: 20))
                                .foregroundColor(AdminSurface.primary.opacity(0.7))
                        }
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            let categoryName = !service.category.isEmpty ? service.category : service.localizedTypeName()
                            Text(categoryName.isEmpty ? Language.get("Service_Type_Service", alter: "خدمة") : categoryName)
                                .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(AdminSurface.primary.opacity(0.10), in: Capsule())

                            Spacer()

                            // Status Tag
                            statusTag
                        }

                        Text(service.title.isEmpty ? Language.get("Service_Untitled", alter: "خدمة بدون عنوان") : service.title)
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .body))
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(String(format: "%.2f %@", service.price, Language.get("QAR", alter: "ر.ق")))
                                .font(.system(size: 12, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(Color(uiColor: .ppSuccess))

                            if !service.serviceOwnerID.isEmpty {
                                let owner = service.serviceOwnerID
                                Text("•").foregroundColor(AdminSurface.hairline)
                                Text("ID: \(String(owner.prefix(8)))")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Quick Edit Button
            Button(action: onEdit) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.10))
                        .frame(width: 32, height: 32)
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(10)
        .background(isSelected ? AdminSurface.primary.opacity(0.08) : AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSelected ? 1.6 : 1)
        )
    }

    @ViewBuilder
    private var statusTag: some View {
        if service.isDeleted {
            Text(Language.get("Service_Stat_Archived", alter: "مؤرشفة")).font(Font.custom("Beiruti-Bold", size: 10)).foregroundColor(.gray)
        } else if service.isBlocked {
            Text(Language.get("Service_Filter_Blocked", alter: "محظورة")).font(Font.custom("Beiruti-Bold", size: 10)).foregroundColor(.red)
        } else if service.isDisabled {
            Text(Language.get("Service_Filter_Disabled", alter: "معطلة")).font(Font.custom("Beiruti-Bold", size: 10)).foregroundColor(.orange)
        } else {
            Text(Language.get("Service_Stat_Live", alter: "نشطة")).font(Font.custom("Beiruti-Bold", size: 10)).foregroundColor(.green)
        }
    }
}

// MARK: - Living Empty State

private struct ServicesLivingEmptyState: View {
    let hasSearch: Bool
    let onAdd: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Concentric Breathing Rings
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.04))
                    .frame(width: 130, height: 130)

                Circle()
                    .fill(AdminSurface.primary.opacity(0.08))
                    .frame(width: 96, height: 96)

                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AdminSurface.surface)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)

                    Image(systemName: hasSearch ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack.fill")
                        .font(.system(size: 28))
                        .foregroundColor(AdminSurface.primary)
                }
            }
            .padding(.top, 16)

            // Copy Stack
            VStack(spacing: 6) {
                Text(hasSearch
                     ? Language.get("Service_Empty_Filtered_Title", alter: "لا توجد خدمات مطابقة")
                     : Language.get("Service_Empty_Title", alter: "لا توجد خدمات بعد"))
                    .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)

                Text(hasSearch
                     ? Language.get("Service_Empty_Filtered_Subtitle", alter: "جرّب بحثًا مختلفًا أو غيّر الفلاتر أو طريقة الترتيب.")
                     : Language.get("Service_Empty_Subtitle", alter: "أنشئ أول عرض خدمة أو انتظر وصول تحديثات Firestore."))
                    .font(Font.custom("Beiruti-Regular", size: 13.5, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Primary Action Button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if hasSearch {
                    onReset()
                } else {
                    onAdd()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: hasSearch ? "arrow.counterclockwise" : "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(hasSearch
                         ? Language.get("Service_ClearFilters", alter: "مسح الفلاتر")
                         : Language.get("Service_Add_Title", alter: "إضافة خدمة"))
                        .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .callout))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .shadow(color: AdminSurface.primary.opacity(0.24), radius: 8, y: 3)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - UIViewControllerRepresentable Wrappers

struct AdminServiceAddEditSheetRepresentable: UIViewControllerRepresentable {
    let service: PPServiceModel?

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = PPAddEditServiceViewController(service: service)
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.isHidden = true
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

struct AdminServiceDetailSheetRepresentable: UIViewControllerRepresentable {
    let service: PPServiceModel

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = PPServiceDetailViewController(service: service)
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.isHidden = true
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

struct AdminServiceModerationSheetRepresentable: UIViewControllerRepresentable {
    let service: PPServiceModel

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = PPServiceModerationViewController(service: service)
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.isHidden = true
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
