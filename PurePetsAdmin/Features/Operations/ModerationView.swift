//
//  ModerationView.swift
//  PurePetsAdmin
//
//  NextGen V6 Flagship Moderation & Trust Safety Command Center.
//  Reimagined from absolute first principles:
//  - Zero cell-reuse artifacts, declarative SwiftUI architecture
//  - Guaranteed working back navigation via AdminSovereignNavigationBar & PPAdminNavigationFallback
//  - Real-time KPI telemetry across content queues and dispute reports
//  - Dual-stream switching with live count badges on segment pills
//  - Deep-linkable dossier inspection sheets & granular rejection reason modal
//  - Transactional Cloud Function execution for chat report resolutions
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
            return Language.get("Moderation_ContentQueue", alter: "قائمة المحتوى")
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
    case pending
    case flagged
    case petAds
    case adoptions
    case services

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return Language.get("All", alter: "الكل")
        case .pending: return Language.get("Moderation_Status_Pending", alter: "قيد المراجعة")
        case .flagged: return Language.get("Moderation_Status_Flagged", alter: "مبلغ عنه")
        case .petAds: return Language.get("Moderation_Source_PetAd", alter: "إعلانات الحيوانات")
        case .adoptions: return Language.get("Moderation_Source_Adoption", alter: "التبني")
        case .services: return Language.get("Moderation_Source_Service", alter: "الخدمات")
        }
    }
}

