//
//  PPListingsCommandCenterView.swift
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 03/09/2026.
//  First-Principles Category-Defining Listings & Content Moderation Command Center.
//

import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore

// MARK: - Filter Rail Enum

public enum PPListingRailFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case active
    case adoption
    case archived
    case rejected

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .all: return Language.get("ListingsRail_All", alter: "الكل")
        case .pending: return Language.get("ListingsRail_Pending", alter: "قيد المراجعة")
        case .active: return Language.get("ListingsRail_Active", alter: "نشط بالسوق")
        case .adoption: return Language.get("ListingsRail_Adoption", alter: "معروض للتبني")
        case .archived: return Language.get("ListingsRail_Archived", alter: "مؤرشف")
        case .rejected: return Language.get("ListingsRail_Rejected", alter: "مرفوض")
        }
    }

    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .pending: return "clock.badge.exclamationmark"
        case .active: return "checkmark.seal"
        case .adoption: return "heart.circle"
        case .archived: return "archivebox"
        case .rejected: return "xmark.seal"
        }
    }
}

// MARK: - Listing Item Model

public struct PPListingModerationModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let source: String // "pet_ads" or "adopt_pets"
    public var title: String
    public var desc: String
    public var price: String
    public var category: String
    public var subcategory: String
    public var ownerID: String
    public var ownerName: String
    public var imageUrl: String
    public var status: Int // 0: Pending/Draft, 1: Active, 4: Archived, 5: Rejected
    public var visibility: Bool
    public var isApproved: Bool
    public var isBlocked: Bool
    public var viewsCount: Int
    public var createdAt: Date?
    public var updatedAt: Date?
    public var location: String
    public var petAge: String

    public var isMarketplace: Bool { source == "pet_ads" }
    public var isAdoption: Bool { source == "adopt_pets" }
    public var isPending: Bool { status == 0 && !isApproved }
    public var isActive: Bool { status == 1 && visibility && isApproved }
    public var isArchived: Bool { status == 4 }
    public var isRejected: Bool { status == 5 }

    public var statusTitle: String {
        switch status {
        case 0: return Language.get("Status_Pending", alter: "قيد المراجعة")
        case 1: return Language.get("Status_Active", alter: "نشط ومعتمد")
        case 4: return Language.get("Status_Archived", alter: "مؤرشف")
        case 5: return Language.get("Status_Rejected", alter: "مرفوض")
        default: return Language.get("Status_Unknown", alter: "غير محدد")
        }
    }

    public var statusColor: Color {
        switch status {
        case 0: return Color(uiColor: .ppWarning)
        case 1: return Color(uiColor: .ppSuccess)
        case 4: return AdminCommandInk.secondary
        case 5: return Color(uiColor: .ppError)
        default: return AdminCommandInk.tertiary
        }
    }

    public var formattedDateString: String {
        guard let date = updatedAt ?? createdAt else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    public var formattedPriceString: String {
        if isAdoption {
            return Language.get("FreeAdoption", alter: "مجاني (للتبني)")
        }
        let clean = price.trimmingCharacters(in: .whitespaces)
        if clean.isEmpty || clean == "0" {
            return Language.get("PriceNegotiable", alter: "قابل للتفاوض")
        }
        return "\(clean) " + Language.get("Currency_QAR", alter: "ر.ق")
    }
}

// MARK: - View Model

@MainActor
public final class PPListingsCommandCenterViewModel: ObservableObject {
    public let onDismiss: @Sendable () -> Void

    @Published public var listings: [PPListingModerationModel] = []
    @Published public var searchQuery: String = ""
    @Published public var selectedFilter: PPListingRailFilter = .all

    // State & Loading
    @Published public var isLoading: Bool = true
    @Published public var errorMessage: String? = nil
    @Published public var showSuccessToast: Bool = false
    @Published public var toastMessage: String = ""

