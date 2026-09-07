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

// MARK: - Species Taxonomy

public enum SpeciesTaxonomy: String, CaseIterable, Sendable {
    case birds
    case cats
    case dogs
    case falcons
    case horses
    case other

    public var iconName: String {
        switch self {
        case .birds: return "bird.fill"
        case .cats: return "pawprint.fill"
        case .dogs: return "pawprint.fill"
        case .falcons: return "wind"
        case .horses: return "figure.equestrian.sports"
        case .other: return "pawprint.fill"
        }
    }

    public var localizedTitle: String {
        switch self {
        case .birds: return Language.get("Listing_Taxonomy_Bird", alter: "طيور وببغاوات")
        case .cats: return Language.get("Listing_Taxonomy_Cat", alter: "قطط وفصائلها")
        case .dogs: return Language.get("Listing_Taxonomy_Dog", alter: "كلاب وجراء")
        case .falcons: return Language.get("Listing_Taxonomy_Falcon", alter: "صقور وجوارح")
        case .horses: return Language.get("Listing_Taxonomy_Horse", alter: "خيول وفروسية")
        case .other: return Language.get("Listing_Taxonomy_General", alter: "أليف متنوع")
        }
    }

    public var accentColor: Color {
        switch self {
        case .birds: return Color.orange
        case .cats: return Color.teal
        case .dogs: return Color.indigo
        case .falcons: return Color(red: 0.78, green: 0.52, blue: 0.28)
        case .horses: return Color.green
        case .other: return AdminSurface.primary
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
    public var rejectionReason: String?

    public var isMarketplace: Bool { source == "pet_ads" }
    public var isAdoption: Bool { source == "adopt_pets" }
    public var isPending: Bool { status == 0 && !isApproved }
    public var isActive: Bool { status == 1 && visibility && isApproved }
    public var isArchived: Bool { status == 4 }
    public var isRejected: Bool { status == 5 }

    public var taxonomy: SpeciesTaxonomy {
        let corpus = "\(title) \(category) \(subcategory) \(desc)".lowercased()

        let birdTokens = ["كوكتيل", "كروان", "ببغاء", "طائر", "طيور", "كاسكو", "روز", "بادجي", "كناري", "حمام", "بلبل", "cockatiel", "parrot", "bird", "canary"]
        for token in birdTokens {
            if corpus.contains(token) { return .birds }
        }

        let catTokens = ["قط", "قطط", "بسة", "بسه", "شيرازي", "هملايا", "سيامي", "بريطاني", "cat", "kitten", "persian"]
        for token in catTokens {
            if corpus.contains(token) { return .cats }
        }

        let dogTokens = ["كلب", "كلاب", "جرو", "هاسكي", "بولدوج", "بيتبول", "جيرمن", "dog", "puppy", "husky"]
        for token in dogTokens {
            if corpus.contains(token) { return .dogs }
        }

        let falconTokens = ["صقر", "صقور", "شواهين", "شاهين", "حر", "جير", "falcon", "hawk", "raptor"]
        for token in falconTokens {
            if corpus.contains(token) { return .falcons }
        }

        let horseTokens = ["خيل", "خيول", "حصان", "مهرة", "فرس", "horse", "equestrian", "stallion"]
        for token in horseTokens {
            if corpus.contains(token) { return .horses }
        }

        return .other
    }

    public var statusTitle: String {
        switch status {
        case 0: return Language.get("Listing_Status_Pending_Badge", alter: "بانتظار المراجعة")
        case 1: return Language.get("Listing_Status_Active_Badge", alter: "نشط ومعتمد")
        case 4: return Language.get("Listing_Status_Archived_Badge", alter: "مؤرشف")
        case 5: return Language.get("Listing_Status_Rejected_Badge", alter: "مرفوض")
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

    // Publisher Isolation Filter
    @Published public var activePublisherUIDFilter: String? = nil
    @Published public var activePublisherName: String? = nil

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

    // Rejection Reason Modal Selection
    @Published public var itemForRejectionSheet: PPListingModerationModel? = nil

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
        let rejectionReason = data["rejectionReason"] as? String

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
            petAge: petAge,
            rejectionReason: rejectionReason
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
            petAge: "",
            rejectionReason: nil
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
            // 0. Publisher Filter Check
            if let pubUID = activePublisherUIDFilter, !pubUID.isEmpty {
                guard item.ownerID == pubUID else { return false }
            }

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
            let inTaxonomy = item.taxonomy.localizedTitle.lowercased().contains(query)

            return inTitle || inOwner || inCategory || inLocation || inTaxonomy
        }
    }

    // MARK: - Publisher Filter Actions

    public func filterByPublisher(uid: String, name: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        activePublisherUIDFilter = uid
        activePublisherName = name.isEmpty ? uid : name
        selectedFilter = .all
        searchQuery = ""
    }

    public func clearPublisherFilter() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activePublisherUIDFilter = nil
        activePublisherName = nil
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

    public func rejectListing(_ item: PPListingModerationModel, reason: String? = nil) {
        guard item.isMarketplace else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let db = Firestore.firestore()
        var patchData: [String: Any] = [
            "status": 5,
            "isApproved": false,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        let cleanReason = reason?.trimmingCharacters(in: .whitespaces)
        if let cleanReason = cleanReason, !cleanReason.isEmpty {
            patchData["rejectionReason"] = cleanReason
        }

        db.collection("pet_ads").document(item.id).updateData(patchData) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = error.localizedDescription
            } else {
                self.toastMessage = Language.get("ListingRejectedSuccess", alter: "تم رفض الإعلان وإيقافه")
                self.showSuccessToast = true
                self.writeAuditLog(action: "reject_listing", item: item, reason: cleanReason)
                if self.selectedListingForDossier?.id == item.id {
                    self.selectedListingForDossier = nil
                }
                if self.itemForRejectionSheet?.id == item.id {
                    self.itemForRejectionSheet = nil
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

    private func writeAuditLog(action: String, item: PPListingModerationModel, reason: String? = nil) {
        let adminUid = Auth.auth().currentUser?.uid ?? "system_admin"
        var details: [String: Any] = [
            "title": item.title,
            "source": item.source,
            "price": item.price,
            "ownerID": item.ownerID,
            "ownerName": item.ownerName
        ]
        if let reason = reason, !reason.isEmpty {
            details["rejectionReason"] = reason
        }
        Firestore.firestore().collection("AdminAuditLogs").addDocument(data: [
            "action": action,
            "targetCollection": item.source,
            "targetId": item.id,
            "adminUid": adminUid,
            "details": details,
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

                    // Floating Success Toast if triggered
                    if viewModel.showSuccessToast {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppSuccess))
                            Text(viewModel.toastMessage)
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.4), lineWidth: 1)
                        )
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                withAnimation {
                                    viewModel.showSuccessToast = false
                                }
                            }
                        }
                    }

                    // Error Banner if needed
                    if let err = viewModel.errorMessage {
                        AdminErrorBanner(message: err) {
                            viewModel.errorMessage = nil
                        }
                        .padding(.horizontal, AdminSpacing.screenMargin)
                    }

                    // Active Publisher Filter Banner
                    if let publisherUID = viewModel.activePublisherUIDFilter {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AdminSurface.primary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(Language.get("Listing_View_Publisher_Ads", alter: "إعلانات الناشر"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(AdminCommandInk.secondary)
                                Text(viewModel.activePublisherName ?? publisherUID)
                                    .font(AdminType.calloutBold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                viewModel.clearPublisherFilter()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                    Text(Language.get("Listing_Reject_Cancel_Action", alter: "إلغاء"))
                                        .font(AdminType.caption2Bold)
                                }
                                .foregroundStyle(Color(uiColor: .ppError))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(uiColor: .ppError).opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AdminSurface.primary.opacity(0.4), lineWidth: 1)
                        )
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
        .sheet(item: $viewModel.itemForRejectionSheet) { item in
            ListingRejectionReasonSheet(item: item, viewModel: viewModel)
        }
        .background(
            NavigationLink(
                isActive: Binding(
                    get: { viewModel.selectedListingForDossier != nil },
                    set: { if !$0 { viewModel.selectedListingForDossier = nil } }
                ),
                destination: {
                    if let listing = viewModel.selectedListingForDossier {
                        PPListingDetailDossierSheet(
                            item: listing,
                            viewModel: viewModel,
                            isPushMode: true,
                            onBack: {
                                viewModel.selectedListingForDossier = nil
                            }
                        )
                    } else {
                        EmptyView()
                    }
                },
                label: { EmptyView() }
            )
            .hidden()
        )
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Sovereign Glassmorphic Navigation Bar

    private var sovereignNavigationBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("ListingsAdmin_Title", alter: "إدارة الإعلانات والقوائم"),
            subtitle: viewModel.pendingCount > 0
                ? "\(viewModel.totalCount) " + Language.get("TotalListings", alter: "إعلان") + " • \(viewModel.pendingCount) " + Language.get("Listing_Queue_Critical", alter: "إعلانات تحتاج تدقيقك الفوري")
                : "\(viewModel.totalCount) " + Language.get("TotalListings", alter: "إعلان") + " • " + Language.get("Listing_Queue_Healthy", alter: "كافة الإعلانات معتمدة ومحدثة"),
            statusDotColor: viewModel.pendingCount > 0 ? Color(uiColor: .ppWarning) : Color(uiColor: .ppSuccess),
            onBack: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.onDismiss()
            }
        ) {
            AdminSquircleActionButton(
                systemImage: "arrow.clockwise",
                isLoading: false,
                accessibilityLabel: Language.get("Refresh", alter: "تحديث")
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.startRealtimeListeners()
            }
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
                                    .fixedSize(horizontal: true, vertical: false)

                                Text("\(count)")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
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
                // High-Res Media Thumbnail Slot with Channel & Taxonomy Badges
                ZStack(alignment: .bottomLeading) {
                    if let url = URL(string: item.imageUrl), !item.imageUrl.isEmpty {
                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 90, height: 90)) {
                            thumbnailPlaceholder(item)
                        }
                        .frame(width: 90, height: 90)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        thumbnailPlaceholder(item)
                            .frame(width: 90, height: 90)
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

                    // Taxonomy & Location Row
                    HStack(spacing: 6) {
                        // Taxonomy micro-pill
                        HStack(spacing: 3) {
                            Image(systemName: item.taxonomy.iconName)
                                .font(.system(size: 9))
                            Text(item.taxonomy.localizedTitle)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(item.taxonomy.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.taxonomy.accentColor.opacity(0.12), in: Capsule())

                        if !item.location.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 9))
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

                    // Rejection Reason Callout (if rejected and present)
                    if item.isRejected, let reason = item.rejectionReason, !reason.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color(uiColor: .ppError))
                            Text(reason)
                                .font(AdminType.caption2)
                                .foregroundStyle(Color(uiColor: .ppError))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }

                // Left Chevron Navigation Indicator
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminCommandInk.tertiary)
            }

            // Inline High-Velocity Triage Bar (For Pending Market Listings)
            if item.isPending && item.isMarketplace && viewModel.canModerate {
                Divider().background(Color(uiColor: .ppSurfaceBorder).opacity(0.5))

                HStack(spacing: 10) {
                    Button {
                        viewModel.approveListing(item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(Language.get("Listing_Quick_Approve", alter: "اعتماد فوري"))
                        }
                        .font(AdminType.caption1Bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Color(uiColor: .ppSuccess), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.itemForRejectionSheet = item
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text(Language.get("Listing_Quick_Reject", alter: "رفض مع السبب"))
                        }
                        .font(AdminType.caption1Bold)
                        .foregroundColor(Color(uiColor: .ppError))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Color(uiColor: .ppError).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppError).opacity(0.35), lineWidth: 0.8)
                        )
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
                .fill(item.taxonomy.accentColor.opacity(0.12))
            Image(systemName: item.taxonomy.iconName)
                .font(.system(size: 28))
                .foregroundStyle(item.taxonomy.accentColor)
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
    public var isPushMode: Bool = true
    public var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    public init(
        item: PPListingModerationModel,
        viewModel: PPListingsCommandCenterViewModel,
        isPushMode: Bool = true,
        onBack: (() -> Void)? = nil
    ) {
        self.item = item
        self.viewModel = viewModel
        self.isPushMode = isPushMode
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            AdminSovereignNavigationBar(
                title: Language.get("ListingDossierTitle", alter: "ملف فحص الإعلان"),
                subtitle: item.title,
                statusDotColor: item.statusColor,
                isModal: !isPushMode,
                onBack: {
                    if let onBack = onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                }
            )

            ZStack(alignment: .bottom) {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // Hero Media Showcase Slot with Taxonomy Tag
                        ZStack(alignment: .topTrailing) {
                            if let url = URL(string: item.imageUrl), !item.imageUrl.isEmpty {
                                AdminRemoteImage(url: url, contentMode: .fill) {
                                    heroImagePlaceholder
                                }
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
                                )
                            } else {
                                heroImagePlaceholder
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }

                            // Taxonomy Overlay Badge
                            HStack(spacing: 4) {
                                Image(systemName: item.taxonomy.iconName)
                                    .font(.system(size: 11, weight: .bold))
                                Text(item.taxonomy.localizedTitle)
                                    .font(AdminType.caption2Bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(item.taxonomy.accentColor, in: Capsule())
                            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                            .padding(12)
                        }

                        // Rejection Alert Banner (if rejected)
                        if item.isRejected, let reason = item.rejectionReason, !reason.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color(uiColor: .ppError))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Language.get("Listing_Reject_Title", alter: "سبب الرفض المسجل:"))
                                        .font(AdminType.caption1Bold)
                                        .foregroundStyle(Color(uiColor: .ppError))
                                    Text(reason)
                                        .font(AdminType.callout)
                                        .foregroundStyle(AdminSurface.primaryText)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppError).opacity(0.4), lineWidth: 1)
                            )
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

                        // Publisher Trust & Isolation Dossier
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(Language.get("PublisherDossier", alter: "بيانات المعلن والناشر"), systemImage: "person.crop.circle.badge.checkmark")
                                    .font(AdminType.headline)
                                    .foregroundStyle(AdminSurface.primaryText)

                                Spacer()

                                Text(Language.get("Listing_Publisher_Verified", alter: "معلن معتمد"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(Color(uiColor: .ppSuccess))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                            }

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

                            Divider().background(Color(uiColor: .ppSurfaceBorder).opacity(0.5))

                            // Action buttons: Copy UID & View All Publisher Ads
                            HStack(spacing: 10) {
                                Button {
                                    UIPasteboard.general.string = item.ownerID
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    viewModel.toastMessage = Language.get("Listing_UID_Copied", alter: "تم نسخ معرف المعلن")
                                    viewModel.showSuccessToast = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "doc.on.doc.fill")
                                            .font(.system(size: 11))
                                        Text(Language.get("Listing_Copy_UID", alter: "نسخ المعرف"))
                                    }
                                    .font(AdminType.caption1Bold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    viewModel.filterByPublisher(uid: item.ownerID, name: item.ownerName)
                                    if let onBack = onBack {
                                        onBack()
                                    } else {
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "rectangle.stack.fill")
                                            .font(.system(size: 11))
                                        Text(Language.get("Listing_View_Publisher_Ads", alter: "إعلانات الناشر"))
                                    }
                                    .font(AdminType.caption1Bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
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
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var heroImagePlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(item.taxonomy.accentColor.opacity(0.12))
            VStack(spacing: 8) {
                Image(systemName: item.taxonomy.iconName)
                    .font(.system(size: 48))
                    .foregroundStyle(item.taxonomy.accentColor)
                Text(item.taxonomy.localizedTitle)
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(item.taxonomy.accentColor)
            }
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
                    if let onBack = onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
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
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.itemForRejectionSheet = item
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
                    if let onBack = onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
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
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Rejection Reason Sheet

public struct ListingRejectionReasonSheet: View {
    public let item: PPListingModerationModel
    @ObservedObject public var viewModel: PPListingsCommandCenterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: String? = nil
    @State private var customReason: String = ""

    private let presetReasons: [(key: String, title: String)] = [
        ("Listing_Reject_Reason_Photos", Language.get("Listing_Reject_Reason_Photos", alter: "صور غير واضحة أو مخالفة لمعايير العرض")),
        ("Listing_Reject_Reason_Price", Language.get("Listing_Reject_Reason_Price", alter: "سعر غير واقعي أو مضلل")),
        ("Listing_Reject_Reason_Prohibited", Language.get("Listing_Reject_Reason_Prohibited", alter: "حيوان أو صنف محظور عرضه في المنصة")),
        ("Listing_Reject_Reason_Duplicate", Language.get("Listing_Reject_Reason_Duplicate", alter: "إعلان مكرر أو بيانات غير مكتملة")),
        ("Listing_Reject_Reason_Terms", Language.get("Listing_Reject_Reason_Terms", alter: "مخالفة عامة لشروط الاستخدام والخدمة"))
    ]

    public init(item: PPListingModerationModel, viewModel: PPListingsCommandCenterViewModel) {
        self.item = item
        self.viewModel = viewModel
    }

    private var effectiveReason: String {
        var reasons: [String] = []
        if let selectedPreset = selectedPreset, !selectedPreset.isEmpty {
            reasons.append(selectedPreset)
        }
        let customClean = customReason.trimmingCharacters(in: .whitespaces)
        if !customClean.isEmpty {
            reasons.append(customClean)
        }
        return reasons.joined(separator: " - ")
    }

    private var canSubmit: Bool {
        !effectiveReason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header info card
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(uiColor: .ppError).opacity(0.14))
                                    .frame(width: 46, height: 46)
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color(uiColor: .ppError))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(Language.get("Listing_Reject_Title", alter: "رفض الإعلان"))
                                    .font(AdminType.headline)
                                    .foregroundStyle(AdminSurface.primaryText)
                                Text(item.title.isEmpty ? Language.get("UntitledListing", alter: "إعلان بدون عنوان") : item.title)
                                    .font(AdminType.caption1)
                                    .foregroundStyle(AdminCommandInk.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.75)
                        )

                        Text(Language.get("Listing_Reject_Subtitle", alter: "حدد سبب الرفض لتوثيقه في سجل التدقيق وإشعار المعلن:"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)

                        // Preset radio-list
                        VStack(spacing: 10) {
                            ForEach(presetReasons, id: \.key) { preset in
                                let isSelected = selectedPreset == preset.title
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        if selectedPreset == preset.title {
                                            selectedPreset = nil
                                        } else {
                                            selectedPreset = preset.title
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18, weight: isSelected ? .bold : .regular))
                                            .foregroundStyle(isSelected ? Color(uiColor: .ppError) : AdminCommandInk.tertiary)

                                        Text(preset.title)
                                            .font(AdminType.callout)
                                            .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminCommandInk.secondary)
                                            .multilineTextAlignment(.leading)

                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(
                                        isSelected ? Color(uiColor: .ppError).opacity(0.08) : AdminSurface.surface,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(
                                                isSelected ? Color(uiColor: .ppError).opacity(0.5) : Color(uiColor: .ppSurfaceBorder).opacity(0.6),
                                                lineWidth: isSelected ? 1.2 : 0.75
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Custom reason input
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Language.get("Listing_Reject_Reason_Custom", alter: "سبب إضافي أو مخصص..."))
                                .font(AdminType.caption1Bold)
                                .foregroundStyle(AdminCommandInk.secondary)

                            TextField(
                                Language.get("Listing_Reject_Reason_Placeholder", alter: "اكتب تفاصيل سبب الرفض هنا..."),
                                text: $customReason,
                                axis: .vertical
                            )
                            .font(AdminType.callout)
                            .lineLimit(3...5)
                            .padding(12)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.75)
                            )
                        }

                        // Action buttons
                        VStack(spacing: 10) {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                viewModel.rejectListing(item, reason: effectiveReason)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "xmark.seal.fill")
                                    Text(Language.get("Listing_Reject_Confirm_Action", alter: "تأكيد الرفض والإيقاف"))
                                }
                                .font(AdminType.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(
                                    canSubmit ? Color(uiColor: .ppError) : Color(uiColor: .ppError).opacity(0.35),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSubmit)

                            Button {
                                dismiss()
                            } label: {
                                Text(Language.get("Listing_Reject_Cancel_Action", alter: "إلغاء"))
                                    .font(AdminType.calloutBold)
                                    .foregroundStyle(AdminCommandInk.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 10)
                    }
                    .padding(18)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        dismiss()
                    }
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Hosting Controller Bridge

@objc @MainActor public final class PPListingsCommandCenterHostingBridge: NSObject {
    @objc(makeViewControllerWithOnDismiss:) public static func makeViewController(onDismiss: @escaping @Sendable () -> Void) -> UIViewController {
        let viewModel = PPListingsCommandCenterViewModel(onDismiss: onDismiss)
        let root = NavigationView {
            PPListingsCommandCenterScreen(viewModel: viewModel)
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)

        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        return host
    }
}
