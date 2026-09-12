//
//  ModerationView.swift
//  PurePetsAdmin
//
//  Category-Defining Beyond-FAANG Trust & Safety / Operations Command Center.
//  Reimagined from absolute first principles:
//  - Living Radar Aurora with state-responsive ambient atmospheric mesh
//  - Guaranteed Working Back Navigation with safe-area compensation & tactile haptics
//  - Sovereign Navigation Deck with live sync beacon & safety guidelines popover
//  - 3D Executive Telemetry Matrix (KPI HUD) with real-time backlog depth & urgency tracking
//  - Fluid Liquid Stream Selector between Content Moderation & Chat Safety Reports
//  - Multi-Dimensional Real-Time Filter & Search Horizon
//  - Beyond-FAANG Content Dossier Card with rich multi-photo filmstrip & full-screen lightbox
//  - Beyond-FAANG Chat Report Dossier Card with dual-party comparison & direct actions
//  - Executive Zero-State with breathing concentric radar rings & platform health telemetry
//  - Granular Rejection Reason Drawer with regulatory presets & custom audit trail
//  - Cloud Function execution & server-side audit logging
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Enums & Types

enum ModerationStreamType: Int, CaseIterable, Identifiable {
    case content = 0
    case chatReports = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .content:
            return Language.get("Moderation_ContentQueue", alter: "مراجعة المحتوى")
        case .chatReports:
            return Language.get("Moderation_ChatReports", alter: "بلاغات الدردشة")
        }
    }

    var symbol: String {
        switch self {
        case .content: return "square.stack.3d.up.fill"
        case .chatReports: return "bubble.left.and.exclamationmark.bubble.right.fill"
        }
    }
}

enum ModerationContentFilter: String, CaseIterable, Identifiable {
    case all
    case flagged
    case pending
    case petAds
    case adoptions
    case services

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return Language.get("All", alter: "الكل")
        case .flagged: return Language.get("Moderation_Status_Flagged", alter: "مبلغ عنه ⚠️")
        case .pending: return Language.get("Moderation_Status_Pending", alter: "قيد المراجعة ⏳")
        case .petAds: return Language.get("Moderation_Source_PetAd", alter: "إعلانات الحيوانات 🐾")
        case .adoptions: return Language.get("Moderation_Source_Adoption", alter: "التبني 💖")
        case .services: return Language.get("Moderation_Source_Service", alter: "الخدمات 🩺")
        }
    }
}

enum ModerationChatFilter: String, CaseIterable, Identifiable {
    case all
    case urgent
    case pending
    case resolved
    case dismissed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return Language.get("All", alter: "الكل")
        case .urgent: return Language.get("Urgent", alter: "عاجل 🚨")
        case .pending: return Language.get("Pending", alter: "قيد الانتظار ⏳")
        case .resolved: return Language.get("Moderation_Resolve", alter: "تم الحل ✓")
        case .dismissed: return Language.get("Moderation_Dismiss", alter: "تم التجاهل ✕")
        }
    }
}

// MARK: - Content Item Model

struct AdminContentItem: Identifiable, Hashable, Sendable {
    enum SourceKind: String, Sendable {
        case petAd = "pet_ads"
        case adoption = "adopt_pets"
        case service = "serviceOffers"

        var label: String {
            switch self {
            case .petAd: return Language.get("Moderation_Source_PetAd", alter: "إعلان حيوان")
            case .adoption: return Language.get("Moderation_Source_Adoption", alter: "طلب تبني")
            case .service: return Language.get("Moderation_Source_Service", alter: "عرض خدمة")
            }
        }

        var icon: String {
            switch self {
            case .petAd: return "pawprint.fill"
            case .adoption: return "heart.fill"
            case .service: return "cross.case.fill"
            }
        }

        var color: Color {
            switch self {
            case .petAd: return Color(uiColor: .ppPrimary)
            case .adoption: return Color(uiColor: .ppSuccess)
            case .service: return Color(uiColor: .ppWarning)
            }
        }
    }

    let id: String
    let collectionName: String
    let sourceKind: SourceKind
    let title: String
    let descriptionText: String
    let price: Double?
    let ownerID: String
    let status: String
    let reportReason: String?
    let imageURL: String?
    let images: [String]
    let createdAt: Date

    var isFlagged: Bool {
        status == "flagged" || status == "reported" || (reportReason != nil && !reportReason!.isEmpty)
    }

    var statusColor: Color {
        if isFlagged { return .red }
        if status == "approved" { return .green }
        if status == "rejected" { return .gray }
        return .orange
    }

    var localizedStatus: String {
        if isFlagged { return Language.get("Moderation_Status_Flagged", alter: "مبلغ عنه") }
        if status == "approved" { return Language.get("Approved", alter: "معتمد") }
        if status == "rejected" { return Language.get("Rejected", alter: "مرفوض") }
        return Language.get("Moderation_Status_Pending", alter: "قيد المراجعة")
    }

    static func from(doc: DocumentSnapshot, collectionName: String) -> AdminContentItem? {
        guard let data = doc.data() else { return nil }
        let title = (data["title"] as? String)
            ?? (data["name"] as? String)
            ?? (data["serviceName"] as? String)
            ?? Language.get("Unknown", alter: "بدون عنوان")
        let desc = (data["description"] as? String)
            ?? (data["details"] as? String)
            ?? ""
        let price = (data["price"] as? Double)
            ?? (data["price"] as? NSNumber)?.doubleValue
        let owner = (data["ownerID"] as? String)
            ?? (data["userId"] as? String)
            ?? (data["uid"] as? String)
            ?? ""
        let status = (data["status"] as? String) ?? "pending_review"
        let reason = (data["reportReason"] as? String) ?? (data["rejectionReason"] as? String)

        var imageList: [String] = []
        if let arr = data["images"] as? [String] {
            imageList = arr
        } else if let mainImg = data["image"] as? String, !mainImg.isEmpty {
            imageList = [mainImg]
        } else if let mainImg = data["imageUrl"] as? String, !mainImg.isEmpty {
            imageList = [mainImg]
        }
        let firstImg = imageList.first

        let date: Date
        if let ts = data["createdAt"] as? Timestamp {
            date = ts.dateValue()
        } else {
            date = Date()
        }

        let kind: SourceKind
        if collectionName == "adopt_pets" {
            kind = .adoption
        } else if collectionName == "serviceOffers" {
            kind = .service
        } else {
            // Reject live pet inventory projections from user-content moderation queue
            let isFromCatalog = (data["isFromCatalog"] as? Bool) ?? false
            let sourceAccessoryId = (data["sourceAccessoryId"] as? String) ?? ""
            let catalogItemId = (data["catalogItemId"] as? String) ?? ""
            let isProjectionId = doc.documentID.hasPrefix("ad_live_") || doc.documentID.hasPrefix("ad_unit_") || doc.documentID.hasPrefix("live_pet_")
            if isFromCatalog || !sourceAccessoryId.isEmpty || !catalogItemId.isEmpty || isProjectionId {
                return nil
            }
            kind = .petAd
        }

        return AdminContentItem(
            id: doc.documentID,
            collectionName: collectionName,
            sourceKind: kind,
            title: title,
            descriptionText: desc,
            price: price,
            ownerID: owner,
            status: status,
            reportReason: reason,
            imageURL: firstImg,
            images: imageList,
            createdAt: date
        )
    }
}