    // Permissions
    @Published public var canView: Bool = true
    @Published public var canManage: Bool = true
    @Published public var canModerate: Bool = true

    // Inspection Dossier Selection
    @Published public var selectedListingForDossier: PPListingModerationModel? = nil

    nonisolated(unsafe) private var marketplaceListener: ListenerRegistration?
    nonisolated(unsafe) private var adoptionListener: ListenerRegistration?
    private var rawMarketplaceItems: [PPListingModerationModel] = []
    private var rawAdoptionItems: [PPListingModerationModel] = []

    public init(onDismiss: @escaping @Sendable () -> Void) {
        self.onDismiss = onDismiss
        evaluatePermissions()
        startRealtimeListeners()
    }

    deinit {
        marketplaceListener?.remove()
        adoptionListener?.remove()
    }

    public func evaluatePermissions() {
        if let staff = PPStaffAuth.shared().cachedCurrentStaff {
            canView = staff.hasPermission(kStaffPermListingsView)
            canManage = staff.hasPermission(kStaffPermListingsManage)
            canModerate = staff.hasPermission(kStaffPermListingsModerate)
        } else {
            canView = true
            canManage = true
            canModerate = true
        }
    }

    // MARK: - Real-time Listeners

    public func startRealtimeListeners() {
        isLoading = true
        errorMessage = nil

        let db = Firestore.firestore()

        // 1. Marketplace Listings Listener (pet_ads)
        let marketQuery = db.collection("pet_ads")
            .order(by: "createdAt", descending: true)
            .limit(to: 350)

        marketplaceListener?.remove()
        marketplaceListener = marketQuery.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                return
            }
            guard let docs = snapshot?.documents else { return }

