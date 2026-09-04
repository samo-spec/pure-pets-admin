//
//  ChatsView.swift
//  PurePetsAdmin
//
//  Native SwiftUI support-chats command surface, replacing the embedded legacy
//  PPChatsViewController UIKit stack.
//
//  Backend authority is unchanged and reproduced verbatim from the legacy
//  implementation:
//    • List:     Chats where conversationType in ["user_support","support"],
//                orderBy lastMessageAt desc, limit 100, live snapshot listener.
//    • Thread:   Chats/{id} doc listener + Chats/{id}/Messages orderBy timestamp
//                desc limit 200, live snapshot listener, displayed oldest→newest.
//    • Mutations: the single callable `supportChatCommand` in us-central1 with a
//                30s timeout and actions mark_read | send_staff_reply | transition.
//                No direct Firestore writes are ever performed from the client.
//    • Identity: the client never stamps official-vs-staff identity; the server
//                owns that projection and every audit write.
//    • Permissions: support.view gates reading, support.manage gates replying,
//                status transitions and mark_read.
//

import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Backend Contract Constants

private enum SupportContract {
    static let chatsCollection = "Chats"
    static let messagesCollection = "Messages"
    static let conversationTypes = ["user_support", "support"]
    static let listLimit = 100
    static let messageLimit = 200

    static let callableName = "supportChatCommand"
    static let callableRegion = "us-central1"
    static let callableTimeout: TimeInterval = 30.0

    static let officialSupportUserID = "PUIDPOFFICILAL20262214"
    static let officialActorKey = "support:official"

    static let sourceApp = "admin_ios"
    static let sourcePlatform = "ios"
    static let transitionReason = "admin_status_change"
}

private func supportText(_ key: String, _ fallback: String) -> String {
    Language.get(key, alter: fallback)
}