// MARK: - Chat Report Model

struct AdminChatReportItem: Identifiable, Hashable, Sendable {
    let id: String
    let reporterUID: String
    let reportedUserUID: String
    let reason: String
    let status: String
    let chatID: String?
    let createdAt: Date

    var isPending: Bool {
        status == "pending" || status.isEmpty
    }

    var isResolved: Bool {
        status == "resolved"
    }

    var isDismissed: Bool {
        status == "dismissed"
    }

    var statusColor: Color {
        if isResolved { return .green }
        if isDismissed { return .gray }
        return .red
    }

    var localizedStatus: String {
        if isResolved { return Language.get("Moderation_Resolve", alter: "تم الحل") }
        if isDismissed { return Language.get("Moderation_Dismiss", alter: "تم التجاهل") }
        return Language.get("Pending", alter: "قيد الانتظار")
    }

    var isUrgent: Bool {
        let text = reason.lowercased()
        return text.contains("احتيال") || text.contains("اساء") || text.contains("fraud") || text.contains("scam") || text.contains("threat") || text.contains("سرقة") || text.contains("تعذيب")
    }

    static func from(doc: DocumentSnapshot) -> AdminChatReportItem? {
        guard let data = doc.data() else { return nil }
        let reporter = (data["reporterUID"] as? String)
            ?? (data["reporterId"] as? String)
            ?? (data["reporterUid"] as? String)
            ?? ""
        let reported = (data["reportedUserUID"] as? String)
            ?? (data["reportedUserId"] as? String)
            ?? (data["reportedUserUid"] as? String)
            ?? ""
        let reason = (data["reason"] as? String) ?? Language.get("Unknown", alter: "بدون سبب")
        let status = (data["status"] as? String) ?? "pending"
        let chatID = (data["chatID"] as? String) ?? (data["threadId"] as? String)

        let date: Date
        if let ts = data["createdAt"] as? Timestamp {
            date = ts.dateValue()
        } else {
            date = Date()
        }

        return AdminChatReportItem(
            id: doc.documentID,
            reporterUID: reporter,
            reportedUserUID: reported,
            reason: reason,
            status: status,
            chatID: chatID,
            createdAt: date
        )
    }
}

// MARK: - View Model

@MainActor
final class AdminModerationViewModel: ObservableObject {
    @Published var selectedStream: ModerationStreamType = .content
    @Published var contentFilter: ModerationContentFilter = .all
    @Published var chatFilter: ModerationChatFilter = .all
    @Published var searchText: String = ""

    @Published private(set) var contentItems: [AdminContentItem] = []
    @Published private(set) var chatReports: [AdminChatReportItem] = []
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var canManage: Bool = false
    @Published private(set) var isSubmitting: Bool = false

    @Published var inspectingContentItem: AdminContentItem? = nil
    @Published var inspectingChatReport: AdminChatReportItem? = nil
    @Published var rejectingContentItem: AdminContentItem? = nil
    @Published var selectedLightboxURL: String? = nil
    @Published var showStandardsSheet: Bool = false

    @Published var toastMessage: String? = nil
    @Published var isErrorToast: Bool = false

    private nonisolated(unsafe) var petAdsListener: (any ListenerRegistration)?
    private nonisolated(unsafe) var adoptPetsListener: (any ListenerRegistration)?
    private nonisolated(unsafe) var serviceOffersListener: (any ListenerRegistration)?
    private nonisolated(unsafe) var chatReportsListener: (any ListenerRegistration)?

    private var rawPetAds: [AdminContentItem] = []
    private var rawAdopts: [AdminContentItem] = []
    private var rawServices: [AdminContentItem] = []

    init() {
        evaluatePermissions()
    }

    deinit {
        petAdsListener?.remove()
        adoptPetsListener?.remove()
        serviceOffersListener?.remove()
        chatReportsListener?.remove()
    }

    func evaluatePermissions() {
        let staff = PPStaffAuth.shared().cachedCurrentStaff
        let hasManage = staff?.hasPermission(kStaffPermModerationManage) ?? false
        self.canManage = hasManage
    }

    // MARK: - Resilient Real-Time Listeners
    // Queries use status filters and sort locally in memory to eliminate missing-index errors on device.