            self.rawMarketplaceItems = docs.compactMap { self.parseMarketplaceItem(doc: $0) }
            self.mergeAndPublishListings()
        }

        // 2. Adoption Listings Listener (adopt_pets)
        let adoptionQuery = db.collection("adopt_pets")
            .order(by: "createdAt", descending: true)
            .limit(to: 350)

        adoptionListener?.remove()
        adoptionListener = adoptionQuery.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                return
            }
            guard let docs = snapshot?.documents else { return }

            self.rawAdoptionItems = docs.compactMap { self.parseAdoptionItem(doc: $0) }
            self.mergeAndPublishListings()
        }
    }

    private func mergeAndPublishListings() {
        var combined = rawMarketplaceItems + rawAdoptionItems
        combined.sort { (a, b) -> Bool in
            let dateA = a.updatedAt ?? a.createdAt ?? Date.distantPast
            let dateB = b.updatedAt ?? b.createdAt ?? Date.distantPast
            return dateA > dateB
        }
        self.listings = combined
        self.isLoading = false
    }

    private func parseMarketplaceItem(doc: QueryDocumentSnapshot) -> PPListingModerationModel? {
        let data = doc.data()
        let id = doc.documentID

        let title = (data["adTitle"] as? String) ?? (data["title"] as? String) ?? (data["name"] as? String) ?? ""
        let desc = (data["desc"] as? String) ?? ""
        let price = (data["price"] as? String) ?? "\(data["price"] as? Double ?? 0)"
        let category = (data["category"] as? String) ?? ""
        let subcategory = (data["subcategory"] as? String) ?? ""
        let ownerID = (data["ownerID"] as? String) ?? ""
        let ownerName = (data["ownerName"] as? String) ?? ""
        let imageUrl = (data["imageUrl"] as? String) ?? (data["imageURL"] as? String) ?? ""
        let status = (data["status"] as? Int) ?? 0
        let visibility = (data["visibility"] as? Bool) ?? ((data["visibility"] as? Int) == 1)
        let isApproved = (data["isApproved"] as? Bool) ?? false
        let isBlocked = (data["isBlocked"] as? Bool) ?? false
        let viewsCount = (data["viewsCount"] as? Int) ?? 0
        let petAge = (data["petAge"] as? String) ?? ""

        let location = (data["locationName"] as? String)
            ?? (data["cityName"] as? String)
            ?? (data["city"] as? String)
            ?? (data["address"] as? String)
            ?? (data["area"] as? String)
            ?? ""

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()

        return PPListingModerationModel(
            id: id,
            source: "pet_ads",
            title: title,
            desc: desc,
            price: price,
            category: category,
            subcategory: subcategory,
            ownerID: ownerID,
            ownerName: ownerName,
            imageUrl: imageUrl,
            status: status,
            visibility: visibility,
            isApproved: isApproved,
            isBlocked: isBlocked,
            viewsCount: viewsCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            location: location,
            petAge: petAge
        )
    }

    private func parseAdoptionItem(doc: QueryDocumentSnapshot) -> PPListingModerationModel? {
        let data = doc.data()
        let id = doc.documentID

        let title = (data["name"] as? String) ?? (data["title"] as? String) ?? ""
        let desc = (data["details"] as? String) ?? ""
        let price = "0"
        let category = (data["kindID"] as? String) ?? ""
        let ownerID = (data["ownerID"] as? String) ?? ""
        let ownerName = (data["ownerName"] as? String) ?? ""
        let imageArray = (data["imageURLsArray"] as? [String]) ?? []
        let imageUrl = imageArray.first ?? (data["imageUrl"] as? String) ?? ""
        let isBlocked = (data["isBlocked"] as? Bool) ?? false

        let location = (data["locationName"] as? String)
            ?? (data["cityName"] as? String)
            ?? (data["address"] as? String)
            ?? ""

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()

        return PPListingModerationModel(
            id: id,
            source: "adopt_pets",
            title: title,
            desc: desc,
            price: price,
            category: category,
            subcategory: "",
            ownerID: ownerID,
            ownerName: ownerName,
            imageUrl: imageUrl,
            status: 1, // Adoption pets are active by default
            visibility: true,
            isApproved: true,
            isBlocked: isBlocked,
            viewsCount: 0,
            createdAt: createdAt,
            updatedAt: createdAt,
            location: location,
            petAge: ""
        )
    }

    // MARK: - Computed Counts

    public var totalCount: Int { listings.count }
    public var pendingCount: Int { listings.filter { $0.isPending }.count }
    public var activeCount: Int { listings.filter { $0.isActive }.count }
    public var adoptionCount: Int { listings.filter { $0.isAdoption }.count }
    public var archivedCount: Int { listings.filter { $0.isArchived }.count }
    public var rejectedCount: Int { listings.filter { $0.isRejected }.count }

    public func count(for filter: PPListingRailFilter) -> Int {
        switch filter {
        case .all: return totalCount
        case .pending: return pendingCount
        case .active: return activeCount
        case .adoption: return adoptionCount
        case .archived: return archivedCount
        case .rejected: return rejectedCount
        }
    }

    // MARK: - Filtered Listings

    public var filteredListings: [PPListingModerationModel] {
        listings.filter { item in
            // 1. Rail Filter Check
            let passesRail: Bool
            switch selectedFilter {
            case .all:
                passesRail = true
            case .pending:
                passesRail = item.isPending
            case .active:
                passesRail = item.isActive && item.isMarketplace
            case .adoption:
                passesRail = item.isAdoption
            case .archived:
                passesRail = item.isArchived
            case .rejected:
                passesRail = item.isRejected
            }

            guard passesRail else { return false }

            // 2. Search Query Check
            let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
            guard !query.isEmpty else { return true }

            let inTitle = item.title.lowercased().contains(query)
            let inOwner = item.ownerName.lowercased().contains(query) || item.ownerID.lowercased().contains(query)
            let inCategory = item.category.lowercased().contains(query)
            let inLocation = item.location.lowercased().contains(query)

            return inTitle || inOwner || inCategory || inLocation
        }
    }

    // MARK: - Moderation Actions

    public func approveListing(_ item: PPListingModerationModel) {
        guard item.isMarketplace else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let db = Firestore.firestore()
        db.collection("pet_ads").document(item.id).updateData([
            "status": 1,
            "visibility": 1,
            "isApproved": true,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = error.localizedDescription
            } else {
                self.toastMessage = Language.get("ListingApprovedSuccess", alter: "تم اعتماد ونشر الإعلان بنجاح")
                self.showSuccessToast = true
                self.writeAuditLog(action: "approve_listing", item: item)
                if self.selectedListingForDossier?.id == item.id {
                    self.selectedListingForDossier = nil
                }
            }
        }
    }

    public func rejectListing(_ item: PPListingModerationModel) {
        guard item.isMarketplace else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let db = Firestore.firestore()
        db.collection("pet_ads").document(item.id).updateData([
            "status": 5,
            "isApproved": false,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = error.localizedDescription
            } else {
                self.toastMessage = Language.get("ListingRejectedSuccess", alter: "تم رفض الإعلان وإيقافه")
                self.showSuccessToast = true
                self.writeAuditLog(action: "reject_listing", item: item)
                if self.selectedListingForDossier?.id == item.id {
                    self.selectedListingForDossier = nil
                }
            }
        }
    }

    public func archiveListing(_ item: PPListingModerationModel) {
        guard item.isMarketplace else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let db = Firestore.firestore()
        db.collection("pet_ads").document(item.id).updateData([
            "status": 4,
            "visibility": 0,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = error.localizedDescription
            } else {
                self.toastMessage = Language.get("ListingArchivedSuccess", alter: "تمت أرشفة الإعلان")
                self.showSuccessToast = true
                self.writeAuditLog(action: "archive_listing", item: item)
                if self.selectedListingForDossier?.id == item.id {
                    self.selectedListingForDossier = nil
                }
            }
        }
    }

    private func writeAuditLog(action: String, item: PPListingModerationModel) {
        let adminUid = Auth.auth().currentUser?.uid ?? "system_admin"
        Firestore.firestore().collection("AdminAuditLogs").addDocument(data: [
            "action": action,
            "targetCollection": item.source,
            "targetId": item.id,
            "adminUid": adminUid,
            "details": [
                "title": item.title,
                "source": item.source,
                "price": item.price,
                "ownerID": item.ownerID
            ],
            "timestamp": FieldValue.serverTimestamp()
        ])
    }
}