private func supportTrimmed(_ value: Any?) -> String {
    guard let string = value as? String else { return "" }
    return string.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func supportDate(_ value: Any?) -> Date? {
    if let date = value as? Date { return date }
    if let timestamp = value as? Timestamp { return timestamp.dateValue() }
    return nil
}

private func supportRelativeDate(_ date: Date?) -> String {
    guard let date else { return "" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    formatter.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
    return formatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - Support Status

/// The four server statuses, plus a passthrough for any value the server may
/// introduce later. Legacy behaviour is preserved exactly: an empty status is
/// Waiting, an unrecognised status renders as "Support", counts as not-open,
/// and cannot be transitioned away from.
enum SupportStatus: Equatable, Hashable, Sendable {
    case waiting
    case active
    case resolved
    case closed
    case unknown(String)

    static let selectable: [SupportStatus] = [.waiting, .active, .resolved, .closed]

    init(raw: Any?) {
        let value = supportTrimmed(raw).lowercased()
        switch value {
        case "", "waiting_for_agent": self = .waiting
        case "active": self = .active
        case "resolved": self = .resolved
        case "closed": self = .closed
        default: self = .unknown(value)
        }
    }

    var wireValue: String {
        switch self {
        case .waiting: return "waiting_for_agent"
        case .active: return "active"
        case .resolved: return "resolved"
        case .closed: return "closed"
        case .unknown(let raw): return raw
        }
    }

    var title: String {
        switch self {
        case .waiting: return supportText("SupportChats_Status_Waiting", "انتظار")
        case .active: return supportText("SupportChats_Status_Active", "نشطة")
        case .resolved: return supportText("SupportChats_Status_Resolved", "تم الحل")
        case .closed: return supportText("SupportChats_Status_Closed", "مغلقة")
        case .unknown: return supportText("SupportChats_Status_Support", "الدعم")
        }
    }

    var tint: Color {
        switch self {
        case .resolved: return Color(uiColor: .ppSuccess)
        case .closed: return Color(uiColor: .ppTextSecondary)
        case .active: return Color(uiColor: .ppInfo)
        case .waiting, .unknown: return Color(uiColor: .ppPrimary)
        }
    }

    var symbol: String {
        switch self {
        case .waiting: return "clock.badge.exclamationmark"
        case .active: return "bubble.left.and.bubble.right.fill"
        case .resolved: return "checkmark.seal.fill"
        case .closed: return "archivebox.fill"
        case .unknown: return "lifepreserver"
        }
    }

    /// Counted by the "Open" hero metric.
    var isOpen: Bool {
        switch self {
        case .waiting, .active: return true
        case .resolved, .closed, .unknown: return false
        }
    }

    /// Legacy rule: only resolved and closed block replying.
    var allowsReply: Bool {
        switch self {
        case .resolved, .closed: return false
        case .waiting, .active, .unknown: return true
        }
    }

    /// Legacy transition matrix, preserved exactly.
    func canTransition(to next: SupportStatus) -> Bool {
        if self == next { return true }
        switch self {
        case .waiting, .active:
            return SupportStatus.selectable.contains(next)
        case .resolved:
            return next == .active || next == .closed
        case .closed:
            return next == .active
        case .unknown:
            return false
        }
    }
}

// MARK: - Chat Context Model

struct SupportContextMetaItem: Sendable, Equatable, Hashable, Identifiable {
    var id: String { "\(label)-\(value)" }
    let label: String
    let value: String
}

struct SupportChatContextDescriptor: Equatable, Sendable {
    enum Category: String, Sendable {
        case order
        case petListing
        case adoption
        case hotelStay
        case serviceBooking
        case appScreen
        case customerIntelligence

        var iconName: String {
            switch self {
            case .order: return "bag.fill"
            case .petListing: return "pawprint.fill"
            case .adoption: return "heart.text.square.fill"
            case .hotelStay: return "bed.double.fill"
            case .serviceBooking: return "cross.case.fill"
            case .appScreen: return "arrow.triangle.turn.up.right.diamond.fill"
            case .customerIntelligence: return "person.crop.circle.badge.checkmark"
            }
        }

        var localizedCategoryName: String {
            switch self {
            case .order: return supportText("SupportContext_Cat_Order", "طلب شراء")
            case .petListing: return supportText("SupportContext_Cat_PetAd", "إعلان حيوان")
            case .adoption: return supportText("SupportContext_Cat_Adoption", "طلب تبني")
            case .hotelStay: return supportText("SupportContext_Cat_Hotel", "حجز فندقي")
            case .serviceBooking: return supportText("SupportContext_Cat_Service", "خدمة بيطرية")
            case .appScreen: return supportText("SupportContext_Cat_AppScreen", "نقطة انطلاق")
            case .customerIntelligence: return supportText("SupportContext_Cat_CustomerRadar", "سجل العميل")
            }
        }

        var accentColor: Color {
            switch self {
            case .order: return Color(red: 0.94, green: 0.44, blue: 0.28)
            case .petListing: return Color(red: 0.25, green: 0.65, blue: 0.85)
            case .adoption: return Color(red: 0.88, green: 0.35, blue: 0.55)
            case .hotelStay: return Color(red: 0.60, green: 0.45, blue: 0.88)
            case .serviceBooking: return Color(red: 0.30, green: 0.75, blue: 0.65)
            case .appScreen: return Color(red: 0.88, green: 0.62, blue: 0.22)
            case .customerIntelligence: return Color(uiColor: .ppPrimary)
            }
        }
    }

    let category: Category
    let title: String
    let referenceId: String
    let primaryMetric: String
    let statusText: String
    let statusColor: Color
    let originScreen: String
    let platform: String
    let metadataItems: [SupportContextMetaItem]
    let rawEntityId: String
}

// MARK: - Thread Model

/// Sendable projection of a `Chats` document. Every field the legacy screen read
/// is captured here so nothing crosses an actor boundary as a raw dictionary.
struct SupportThread: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let lastMessage: String
    let status: SupportStatus
    let isUnread: Bool
    let date: Date?
    let lastMessageID: String
    let lifecycleVersion: Int
    let sourcePlatform: String
    let supportUnread: Bool
    let customerID: String
    let contextType: String
    let contextID: String
    let orderID: String
    let sourceScreen: String
    let sourceEntityID: String
    let initialCustomerPhotoURL: String

    init(data: [String: Any], documentID: String, currentUID: String) {
        id = documentID
        lastMessage = supportTrimmed(data["lastMessage"])
        status = SupportStatus(raw: data["supportStatus"])
        displayName = SupportThread.customerDisplayName(data: data, currentUID: currentUID)
        isUnread = SupportThread.isUnread(data: data, currentUID: currentUID)
        date = supportDate(data["lastMessageAt"]) ?? supportDate(data["timestamp"])
        let projectedID = supportTrimmed(data["lastMessageId"])
        lastMessageID = projectedID.isEmpty ? supportTrimmed(data["lastProjectedMessageId"]) : projectedID
        lifecycleVersion = (data["supportLifecycleVersion"] as? NSNumber)?.intValue ?? 0
        sourcePlatform = supportTrimmed(data["sourcePlatform"])
        supportUnread = (data["supportUnread"] as? NSNumber)?.boolValue ?? false

        let cid = SupportThread.resolveCustomerID(data: data, currentUID: currentUID)
        customerID = cid
        let rawCType = supportTrimmed(data["contextType"]).isEmpty ? supportTrimmed(data["conversationType"]) : supportTrimmed(data["contextType"])
        contextType = rawCType
        contextID = supportTrimmed(data["contextId"]).isEmpty ? supportTrimmed(data["contextID"]) : supportTrimmed(data["contextId"])
        let rawOrd = supportTrimmed(data["orderId"]).isEmpty ? supportTrimmed(data["orderNumber"]) : supportTrimmed(data["orderId"])
        orderID = rawOrd.isEmpty ? supportTrimmed(data["orderID"]) : rawOrd
        sourceScreen = supportTrimmed(data["sourceScreen"])
        sourceEntityID = supportTrimmed(data["sourceEntityId"]).isEmpty ? supportTrimmed(data["sourceEntityID"]) : supportTrimmed(data["sourceEntityId"])

        var photo = supportTrimmed(data["customerPhotoURL"])
        if photo.isEmpty { photo = supportTrimmed(data["userImage"]) }
        if photo.isEmpty { photo = supportTrimmed(data["photoURL"]) }
        if photo.isEmpty, let memberPhotos = data["memberPhotos"] as? [String: Any], !cid.isEmpty {
            photo = supportTrimmed(memberPhotos[cid])
        }
        initialCustomerPhotoURL = photo
    }

    /// Fields the local search blob matches, mirroring the legacy blob exactly:
    /// resolved name, last message, localized status label, source platform, id.
    var searchBlob: String {
        [displayName, lastMessage, status.title, sourcePlatform, id]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var relativeDate: String { supportRelativeDate(date) }

    // MARK: Legacy helpers reproduced verbatim

    /// `PPChatsIsSupportOfficialSender`
    static func isOfficialSender(data: [String: Any]) -> Bool {
        let actorKeys = ["lastMessageSenderActorKey", "senderActorKey", "visibleSenderActorKey"]
        for key in actorKeys {
            let value = supportTrimmed(data[key])
            if !value.isEmpty {
                return value == SupportContract.officialActorKey
            }
        }
        let senderID = supportTrimmed(data["senderID"]).isEmpty
            ? supportTrimmed(data["senderId"])
            : supportTrimmed(data["senderID"])
        return senderID == SupportContract.officialSupportUserID
    }

    /// `PPChatsThreadIsUnread` — all four conditions must hold.
    static func isUnread(data: [String: Any], currentUID: String) -> Bool {
        guard !supportTrimmed(data["lastMessage"]).isEmpty else { return false }
        guard !isOfficialSender(data: data) else { return false }
        guard supportTrimmed(data["lastReadActorKey"]) != SupportContract.officialActorKey else { return false }
        let staffUID = currentUID.trimmingCharacters(in: .whitespacesAndNewlines)
        return supportTrimmed(data["lastReadBy"]) != staffUID
    }

    /// `PPChatsResolveCustomerID` — skips the official support UID and the staff UID.
    static func resolveCustomerID(data: [String: Any], currentUID: String) -> String {
        let staffUID = currentUID.trimmingCharacters(in: .whitespacesAndNewlines)
        func eligible(_ value: String) -> Bool {
            !value.isEmpty && value != SupportContract.officialSupportUserID && value != staffUID
        }

        for key in ["customerId", "customerID", "userId", "userID", "targetUid"] {
            let value = supportTrimmed(data[key])
            if eligible(value) { return value }
        }
        for key in ["participantUids", "members"] {
            if let list = data[key] as? [Any] {
                for entry in list {
                    let value = supportTrimmed(entry)
                    if eligible(value) { return value }
                }
            }
        }
        for key in ["senderID", "senderId", "receiverID", "receiverId"] {
            let value = supportTrimmed(data[key])
            if eligible(value) { return value }
        }
        return ""
    }

    /// `PPChatsCustomerDisplayName` — first non-empty wins.
    static func customerDisplayName(data: [String: Any], currentUID: String) -> String {
        let customerID = resolveCustomerID(data: data, currentUID: currentUID)
        if let names = data["memberNames"] as? [String: Any], !customerID.isEmpty {
            let mapped = supportTrimmed(names[customerID])
            if !mapped.isEmpty { return mapped }
        }
        for key in ["customerName", "displayName", "name"] {
            let value = supportTrimmed(data[key])
            if !value.isEmpty { return value }
        }
        if customerID.count >= 8 { return String(customerID.prefix(8)) }
        return supportText("SupportChats_CustomerFallback", "عميل")
    }
}

// MARK: - Message Model

struct SupportMessage: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let isOfficial: Bool
    let date: Date?

    init(data: [String: Any], documentID: String) {
        id = documentID
        text = SupportMessage.displayText(data: data)
        isOfficial = SupportThread.isOfficialSender(data: data)
        date = supportDate(data["timestamp"]) ?? supportDate(data["createdAt"])
    }

    var relativeDate: String { supportRelativeDate(date) }

    /// `PPChatsMessageDisplayText` — text wins regardless of type; otherwise the
    /// integer `type` selects a localized placeholder.
    static func displayText(data: [String: Any]) -> String {
        let primary = supportTrimmed(data["text"])
        if !primary.isEmpty { return primary }
        let secondary = supportTrimmed(data["message"])
        if !secondary.isEmpty { return secondary }

        switch (data["type"] as? NSNumber)?.intValue ?? 0 {
        case 1: return supportText("SupportChats_MessageImage", "رسالة صورة")
        case 2: return supportText("SupportChats_MessageAudio", "رسالة صوتية")
        case 3: return supportText("SupportChats_MessageVideo", "رسالة فيديو")
        case 4: return supportText("SupportChats_MessageFile", "رسالة ملف")
        case 5: return supportText("SupportChats_MessageSystem", "رسالة نظام")
        default: return supportText("SupportChats_MessageFallback", "لا توجد رسائل بعد.")
        }
    }
}

// MARK: - Callable Bridge

/// Sendable slice of the callable response the client is allowed to consume.
private struct SupportCommandResult: Sendable {
    let supportStatus: String?
    let lifecycleVersion: Int?
}

private enum SupportCommand {
    /// Single mutation entry point. Mirrors the legacy callable exactly.
    /// A nil result means the command failed; the caller decides the copy.
    static func invoke(
        payload: sending [String: Any],
        completion: @escaping @Sendable (SupportCommandResult?) -> Void
    ) {
        let callable = Functions
            .functions(region: SupportContract.callableRegion)
            .httpsCallable(SupportContract.callableName)
        callable.timeoutInterval = SupportContract.callableTimeout
        callable.call(payload) { result, error in
            if error != nil {
                completion(nil)
                return
            }
            let data = result?.data as? [String: Any] ?? [:]
            let status = supportTrimmed(data["supportStatus"])
            completion(SupportCommandResult(
                supportStatus: status.isEmpty ? nil : status,
                lifecycleVersion: (data["supportLifecycleVersion"] as? NSNumber)?.intValue
            ))
        }
    }

    /// Fire-and-forget, exactly like the legacy screen: no UI feedback, no retry.
    static func markRead(threadID: String, expectedLastMessageID: String) {
        guard !threadID.isEmpty else { return }
        invoke(payload: [
            "action": "mark_read",
            "threadId": threadID,
            "expectedLastMessageId": expectedLastMessageID
        ]) { _ in }
    }
}

// MARK: - List View Model

@MainActor
final class AdminSupportChatsViewModel: ObservableObject {
    @Published private(set) var threads: [SupportThread] = []
    @Published private(set) var filteredThreads: [SupportThread] = []
    @Published var searchText: String = ""

    @Published private(set) var isLoading = true
    @Published private(set) var hasError = false
    @Published private(set) var accessDenied = false
    @Published private(set) var canManage = false
    @Published private(set) var currentUID = ""

    /// Hero metrics are computed over the unfiltered window, so search never
    /// changes the numbers — matching the legacy behaviour.
    @Published private(set) var unreadCount = 0
    @Published private(set) var openCount = 0

    private nonisolated(unsafe) var listener: (any ListenerRegistration)?

    deinit { listener?.remove() }

    // MARK: Permissions

    func start() {
        isLoading = true
        hasError = false

        if let staff = PPStaffAuth.shared().cachedCurrentStaff {
            apply(staff: staff)
            return
        }
        PPStaffAuth.shared().refreshCurrentStaff { [weak self] doc, _ in
            // Project to Sendable values before hopping to the main actor.
            let canView = doc?.hasAnyPermission([kStaffPermSupportView, kStaffPermSupportManage]) ?? false
            let canManage = doc?.hasPermission(kStaffPermSupportManage) ?? false
            let uid = doc?.uid ?? ""
            Task { @MainActor in
                self?.apply(canView: canView, canManage: canManage, staffUID: uid)
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    private func apply(staff: PPStaffDoc) {
        apply(
            canView: staff.hasAnyPermission([kStaffPermSupportView, kStaffPermSupportManage]),
            canManage: staff.hasPermission(kStaffPermSupportManage),
            staffUID: staff.uid
        )
    }

    private func apply(canView: Bool, canManage: Bool, staffUID: String) {
        let authUID = Auth.auth().currentUser?.uid ?? ""
        currentUID = authUID.isEmpty ? staffUID : authUID
        self.canManage = canManage

        guard canView, !currentUID.isEmpty else {
            listener?.remove()
            listener = nil
            accessDenied = true
            isLoading = false
            threads = []
            filteredThreads = []
            recomputeMetrics()
            return
        }
        accessDenied = false
        startListening()
    }

    // MARK: Firestore

    private func startListening() {
        listener?.remove()
        listener = nil
        isLoading = true
        hasError = false

        let uid = currentUID
        let query = Firestore.firestore()
            .collection(SupportContract.chatsCollection)
            .whereField("conversationType", in: SupportContract.conversationTypes)
            .order(by: "lastMessageAt", descending: true)
            .limit(to: SupportContract.listLimit)

        listener = query.addSnapshotListener { [weak self] snapshot, error in
            let failed = error != nil
            let parsed: [SupportThread] = (snapshot?.documents ?? []).map {
                SupportThread(data: $0.data(), documentID: $0.documentID, currentUID: uid)
            }
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if failed {
                    self.hasError = true
                    self.threads = []
                    self.filteredThreads = []
                    self.recomputeMetrics()
                    return
                }
                self.hasError = false
                self.threads = parsed
                self.applyFilter()
            }
        }
    }

    func refresh() { start() }

    // MARK: Search + metrics

    func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredThreads = threads
        } else {
            filteredThreads = threads.filter {
                $0.searchBlob.localizedCaseInsensitiveContains(query)
            }
        }
        recomputeMetrics()
    }

    private func recomputeMetrics() {
        unreadCount = threads.filter(\.isUnread).count
        openCount = threads.filter { $0.status.isOpen }.count
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Legacy side effect on row tap: fire-and-forget mark_read, manage-gated.
    func markRead(_ thread: SupportThread) {
        guard canManage, !currentUID.isEmpty else { return }
        SupportCommand.markRead(threadID: thread.id, expectedLastMessageID: thread.lastMessageID)
    }
}

// MARK: - List View

@available(iOS 16.0, *)
struct AdminChatsView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sizeCategory) private var sizeCategory
    @StateObject private var viewModel = AdminSupportChatsViewModel()
    @State private var selectedThread: SupportThread?

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationView {
            chatsContent
                .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var chatsContent: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerPill
                identityCard
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.md)
                threadList
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.searchText) { _ in viewModel.applyFilter() }
        .background(threadPushLink)
    }

    private var threadPushLink: some View {
        NavigationLink(
            destination: threadDestination,
            isActive: Binding(
                get: { selectedThread != nil },
                set: { isActive in
                    if !isActive {
                        selectedThread = nil
                    }
                }
            )
        ) {
            EmptyView()
        }
        .hidden()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var threadDestination: some View {
        if let thread = selectedThread {
            SupportThreadView(
                thread: thread,
                currentUID: viewModel.currentUID,
                canManage: viewModel.canManage
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .navigationBarHidden(true)
        } else {
            EmptyView()
        }
    }

    // MARK: Header

    private var headerPill: some View {
        AdminSovereignNavigationBar(
            title: supportText("Chats", "المحادثات"),
            subtitle: supportText("CommandCenter_Customers_Workspace", "مساحة العملاء • الدعم الفني"),
            statusDotColor: Color(uiColor: .ppSuccess),
            onBack: {
                if let onDismiss { onDismiss() } else { dismiss() }
            }
        ) {
            if !viewModel.canManage && !viewModel.accessDenied {
                Text(supportText("SupportChats_ReadOnly", "عرض فقط"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(AdminSurface.surface, in: Capsule())
                    .overlay(Capsule().stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8))
            }
        }
    }

    // MARK: Identity + metrics + search

    private var identityCard: some View {
        VStack(spacing: AdminSpacing.md) {
            HStack(alignment: .top, spacing: AdminSpacing.md) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 40, height: 40)
                    .background(
                        AdminSurface.primary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: AdminRadius.small)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(supportText("SupportChats_HeroKicker", "هوية الدعم"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.primary)
                    Text(supportText("SupportChats_OfficialName", "دعم بيور بتس الرسمي"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(2)
                    Text(viewModel.canManage
                         ? supportText("SupportChats_HeroSubtitleManage", "الرد باسم فريق الدعم الرسمي مع حفظ هوية الموظف في سجل التدقيق.")
                         : supportText("SupportChats_HeroSubtitleView", "متابعة محادثات الدعم الرسمية بصلاحية عرض فقط."))
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            metricsRow

            AdminSearchField(
                text: $viewModel.searchText,
                placeholder: supportText("SupportChats_SearchPlaceholder", "ابحث في محادثات الدعم…")
            )
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
    }

    @ViewBuilder
    private var metricsRow: some View {
        // Stacks vertically at accessibility text sizes so the numbers never clip.
        if sizeCategory.isAccessibilityCategory {
            VStack(spacing: AdminSpacing.sm) {
                unreadChip
                openChip
            }
        } else {
            HStack(spacing: AdminSpacing.sm) {
                unreadChip
                openChip
            }
        }
    }

    private var unreadChip: some View {
        metricChip(
            title: supportText("SupportChats_HeroMetricUnread", "غير مقروء"),
            value: viewModel.unreadCount,
            tint: Color(uiColor: .ppPrimary),
            symbol: "envelope.badge.fill"
        )
    }

    private var openChip: some View {
        metricChip(
            title: supportText("SupportChats_HeroMetricActive", "مفتوح"),
            value: viewModel.openCount,
            tint: Color(uiColor: .ppInfo),
            symbol: "bubble.left.and.bubble.right.fill"
        )
    }

    private func metricChip(title: String, value: Int, tint: Color, symbol: String) -> some View {
        HStack(spacing: AdminSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
            Text(title)
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .lineLimit(1)
            Spacer(minLength: AdminSpacing.xs)
            Text("\(value)")
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .foregroundColor(AdminSurface.primaryText)
                .animation(reduceMotion ? nil : AdminAnimation.standard, value: value)
        }
        .padding(.horizontal, AdminSpacing.md)
        .frame(maxWidth: .infinity)
        .frame(minHeight: AdminTouchTarget.minimum)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.small))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
    }

    // MARK: List + states

    @ViewBuilder
    private var threadList: some View {
        if viewModel.accessDenied {
            stateView(
                symbol: "lock.shield.fill",
                title: supportText("SupportChats_NoAccess", "ليست لديك صلاحية لعرض محادثات الدعم."),
                subtitle: supportText("SupportChats_NoAccess_Subtitle", "اطلب من المالك منح صلاحية support.view أو support.manage.")
            )
        } else if viewModel.isLoading && viewModel.threads.isEmpty {
            VStack(spacing: AdminSpacing.md) {
                ProgressView().tint(AdminSurface.primary)
                Text(supportText("SupportChats_Loading", "جارٍ تحميل محادثات الدعم…"))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.hasError {
            VStack(spacing: AdminSpacing.md) {
                stateView(
                    symbol: "wifi.exclamationmark",
                    title: supportText("SupportChats_Error", "تعذر تحميل محادثات الدعم."),
                    subtitle: nil
                )
                Button {
                    viewModel.refresh()
                } label: {
                    Text(supportText("TryAgain", "إعادة المحاولة"))
                        .font(AdminType.captionBold)
                        .padding(.horizontal, AdminSpacing.lg)
                        .frame(minHeight: AdminTouchTarget.minimum)
                }
                .buttonStyle(.borderedProminent)
                .tint(AdminSurface.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredThreads.isEmpty {
            stateView(
                symbol: viewModel.isSearching ? "magnifyingglass" : "lifepreserver.fill",
                title: viewModel.isSearching
                    ? supportText("SupportChats_NoResults", "لا توجد محادثات دعم مطابقة.")
                    : supportText("SupportChats_Empty", "لا توجد محادثات دعم بعد."),
                subtitle: viewModel.isSearching
                    ? nil
                    : supportText("SupportChats_Empty_Subtitle", "ستظهر محادثات دعم العملاء الجديدة هنا.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: AdminSpacing.sm) {
                    ForEach(viewModel.filteredThreads) { thread in
                        Button {
                            viewModel.markRead(thread)
                            selectedThread = thread
                        } label: {
                            SupportThreadRow(thread: thread)
                        }
                        .buttonStyle(SupportRowPressStyle())
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, AdminSpacing.md)
            }
            .refreshable { viewModel.refresh() }
        }
    }

    private func stateView(symbol: String, title: String, subtitle: String?) -> some View {
        VStack(spacing: AdminSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
            Text(title)
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(AdminType.subheadline)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, AdminSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Legacy UIKit host is retained elsewhere; this file no longer embeds it.

private struct SupportRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(AdminAnimation.fast, value: configuration.isPressed)
    }
}

// MARK: - Thread Row

private struct SupportThreadRow: View {
    let thread: SupportThread

    var body: some View {
        HStack(spacing: AdminSpacing.md) {
            // Unread rail, mirroring the legacy leading indicator bar.
            RoundedRectangle(cornerRadius: 2)
                .fill(thread.isUnread ? thread.status.tint : Color.clear)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            Image(systemName: thread.isUnread ? "exclamationmark.bubble.fill" : "person.crop.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(thread.status.tint)
                .frame(width: 40, height: 40)
                .background(
                    thread.status.tint.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: AdminRadius.small)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: AdminSpacing.sm) {
                    Text(thread.displayName)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(thread.relativeDate)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }

                Text(thread.lastMessage.isEmpty
                     ? supportText("SupportChats_MessageFallback", "لا توجد رسائل بعد.")
                     : thread.lastMessage)
                    .font(thread.isUnread ? AdminType.footnoteBold : AdminType.footnote)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                statusPill
                    .padding(.top, 2)
            }
        }
        .padding(AdminSpacing.md)
        .background(
            thread.isUnread ? AdminSurface.control : AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: AdminRadius.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card)
                .stroke(thread.isUnread ? thread.status.tint.opacity(0.35) : AdminSurface.hairline)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            Image(systemName: thread.status.symbol)
                .font(.system(size: 9, weight: .bold))
            Text(thread.status.title)
                .font(AdminType.caption2Bold)
        }
        .foregroundColor(thread.status.tint)
        .padding(.horizontal, AdminSpacing.sm)
        .frame(minHeight: 22)
        .background(thread.status.tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(thread.status.tint.opacity(0.35)))
    }

    private var accessibilitySummary: String {
        [
            thread.displayName,
            thread.isUnread ? supportText("SupportChats_HeroMetricUnread", "غير مقروء") : "",
            thread.status.title,
            thread.lastMessage,
            thread.relativeDate
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}

// MARK: - Thread View Model

@MainActor
final class AdminSupportThreadViewModel: ObservableObject {
    @Published private(set) var messages: [SupportMessage] = []
    @Published private(set) var isLoading = true
    @Published private(set) var hasMessagesError = false

    @Published private(set) var status: SupportStatus
    @Published private(set) var lifecycleVersion: Int
    @Published private(set) var title: String

    @Published var draft: String = ""
    @Published private(set) var isSending = false
    @Published private(set) var isUpdatingStatus = false
    @Published var alertMessage: String?

    let threadID: String
    let currentUID: String
    let canManage: Bool
    let customerID: String
    let sourcePlatform: String
    let initialContextType: String
    let initialContextID: String
    let initialOrderID: String
    let initialSourceScreen: String
    let initialSourceEntityID: String

    // Customer Live Enrichment
    @Published private(set) var customerName: String
    @Published private(set) var customerAvatarUrl: String
    @Published private(set) var customerPhone: String = ""
    @Published private(set) var customerEmail: String = ""
    @Published private(set) var customerJoinDate: String = ""
    @Published private(set) var isCustomerVerified: Bool = false

    // Chat Context Intelligence
    @Published private(set) var chatContext: SupportChatContextDescriptor?
    @Published private(set) var isLoadingContext: Bool = false
    @Published var isContextExpanded: Bool = false
    @Published var isShowingCustomerDossier: Bool = false
    @Published var isShowingContextDetail: Bool = false

    private var lastMessageID: String
    private var isMarkingRead = false

    /// Idempotency: a retry of the same text reuses the same messageId.
    private var pendingMessageID = ""
    private var pendingMessageText = ""

    private nonisolated(unsafe) var messagesListener: (any ListenerRegistration)?
    private nonisolated(unsafe) var threadListener: (any ListenerRegistration)?

    init(thread: SupportThread, currentUID: String, canManage: Bool) {
        threadID = thread.id
        self.currentUID = currentUID
        self.canManage = canManage
        status = thread.status
        lifecycleVersion = thread.lifecycleVersion
        title = thread.displayName
        lastMessageID = thread.lastMessageID
        customerID = thread.customerID
        sourcePlatform = thread.sourcePlatform
        initialContextType = thread.contextType
        initialContextID = thread.contextID
        initialOrderID = thread.orderID
        initialSourceScreen = thread.sourceScreen
        initialSourceEntityID = thread.sourceEntityID

        customerName = thread.displayName
        customerAvatarUrl = thread.initialCustomerPhotoURL
    }

    deinit {
        messagesListener?.remove()
        threadListener?.remove()
    }

    var allowsReply: Bool { status.allowsReply }

    var canSend: Bool {
        canManage
            && allowsReply
            && !isSending
            && !isUpdatingStatus
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Legacy placeholder precedence, preserved in order.
    var composerPlaceholder: String {
        if !canManage { return supportText("SupportChats_ManageDenied", "الرد يتطلب صلاحية support.manage.") }
        if !allowsReply { return supportText("SupportChats_ReopenToReply", "اضبط الحالة على نشطة قبل الرد.") }
        if isUpdatingStatus { return supportText("SupportChats_StatusUpdating", "جارٍ تحديث حالة المحادثة…") }
        if isSending { return supportText("SupportChats_Sending", "جارٍ إرسال الرد…") }
        return supportText("SupportChats_MessagePlaceholder", "الرد على العميل")
    }

    // MARK: Listeners

    func start() {
        listenThread()
        listenMessages()
        markRead()
        enrichCustomerProfile()
        resolveInitialChatContext()
    }

    func stop() {
        messagesListener?.remove()
        messagesListener = nil
        threadListener?.remove()
        threadListener = nil
    }

    private func listenThread() {
        guard !threadID.isEmpty else { return }
        threadListener?.remove()

        let uid = currentUID
        threadListener = Firestore.firestore()
            .collection(SupportContract.chatsCollection)
            .document(threadID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard error == nil, let snapshot, snapshot.exists else { return }
                let data = snapshot.data() ?? [:]
                let projected = SupportThread(
                    data: data,
                    documentID: snapshot.documentID,
                    currentUID: uid
                )
                Task { @MainActor in
                    guard let self else { return }
                    self.status = projected.status
                    self.lifecycleVersion = projected.lifecycleVersion
                    if !projected.displayName.isEmpty && (self.customerName.isEmpty || self.customerName == self.threadID.prefix(8) || self.customerName == self.customerID.prefix(8)) {
                        self.customerName = projected.displayName
                        self.title = projected.displayName
                    }
                    self.lastMessageID = projected.lastMessageID
                    if self.canManage && projected.supportUnread {
                        self.markRead()
                    }
                    self.resolveInitialChatContext(threadData: data)
                }
            }
    }

    func listenMessages() {
        guard !threadID.isEmpty else {
            isLoading = false
            return
        }
        messagesListener?.remove()
        isLoading = true
        hasMessagesError = false

        messagesListener = Firestore.firestore()
            .collection(SupportContract.chatsCollection)
            .document(threadID)
            .collection(SupportContract.messagesCollection)
            .order(by: "timestamp", descending: true)
            .limit(to: SupportContract.messageLimit)
            .addSnapshotListener { [weak self] snapshot, error in
                let failed = error != nil
                // Server returns newest-first; display oldest→newest.
                let parsed: [SupportMessage] = (snapshot?.documents ?? [])
                    .reversed()
                    .map { SupportMessage(data: $0.data(), documentID: $0.documentID) }
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false
                    if failed {
                        self.hasMessagesError = true
                        self.messages = []
                        return
                    }
                    self.hasMessagesError = false
                    self.messages = parsed
                    self.markRead()
                }
            }
    }

    // MARK: Customer & Context Enrichment

    private func enrichCustomerProfile() {
        guard !customerID.isEmpty else { return }
        let cid = customerID
        let db = Firestore.firestore()

        // 1. Fetch PublicUserProfiles for fast resolution
        db.collection("PublicUserProfiles").document(cid).getDocument { [weak self] snapshot, _ in
            guard let self, let data = snapshot?.data(), snapshot?.exists == true else { return }
            let name = supportTrimmed(data["displayName"]).isEmpty ? supportTrimmed(data["name"]) : supportTrimmed(data["displayName"])
            let photo = supportTrimmed(data["photoURL"]).isEmpty ? supportTrimmed(data["userImage"]) : supportTrimmed(data["photoURL"])
            let phone = supportTrimmed(data["phone"]).isEmpty ? supportTrimmed(data["phoneNumber"]) : supportTrimmed(data["phone"])

            Task { @MainActor in
                if !name.isEmpty && (self.customerName.isEmpty || self.customerName == self.threadID.prefix(8) || self.customerName == cid.prefix(8)) {
                    self.customerName = name
                    self.title = name
                }
                if !photo.isEmpty && self.customerAvatarUrl.isEmpty {
                    self.customerAvatarUrl = photo
                }
                if !phone.isEmpty && self.customerPhone.isEmpty {
                    self.customerPhone = phone
                }
            }
        }

        // 2. Fetch UsersCol for full profile, verification, phone, email, join date
        db.collection("UsersCol").document(cid).getDocument { [weak self] snapshot, _ in
            guard let self, let data = snapshot?.data(), snapshot?.exists == true else { return }
            let uName = supportTrimmed(data["UserName"]).isEmpty
                ? (supportTrimmed(data["displayName"]).isEmpty
                   ? (supportTrimmed(data["Name"]).isEmpty ? supportTrimmed(data["name"]) : supportTrimmed(data["Name"]))
                   : supportTrimmed(data["displayName"]))
                : supportTrimmed(data["UserName"])
            let uPhoto = supportTrimmed(data["userImage"]).isEmpty
                ? (supportTrimmed(data["photoURL"]).isEmpty ? supportTrimmed(data["avatarUrl"]) : supportTrimmed(data["photoURL"]))
                : supportTrimmed(data["userImage"])
            let uPhone = supportTrimmed(data["phoneNumber"]).isEmpty ? supportTrimmed(data["phone"]) : supportTrimmed(data["phoneNumber"])
            let uEmail = supportTrimmed(data["email"])
            let verified = (data["isVerified"] as? Bool) ?? (data["verified"] as? Bool) ?? false
            let created = supportDate(data["createdAt"]) ?? supportDate(data["accountCreatedAt"]) ?? supportDate(data["registrationDate"])

            Task { @MainActor in
                if !uName.isEmpty {
                    self.customerName = uName
                    self.title = uName
                }
                if !uPhoto.isEmpty {
                    self.customerAvatarUrl = uPhoto
                }
                if !uPhone.isEmpty {
                    self.customerPhone = uPhone
                }
                if !uEmail.isEmpty {
                    self.customerEmail = uEmail
                }
                self.isCustomerVerified = verified
                if let created {
                    let fmt = DateFormatter()
                    fmt.dateStyle = .medium
                    fmt.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
                    self.customerJoinDate = fmt.string(from: created)
                }
            }
        }
    }

    func resolveInitialChatContext(threadData: [String: Any]? = nil) {
        isLoadingContext = true
        let db = Firestore.firestore()
        let cid = customerID

        var cType = initialContextType.lowercased()
        var cID = initialContextID
        var ordID = initialOrderID
        var screen = initialSourceScreen
        var platform = sourcePlatform.isEmpty ? "iOS" : sourcePlatform

        if let threadData {
            let tType = supportTrimmed(threadData["contextType"]).lowercased()
            if !tType.isEmpty { cType = tType }
            let tID = supportTrimmed(threadData["contextId"]).isEmpty ? supportTrimmed(threadData["contextID"]) : supportTrimmed(threadData["contextId"])
            if !tID.isEmpty { cID = tID }
            let tOrd = supportTrimmed(threadData["orderId"]).isEmpty ? supportTrimmed(threadData["orderNumber"]) : supportTrimmed(threadData["orderId"])
            if !tOrd.isEmpty { ordID = tOrd }
            let tScreen = supportTrimmed(threadData["sourceScreen"])
            if !tScreen.isEmpty { screen = tScreen }
            let tPlatform = supportTrimmed(threadData["sourcePlatform"])
            if !tPlatform.isEmpty { platform = tPlatform }
        }

        // CASE 1: Explicit Order Context
        if !ordID.isEmpty || cType == "order" || cType == "orders" {
            let targetID = !ordID.isEmpty ? ordID : cID
            resolveOrderContext(orderID: targetID, screen: screen, platform: platform)
            return
        }

        // CASE 2: Pet Ad / Adoption
        if cType == "pet" || cType == "pet_ad" || cType == "adopt" || cType == "adopt_pets" {
            resolvePetContext(category: cType, petID: cID, screen: screen, platform: platform)
            return
        }

        // CASE 3: Hotel Stay
        if cType == "hotel" || cType == "hotelreservations" || cType == "pets_hotel" {
            resolveHotelContext(reservationID: cID, screen: screen, platform: platform)
            return
        }

        // CASE 4: App Screen Origin
        if !screen.isEmpty {
            self.chatContext = SupportChatContextDescriptor(
                category: .appScreen,
                title: String(format: supportText("SupportContext_FromScreen_Format", "استفسار من: %@"), screen),
                referenceId: cID.isEmpty ? cid : cID,
                primaryMetric: supportText("SupportContext_ActiveSession", "جلسة نشطة"),
                statusText: supportText("SupportContext_DirectInquiry", "استفسار مباشر"),
                statusColor: Color(red: 0.88, green: 0.62, blue: 0.22),
                originScreen: screen,
                platform: "\(platform) App",
                metadataItems: [
                    SupportContextMetaItem(label: supportText("SupportContext_OriginScreen", "شاشة البدء"), value: screen),
                    SupportContextMetaItem(label: supportText("SupportContext_Platform", "بيئة التشغيل"), value: "\(platform) App"),
                    SupportContextMetaItem(label: supportText("SupportContext_CustomerID", "معرّف العميل"), value: cid.isEmpty ? "-" : cid)
                ],
                rawEntityId: cID
            )
            self.isLoadingContext = false
            return
        }

        // CASE 5: Proactively check for customer's latest order
        if !cid.isEmpty {
            db.collection("Orders")
                .whereField("userId", isEqualTo: cid)
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .getDocuments { [weak self] snap, _ in
                    guard let self else { return }
                    if let doc = snap?.documents.first, doc.exists {
                        self.buildOrderDescriptor(docID: doc.documentID, data: doc.data(), isProactiveRecent: true, platform: platform)
                    } else {
                        self.buildCustomerRadarDescriptor(platform: platform)
                    }
                }
        } else {
            buildCustomerRadarDescriptor(platform: platform)
        }
    }

    private func resolveOrderContext(orderID: String, screen: String, platform: String) {
        let db = Firestore.firestore()
        db.collection("Orders").document(orderID).getDocument { [weak self] snapshot, _ in
            guard let self else { return }
            if let data = snapshot?.data(), snapshot?.exists == true {
                self.buildOrderDescriptor(docID: snapshot?.documentID ?? orderID, data: data, isProactiveRecent: false, platform: platform)
            } else {
                db.collection("Orders").whereField("orderNumber", isEqualTo: orderID).limit(to: 1).getDocuments { [weak self] querySnap, _ in
                    guard let self else { return }
                    if let doc = querySnap?.documents.first, doc.exists {
                        self.buildOrderDescriptor(docID: doc.documentID, data: doc.data(), isProactiveRecent: false, platform: platform)
                    } else {
                        let meta = [
                            SupportContextMetaItem(label: supportText("SupportContext_OrderNum", "رقم الطلب"), value: "#\(orderID)"),
                            SupportContextMetaItem(label: supportText("SupportContext_Platform", "المنصة"), value: "\(platform) App")
                        ]
                        self.chatContext = SupportChatContextDescriptor(
                            category: .order,
                            title: "\(supportText("SupportContext_OrderActive", "طلب شراء")) #\(orderID)",
                            referenceId: orderID,
                            primaryMetric: supportText("SupportContext_OrderActive", "طلب شراء"),
                            statusText: supportText("SupportContext_Active", "نشط"),
                            statusColor: Color(red: 0.94, green: 0.44, blue: 0.28),
                            originScreen: screen.isEmpty ? supportText("SupportContext_Storefront", "متجر بيور بتس") : screen,
                            platform: "\(platform) App",
                            metadataItems: meta,
                            rawEntityId: orderID
                        )
                        self.isLoadingContext = false
                    }
                }
            }
        }
    }

    private func resolvePetContext(category: String, petID: String, screen: String, platform: String) {
        let db = Firestore.firestore()
        let col = (category == "adopt" || category == "adopt_pets") ? "adopt_pets" : "pet_ads"
        let isAdopt = (category == "adopt" || category == "adopt_pets")

        db.collection(col).document(petID).getDocument { [weak self] snapshot, _ in
            guard let self else { return }
            if let data = snapshot?.data(), snapshot?.exists == true {
                let name = supportTrimmed(data["name"]).isEmpty ? supportTrimmed(data["title"]) : supportTrimmed(data["name"])
                let breed = supportTrimmed(data["breed"]).isEmpty ? supportTrimmed(data["kind"]) : supportTrimmed(data["breed"])
                let price = (data["price"] as? NSNumber)?.doubleValue ?? 0.0
                let curr = supportTrimmed(data["currency"]).isEmpty ? "ر.ق" : supportTrimmed(data["currency"])
                let status = supportTrimmed(data["status"])

                let titleText = name.isEmpty ? (isAdopt ? supportText("SupportContext_AdoptionListing", "طلب تبني") : supportText("SupportContext_PetListing", "إعلان حيوان أليف")) : name
                let metric = isAdopt ? supportText("SupportContext_FreeAdoption", "تبني مجاني") : (price > 0 ? String(format: "%.2f %@", price, curr) : "")

                var meta: [SupportContextMetaItem] = [
                    SupportContextMetaItem(label: supportText("SupportContext_PetName", "الاسم"), value: titleText),
                    SupportContextMetaItem(label: supportText("SupportContext_Breed", "السلالة / النوع"), value: breed.isEmpty ? supportText("Unknown", "غير محدد") : breed)
                ]
                if !metric.isEmpty {
                    meta.append(SupportContextMetaItem(label: supportText("SupportContext_Fee", "السعر / المقابل"), value: metric))
                }
                if !status.isEmpty {
                    meta.append(SupportContextMetaItem(label: supportText("SupportContext_Status", "الحالة"), value: status))
                }

                self.chatContext = SupportChatContextDescriptor(
                    category: isAdopt ? .adoption : .petListing,
                    title: titleText,
                    referenceId: petID,
                    primaryMetric: metric.isEmpty ? breed : metric,
                    statusText: status.isEmpty ? supportText("Active", "نشط") : status,
                    statusColor: isAdopt ? Color(red: 0.88, green: 0.35, blue: 0.55) : Color(red: 0.25, green: 0.65, blue: 0.85),
                    originScreen: screen.isEmpty ? (isAdopt ? supportText("SupportContext_Adoptions", "قسم التبني") : supportText("SupportContext_PetMarket", "سوق الحيوانات")) : screen,
                    platform: "\(platform) App",
                    metadataItems: meta,
                    rawEntityId: petID
                )
                self.isLoadingContext = false
            } else {
                self.buildCustomerRadarDescriptor(platform: platform)
            }
        }
    }

    private func resolveHotelContext(reservationID: String, screen: String, platform: String) {
        let db = Firestore.firestore()
        db.collection("hotelReservations").document(reservationID).getDocument { [weak self] snapshot, _ in
            guard let self else { return }
            if let data = snapshot?.data(), snapshot?.exists == true {
                let suite = supportTrimmed(data["suiteName"]).isEmpty ? supportTrimmed(data["roomName"]) : supportTrimmed(data["suiteName"])
                let petName = supportTrimmed(data["petName"])
                let checkIn = supportDate(data["checkInDate"])
                let checkOut = supportDate(data["checkOutDate"])
                let status = supportTrimmed(data["status"])

                let titleText = suite.isEmpty ? supportText("SupportContext_HotelBooking", "حجز فندق الحيوانات") : suite
                var datesStr = ""
                if let checkIn {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "d MMM"
                    fmt.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
                    datesStr = fmt.string(from: checkIn)
                    if let checkOut {
                        datesStr += " - \(fmt.string(from: checkOut))"
                    }
                }

                var meta: [SupportContextMetaItem] = [
                    SupportContextMetaItem(label: supportText("SupportContext_Suite", "الجناح"), value: titleText)
                ]
                if !petName.isEmpty {
                    meta.append(SupportContextMetaItem(label: supportText("SupportContext_PetGuest", "النزيل"), value: petName))
                }
                if !datesStr.isEmpty {
                    meta.append(SupportContextMetaItem(label: supportText("SupportContext_StayDates", "فترة الإقامة"), value: datesStr))
                }

                self.chatContext = SupportChatContextDescriptor(
                    category: .hotelStay,
                    title: titleText,
                    referenceId: reservationID,
                    primaryMetric: datesStr.isEmpty ? petName : datesStr,
                    statusText: status.isEmpty ? supportText("Active", "مؤكد") : status,
                    statusColor: Color(red: 0.60, green: 0.45, blue: 0.88),
                    originScreen: screen.isEmpty ? supportText("SupportContext_HotelSection", "فندق بيور بتس") : screen,
                    platform: "\(platform) App",
                    metadataItems: meta,
                    rawEntityId: reservationID
                )
                self.isLoadingContext = false
            } else {
                self.buildCustomerRadarDescriptor(platform: platform)
            }
        }
    }

    private func buildOrderDescriptor(docID: String, data: [String: Any], isProactiveRecent: Bool, platform: String) {
        let ordNum = supportTrimmed(data["orderNumber"]).isEmpty ? docID : supportTrimmed(data["orderNumber"])
        let total = (data["totalAmount"] as? NSNumber)?.doubleValue ?? 0.0
        let curr = supportTrimmed(data["currency"]).isEmpty ? "ر.ق" : supportTrimmed(data["currency"])
        let rawStatus = supportTrimmed(data["status"]).isEmpty ? supportTrimmed(data["rawStatus"]) : supportTrimmed(data["status"])
        let deliveryStatus = supportTrimmed(data["deliveryStatus"])
        let itemsCount = (data["items"] as? [Any])?.count ?? (data["itemCount"] as? NSNumber)?.intValue ?? 1

        let statusTitle: String
        let statusColor: Color
        switch rawStatus.lowercased() {
        case "pending", "awaiting_payment":
            statusTitle = supportText("OrderStatus_Pending", "بانتظار الدفع")
            statusColor = Color(red: 0.88, green: 0.62, blue: 0.22)
        case "processing", "preparing":
            statusTitle = supportText("OrderStatus_Processing", "قيد التجهيز")
            statusColor = Color(red: 0.25, green: 0.65, blue: 0.85)
        case "ready", "ready_for_pickup":
            statusTitle = supportText("OrderStatus_Ready", "جاهز للتسليم")
            statusColor = Color(red: 0.30, green: 0.75, blue: 0.65)
        case "in_transit", "shipped", "out_for_delivery":
            statusTitle = supportText("OrderStatus_InTransit", "في الطريق إلى العميل")
            statusColor = Color(uiColor: .ppPrimary)
        case "completed", "delivered":
            statusTitle = supportText("OrderStatus_Delivered", "تم التوصيل بنجاح")
            statusColor = Color(uiColor: .ppSuccess)
        case "cancelled", "rejected":
            statusTitle = supportText("OrderStatus_Cancelled", "ملغي")
            statusColor = Color(uiColor: .ppError)
        default:
            statusTitle = rawStatus.isEmpty ? supportText("OrderStatus_Active", "طلب نشط") : rawStatus
            statusColor = Color(uiColor: .ppPrimary)
        }

        let prefix = isProactiveRecent
            ? supportText("SupportContext_OrderRecent", "آخر طلب للعميل")
            : supportText("SupportContext_OrderActive", "طلب شراء")

        var meta: [SupportContextMetaItem] = [
            SupportContextMetaItem(label: supportText("SupportContext_OrderNum", "رقم الطلب"), value: "#\(ordNum)"),
            SupportContextMetaItem(label: supportText("SupportContext_Total", "الإجمالي"), value: String(format: "%.2f %@", total, curr)),
            SupportContextMetaItem(label: supportText("SupportContext_Status", "حالة الطلب"), value: statusTitle),
            SupportContextMetaItem(label: supportText("SupportContext_ItemsCount", "عدد الأصناف"), value: "\(itemsCount)")
        ]
        if !deliveryStatus.isEmpty {
            meta.append(SupportContextMetaItem(label: supportText("SupportContext_Delivery", "حالة الشحن"), value: deliveryStatus))
        }

        self.chatContext = SupportChatContextDescriptor(
            category: .order,
            title: "\(prefix) #\(ordNum)",
            referenceId: docID,
            primaryMetric: String(format: "%.2f %@", total, curr),
            statusText: statusTitle,
            statusColor: statusColor,
            originScreen: supportText("SupportContext_Storefront", "متجر بيور بتس"),
            platform: "\(platform) App",
            metadataItems: meta,
            rawEntityId: docID
        )
        self.isLoadingContext = false
    }

    private func buildCustomerRadarDescriptor(platform: String) {
        let titleText = String(format: supportText("SupportContext_GeneralSupport_Format", "محادثة دعم مباشرة • %@"), "\(platform) App")
        var meta: [SupportContextMetaItem] = [
            SupportContextMetaItem(label: supportText("SupportContext_Customer", "العميل"), value: customerName.isEmpty ? customerID : customerName),
            SupportContextMetaItem(label: supportText("SupportContext_Platform", "المنصة"), value: "\(platform) App")
        ]
        if !customerPhone.isEmpty {
            meta.append(SupportContextMetaItem(label: supportText("SupportContext_Phone", "رقم الجوال"), value: customerPhone))
        }
        if !customerJoinDate.isEmpty {
            meta.append(SupportContextMetaItem(label: supportText("SupportContext_MemberSince", "عضو منذ"), value: customerJoinDate))
        }

        self.chatContext = SupportChatContextDescriptor(
            category: .customerIntelligence,
            title: titleText,
            referenceId: customerID,
            primaryMetric: isCustomerVerified ? supportText("SupportContext_Verified", "عميل موثق") : supportText("SupportContext_Registered", "عميل مسجل"),
            statusText: supportText("SupportContext_LiveChat", "دعم مباشر"),
            statusColor: Color(uiColor: .ppSuccess),
            originScreen: supportText("SupportContext_AppHome", "التطبيق الرئيسي"),
            platform: "\(platform) App",
            metadataItems: meta,
            rawEntityId: customerID
        )
        self.isLoadingContext = false
    }

    // MARK: Mutations

    func markRead() {
        guard canManage, !isMarkingRead, !threadID.isEmpty, !currentUID.isEmpty else { return }
        isMarkingRead = true
        let expected = lastMessageID
        SupportCommand.invoke(payload: [
            "action": "mark_read",
            "threadId": threadID,
            "expectedLastMessageId": expected
        ]) { [weak self] _ in
            Task { @MainActor in self?.isMarkingRead = false }
        }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canManage, allowsReply, !isSending, !isUpdatingStatus,
              !text.isEmpty, !threadID.isEmpty, !currentUID.isEmpty else { return }

        // Reuse the pending command ID when retrying identical text.
        let retrying = !pendingMessageID.isEmpty && pendingMessageText == text
        if !retrying {
            pendingMessageID = UUID().uuidString
            pendingMessageText = text
        }

        isSending = true
        draft = ""

        SupportCommand.invoke(payload: [
            "action": "send_staff_reply",
            "threadId": threadID,
            "messageId": pendingMessageID,
            "expectedVersion": lifecycleVersion,
            "sourceApp": SupportContract.sourceApp,
            "sourcePlatform": SupportContract.sourcePlatform,
            "message": ["text": text, "type": 0]
        ]) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isSending = false
                guard let response = result else {
                    // Restore the text and keep the command ID for an idempotent retry.
                    self.draft = text
                    self.alertMessage = supportText("SupportChats_ReplyError", "تعذر إرسال رد الدعم.")
                    return
                }
                self.pendingMessageID = ""
                self.pendingMessageText = ""
                self.status = SupportStatus(raw: response.supportStatus ?? "active")
                if let version = response.lifecycleVersion { self.lifecycleVersion = version }
            }
        }
    }

    func transition(to next: SupportStatus) {
        guard canManage, !isUpdatingStatus, !isSending, next != status,
              status.canTransition(to: next),
              !threadID.isEmpty, !currentUID.isEmpty else { return }

        isUpdatingStatus = true
        SupportCommand.invoke(payload: [
            "action": "transition",
            "threadId": threadID,
            "toStatus": next.wireValue,
            "expectedVersion": lifecycleVersion,
            "reason": SupportContract.transitionReason
        ]) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isUpdatingStatus = false
                guard let response = result else {
                    self.alertMessage = supportText("SupportChats_StatusError", "تعذر تحديث حالة المحادثة.")
                    return
                }
                self.status = next
                if let version = response.lifecycleVersion { self.lifecycleVersion = version }
            }
        }
    }
}

// MARK: - Redesigned Top Bar (Customer Name & Luxury Avatar)

private struct SupportThreadTopBar: View {
    @ObservedObject var viewModel: AdminSupportThreadViewModel
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 1. Sovereign Circular Back Button
            AdminSquircleBackButton(action: onBack)

            // 2. Customer Avatar & Name Group (Interactive Dossier Trigger)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.isShowingCustomerDossier = true
            } label: {
                HStack(spacing: 10) {
                    // Avatar with Presence Dot
                    ZStack(alignment: .bottomTrailing) {
                        if !viewModel.customerAvatarUrl.isEmpty, let url = URL(string: viewModel.customerAvatarUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                        .scaledToFill()
                                        .frame(width: 42, height: 42)
                                        .clipShape(Circle())
                                case .failure, .empty:
                                    customerMonogram
                                @unknown default:
                                    customerMonogram
                                }
                            }
                        } else {
                            customerMonogram
                        }

                        // Active Presence Ring Dot
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(uiColor: .ppSurface), lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }

                    // Name & Identity Column
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(viewModel.customerName.isEmpty ? viewModel.title : viewModel.customerName)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)

                            if viewModel.isCustomerVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(uiColor: .ppInfo))
                            }
                        }

                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(uiColor: .ppSuccess))
                                .frame(width: 6, height: 6)

                            if !viewModel.customerPhone.isEmpty {
                                Text(viewModel.customerPhone)
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            } else {
                                Text(viewModel.canManage
                                     ? supportText("SupportChats_SupportReady", "صلاحية الرد الرسمي مفعّلة")
                                     : supportText("SupportChats_ReadOnly", "عرض فقط"))
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.customerName)
            .accessibilityHint(supportText("SupportChats_ViewCustomerHint", "انقر لعرض ملف العميل."))

            Spacer(minLength: 4)

            // 3. Trailing Status Capsule Dropdown Menu
            statusMenu
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(AdminSurface.surface.opacity(0.85).background(.ultraThinMaterial))
    }

    private var customerMonogram: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(uiColor: .ppPrimary).opacity(0.85),
                            Color(red: 0.94, green: 0.44, blue: 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 42, height: 42)

            Text(monogramLetters)
                .font(AdminType.subheadlineBold)
                .foregroundColor(.white)
        }
    }

    private var monogramLetters: String {
        let name = viewModel.customerName.isEmpty ? viewModel.title : viewModel.customerName
        let parts = name.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first, let second = parts[1].first {
            return "\(first)\(second)"
        } else if let first = name.first {
            return String(first)
        }
        return "P"
    }

    private var statusMenu: some View {
        Menu {
            ForEach(SupportStatus.selectable, id: \.self) { candidate in
                Button {
                    viewModel.transition(to: candidate)
                } label: {
                    if candidate == viewModel.status {
                        Label(candidate.title, systemImage: "checkmark")
                    } else {
                        Text(candidate.title)
                    }
                }
                .disabled(!viewModel.status.canTransition(to: candidate) || candidate == viewModel.status)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: viewModel.status.symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(viewModel.status.title)
                    .font(AdminType.caption2Bold)
                    .lineLimit(1)
                if viewModel.canManage {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundColor(viewModel.status.tint)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(viewModel.status.tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(viewModel.status.tint.opacity(0.35)))
        }
        .disabled(!viewModel.canManage || viewModel.isUpdatingStatus || viewModel.isSending)
        .accessibilityLabel(supportText("SupportChats_StatusSelector", "حالة المحادثة"))
        .accessibilityValue(viewModel.status.title)
        .accessibilityHint(viewModel.canManage
                           ? supportText("SupportChats_StatusSelectorHint", "اختر حالة الدعم التالية.")
                           : supportText("SupportChats_ReadOnly", "عرض فقط"))
    }
}

// MARK: - Reimagined Chat Context Flight Deck (HUD)

private struct SupportChatContextFlightDeck: View {
    @ObservedObject var viewModel: AdminSupportThreadViewModel
    @State private var copiedNotice = false

    var body: some View {
        if let context = viewModel.chatContext {
            VStack(spacing: 0) {
                // Docked Compact Strip
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        viewModel.isContextExpanded.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 10) {
                        // Category Icon Badge with Ambient Breathing Glow
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(context.category.accentColor.opacity(0.14))
                                .frame(width: 34, height: 34)
                            Image(systemName: context.category.iconName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(context.category.accentColor)
                        }

                        // Summary Text Block
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(context.title)
                                    .font(AdminType.captionBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                    .lineLimit(1)

                                Text(context.category.localizedCategoryName)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(context.category.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(context.category.accentColor.opacity(0.12), in: Capsule())
                            }

                            HStack(spacing: 5) {
                                Text(context.primaryMetric)
                                    .font(AdminType.caption2Bold)
                                    .foregroundColor(context.category.accentColor)

                                Text("•")
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.secondaryText.opacity(0.5))

                                Text(context.statusText)
                                    .font(AdminType.caption2)
                                    .foregroundColor(context.statusColor)

                                if !context.platform.isEmpty {
                                    Text("•")
                                        .font(AdminType.caption2)
                                        .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                                    Text(context.platform)
                                        .font(AdminType.caption2)
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                            }
                        }

                        Spacer(minLength: 4)

                        // Expand Chevron Indicator
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AdminSurface.secondaryText)
                            .rotationEffect(.degrees(viewModel.isContextExpanded ? 180 : 0))
                            .frame(width: 24, height: 24)
                            .background(AdminSurface.hairline.opacity(0.4), in: Circle())
                    }
                    .padding(.horizontal, AdminSpacing.md)
                    .padding(.vertical, 7)
                }
                .buttonStyle(PlainButtonStyle())

                // Expanded Spatial Dossier Content
                if viewModel.isContextExpanded {
                    VStack(spacing: 12) {
                        Divider().background(AdminSurface.hairline)

                        // 2x2 Matrix of Key Data
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(context.metadataItems) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.label)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(AdminSurface.secondaryText)
                                    Text(item.value)
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.primaryText)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AdminSurface.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                            }
                        }

                        // Action Toolbar
                        HStack(spacing: 8) {
                            // Copy Reference Button
                            Button {
                                UIPasteboard.general.string = context.referenceId
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                withAnimation { copiedNotice = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                    withAnimation { copiedNotice = false }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedNotice ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(copiedNotice ? supportText("Copied", "تم النسخ ✓") : supportText("SupportContext_CopyRef", "نسخ المرجع"))
                                        .font(AdminType.caption2Bold)
                                }
                                .foregroundColor(copiedNotice ? Color(uiColor: .ppSuccess) : AdminSurface.primaryText)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(AdminSurface.surface, in: Capsule())
                                .overlay(Capsule().stroke(copiedNotice ? Color(uiColor: .ppSuccess) : AdminSurface.hairline))
                            }

                            // Customer Call Button (if phone available)
                            if !viewModel.customerPhone.isEmpty {
                                Button {
                                    if let url = URL(string: "tel:\(viewModel.customerPhone)"), UIApplication.shared.canOpenURL(url) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "phone.fill")
                                            .font(.system(size: 11, weight: .bold))
                                        Text(supportText("SupportContext_CallCustomer", "اتصال"))
                                            .font(AdminType.caption2Bold)
                                    }
                                    .foregroundColor(Color(uiColor: .ppSuccess))
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                                    .overlay(Capsule().stroke(Color(uiColor: .ppSuccess).opacity(0.3)))
                                }
                            }

                            Spacer()

                            // Full Preview Sheet Trigger
                            Button {
                                viewModel.isShowingContextDetail = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(supportText("SupportContext_ViewFull", "معاينة كاملة"))
                                        .font(AdminType.caption2Bold)
                                }
                                .foregroundColor(context.category.accentColor)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(context.category.accentColor.opacity(0.12), in: Capsule())
                                .overlay(Capsule().stroke(context.category.accentColor.opacity(0.3)))
                            }
                        }
                    }
                    .padding(.horizontal, AdminSpacing.md)
                    .padding(.bottom, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AdminSurface.control.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        context.category.accentColor.opacity(0.35),
                                        AdminSurface.hairline
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
            )
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }
}