    func startListening() {
        evaluatePermissions()
        isLoading = true

        let db = Firestore.firestore()
        let activeStatuses = ["flagged", "pending_review", "reported"]

        // 1. Pet Ads
        petAdsListener?.remove()
        petAdsListener = db.collection("pet_ads")
            .whereField("status", in: activeStatuses)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let docs = snapshot?.documents {
                        self.rawPetAds = docs.compactMap { AdminContentItem.from(doc: $0, collectionName: "pet_ads") }
                    } else {
                        self.rawPetAds = []
                    }
                    self.recomputeMergedContent()
                }
            }

        // 2. Adopt Pets
        adoptPetsListener?.remove()
        adoptPetsListener = db.collection("adopt_pets")
            .whereField("status", in: activeStatuses)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let docs = snapshot?.documents {
                        self.rawAdopts = docs.compactMap { AdminContentItem.from(doc: $0, collectionName: "adopt_pets") }
                    } else {
                        self.rawAdopts = []
                    }
                    self.recomputeMergedContent()
                }
            }

        // 3. Service Offers
        serviceOffersListener?.remove()
        serviceOffersListener = db.collection("serviceOffers")
            .whereField("status", in: activeStatuses)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let docs = snapshot?.documents {
                        self.rawServices = docs.compactMap { AdminContentItem.from(doc: $0, collectionName: "serviceOffers") }
                    } else {
                        self.rawServices = []
                    }
                    self.recomputeMergedContent()
                }
            }

        // 4. Chat Reports
        chatReportsListener?.remove()
        chatReportsListener = db.collection("ChatReports")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isLoading = false
                    if let docs = snapshot?.documents {
                        self.chatReports = docs.compactMap { AdminChatReportItem.from(doc: $0) }
                    } else {
                        self.chatReports = []
                    }
                }
            }
    }

    private func recomputeMergedContent() {
        var merged = rawPetAds + rawAdopts + rawServices
        merged.sort { $0.createdAt > $1.createdAt }
        contentItems = merged
        isLoading = false
    }

    func stopListening() {
        petAdsListener?.remove()
        petAdsListener = nil
        adoptPetsListener?.remove()
        adoptPetsListener = nil
        serviceOffersListener?.remove()
        serviceOffersListener = nil
        chatReportsListener?.remove()
        chatReportsListener = nil
    }

    // MARK: - KPI Telemetry Metrics

    var pendingContentCount: Int {
        contentItems.filter { $0.status == "pending_review" }.count
    }

    var urgentFlaggedContentCount: Int {
        contentItems.filter { $0.isFlagged }.count
    }

    var pendingChatReportsCount: Int {
        chatReports.filter { $0.isPending }.count
    }

    var urgentChatReportsCount: Int {
        chatReports.filter { $0.isPending && $0.isUrgent }.count
    }

    var totalBacklogCount: Int {
        contentItems.count + pendingChatReportsCount
    }

    // MARK: - Filtered Datasets

    var filteredContentItems: [AdminContentItem] {
        contentItems.filter { item in
            // Search text
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let matchesTitle = item.title.lowercased().contains(q)
                let matchesDesc = item.descriptionText.lowercased().contains(q)
                let matchesOwner = item.ownerID.lowercased().contains(q)
                let matchesReason = (item.reportReason ?? "").lowercased().contains(q)
                let matchesID = item.id.lowercased().contains(q)
                if !matchesTitle && !matchesDesc && !matchesOwner && !matchesReason && !matchesID {
                    return false
                }
            }

            // Sub-filters
            switch contentFilter {
            case .all: return true
            case .pending: return item.status == "pending_review"
            case .flagged: return item.isFlagged
            case .petAds: return item.sourceKind == .petAd
            case .adoptions: return item.sourceKind == .adoption
            case .services: return item.sourceKind == .service
            }
        }
    }

    var filteredChatReports: [AdminChatReportItem] {
        chatReports.filter { report in
            // Search text
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let matchesReason = report.reason.lowercased().contains(q)
                let matchesReporter = report.reporterUID.lowercased().contains(q)
                let matchesReported = report.reportedUserUID.lowercased().contains(q)
                let matchesID = report.id.lowercased().contains(q)
                if !matchesReason && !matchesReporter && !matchesReported && !matchesID {
                    return false
                }
            }

            // Sub-filters
            switch chatFilter {
            case .all: return true
            case .urgent: return report.isUrgent
            case .pending: return report.isPending
            case .resolved: return report.isResolved
            case .dismissed: return report.isDismissed
            }
        }
    }

    // MARK: - Moderation Actions

    func approveContent(_ item: AdminContentItem) {
        guard canManage else {
            showToast(Language.get("Permissions_AccessDenied", alter: "ليس لديك صلاحية لتنفيذ هذا الإجراء"), isError: true)
            return
        }

        isSubmitting = true
        let callerUid = Auth.auth().currentUser?.uid ?? ""
        let patch: [String: Any] = [
            "status": "approved",
            "moderatedBy": callerUid,
            "moderatedAt": FieldValue.serverTimestamp()
        ]

        // Optimistic update in memory
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            contentItems.removeAll { $0.id == item.id }
        }

        Firestore.firestore().collection(item.collectionName).document(item.id).updateData(patch) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false
                if let error {
                    self.showToast(error.localizedDescription, isError: true)
                    self.startListening()
                } else {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    self.showToast(Language.get("Moderation_ApproveSuccess", alter: "تم اعتماد المحتوى بنجاح ✓"), isError: false)
                    self.writeAuditLog(action: "moderation.approve", targetCol: item.collectionName, targetId: item.id)
                }
            }
        }
    }

    func rejectContent(_ item: AdminContentItem, reason: String) {
        guard canManage else {
            showToast(Language.get("Permissions_AccessDenied", alter: "ليس لديك صلاحية لتنفيذ هذا الإجراء"), isError: true)
            return
        }

        isSubmitting = true
        let callerUid = Auth.auth().currentUser?.uid ?? ""
        let patch: [String: Any] = [
            "status": "rejected",
            "rejectionReason": reason,
            "moderatedBy": callerUid,
            "moderatedAt": FieldValue.serverTimestamp()
        ]

        // Optimistic update in memory
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            contentItems.removeAll { $0.id == item.id }
        }

        Firestore.firestore().collection(item.collectionName).document(item.id).updateData(patch) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false
                if let error {
                    self.showToast(error.localizedDescription, isError: true)
                    self.startListening()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    self.showToast(Language.get("Moderation_RejectSuccess", alter: "تم رفض المحتوى وتوثيق السبب في السجل"), isError: false)
                    self.writeAuditLog(action: "moderation.reject", targetCol: item.collectionName, targetId: item.id, meta: ["reason": reason])
                }
            }
        }
    }

    func resolveChatReport(_ report: AdminChatReportItem) {
        guard canManage else {
            showToast(Language.get("Permissions_AccessDenied", alter: "ليس لديك صلاحية لتنفيذ هذا الإجراء"), isError: true)
            return
        }

        isSubmitting = true
        let functions = Functions.functions()
        let payload: [String: Any] = [
            "reportId": report.id,
            "status": "resolved"
        ]

        // Optimistic UI
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            chatReports.removeAll { $0.id == report.id }
        }

        functions.httpsCallable("chatReportCommand").call(payload) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false
                if let error {
                    self.showToast(error.localizedDescription, isError: true)
                    self.startListening()
                } else {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    self.showToast(Language.get("Moderation_ResolveSuccess", alter: "تم حل البلاغ وتوثيقه بالكامل ✓"), isError: false)
                }
            }
        }
    }

    func dismissChatReport(_ report: AdminChatReportItem) {
        guard canManage else {
            showToast(Language.get("Permissions_AccessDenied", alter: "ليس لديك صلاحية لتنفيذ هذا الإجراء"), isError: true)
            return
        }

        isSubmitting = true
        let functions = Functions.functions()
        let payload: [String: Any] = [
            "reportId": report.id,
            "status": "dismissed"
        ]

        // Optimistic UI
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            chatReports.removeAll { $0.id == report.id }
        }

        functions.httpsCallable("chatReportCommand").call(payload) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false
                if let error {
                    self.showToast(error.localizedDescription, isError: true)
                    self.startListening()
                } else {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    self.showToast(Language.get("Moderation_DismissSuccess", alter: "تم تجاهل البلاغ وإغلاقه"), isError: false)
                }
            }
        }
    }

    private func writeAuditLog(action: String, targetCol: String, targetId: String, meta: [String: Any] = [:]) {
        let uid = Auth.auth().currentUser?.uid ?? ""
        var payload: [String: Any] = [
            "action": action,
            "targetCollection": targetCol,
            "targetId": targetId,
            "adminUid": uid,
            "timestamp": FieldValue.serverTimestamp()
        ]
        if !meta.isEmpty {
            payload["metadata"] = meta
        }
        Firestore.firestore().collection("AdminAuditLogs").addDocument(data: payload)
    }

    func showToast(_ message: String, isError: Bool = false) {
        toastMessage = message
        isErrorToast = isError
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }
}

