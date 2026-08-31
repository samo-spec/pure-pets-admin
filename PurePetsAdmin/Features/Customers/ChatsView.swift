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
        .fullScreenCover(item: $selectedThread) { thread in
            SupportThreadView(
                thread: thread,
                currentUID: viewModel.currentUID,
                canManage: viewModel.canManage
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: Header

    private var headerPill: some View {
        HStack(spacing: AdminSpacing.sm) {
            Button {
                if let onDismiss { onDismiss() } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 38, height: 38)
                    .background(AdminSurface.control, in: Circle())
            }
            .accessibilityLabel(supportText("Close", "إغلاق"))

            VStack(alignment: .leading, spacing: 0) {
                Text(supportText("CommandCenter_Customers_Workspace", "مساحة العملاء"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
                Text(supportText("Chats", "المحادثات"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.canManage && !viewModel.accessDenied {
                Text(supportText("SupportChats_ReadOnly", "عرض فقط"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 26)
                    .background(AdminSurface.control, in: Capsule())
                    .overlay(Capsule().stroke(AdminSurface.hairline))
            }
        }
        .padding(.horizontal, AdminSpacing.sm)
        .padding(.vertical, AdminSpacing.sm)
        .frame(maxHeight: 58)
        .background(AdminSurface.surface, in: Capsule())
        .overlay(Capsule().stroke(AdminSurface.hairline))
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
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
                let projected = SupportThread(
                    data: snapshot.data() ?? [:],
                    documentID: snapshot.documentID,
                    currentUID: uid
                )
                Task { @MainActor in
                    guard let self else { return }
                    self.status = projected.status
                    self.lifecycleVersion = projected.lifecycleVersion
                    self.title = projected.displayName
                    self.lastMessageID = projected.lastMessageID
                    if self.canManage && projected.supportUnread {
                        self.markRead()
                    }
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

// MARK: - Thread View

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
                threadHeader
                Divider().background(AdminSurface.hairline)
                timeline
            }

            if viewModel.isUpdatingStatus {
                AdminLoadingOverlay(message: supportText("SupportChats_StatusUpdating", "جارٍ تحديث حالة المحادثة…"))
                    .background(Color.black.opacity(0.08))
                    .accessibilityAddTraits(.isModal)
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
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

    // MARK: Header

    private var threadHeader: some View {
        VStack(spacing: AdminSpacing.sm) {
            HStack(spacing: AdminSpacing.sm) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 38, height: 38)
                        .background(AdminSurface.control, in: Circle())
                }
                .accessibilityLabel(supportText("Close", "إغلاق"))

                VStack(alignment: .leading, spacing: 0) {
                    Text(viewModel.title)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                    Text(viewModel.canManage
                         ? supportText("SupportChats_SupportReady", "صلاحية الرد الرسمي مفعّلة.")
                         : supportText("SupportChats_ReadOnly", "عرض فقط"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                statusMenu
            }

            Text(supportText("SupportChats_ChannelDetail", "قناة دعم العملاء الرسمية"))
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.md)
    }

    /// A menu at every text size — replaces the legacy segmented-control /
    /// menu-button swap, and disables illegal transitions up front instead of
    /// letting the operator pick one and silently reverting.
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
            .padding(.horizontal, AdminSpacing.md)
            .frame(minHeight: 34)
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