// MARK: - Customer Quick Dossier Modal Sheet

@available(iOS 16.0, *)
private struct CustomerQuickDossierSheet: View {
    @ObservedObject var viewModel: AdminSupportThreadViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Avatar & Hero Name
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(uiColor: .ppPrimary), Color(red: 0.94, green: 0.44, blue: 0.28)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 76, height: 76)
                                .shadow(color: Color(uiColor: .ppPrimary).opacity(0.3), radius: 12, x: 0, y: 6)

                            if !viewModel.customerAvatarUrl.isEmpty, let url = URL(string: viewModel.customerAvatarUrl) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill().frame(width: 76, height: 76).clipShape(Circle())
                                    } else {
                                        monogramLarge
                                    }
                                }
                            } else {
                                monogramLarge
                            }
                        }

                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Text(viewModel.customerName.isEmpty ? viewModel.title : viewModel.customerName)
                                    .font(AdminType.title3)
                                    .foregroundColor(AdminSurface.primaryText)

                                if viewModel.isCustomerVerified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(Color(uiColor: .ppInfo))
                                }
                            }

                            Text(String(format: supportText("SupportDossier_ID_Format", "معرف العميل: %@"), viewModel.customerID))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                    .padding(.top, 16)

                    // Quick Action Buttons (Call / WhatsApp / Copy ID)
                    HStack(spacing: 12) {
                        if !viewModel.customerPhone.isEmpty {
                            Button {
                                if let url = URL(string: "tel:\(viewModel.customerPhone)"), UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label(supportText("Call", "اتصال"), systemImage: "phone.fill")
                                    .font(AdminType.subheadlineBold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color(uiColor: .ppSuccess), in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundColor(.white)
                            }

                            Button {
                                let clean = viewModel.customerPhone.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: " ", with: "")
                                if let url = URL(string: "https://wa.me/\(clean)"), UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label(supportText("WhatsApp", "واتساب"), systemImage: "message.fill")
                                    .font(AdminType.subheadlineBold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color(red: 0.15, green: 0.78, blue: 0.45), in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundColor(.white)
                            }
                        }

                        Button {
                            UIPasteboard.general.string = viewModel.customerID
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            Label(supportText("CopyID", "نسخ المعرف"), systemImage: "doc.on.doc")
                                .font(AdminType.subheadlineBold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundColor(AdminSurface.primaryText)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AdminSurface.hairline))
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)

                    // Profile Attributes List
                    VStack(spacing: 1) {
                        dossierRow(icon: "phone.circle.fill", label: supportText("Phone", "رقم الجوال"), value: viewModel.customerPhone.isEmpty ? supportText("NotAvailable", "غير متوفر") : viewModel.customerPhone)
                        dossierRow(icon: "envelope.circle.fill", label: supportText("Email", "البريد الإلكتروني"), value: viewModel.customerEmail.isEmpty ? supportText("NotAvailable", "غير متوفر") : viewModel.customerEmail)
                        dossierRow(icon: "calendar.circle.fill", label: supportText("Joined", "تاريخ الانضمام"), value: viewModel.customerJoinDate.isEmpty ? supportText("NotAvailable", "غير متوفر") : viewModel.customerJoinDate)
                        dossierRow(icon: "shield.lefthalf.filled", label: supportText("Status", "حالة الحساب"), value: viewModel.isCustomerVerified ? supportText("Verified", "موثق ✓") : supportText("Active", "نشط"))
                    }
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AdminSurface.hairline))
                    .padding(.horizontal, AdminSpacing.screenMargin)
                }
                .padding(.vertical, 16)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(supportText("CustomerProfile", "ملف العميل"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(supportText("Close", "إغلاق")) { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var monogramLarge: some View {
        Text(viewModel.customerName.prefix(1).uppercased())
            .font(.system(size: 32, weight: .bold))
            .foregroundColor(.white)
    }

    private func dossierRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(uiColor: .ppPrimary))
                .frame(width: 28)
            Text(label)
                .font(AdminType.subheadline)
                .foregroundColor(AdminSurface.secondaryText)
            Spacer()
            Text(value)
                .font(AdminType.subheadlineBold)
                .foregroundColor(AdminSurface.primaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Support Context Detail Modal Sheet

@available(iOS 16.0, *)
private struct SupportContextDetailSheet: View {
    let context: SupportChatContextDescriptor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header card
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(context.category.accentColor.opacity(0.15))
                                .frame(width: 64, height: 64)
                            Image(systemName: context.category.iconName)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(context.category.accentColor)
                        }

                        Text(context.title)
                            .font(AdminType.title3)
                            .foregroundColor(AdminSurface.primaryText)
                            .multilineTextAlignment(.center)

                        Text(context.category.localizedCategoryName)
                            .font(AdminType.caption2Bold)
                            .foregroundColor(context.category.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(context.category.accentColor.opacity(0.12), in: Capsule())
                    }
                    .padding(.top, 16)

                    // Metadata Matrix Table
                    VStack(spacing: 1) {
                        ForEach(context.metadataItems) { item in
                            HStack {
                                Text(item.label)
                                    .font(AdminType.subheadline)
                                    .foregroundColor(AdminSurface.secondaryText)
                                Spacer()
                                Text(item.value)
                                    .font(AdminType.subheadlineBold)
                                    .foregroundColor(AdminSurface.primaryText)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AdminSurface.hairline))
                    .padding(.horizontal, AdminSpacing.screenMargin)

                    // Action Button
                    VStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = context.referenceId
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            Label(supportText("SupportContext_CopyRef", "نسخ المعرف المرجعي"), systemImage: "doc.on.doc")
                                .font(AdminType.subheadlineBold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                }
                .padding(.vertical, 16)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(supportText("SupportContext_DetailTitle", "تفاصيل السياق"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(supportText("Close", "إغلاق")) { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Thread View

@available(iOS 16.0, *)
struct SupportThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: AdminSupportThreadViewModel
    @FocusState private var composerFocused: Bool

    init(thread: SupportThread, currentUID: String, canManage: Bool) {
        _viewModel = StateObject(wrappedValue: AdminSupportThreadViewModel(
            thread: thread,
            currentUID: currentUID,
            canManage: canManage
        ))
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. Redesigned Top Bar with Name & Avatar
                SupportThreadTopBar(viewModel: viewModel, onBack: { dismiss() })

                // 2. Reimagined Chat Context Flight Deck HUD
                SupportChatContextFlightDeck(viewModel: viewModel)

                Divider().background(AdminSurface.hairline)

                // 3. Message Timeline
                timeline
            }

            if viewModel.isUpdatingStatus {
                AdminLoadingOverlay(message: supportText("SupportChats_StatusUpdating", "جارٍ تحديث حالة المحادثة…"))
                    .background(Color.black.opacity(0.08))
                    .accessibilityAddTraits(.isModal)
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .sheet(isPresented: $viewModel.isShowingCustomerDossier) {
            CustomerQuickDossierSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingContextDetail) {
            if let context = viewModel.chatContext {
                SupportContextDetailSheet(context: context)
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .alert(
            supportText("Error_Title", "خطأ"),
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            )
        ) {
            Button(supportText("OK", "موافق")) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    // MARK: Timeline

    @ViewBuilder
    private var timeline: some View {
        if viewModel.isLoading && viewModel.messages.isEmpty {
            VStack(spacing: AdminSpacing.md) {
                ProgressView().tint(AdminSurface.primary)
                Text(supportText("SupportChats_MessagesLoading", "جارٍ تحميل الرسائل…"))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.hasMessagesError {
            VStack(spacing: AdminSpacing.md) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                Text(supportText("SupportChats_MessagesError", "تعذر تحميل هذه المحادثة."))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                Button {
                    viewModel.listenMessages()
                } label: {
                    Text(supportText("TryAgain", "إعادة المحاولة"))
                        .font(AdminType.captionBold)
                        .padding(.horizontal, AdminSpacing.lg)
                        .frame(minHeight: AdminTouchTarget.minimum)
                }
                .buttonStyle(.borderedProminent)
                .tint(AdminSurface.primary)
            }
            .padding(.horizontal, AdminSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.messages.isEmpty {
            VStack(spacing: AdminSpacing.sm) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                Text(supportText("SupportChats_MessagesEmpty", "لا توجد رسائل بعد."))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AdminSpacing.sm) {
                        ForEach(viewModel.messages) { message in
                            SupportMessageBubble(message: message)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id(supportTimelineAnchor)
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.vertical, AdminSpacing.md)
                }
                .onAppear { scrollToEnd(proxy, animated: false) }
                .onChange(of: viewModel.messages.count) { _ in
                    scrollToEnd(proxy, animated: !reduceMotion)
                }
            }
        }
    }

    private var supportTimelineAnchor: String { "pp.support.timeline.end" }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !viewModel.messages.isEmpty else { return }
        if animated {
            withAnimation(AdminAnimation.standard) {
                proxy.scrollTo(supportTimelineAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(supportTimelineAnchor, anchor: .bottom)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: AdminSpacing.xs) {
            HStack(spacing: AdminSpacing.sm) {
                TextField(
                    viewModel.composerPlaceholder,
                    text: $viewModel.draft
                )
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.primaryText)
                .focused($composerFocused)
                .submitLabel(.send)
                .disabled(!viewModel.canManage || !viewModel.allowsReply || viewModel.isSending || viewModel.isUpdatingStatus)
                .padding(.horizontal, AdminSpacing.md)
                .frame(minHeight: AdminTouchTarget.minimum)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.large))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.large).stroke(AdminSurface.hairline))
                .opacity(viewModel.isSending ? 0.68 : 1)
                .onSubmit { viewModel.send() }

                Button {
                    composerFocused = false
                    viewModel.send()
                } label: {
                    Image(systemName: viewModel.isSending ? "ellipsis" : "paperplane.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                        .background(AdminSurface.primary, in: Circle())
                }
                .disabled(!viewModel.canSend)
                .opacity(viewModel.canSend ? 1 : 0.42)
                .accessibilityLabel(supportText("SupportChats_Send", "إرسال"))
                .accessibilityHint(supportText("SupportChats_SendHint", "يُرسل هذا الرد باسم دعم بيور بتس الرسمي."))
            }

            if viewModel.canManage && !viewModel.allowsReply {
                Text(supportText("SupportChats_ReopenToReply", "اضبط الحالة على نشطة قبل الرد."))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.sm)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Message Bubble

private struct SupportMessageBubble: View {
    let message: SupportMessage

    var body: some View {
        HStack {
            if message.isOfficial { Spacer(minLength: 40) }

            VStack(alignment: message.isOfficial ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(message.isOfficial ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text(message.isOfficial
                         ? supportText("SupportChats_MessageOfficial", "دعم بيور بتس الرسمي")
                         : supportText("SupportChats_MessageCustomer", "العميل"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.9))
                    if !message.relativeDate.isEmpty {
                        Text("·")
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                        Text(message.relativeDate)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.9))
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, AdminSpacing.sm)
            .background(
                message.isOfficial
                    ? AdminSurface.primary.opacity(0.14)
                    : AdminSurface.surface,
                in: RoundedRectangle(cornerRadius: AdminRadius.large)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.large)
                    .stroke(message.isOfficial ? AdminSurface.primary.opacity(0.22) : AdminSurface.hairline)
            )

            if !message.isOfficial { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(message.isOfficial ? supportText("SupportChats_MessageOfficial", "دعم بيور بتس الرسمي") : supportText("SupportChats_MessageCustomer", "العميل")). \(message.text). \(message.relativeDate)")
    }
}