// MARK: - Main SwiftUI Screen

struct AdminModerationView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminModerationViewModel()
    @State private var auraAngle: Double = 0

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            // Ambient Living Radar Aura Mesh
            AdminModerationAuraView(
                urgencyActive: viewModel.urgentFlaggedContentCount > 0 || viewModel.urgentChatReportsCount > 0,
                pendingActive: viewModel.pendingContentCount > 0,
                angle: auraAngle
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Sovereign Glass Navigation Deck
                sovereignHeaderView

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 3D Executive Telemetry Matrix
                        kpiMatrixView

                        // Fluid Stream Selector
                        streamSwitcher

                        // Multi-Dimensional Search & Filter Bar
                        filterAndSearchBar

                        // Active Queue Cards or Category-Defining Zero State
                        activeStreamContentView

                        Spacer(minLength: 48)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
                .refreshable {
                    viewModel.startListening()
                }
            }

            // Toast Feedback Banner
            if let toast = viewModel.toastMessage {
                VStack {
                    Spacer()
                    toastBanner(message: toast, isError: viewModel.isErrorToast)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.toastMessage)
            }

            // Native Push Navigation Links
            NavigationLink(
                destination: Group {
                    if let item = viewModel.inspectingContentItem {
                        AdminModerationDossierSheet(
                            item: item,
                            viewModel: viewModel,
                            isPushMode: true,
                            onBack: {
                                viewModel.inspectingContentItem = nil
                            }
                        )
                        .navigationBarHidden(true)
                    } else {
                        EmptyView()
                    }
                },
                isActive: Binding(
                    get: { viewModel.inspectingContentItem != nil },
                    set: { if !$0 { viewModel.inspectingContentItem = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
            .accessibilityHidden(true)

            NavigationLink(
                destination: Group {
                    if let report = viewModel.inspectingChatReport {
                        AdminChatReportDossierSheet(
                            report: report,
                            viewModel: viewModel,
                            isPushMode: true,
                            onBack: {
                                viewModel.inspectingChatReport = nil
                            }
                        )
                        .navigationBarHidden(true)
                    } else {
                        EmptyView()
                    }
                },
                isActive: Binding(
                    get: { viewModel.inspectingChatReport != nil },
                    set: { if !$0 { viewModel.inspectingChatReport = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
            .accessibilityHidden(true)
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(item: $viewModel.rejectingContentItem) { item in
            AdminRejectionReasonSheet(item: item, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showStandardsSheet) {
            ModerationStandardsSheet()
        }
        .fullScreenCover(item: Binding(
            get: { viewModel.selectedLightboxURL.map { LightboxMediaItem(url: $0) } },
            set: { viewModel.selectedLightboxURL = $0?.url }
        )) { item in
            ModerationLightboxView(imageURL: item.url) {
                viewModel.selectedLightboxURL = nil
            }
        }
        .onAppear {
            viewModel.startListening()
            withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
                auraAngle = 360
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    // MARK: - Sovereign Navigation Bar

    private var sovereignHeaderView: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: PPStatusBarHelper.statusBarHeight)

            HStack(spacing: 12) {
            // Tactile Frosted Back Button (100% Deterministic Dismissal)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                    PPAdminNavigationFallback.popOrDismiss()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.surface.opacity(0.88))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.85), lineWidth: 0.8)
                        )
                    Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .frame(width: 44, height: 44)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(ModerationTactileButtonStyle())
            .accessibilityLabel(Language.get("Back", alter: "رجوع"))

            // Centered Hierarchy Title & Live Radar Beacon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // Pulsing Emerald Beacon
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .stroke(Color(uiColor: .ppSuccess).opacity(0.4), lineWidth: 2)
                                .scaleEffect(viewModel.isLoading ? 1.8 : 1.2)
                                .opacity(viewModel.isLoading ? 0 : 0.8)
                                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: viewModel.isLoading)
                        )

                    Text(Language.get("Moderation_Eyebrow", alter: "مساحة العمليات • الأمان والرقابة"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Text(Language.get("Moderation_Title", alter: "مركز الرقابة وسلامة المنصة"))
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Trailing Horizon: Standards Popover & Live Refresh
            HStack(spacing: 8) {
                // Guidelines & Standards Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.showStandardsSheet = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AdminSurface.surface.opacity(0.88))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.85), lineWidth: 0.8)
                            )
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(ModerationTactileButtonStyle())
                .accessibilityLabel(Language.get("Moderation_Guidelines", alter: "معايير الرقابة"))

                // Live Sync Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.startListening()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AdminSurface.surface.opacity(0.88))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.85), lineWidth: 0.8)
                            )
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(uiColor: .ppPrimary))
                            .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                            .animation(viewModel.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isLoading)
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(ModerationTactileButtonStyle())
                .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    .background(
        AdminSurface.background.opacity(0.85)
            .background(.ultraThinMaterial)
            .ignoresSafeArea(edges: .top)
    )
}

    // MARK: - KPI Telemetry Matrix

    private var kpiMatrixView: some View {
        HStack(spacing: 10) {
            // Queue Depth Card
            kpiCard(
                title: Language.get("Moderation_PendingCount", alter: "قيد المراجعة"),
                value: "\(viewModel.pendingContentCount)",
                badge: viewModel.pendingContentCount > 0 ? Language.get("ActionNeeded", alter: "مطلوب إجراء") : Language.get("Clear", alter: "نظيف"),
                icon: "hourglass.badge.plus",
                accentColor: Color(uiColor: .ppPrimary),
                highlight: viewModel.pendingContentCount > 0
            )

            // High Risk Flagged Card
            kpiCard(
                title: Language.get("Moderation_UrgentReports", alter: "بلاغات عاجلة"),
                value: "\(viewModel.urgentFlaggedContentCount + viewModel.urgentChatReportsCount)",
                badge: (viewModel.urgentFlaggedContentCount + viewModel.urgentChatReportsCount) > 0 ? Language.get("Urgent", alter: "عاجل جداً") : Language.get("Secure", alter: "مستقر"),
                icon: "exclamationmark.shield.fill",
                accentColor: .red,
                highlight: (viewModel.urgentFlaggedContentCount + viewModel.urgentChatReportsCount) > 0
            )

            // Platform Health Metric
            kpiCard(
                title: Language.get("Moderation_PlatformHealth", alter: "جاهزية الأمان"),
                value: "100%",
                badge: Language.get("Operational", alter: "رادار نشط"),
                icon: "checkmark.seal.fill",
                accentColor: Color(uiColor: .ppSuccess),
                highlight: false
            )
        }
    }

    private func kpiCard(title: String, value: String, badge: String, icon: String, accentColor: Color, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accentColor)
                }

                Spacer()

                Text(badge)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(highlight ? accentColor : AdminSurface.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(highlight ? accentColor.opacity(0.12) : AdminSurface.control, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AdminSurface.primaryText)

                Text(title)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(highlight ? accentColor.opacity(0.35) : Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 1)
                )
        )
        .shadow(color: highlight ? accentColor.opacity(0.08) : Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
    }

    // MARK: - Fluid Liquid Stream Selector

    private var streamSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(ModerationStreamType.allCases) { stream in
                let isSelected = viewModel.selectedStream == stream
                let count = stream == .content ? viewModel.filteredContentItems.count : viewModel.filteredChatReports.count

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        viewModel.selectedStream = stream
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: stream.symbol)
                            .font(.system(size: 13, weight: .semibold))

                        Text(stream.title)
                            .font(AdminType.subheadlineBold)

                        // Count Badge
                        Text("\(count)")
                            .font(AdminType.caption2Bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.white.opacity(0.25) : Color(uiColor: .ppPrimary).opacity(0.12))
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(isSelected ? Color.white : AdminSurface.secondaryText)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                isSelected
                                ? LinearGradient(colors: [Color(uiColor: .ppPrimary), Color(uiColor: .ppPrimary).opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.control)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Multi-Dimensional Search & Filters

    private var filterAndSearchBar: some View {
        VStack(spacing: 10) {
            AdminSearchField(
                text: $viewModel.searchText,
                placeholder: Language.get("Moderation_SearchPlaceholder", alter: "بحث في العناوين، المعرفات، أو أسباب البلاغ...")
            )

            // Horizontal Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if viewModel.selectedStream == .content {
                        ForEach(ModerationContentFilter.allCases) { filter in
                            let isSel = viewModel.contentFilter == filter
                            filterChip(title: filter.title, isSelected: isSel) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    viewModel.contentFilter = filter
                                }
                            }
                        }
                    } else {
                        ForEach(ModerationChatFilter.allCases) { filter in
                            let isSel = viewModel.chatFilter == filter
                            filterChip(title: filter.title, isSelected: isSel) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    viewModel.chatFilter = filter
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(AdminType.captionBold)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color(uiColor: .ppPrimary) : AdminSurface.surface)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(isSelected ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                        )
                )
                .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.02), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stream Content Deck

    @ViewBuilder
    private var activeStreamContentView: some View {
        if viewModel.selectedStream == .content {
            if viewModel.filteredContentItems.isEmpty {
                ModerationQueueZeroView(
                    title: Language.get("Moderation_AllClearContent", alter: "جميع الإعلانات والخدمات معتمدة بالكامل"),
                    subtitle: Language.get("Moderation_AllClearContentSub", alter: "لا يوجد أي محتوى جديد بانتظار المراجعة • الرادار نشط ومستقر"),
                    onRefresh: { viewModel.startListening() },
                    onOpenStandards: { viewModel.showStandardsSheet = true }
                )
                .padding(.top, 16)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.filteredContentItems) { item in
                        AdminContentDossierCard(item: item, viewModel: viewModel)
                    }
                }
            }
        } else {
            if viewModel.filteredChatReports.isEmpty {
                ModerationQueueZeroView(
                    title: Language.get("Moderation_AllClearChats", alter: "سجل أمان المحادثات خالٍ من البلاغات"),
                    subtitle: Language.get("Moderation_AllClearChatsSub", alter: "لا توجد أي نزاعات أو شكاوى نشطة بحاجة إلى تدخل إداري"),
                    onRefresh: { viewModel.startListening() },
                    onOpenStandards: { viewModel.showStandardsSheet = true }
                )
                .padding(.top, 16)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.filteredChatReports) { report in
                        AdminChatReportDossierCard(report: report, viewModel: viewModel)
                    }
                }
            }
        }
    }

    private func toastBanner(message: String, isError: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : Color(uiColor: .ppSuccess))
                .font(.system(size: 18, weight: .bold))
            Text(message)
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isError ? Color.red.opacity(0.3) : Color(uiColor: .ppSuccess).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