// MARK: - Main Screen View

public struct PPListingsCommandCenterScreen: View {
    @StateObject public var viewModel: PPListingsCommandCenterViewModel

    public init(viewModel: PPListingsCommandCenterViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Background Canvas
            AdminSurface.background
                .ignoresSafeArea()

            // Main Content Area
            ScrollView {
                VStack(spacing: 16) {
                    // Safe Area Offset for Sovereign Navigation Bar
                    Spacer().frame(height: 72)

                    // Error Banner if needed
                    if let err = viewModel.errorMessage {
                        AdminErrorBanner(message: err) {
                            viewModel.errorMessage = nil
                        }
                        .padding(.horizontal, AdminSpacing.screenMargin)
                    }

                    // 1. High-Octane Telemetry Radar Deck
                    telemetryRadarDeck
                        .padding(.horizontal, AdminSpacing.screenMargin)

                    // 2. Search & Channel Filter Rail
                    searchAndFilterRailDeck
                        .padding(.horizontal, AdminSpacing.screenMargin)

                    // 3. Listings List or Empty State
                    if viewModel.isLoading && viewModel.listings.isEmpty {
                        loadingStateView
                            .padding(.top, 40)
                    } else if viewModel.filteredListings.isEmpty {
                        emptyStateView
                            .padding(.top, 40)
                    } else {
                        listingsCardsDeck
                            .padding(.horizontal, AdminSpacing.screenMargin)
                    }

                    // Bottom clearance
                    Spacer().frame(height: 48)
                }
            }

            // Sovereign Glassmorphic Navigation Bar
            sovereignNavigationBar
        }
        .sheet(item: $viewModel.selectedListingForDossier) { listing in
            PPListingDetailDossierSheet(item: listing, viewModel: viewModel)
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Sovereign Glassmorphic Navigation Bar

    private var sovereignNavigationBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Back Button (Luxury Glass Squircle)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.onDismiss()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AdminSurface.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                            )
                        Image(systemName: Language.isRTL() ? "arrow.right" : "arrow.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                // Title & Live Counter Stack
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("ListingsAdmin_Title", alter: "إدارة الإعلانات والقوائم"))
                        .font(AdminType.title3)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.pendingCount > 0 ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess))
                            .frame(width: 6, height: 6)

                        Text(
                            viewModel.pendingCount > 0
                                ? "\(viewModel.totalCount) " + Language.get("TotalListings", alter: "إعلان") + " • \(viewModel.pendingCount) " + Language.get("PendingAction", alter: "بانتظار المراجعة")
                                : "\(viewModel.totalCount) " + Language.get("TotalListings", alter: "إعلان معروض وموثق")
                        )
                        .font(AdminType.caption2)
                        .foregroundStyle(viewModel.pendingCount > 0 ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess))
                    }
                }

                Spacer()

                // Manual Refresh Action
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.startRealtimeListeners()
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.surface)
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle().strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                            )
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(
                Color.clear
                    .ignoresSafeArea(edges: .top)
            )
        }
    }

    // MARK: - High-Octane Telemetry Radar Deck

    private var telemetryRadarDeck: some View {
        HStack(spacing: 8) {
            // Total Listings Pod
            telemetryPod(
                title: Language.get("Telemetry_Total", alter: "الإجمالي"),
                count: viewModel.totalCount,
                accentColor: AdminSurface.primary,
                icon: "square.stack.3d.up.fill",
                showPulsingDot: false
            )

            // Pending Review Pod (Critical Call-To-Action)
            telemetryPod(
                title: Language.get("Telemetry_Pending", alter: "معلق"),
                count: viewModel.pendingCount,
                accentColor: Color(uiColor: .ppWarning),
                icon: "clock.badge.exclamationmark.fill",
                showPulsingDot: viewModel.pendingCount > 0
            )

            // Active Market Pod
            telemetryPod(
                title: Language.get("Telemetry_Active", alter: "نشط"),
                count: viewModel.activeCount,
                accentColor: Color(uiColor: .ppSuccess),
                icon: "checkmark.seal.fill",
                showPulsingDot: false
            )

            // Adoption Pets Pod
            telemetryPod(
                title: Language.get("Telemetry_Adoption", alter: "تبني"),
                count: viewModel.adoptionCount,
                accentColor: Color.blue,
                icon: "heart.fill",
                showPulsingDot: false
            )
        }
    }

    private func telemetryPod(
        title: String,
        count: Int,
        accentColor: Color,
        icon: String,
        showPulsingDot: Bool
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if showPulsingDot {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)
                }
                Text("\(count)")
                    .font(AdminType.title3)
                    .monospacedDigit()
                    .foregroundStyle(accentColor)
            }

            Text(title)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(showPulsingDot ? accentColor.opacity(0.8) : Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: showPulsingDot ? 1.5 : 0.75)
        )
        .shadow(color: showPulsingDot ? accentColor.opacity(0.18) : Color.clear, radius: 8, x: 0, y: 3)
    }

    // MARK: - Search Field & Filter Rail

    private var searchAndFilterRailDeck: some View {
        VStack(spacing: 10) {
            // Search Input Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                TextField(Language.get("SearchHere", alter: "...إبحث هنا في الإعلانات، الأسماء، والمعرّفات"), text: $viewModel.searchQuery)
                    .font(AdminType.callout)

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
            }
            .padding(12)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.75)
            )

            // Horizontal Filter Chips Rail
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PPListingRailFilter.allCases) { filter in
                        let isSelected = viewModel.selectedFilter == filter
                        let count = viewModel.count(for: filter)

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                viewModel.selectedFilter = filter
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: filter.iconName)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))

                                Text(filter.localizedTitle)
                                    .font(AdminType.caption1Bold)

                                Text("\(count)")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        isSelected ? Color.white.opacity(0.25) : AdminSurface.control,
                                        in: Capsule()
                                    )
                            }
                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(
                                isSelected
                                    ? AnyView(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(AdminSurface.primary)
                                            .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, x: 0, y: 2)
                                    )
                                    : AnyView(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(AdminSurface.surface)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.75)
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Listings Cards Deck

    private var listingsCardsDeck: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.filteredListings) { item in
                listingCard(item)
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.selectedListingForDossier = item
                    }
            }
        }
    }

    private func listingCard(_ item: PPListingModerationModel) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                // High-Res Media Thumbnail Slot with Channel Badge
                ZStack(alignment: .bottomLeading) {
                    if let url = URL(string: item.imageUrl), !item.imageUrl.isEmpty {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 86, height: 86)
                                    .clipped()
                            } else {
                                thumbnailPlaceholder(item)
                            }
                        }
                        .frame(width: 86, height: 86)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        thumbnailPlaceholder(item)
                            .frame(width: 86, height: 86)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    // Channel Pill (Marketplace vs Adoption)
                    HStack(spacing: 3) {
                        Image(systemName: item.isMarketplace ? "bag.fill" : "heart.fill")
                            .font(.system(size: 8))
                        Text(item.isMarketplace ? Language.get("MarketTag", alter: "السوق") : Language.get("AdoptionTag", alter: "تبني"))
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item.isMarketplace ? AdminSurface.primary : Color.blue, in: Capsule())
                    .padding(5)
                }

                // Info & Metadata Stack
                VStack(alignment: .leading, spacing: 4) {
                    // Header: Title
                    Text(item.title.isEmpty ? Language.get("UntitledListing", alter: "إعلان بدون عنوان") : item.title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    // Subtitle: Location & Owner
                    HStack(spacing: 4) {
                        if !item.location.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AdminCommandInk.secondary)
                                Text(item.location)
                                    .font(AdminType.caption2)
                                    .foregroundStyle(AdminCommandInk.secondary)
                                    .lineLimit(1)
                            }
                        }

                        if !item.ownerName.isEmpty {
                            Text("• " + item.ownerName)
                                .font(AdminType.caption2)
                                .foregroundStyle(AdminCommandInk.tertiary)
                                .lineLimit(1)
                        }
                    }

                    // Price Readout
                    Text(item.formattedPriceString)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(item.isAdoption ? Color.blue : AdminSurface.primary)
                        .monospacedDigit()

                    // Bottom Row: Date & Status Pill
                    HStack {
                        Text(item.formattedDateString)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.tertiary)

                        Spacer()

                        // Status Aura Pill
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.statusColor)
                                .frame(width: 5, height: 5)
                            Text(item.statusTitle)
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(item.statusColor)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(item.statusColor.opacity(0.12), in: Capsule())
                    }
                }

                // Left Chevron Navigation Indicator
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminCommandInk.tertiary)
            }

            // Inline Quick Action Bar (For Pending Market Listings)
            if item.isPending && item.isMarketplace && viewModel.canModerate {
                Divider().background(Color(uiColor: .ppSurfaceBorder).opacity(0.5))

                HStack(spacing: 10) {
                    Button {
                        viewModel.approveListing(item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(Language.get("QuickApprove", alter: "اعتماد فوري"))
                        }
                        .font(AdminType.caption1Bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Color(uiColor: .ppSuccess), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.rejectListing(item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text(Language.get("QuickReject", alter: "رفض الإعلان"))
                        }
                        .font(AdminType.caption1Bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Color(uiColor: .ppError), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(item.isPending ? Color(uiColor: .ppWarning).opacity(0.5) : Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: item.isPending ? 1.2 : 0.75)
        )
    }

    private func thumbnailPlaceholder(_ item: PPListingModerationModel) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.control)
            Image(systemName: item.isMarketplace ? "pawprint.fill" : "heart.fill")
                .font(.system(size: 26))
                .foregroundStyle(AdminSurface.primary.opacity(0.4))
        }
    }

    // MARK: - Empty & Loading States

    private var loadingStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.3)
                .tint(AdminSurface.primary)
            Text(Language.get("LoadingListings", alter: "جاري مزامنة الإعلانات من السحابة..."))
                .font(AdminType.calloutBold)
                .foregroundStyle(AdminCommandInk.secondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.fill")
                .font(.system(size: 46))
                .foregroundStyle(AdminCommandInk.tertiary)

            Text(Language.get("NoListingsMatch", alter: "لا توجد إعلانات مطابقة"))
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)

            Text(Language.get("NoListingsMatchHint", alter: "جرب تغيير فلتر البحث أو مراجعة شروط الفلترة الحالية"))
                .font(AdminType.caption1)
                .foregroundStyle(AdminCommandInk.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Inspection & Moderation Dossier Modal Sheet

public struct PPListingDetailDossierSheet: View {
    public let item: PPListingModerationModel
    @ObservedObject public var viewModel: PPListingsCommandCenterViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // Hero Image Slot
                        if let url = URL(string: item.imageUrl), !item.imageUrl.isEmpty {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    heroImagePlaceholder
                                }
                            }
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
                            )
                        } else {
                            heroImagePlaceholder
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }

                        // Identity & Status Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(item.isMarketplace ? Language.get("MarketplaceAd", alter: "إعلان تجاري بالسوق") : Language.get("AdoptionListing", alter: "إعلان تبني مجاني"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(item.isMarketplace ? AdminSurface.primary : Color.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background((item.isMarketplace ? AdminSurface.primary : Color.blue).opacity(0.12), in: Capsule())

                                Spacer()

                                HStack(spacing: 4) {
                                    Circle().fill(item.statusColor).frame(width: 6, height: 6)
                                    Text(item.statusTitle)
                                        .font(AdminType.caption2Bold)
                                        .foregroundStyle(item.statusColor)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(item.statusColor.opacity(0.12), in: Capsule())
                            }

                            Text(item.title)
                                .font(AdminType.title2)
                                .foregroundStyle(AdminSurface.primaryText)

                            HStack(alignment: .firstTextBaseline) {
                                Text(item.formattedPriceString)
                                    .font(AdminType.title3)
                                    .foregroundStyle(item.isAdoption ? Color.blue : AdminSurface.primary)
                                    .monospacedDigit()

                                Spacer()

                                if item.viewsCount > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "eye.fill")
                                            .font(.system(size: 11))
                                        Text("\(item.viewsCount) " + Language.get("Views", alter: "مشاهدة"))
                                            .font(AdminType.caption2)
                                    }
                                    .foregroundStyle(AdminCommandInk.secondary)
                                }
                            }
                        }
                        .padding(16)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        // Publisher Dossier
                        VStack(alignment: .leading, spacing: 10) {
                            Label(Language.get("PublisherDossier", alter: "بيانات المعلن والناشر"), systemImage: "person.crop.circle.badge.checkmark")
                                .font(AdminType.headline)
                                .foregroundStyle(AdminSurface.primaryText)

                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(AdminSurface.control)
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(AdminSurface.primary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.ownerName.isEmpty ? Language.get("UnknownOwner", alter: "معلن غير معروف") : item.ownerName)
                                        .font(AdminType.calloutBold)
                                        .foregroundStyle(AdminSurface.primaryText)

                                    Text(Language.get("OwnerIDLabel", alter: "المعرّف: ") + item.ownerID)
                                        .font(AdminType.caption2)
                                        .foregroundStyle(AdminCommandInk.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                        .padding(16)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        // Details & Specifications Grid
                        VStack(alignment: .leading, spacing: 12) {
                            Label(Language.get("ListingSpecs", alter: "تفاصيل ومواصفات الإعلان"), systemImage: "doc.plaintext")
                                .font(AdminType.headline)
                                .foregroundStyle(AdminSurface.primaryText)

                            if !item.category.isEmpty {
                                specRow(title: Language.get("CategoryLabel", alter: "التصنيف"), value: item.category)
                            }
                            if !item.location.isEmpty {
                                specRow(title: Language.get("LocationLabel", alter: "الموقع الجغرافي"), value: item.location)
                            }
                            if !item.petAge.isEmpty {
                                specRow(title: Language.get("PetAgeLabel", alter: "عمر الحيوان"), value: item.petAge)
                            }
                            specRow(title: Language.get("PublishDateLabel", alter: "تاريخ النشر"), value: item.formattedDateString)

                            if !item.desc.isEmpty {
                                Divider()
                                Text(Language.get("DescriptionLabel", alter: "الوصف التفصيلي:"))
                                    .font(AdminType.caption1Bold)
                                    .foregroundStyle(AdminCommandInk.secondary)
                                Text(item.desc)
                                    .font(AdminType.callout)
                                    .foregroundStyle(AdminSurface.primaryText)
                            }
                        }
                        .padding(16)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        // Bottom safe clearance for action dock
                        Spacer().frame(height: 100)
                    }
                    .padding(16)
                }

                // Executive Moderation Dock
                if item.isMarketplace && (viewModel.canManage || viewModel.canModerate) {
                    moderationActionDock
                }
            }
            .navigationTitle(Language.get("ListingDossierTitle", alter: "ملف فحص الإعلان"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) { dismiss() }
                        .font(AdminType.calloutBold)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var heroImagePlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.control)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(AdminSurface.primary.opacity(0.4))
        }
    }

    private func specRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AdminType.callout)
                .foregroundStyle(AdminCommandInk.secondary)
            Spacer()
            Text(value)
                .font(AdminType.calloutBold)
                .foregroundStyle(AdminSurface.primaryText)
        }
    }

    private var moderationActionDock: some View {
        HStack(spacing: 12) {
            if viewModel.canModerate && item.status != 1 {
                Button {
                    viewModel.approveListing(item)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                        Text(Language.get("ApproveListing", alter: "اعتماد ونشر"))
                    }
                    .font(AdminType.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(uiColor: .ppSuccess), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if viewModel.canModerate && item.status != 5 {
                Button {
                    viewModel.rejectListing(item)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.seal.fill")
                        Text(Language.get("RejectListing", alter: "رفض الإعلان"))
                    }
                    .font(AdminType.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(uiColor: .ppError), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if viewModel.canManage && item.status != 4 {
                Button {
                    viewModel.archiveListing(item)
                    dismiss()
                } label: {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(width: 48, height: 48)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Divider().background(Color(uiColor: .ppSurfaceBorder).opacity(0.6))
                }
        )
    }
}

// MARK: - Hosting Controller Bridge

@objc @MainActor public final class PPListingsCommandCenterHostingBridge: NSObject {
    @objc(makeViewControllerWithOnDismiss:) public static func makeViewController(onDismiss: @escaping @Sendable () -> Void) -> UIViewController {
        let viewModel = PPListingsCommandCenterViewModel(onDismiss: onDismiss)
        let host = UIHostingController(rootView: PPListingsCommandCenterScreen(viewModel: viewModel))
        host.view.backgroundColor = .clear
        return host
    }
}