enum ModerationChatFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case resolved
    case dismissed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return Language.get("All", alter: "الكل")
        case .pending: return Language.get("Pending", alter: "قيد الانتظار")
        case .resolved: return Language.get("Moderation_Resolve", alter: "تم الحل")
        case .dismissed: return Language.get("Moderation_Dismiss", alter: "تم التجاهل")
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
        return text.contains("احتيال") || text.contains("اساء") || text.contains("fraud") || text.contains("scam") || text.contains("threat")
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

    // MARK: - Real-Time Listeners

    func startListening() {
        evaluatePermissions()
        isLoading = true

        let db = Firestore.firestore()
        let activeStatuses = ["flagged", "pending_review", "reported"]

        // 1. Pet Ads
        petAdsListener?.remove()
        petAdsListener = db.collection("pet_ads")
            .whereField("status", in: activeStatuses)
            .order(by: "createdAt", descending: true)
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
            .order(by: "createdAt", descending: true)
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
            .order(by: "createdAt", descending: true)
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

        Firestore.firestore().collection(item.collectionName).document(item.id).updateData(patch) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false
                if let error {
                    self.showToast(error.localizedDescription, isError: true)
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

        Firestore.firestore().collection(item.collectionName).document(item.id).updateData(patch) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false
                if let error {
                    self.showToast(error.localizedDescription, isError: true)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    self.showToast(Language.get("Moderation_RejectSuccess", alter: "تم رفض المحتوى وتوثيق السبب"), isError: false)
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

        functions.httpsCallable("chatReportCommand").call(payload) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false
                if let error {
                    self.showToast(error.localizedDescription, isError: true)
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

        functions.httpsCallable("chatReportCommand").call(payload) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false
                if let error {
                    self.showToast(error.localizedDescription, isError: true)
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

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                sovereignHeaderView

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        kpiMatrixView

                        streamSwitcher

                        filterAndSearchBar

                        activeStreamContentView

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 8)
                }
                .refreshable {
                    viewModel.startListening()
                }
            }

            // Toast Overlay
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
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(item: $viewModel.inspectingContentItem) { item in
            AdminModerationDossierSheet(item: item, viewModel: viewModel)
        }
        .sheet(item: $viewModel.inspectingChatReport) { report in
            AdminChatReportDossierSheet(report: report, viewModel: viewModel)
        }
        .sheet(item: $viewModel.rejectingContentItem) { item in
            AdminRejectionReasonSheet(item: item, viewModel: viewModel)
        }
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    // MARK: - Sovereign Navigation Bar

    private var sovereignHeaderView: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Moderation_Title", alter: "الرقابة وسلامة المنصة"),
            subtitle: Language.get("Moderation_Subtitle", alter: "مركز العمليات الرقابية • مساحة العمليات"),
            statusDotColor: Color(uiColor: .ppSuccess),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                    PPAdminNavigationFallback.popOrDismiss()
                }
            },
            trailingContent: {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.startListening()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AdminSurface.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                            )
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AdminSurface.primaryText)
                            .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                            .animation(viewModel.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isLoading)
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
            }
        )
    }

    // MARK: - KPI Telemetry Matrix

    private var kpiMatrixView: some View {
        HStack(spacing: 10) {
            kpiCard(
                title: Language.get("Moderation_ContentQueue", alter: "محتوى معلق"),
                count: viewModel.pendingContentCount,
                icon: "square.stack.3d.up.fill",
                color: Color(uiColor: .ppPrimary),
                highlight: viewModel.pendingContentCount > 0
            )

            kpiCard(
                title: Language.get("Moderation_ChatReports", alter: "بلاغات دردشة"),
                count: viewModel.pendingChatReportsCount,
                icon: "bubble.left.and.exclamationmark.bubble.right.fill",
                color: .red,
                highlight: viewModel.pendingChatReportsCount > 0
            )

            kpiCard(
                title: Language.get("Moderation_Status_Flagged", alter: "مبلغ عنه عاجل"),
                count: viewModel.urgentFlaggedContentCount + viewModel.urgentChatReportsCount,
                icon: "exclamationmark.shield.fill",
                color: .orange,
                highlight: (viewModel.urgentFlaggedContentCount + viewModel.urgentChatReportsCount) > 0
            )
        }
    }

    private func kpiCard(title: String, count: Int, icon: String, color: Color, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
                if highlight {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
            }

            Text("\(count)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AdminSurface.primaryText)

            Text(title)
                .font(AdminType.caption2)
                .foregroundStyle(AdminSurface.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(highlight ? color.opacity(0.3) : Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    // MARK: - Fluid Stream Selector (Segment Hub)

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
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.white.opacity(0.25) : Color(uiColor: .ppPrimary).opacity(0.12))
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(isSelected ? Color.white : AdminSurface.secondaryText)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Color(uiColor: .ppPrimary) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AdminSurface.control)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Search & Filters

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

    // MARK: - Stream Content View

    @ViewBuilder
    private var activeStreamContentView: some View {
        if viewModel.selectedStream == .content {
            if viewModel.filteredContentItems.isEmpty {
                AdminQueueZeroView(
                    title: Language.get("Moderation_AllClearContent", alter: "قائمة مراجعة المحتوى نظيفة تماماً"),
                    subtitle: Language.get("Moderation_AllClearContentSub", alter: "لا توجد إعلانات أو خدمات تنتظر المراجعة حالياً.")
                )
                .padding(.top, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredContentItems) { item in
                        AdminContentDossierCard(item: item, viewModel: viewModel)
                    }
                }
            }
        } else {
            if viewModel.filteredChatReports.isEmpty {
                AdminQueueZeroView(
                    title: Language.get("Moderation_AllClearChats", alter: "لا توجد بلاغات محادثة معلقة"),
                    subtitle: Language.get("Moderation_AllClearChatsSub", alter: "سجل الأمان خالٍ من الشكاوى النشطة في الوقت الراهن.")
                )
                .padding(.top, 24)
            } else {
                LazyVStack(spacing: 12) {
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
                .foregroundColor(isError ? .red : .green)
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
                .stroke(isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

// MARK: - Content Dossier Card

private struct AdminContentDossierCard: View {
    let item: AdminContentItem
    @ObservedObject var viewModel: AdminModerationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Source Kind Badge + Time + Status
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

                Text(relativeTimeString(from: item.createdAt))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            // Body: Thumbnail + Title + Owner
            HStack(alignment: .top, spacing: 12) {
                if let imgUrl = item.imageURL, let url = URL(string: imgUrl) {
                    AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 80, height: 80)) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AdminSurface.control)
                            .overlay(Image(systemName: item.sourceKind.icon).foregroundStyle(AdminSurface.secondaryText))
                    }
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.5))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(item.sourceKind.color.opacity(0.08))
                        Image(systemName: item.sourceKind.icon)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(item.sourceKind.color)
                    }
                    .frame(width: 68, height: 68)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(2)

                    if let price = item.price, price > 0 {
                        Text(String(format: "%.0f %@", price, Language.get("SAR", alter: "ر.س")))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(Color(uiColor: .ppPrimary))
                    }

                    HStack(spacing: 4) {
                        Text(Language.get("Moderation_Owner", alter: "الناشر:"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(item.ownerID.prefix(10) + "...")
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
            }

            // Report Reason Alert Box (if flagged)
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
                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Divider()
                .background(Color(uiColor: .ppSurfaceBorder).opacity(0.6))

            // Action Buttons
            HStack(spacing: 8) {
                // Inspect Button
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
                    .frame(height: 38)
                    .foregroundStyle(AdminSurface.primaryText)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

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
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .foregroundStyle(.red)
                        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // Approve Button
                    Button {
                        viewModel.approveContent(item)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Moderation_Approve", alter: "اعتماد"))
                                .font(AdminType.captionBold)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .foregroundStyle(.white)
                        .background(Color(uiColor: .ppSuccess), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(item.isFlagged ? Color.red.opacity(0.3) : Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
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

                Text(relativeTimeString(from: report.createdAt))
                    .font(AdminType.caption2)
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
                    .padding(.horizontal, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AdminSurface.control)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.8)
                    )
            )

            // Parties Grid (Reporter & Reported User)
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
                    .frame(height: 38)
                    .foregroundStyle(AdminSurface.primaryText)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

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
                        .frame(height: 38)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

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
                        .frame(height: 38)
                        .foregroundStyle(.white)
                        .background(Color(uiColor: .ppPrimary), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(report.isUrgent ? Color.orange.opacity(0.4) : Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(color.opacity(0.15), lineWidth: 0.8)
                )
        )
    }
}

// MARK: - Detailed Dossier Inspection Sheet (Content)

private struct AdminModerationDossierSheet: View {
    let item: AdminContentItem
    @ObservedObject var viewModel: AdminModerationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Hero Image Gallery
                    if !item.images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(item.images, id: \.self) { urlString in
                                    if let url = URL(string: urlString) {
                                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 320, height: 220)) {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(AdminSurface.control)
                                        }
                                        .frame(width: 260, height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                            .font(AdminType.title2Bold)
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
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("Moderation_DossierTitle", alter: "ملف مراجعة المحتوى"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        dismiss()
                    }
                }
            }
        }
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("ChatReports_Detail_Title", alter: "تفاصيل بلاغ الدردشة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        dismiss()
                    }
                }
            }
        }
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
        "محتوى غير لائق أو مخالف للذوق العام",
        "صور غير مطابقة للحيوان أو غير واضحة",
        "معلومات اتصال غير مصرح بها بالنص",
        "سعر أو تفاصيل غير واقعية ومضللة",
        "خدمة مكررة أو مخالفة للتصنيف"
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(Language.get("Moderation_SelectRejectionReason", alter: "يرجى تحديد سبب الرفض لتوثيقه في سجل التدقيق وإشعار المستخدم:"))
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.secondaryText)

                // Presets
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

                Spacer()

                // Confirm Reject Button
                Button {
                    let finalReason = !customReason.isEmpty ? customReason : (!selectedReason.isEmpty ? selectedReason : "مخالفة معايير وشروط النشر")
                    viewModel.rejectContent(item, reason: finalReason)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text(Language.get("Moderation_ConfirmReject", alter: "تأكيد الرفض"))
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

// MARK: - Queue Zero State

private struct AdminQueueZeroView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(uiColor: .ppSuccess).opacity(0.18), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(AdminSurface.surface)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.4), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color(uiColor: .ppSuccess))
            }
            .padding(.top, 16)

            VStack(spacing: 6) {
                Text(title)
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Helper Functions

private func relativeTimeString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    formatter.locale = Locale(identifier: Language.currentLanguageCode())
    return formatter.localizedString(for: date, relativeTo: Date())
}