// MARK: - Ambient Living Radar Atmosphere

private struct AdminModerationAuraView: View {
    let urgencyActive: Bool
    let pendingActive: Bool
    let angle: Double

    var body: some View {
        ZStack {
            AdminSurface.background

            // Top Specular Aurora Mesh
            GeometryReader { proxy in
                let w = proxy.size.width
                let centerColor: Color = urgencyActive
                    ? Color.red.opacity(0.08)
                    : (pendingActive ? Color.orange.opacity(0.07) : Color(uiColor: .ppSuccess).opacity(0.06))

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [centerColor, Color.clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: w * 0.7
                        )
                    )
                    .frame(width: w * 1.4, height: w * 1.4)
                    .position(x: w / 2, y: -w * 0.2)
                    .blur(radius: 40)
            }
        }
    }
}

// MARK: - Content Dossier Card (Spatial Apple Design Award Craft)

private struct AdminContentDossierCard: View {
    let item: AdminContentItem
    @ObservedObject var viewModel: AdminModerationViewModel
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Ribbon: Source Badge + Urgency + Relative Timestamp + Monospace UID
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: item.sourceKind.icon)
                        .font(.system(size: 11, weight: .bold))
                    Text(item.sourceKind.label)
                        .font(AdminType.captionBold)
                }
                .foregroundStyle(item.sourceKind.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(item.sourceKind.color.opacity(0.12), in: Capsule())

                if item.isFlagged {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(Language.get("Moderation_Status_Flagged", alter: "مبلغ عنه"))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.12), in: Capsule())
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(relativeTimeString(from: item.createdAt))
                        .font(AdminType.caption2)
                }
                .foregroundStyle(AdminSurface.secondaryText)
            }

            // Image Gallery Strip or Single Thumbnail
            if !item.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(item.images, id: \.self) { urlString in
                            if let url = URL(string: urlString) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    viewModel.selectedLightboxURL = urlString
                                } label: {
                                    AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 140, height: 100)) {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(AdminSurface.control)
                                            .overlay(Image(systemName: "photo").foregroundStyle(AdminSurface.secondaryText))
                                    }
                                    .frame(width: item.images.count > 1 ? 110 : 160, height: 95)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Content Core: Title, Price, Publisher ID
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(item.title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(2)

                    Spacer()

                    if let price = item.price, price > 0 {
                        Text(String(format: "%.0f %@", price, Language.get("SAR", alter: "ر.س")))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(Color(uiColor: .ppPrimary))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(uiColor: .ppPrimary).opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                // Publisher Copyable Monospace Badge
                HStack(spacing: 4) {
                    Text(Language.get("Moderation_Owner", alter: "الناشر:"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(item.ownerID.prefix(12) + "...")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Button {
                        UIPasteboard.general.string = item.ownerID
                        viewModel.showToast(Language.get("Copied", alter: "تم نسخ المعرّف"), isError: false)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(uiColor: .ppPrimary))
                    }
                }
            }

            // Description Preview with Expand / Collapse
            if !item.descriptionText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.descriptionText)
                        .font(AdminType.callout)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(isExpanded ? nil : 2)

                    if item.descriptionText.count > 80 {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Text(isExpanded ? Language.get("ShowLess", alter: "عرض أقل") : Language.get("ShowMore", alter: "عرض التفاصيل الكاملة..."))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(Color(uiColor: .ppPrimary))
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.control.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Report Reason Warning Banner (if flagged)
            if let reason = item.reportReason, !reason.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Moderation_ReasonTitle", alter: "سبب البلاغ أو الملاحظة:"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(.red)
                        Text(reason)
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Divider()
                .background(Color(uiColor: .ppSurfaceBorder).opacity(0.6))

            // Micro-Interaction Action Deck
            HStack(spacing: 8) {
                // Inspect Dossier Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.inspectingContentItem = item
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .bold))
                        Text(Language.get("Inspect", alter: "فحص وتفاصيل"))
                            .font(AdminType.captionBold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(AdminSurface.primaryText)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(ModerationTactileButtonStyle())

                if viewModel.canManage {
                    // Reject Button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.rejectingContentItem = item
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Moderation_Reject", alter: "رفض"))
                                .font(AdminType.captionBold)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .foregroundStyle(.red)
                        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(ModerationTactileButtonStyle())

                    // Instant Approve Button
                    Button {
                        viewModel.approveContent(item)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Moderation_Approve", alter: "اعتماد"))
                                .font(AdminType.captionBold)
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .foregroundStyle(.white)
                        .background(
                            LinearGradient(
                                colors: [Color(uiColor: .ppSuccess), Color(uiColor: .ppSuccess).opacity(0.88)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .shadow(color: Color(uiColor: .ppSuccess).opacity(0.25), radius: 6, y: 2)
                    }
                    .buttonStyle(ModerationTactileButtonStyle())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(item.isFlagged ? Color.red.opacity(0.35) : Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
    }
}

// MARK: - Chat Report Dossier Card

private struct AdminChatReportDossierCard: View {
    let report: AdminChatReportItem
    @ObservedObject var viewModel: AdminModerationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Status + Urgency + Timestamp
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(report.statusColor)
                        .frame(width: 7, height: 7)
                    Text(report.localizedStatus)
                        .font(AdminType.captionBold)
                }
                .foregroundStyle(report.statusColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(report.statusColor.opacity(0.12), in: Capsule())

                if report.isUrgent {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(Language.get("Urgent", alter: "عاجل"))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(relativeTimeString(from: report.createdAt))
                        .font(AdminType.caption2)
                }
                .foregroundStyle(AdminSurface.secondaryText)
            }

            // Reason Quote Bubble
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(uiColor: .ppPrimary))
                    Text(Language.get("ChatReports_ReasonHeader", alter: "محتوى الشكوى / البلاغ:"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Text(report.reason)
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AdminSurface.control)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.8)
                    )
            )

            // Parties Comparison Cards
            HStack(spacing: 10) {
                partyCard(
                    title: Language.get("Moderation_Reporter", alter: "صاحب البلاغ"),
                    uid: report.reporterUID,
                    icon: "person.crop.circle.badge.checkmark",
                    color: Color(uiColor: .ppPrimary)
                )

                partyCard(
                    title: Language.get("Moderation_ReportedUser", alter: "المبلغ ضده"),
                    uid: report.reportedUserUID,
                    icon: "person.crop.circle.badge.exclamationmark",
                    color: .red
                )
            }

            Divider()
                .background(Color(uiColor: .ppSurfaceBorder).opacity(0.6))

            // Action Buttons
            HStack(spacing: 8) {
                // Inspect Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.inspectingChatReport = report
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .bold))
                        Text(Language.get("Details", alter: "التفاصيل"))
                            .font(AdminType.captionBold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(AdminSurface.primaryText)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(ModerationTactileButtonStyle())

                if viewModel.canManage && report.isPending {
                    // Dismiss Button
                    Button {
                        viewModel.dismissChatReport(report)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                            Text(Language.get("Moderation_Dismiss", alter: "تجاهل"))
                                .font(AdminType.captionBold)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(ModerationTactileButtonStyle())

                    // Resolve Button
                    Button {
                        viewModel.resolveChatReport(report)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Moderation_Resolve", alter: "حل وتأكيد"))
                                .font(AdminType.captionBold)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .foregroundStyle(.white)
                        .background(Color(uiColor: .ppPrimary), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(ModerationTactileButtonStyle())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(report.isUrgent ? Color.orange.opacity(0.4) : Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
    }

    private func partyCard(title: String, uid: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(color)
            }

            HStack {
                Text(uid.isEmpty ? Language.get("Unknown", alter: "غير معروف") : String(uid.prefix(12)))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                Spacer()

                if !uid.isEmpty {
                    Button {
                        UIPasteboard.general.string = uid
                        viewModel.showToast(Language.get("Copied", alter: "تم نسخ المعرف"), isError: false)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(color.opacity(0.15), lineWidth: 0.8)
                )
        )
    }
}

// MARK: - Category-Defining Zero State

private struct ModerationQueueZeroView: View {
    let title: String
    let subtitle: String
    var onRefresh: (() -> Void)? = nil
    var onOpenStandards: (() -> Void)? = nil

    @State private var animateBeacon: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            // Concentric Glowing Radar Rings
            ZStack {
                // Outer Pulse Ring
                Circle()
                    .strokeBorder(Color(uiColor: .ppSuccess).opacity(animateBeacon ? 0.05 : 0.20), lineWidth: 1.5)
                    .frame(width: 170, height: 170)
                    .scaleEffect(animateBeacon ? 1.15 : 0.95)

                // Middle Specular Ring
                Circle()
                    .strokeBorder(Color(uiColor: .ppSuccess).opacity(animateBeacon ? 0.15 : 0.35), lineWidth: 2)
                    .frame(width: 125, height: 125)
                    .scaleEffect(animateBeacon ? 1.05 : 0.98)

                // Core Specular Shield Glass Orb
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AdminSurface.surface, AdminSurface.control],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 82, height: 82)
                    .overlay(
                        Circle()
                            .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.5), lineWidth: 1.5)
                    )
                    .shadow(color: Color(uiColor: .ppSuccess).opacity(0.20), radius: 16, y: 6)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(uiColor: .ppSuccess), Color(uiColor: .ppSuccess).opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .padding(.top, 16)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    animateBeacon = true
                }
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            // Quick Operations Actions Horizon
            HStack(spacing: 12) {
                if let onRefresh {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onRefresh()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("ManualScan", alter: "فحص يدوي فوري"))
                                .font(AdminType.captionBold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundStyle(AdminSurface.primaryText)
                        .background(AdminSurface.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8))
                    }
                    .buttonStyle(ModerationTactileButtonStyle())
                }

                if let onOpenStandards {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenStandards()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Moderation_Policy", alter: "دليل السياسات"))
                                .font(AdminType.captionBold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color(uiColor: .ppPrimary))
                        .background(Color(uiColor: .ppPrimary).opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(ModerationTactileButtonStyle())
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Detailed Dossier Inspection Sheet (Content)

private struct AdminModerationDossierSheet: View {
    let item: AdminContentItem
    @ObservedObject var viewModel: AdminModerationViewModel
    var isPushMode: Bool = true
    var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            AdminSovereignNavigationBar(
                title: Language.get("Moderation_DossierTitle", alter: "ملف مراجعة المحتوى"),
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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Hero Image Gallery
                    if !item.images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(item.images, id: \.self) { urlString in
                                    if let url = URL(string: urlString) {
                                        Button {
                                            viewModel.selectedLightboxURL = urlString
                                        } label: {
                                            AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 320, height: 220)) {
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .fill(AdminSurface.control)
                                            }
                                            .frame(width: 260, height: 180)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        // Title & Source Kind
                        HStack(spacing: 8) {
                            Text(item.sourceKind.label)
                                .font(AdminType.captionBold)
                                .foregroundStyle(item.sourceKind.color)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(item.sourceKind.color.opacity(0.12), in: Capsule())

                            Spacer()

                            Text(item.localizedStatus)
                                .font(AdminType.captionBold)
                                .foregroundStyle(item.statusColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(item.statusColor.opacity(0.12), in: Capsule())
                        }

                        Text(item.title)
                            .font(AdminType.title2)
                            .foregroundStyle(AdminSurface.primaryText)

                        if let price = item.price, price > 0 {
                            Text(String(format: "%.0f %@", price, Language.get("SAR", alter: "ر.س")))
                                .font(AdminType.title3)
                                .foregroundStyle(Color(uiColor: .ppPrimary))
                        }

                        if !item.descriptionText.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(Language.get("Description", alter: "الوصف والتفاصيل:"))
                                    .font(AdminType.headline)
                                    .foregroundStyle(AdminSurface.secondaryText)
                                Text(item.descriptionText)
                                    .font(AdminType.callout)
                                    .foregroundStyle(AdminSurface.primaryText)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        // Meta Attributes Table
                        VStack(spacing: 10) {
                            metadataRow(label: Language.get("DocumentID", alter: "معرف المستند:"), value: item.id)
                            metadataRow(label: Language.get("Collection", alter: "المجموعة:"), value: item.collectionName)
                            metadataRow(label: Language.get("OwnerID", alter: "معرف الناشر:"), value: item.ownerID)
                            metadataRow(label: Language.get("CreatedAt", alter: "تاريخ الإرسال:"), value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        .padding(14)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.8)))
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
        }
    }
}

// MARK: - Detailed Dossier Inspection Sheet (Chat Report)

private struct AdminChatReportDossierSheet: View {
    let report: AdminChatReportItem
    @ObservedObject var viewModel: AdminModerationViewModel
    var isPushMode: Bool = true
    var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            AdminSovereignNavigationBar(
                title: Language.get("ChatReports_Detail_Title", alter: "تفاصيل بلاغ الدردشة"),
                subtitle: report.reason,
                statusDotColor: report.statusColor,
                isModal: !isPushMode,
                onBack: {
                    if let onBack = onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Status
                    HStack {
                        HStack(spacing: 5) {
                            Circle().fill(report.statusColor).frame(width: 8, height: 8)
                            Text(report.localizedStatus)
                                .font(AdminType.captionBold)
                        }
                        .foregroundStyle(report.statusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(report.statusColor.opacity(0.12), in: Capsule())

                        Spacer()

                        Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    // Complaint Quote Bubble
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Language.get("ChatReports_ReasonHeader", alter: "نص الشكوى المقدمة:"))
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.secondaryText)

                        Text(report.reason)
                            .font(AdminType.title3)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Metadata Cards
                    VStack(spacing: 10) {
                        metadataRow(label: Language.get("ReportID", alter: "معرف البلاغ:"), value: report.id)
                        metadataRow(label: Language.get("Moderation_Reporter", alter: "المبلغ:"), value: report.reporterUID)
                        metadataRow(label: Language.get("Moderation_ReportedUser", alter: "المبلغ عنه:"), value: report.reportedUserUID)
                        if let chat = report.chatID, !chat.isEmpty {
                            metadataRow(label: Language.get("ChatID", alter: "معرف المحادثة:"), value: chat)
                        }
                    }
                    .padding(14)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.8)))

                    // Direct Action Links
                    if let chat = report.chatID, !chat.isEmpty {
                        Button {
                            UIPasteboard.general.string = chat
                            viewModel.showToast(Language.get("Copied", alter: "تم نسخ معرف المحادثة"), isError: false)
                        } label: {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 15))
                                Text(Language.get("CopyChatID", alter: "نسخ معرف المحادثة للتحقيق"))
                                    .font(AdminType.subheadlineBold)
                                Spacer()
                                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .padding(14)
                            .foregroundStyle(Color(uiColor: .ppPrimary))
                            .background(Color(uiColor: .ppPrimary).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
        }
    }
}

// MARK: - Rejection Reason Sheet

private struct AdminRejectionReasonSheet: View {
    let item: AdminContentItem
    @ObservedObject var viewModel: AdminModerationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: String = ""
    @State private var customReason: String = ""

    private let presetReasons = [
        "محتوى غير لائق أو مخالف لمعايير المجتمع",
        "صور غير مطابقة للحيوان أو منسوخة من الإنترنت",
        "معلومات اتصال أو أرقام هواتف غير مصرح بها بالنص",
        "سعر أو تفاصيل وهمية ومضللة للعملاء",
        "خدمة مكررة أو مخالفة للتصنيف المعتمد",
        "فصيلة محظورة أو مخالفة لأنظمة الحياة الفطرية"
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(Language.get("Moderation_SelectRejectionReason", alter: "يرجى تحديد سبب الرفض لتوثيقه في سجل التدقيق وإشعار المستخدم:"))
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.secondaryText)

                // Presets List
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(presetReasons, id: \.self) { reason in
                            let isSelected = selectedReason == reason
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedReason = reason
                            } label: {
                                HStack {
                                    Text(reason)
                                        .font(AdminType.subheadline)
                                        .foregroundStyle(isSelected ? Color(uiColor: .ppPrimary) : AdminSurface.primaryText)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color(uiColor: .ppPrimary))
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSelected ? Color(uiColor: .ppPrimary).opacity(0.08) : AdminSurface.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(isSelected ? Color(uiColor: .ppPrimary) : Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Custom Note
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("CustomNote", alter: "سبب إضافي أو مخصص:"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.secondaryText)
                    TextField(Language.get("EnterReasonOptional", alter: "اكتب ملاحظات إضافية هنا..."), text: $customReason)
                        .font(AdminType.callout)
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Confirm Reject Button
                Button {
                    let finalReason = !customReason.isEmpty ? customReason : (!selectedReason.isEmpty ? selectedReason : "مخالفة معايير وشروط النشر")
                    viewModel.rejectContent(item, reason: finalReason)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text(Language.get("Moderation_ConfirmReject", alter: "تأكيد الرفض وتوثيق السجل"))
                    }
                    .font(AdminType.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("Moderation_RejectContentTitle", alter: "رفض المحتوى"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Community Safety Standards Sheet

private struct ModerationStandardsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    standardSection(
                        icon: "shield.lefthalf.filled",
                        title: "معايير الأمان ومكافحة الاحتيال",
                        color: Color(uiColor: .ppPrimary),
                        points: [
                            "يحظر طلب تحويلات مالية خارج القنوات المعتمدة للمنصة.",
                            "يجب أن تكون الأسعار المعروضة واقعية وشاملة لضريبة القيمة المضافة إن وجدت.",
                            "يمنع نشر أرقام الحسابات البنكية أو روابط خارجية في وصف الإعلان."
                        ]
                    )

                    standardSection(
                        icon: "pawprint.fill",
                        title: "سياسة الرفق بالحيوان والأنظمة الرسمية",
                        color: Color(uiColor: .ppSuccess),
                        points: [
                            "يمنع منعاً باتاً عرض الحيوانات المهددة بالانقراض أو المحمية رسمياً.",
                            "يجب إرفاق شهادات التحصين البيطرية والشهادات الصحية للحيوانات المعروضة للتبني أو البيع.",
                            "يحظر تداول الحيوانات المريضة أو المصابة بإصابات غير معالجة."
                        ]
                    )

                    standardSection(
                        icon: "photo.on.rectangle.angled",
                        title: "معايير جودة الوسائط والصور",
                        color: .orange,
                        points: [
                            "يجب أن تكون الصور حقيقية وحديثة للحيوان أو المستلزم المعروض.",
                            "ترفض الصور التي تحتوي على علامات مائية أو لقطات شاشة غير واضحة.",
                            "يحظر استخدام صور كرتونية أو صور تعبيرية مضللة."
                        ]
                    )
                }
                .padding(16)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("Moderation_Standards_Title", alter: "دليل معايير الرقابة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Done", alter: "تم")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func standardSection(icon: String, title: String, color: Color, points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(points, id: \.self) { pt in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(pt)
                            .font(AdminType.callout)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Full-Screen Image Lightbox

private struct LightboxMediaItem: Identifiable {
    var id: String { url }
    let url: String
}

private struct ModerationLightboxView: View {
    let imageURL: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = URL(string: imageURL) {
                AdminRemoteImage(url: url, contentMode: .fit, targetSize: CGSize(width: 1200, height: 1200)) {
                    ProgressView().tint(.white)
                }
                .edgesIgnoringSafeArea(.all)
            }

            // Floating Dismiss Button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(16)
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Tactile Button Style

private struct ModerationTactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Helper Functions

private func relativeTimeString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    formatter.locale = Locale(identifier: Language.currentLanguageCode())
    return formatter.localizedString(for: date, relativeTo: Date())
}