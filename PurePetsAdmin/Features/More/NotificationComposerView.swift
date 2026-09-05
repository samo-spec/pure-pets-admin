//
//  NotificationComposerView.swift
//  PurePetsAdmin
//
//  Created from absolute first principles.
//  Category-defining Push Notification Studio & Sovereign Broadcast Command Center.
//

import SwiftUI
import UIKit

// MARK: - Notification Template Model

struct AdminNotificationTemplate: Identifiable {
    let id = UUID()
    let icon: String
    let titleAr: String
    let titleEn: String
    let bodyAr: String
    let bodyEn: String
    let type: PPNotificationType
    let audience: PPNotificationAudience
    let badgeTextAr: String
    let badgeTextEn: String

    var localizedTitle: String { Language.isRTL() ? titleAr : titleEn }
    var localizedBody: String { Language.isRTL() ? bodyAr : bodyEn }
    var localizedBadge: String { Language.isRTL() ? badgeTextAr : badgeTextEn }
}

// MARK: - Dispatch Telemetry Receipt

struct AdminNotificationReceipt: Identifiable {
    let id = UUID()
    let idempotencyKey: String
    let recipientCount: Int
    let failureCount: Int
    let requestFailureCount: Int
    let audience: PPNotificationAudience
    let type: PPNotificationType
    let title: String
    let body: String
    let dispatchedAt: Date
}

// MARK: - Dispatch State Machine

enum AdminNotificationDispatchState: Equatable {
    case draft
    case ready
    case sending
    case success(AdminNotificationReceipt)
    case warning(String)
    case error(String)
}

// MARK: - Preview Simulator Mode

enum AdminNotificationPreviewMode: String, CaseIterable {
    case lockScreen = "LockScreen"
    case dynamicIsland = "DynamicIsland"

    var title: String {
        switch self {
        case .lockScreen:
            return Language.get("NotificationComposer_Preview_LockScreen", alter: "شاشة القفل")
        case .dynamicIsland:
            return Language.get("NotificationComposer_Preview_DynamicIsland", alter: "الجزيرة التفاعلية")
        }
    }
}

// MARK: - View Model

@MainActor
final class AdminNotificationComposerViewModel: ObservableObject {
    // Inputs
    @Published var title: String = ""
    @Published var bodyText: String = ""
    @Published var selectedType: PPNotificationType = .general
    @Published var selectedAudience: PPNotificationAudience = .everyone
    @Published var selectedUsers: [UserModel] = []

    // Directory & Picker State
    @Published var allUsers: [UserModel] = []
    @Published var isLoadingUsers: Bool = false
    @Published var isUserPickerPresented: Bool = false
    @Published var userSearchQuery: String = ""

    // UI & Simulator Controls
    @Published var previewMode: AdminNotificationPreviewMode = .lockScreen
    @Published var isTemplatesSheetPresented: Bool = false
    @Published var isBroadcastConfirmPresented: Bool = false
    @Published var dispatchState: AdminNotificationDispatchState = .draft

    // Maximum server recipient constraint
    static let maxRecipientsLimit: Int = 500

    // Curated High-Engagement Flagship Templates
    let templates: [AdminNotificationTemplate] = [
        AdminNotificationTemplate(
            icon: "tag.fill",
            titleAr: "خصم خاص 20% على جميع مستلزمات الحيوانات!",
            titleEn: "Exclusive 20% Off All Pet Supplies!",
            bodyAr: "استمتع بعروض نهاية الأسبوع المميزة في جميع فروع بيور بيتس وعبر التطبيق. العرض سارٍ حتى نفاد الكمية.",
            bodyEn: "Enjoy special weekend discounts across all Pure Pets branches and in-app. Limited time offer!",
            type: .general,
            audience: .allUsers,
            badgeTextAr: "عرض ترويجي",
            badgeTextEn: "Promotion"
        ),
        AdminNotificationTemplate(
            icon: "shippingbox.fill",
            titleAr: "طلبك جاهز للاستلام الآن!",
            titleEn: "Your Order is Ready for Pickup!",
            bodyAr: "تم تجهيز عناصر طلبك بعناية فائقة. يمكنك التفضل بزيارة الفرع لاستلامه في أي وقت يناسبك.",
            bodyEn: "Your order has been carefully prepared. You can visit our branch to pick it up anytime today.",
            type: .order,
            audience: .specificUsers,
            badgeTextAr: "جاهزية الطلب",
            badgeTextEn: "Order Ready"
        ),
        AdminNotificationTemplate(
            icon: "doc.text.magnifyingglass",
            titleAr: "تم اعتماد إعلانك الخاص بنجاح",
            titleEn: "Your Pet Listing is Approved!",
            bodyAr: "أهلاً بك! تمت مراجعة إعلانك واعتماده من فريق الإشراف، وهو متاح الآن لجميع زوار المنصة.",
            bodyEn: "Welcome! Your pet listing has been verified and approved. It is now live to all platform visitors.",
            type: .adReview,
            audience: .specificUsers,
            badgeTextAr: "مراجعة الإعلانات",
            badgeTextEn: "Listing Review"
        ),
        AdminNotificationTemplate(
            icon: "exclamationmark.triangle.fill",
            titleAr: "تحديث مجدول لتحسين خدمات بيور بيتس",
            titleEn: "Scheduled Platform Maintenance Notice",
            bodyAr: "نقوم بأعمال صيانة مجدولة الليلة من 2:00 إلى 3:00 صباحاً لتطوير البنية التحتية وتقديم أفضل سرعة واستقرار.",
            bodyEn: "We are running scheduled infrastructure maintenance tonight from 2:00 to 3:00 AM to ensure peak performance.",
            type: .warning,
            audience: .everyone,
            badgeTextAr: "تنبيه نظام",
            badgeTextEn: "System Notice"
        ),
        AdminNotificationTemplate(
            icon: "sparkles",
            titleAr: "وصلت تشكيلة جديدة من الأغذية الممتازة!",
            titleEn: "Fresh Arrival: Premium Nutritional Diets!",
            bodyAr: "اكتشف أحدث منتجات التغذية الصحية المعتمدة لحيوانك الأليف الآن في قسم الأغذية مع توصيل فوري.",
            bodyEn: "Explore our latest certified healthy nutritional food selection with super-fast delivery to your door.",
            type: .general,
            audience: .allUsers,
            badgeTextAr: "تشكيلة جديدة",
            badgeTextEn: "New Arrival"
        )
    ]

    init() {
        prefetchUsers()
    }

    // MARK: - Validation & Reach Calculation

    var isTitleValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 100
    }

    var isBodyValid: Bool {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 500
    }

    var isAudienceValid: Bool {
        if selectedAudience == .specificUsers {
            return !selectedUsers.isEmpty && selectedUsers.count <= Self.maxRecipientsLimit
        }
        return true
    }

    var canDispatch: Bool {
        isTitleValid && isBodyValid && isAudienceValid && !isSending
    }

    var isSending: Bool {
        if case .sending = dispatchState { return true }
        return false
    }

    var estimatedReachCountString: String {
        switch selectedAudience {
        case .everyone:
            return Language.isRTL() ? "~4,500+ جهاز نشط" : "~4,500+ Active Devices"
        case .allUsers:
            return Language.isRTL() ? "~3,850+ عميل مسجل" : "~3,850+ Registered Customers"
        case .admins:
            return Language.isRTL() ? "~24 عضو فريق" : "~24 Staff & Operators"
        case .specificUsers:
            let count = selectedUsers.count
            return Language.isRTL() ? "\(count) مستلم محدد" : "\(count) Target Recipients"
        @unknown default:
            return "—"
        }
    }

    var estimatedReachDescription: String {
        switch selectedAudience {
        case .everyone:
            return Language.isRTL() ? "جميع الأجهزة والمشتركين عبر iOS و Android" : "All mobile devices and subscribers across iOS & Android"
        case .allUsers:
            return Language.isRTL() ? "جميع حسابات العملاء المسجلين في التطبيق" : "All registered customer accounts in the database"
        case .admins:
            return Language.isRTL() ? "أعضاء فريق العمل ولوحة التحكم النشطين" : "Active admin and operations team members"
        case .specificUsers:
            return Language.isRTL() ? "إرسال مخصص لقائمة المستلمين المحددة فقط" : "Targeted dispatch to selected accounts only"
        @unknown default:
            return ""
        }
    }

    var statusMessage: String {
        if isSending {
            return Language.get("NotificationComposer_Status_Sending", alter: "جارٍ إرسال الإشعار الفوري...")
        }
        if !isTitleValid {
            return Language.get("NotificationComposer_Validation_TitleRequired", alter: "يرجى كتابة عنوان الإشعار")
        }
        if !isBodyValid {
            return Language.get("NotificationComposer_Validation_BodyRequired", alter: "يرجى كتابة نص محتوى الإشعار")
        }
        if selectedAudience == .specificUsers && selectedUsers.isEmpty {
            return Language.get("NotificationComposer_Status_SelectRecipients", alter: "اختر مستلمًا واحدًا على الأقل")
        }
        return Language.get("NotificationComposer_Status_Ready", alter: "جاهز للبث — اضغط للإرسال الفوري")
    }

    // MARK: - Actions

    func prefetchUsers() {
        guard allUsers.isEmpty, !isLoadingUsers else { return }
        isLoadingUsers = true
        UserManager.shared().fetchAllUsers { [weak self] users, error in
            guard let self = self else { return }
            Task { @MainActor in
                self.isLoadingUsers = false
                if let users = users {
                    self.allUsers = users
                }
            }
        }
    }

    func applyTemplate(_ template: AdminNotificationTemplate) {
        title = template.localizedTitle
        bodyText = template.localizedBody
        selectedType = template.type
        selectedAudience = template.audience
        isTemplatesSheetPresented = false
        dispatchState = .draft

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    func resetDraft() {
        title = ""
        bodyText = ""
        selectedType = .general
        selectedAudience = .everyone
        selectedUsers = []
        dispatchState = .draft

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    func removeUser(uid: String) {
        selectedUsers.removeAll { ($0.uid ?? $0.id ?? "") == uid }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    func isUserSelected(_ user: UserModel) -> Bool {
        let uid = user.uid ?? user.id ?? ""
        guard !uid.isEmpty else { return false }
        return selectedUsers.contains { ($0.uid ?? $0.id ?? "") == uid }
    }

    func toggleUserSelection(_ user: UserModel) {
        let uid = user.uid ?? user.id ?? ""
        guard !uid.isEmpty else { return }
        if let idx = selectedUsers.firstIndex(where: { ($0.uid ?? $0.id ?? "") == uid }) {
            selectedUsers.remove(at: idx)
        } else {
            if selectedUsers.count < Self.maxRecipientsLimit {
                selectedUsers.append(user)
            }
        }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    func selectAllFilteredUsers(_ users: [UserModel]) {
        var merged = selectedUsers
        for user in users {
            let uid = user.uid ?? user.id ?? ""
            if !uid.isEmpty && !merged.contains(where: { ($0.uid ?? $0.id ?? "") == uid }) {
                if merged.count < Self.maxRecipientsLimit {
                    merged.append(user)
                }
            }
        }
        selectedUsers = merged
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    func clearUserSelection() {
        selectedUsers.removeAll()
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    // MARK: - Dispatch Flow & Safety Gate

    func handleDispatchTap() {
        guard canDispatch else { return }

        // Mass broadcast protection safety gate
        if selectedAudience == .everyone || selectedAudience == .allUsers {
            isBroadcastConfirmPresented = true
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        } else {
            executeDispatch()
        }
    }

    func executeDispatch() {
        isBroadcastConfirmPresented = false
        dispatchState = .sending

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let idempotencyKey = UUID().uuidString

        let userIDs: [String]? = (selectedAudience == .specificUsers)
            ? selectedUsers.compactMap { $0.uid ?? $0.id }.filter { !$0.isEmpty }
            : nil

        PPNotificationsManager.sendConsoleNotification(
            withTitle: trimmedTitle,
            body: trimmedBody,
            type: selectedType.rawValue,
            audience: selectedAudience,
            userIDs: userIDs,
            idempotencyKey: idempotencyKey
        ) { [weak self] response, error in
            guard let self = self else { return }

            Task { @MainActor in
                let recipientCount = (response?["recipientCount"] as? NSNumber)?.intValue ?? 0
                let failureCount = (response?["failureCount"] as? NSNumber)?.intValue ?? 0
                let requestFailureCount = (response?["requestFailureCount"] as? NSNumber)?.intValue ?? 0

                if let error = error {
                    let errDesc = error.localizedDescription
                    self.dispatchState = .error(errDesc.isEmpty ? Language.get("NotificationComposer_Failed_Message", alter: "تعذرت جدولة هذا الإشعار") : errDesc)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    return
                }

                if recipientCount == 0 && self.selectedAudience != .specificUsers {
                    let failMsg = Language.get("NotificationComposer_Failed_NoRecipients", alter: "لم يتم العثور على أجهزة نشطة لاستقبال الإشعار.")
                    self.dispatchState = .error(failMsg)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    return
                }

                let receipt = AdminNotificationReceipt(
                    idempotencyKey: idempotencyKey,
                    recipientCount: recipientCount,
                    failureCount: failureCount,
                    requestFailureCount: requestFailureCount,
                    audience: self.selectedAudience,
                    type: self.selectedType,
                    title: trimmedTitle,
                    body: trimmedBody,
                    dispatchedAt: Date()
                )

                if requestFailureCount > 0 || failureCount > 0 {
                    let warnMsg = String(
                        format: Language.get("NotificationComposer_Status_Partial", alter: "تمت جدولة الإشعار لـ %ld مستلمين. يحتاج %ld إلى مراجعة."),
                        recipientCount,
                        requestFailureCount + failureCount
                    )
                    self.dispatchState = .warning(warnMsg)
                } else {
                    self.dispatchState = .success(receipt)
                }

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
}

// MARK: - Main Sovereign View

struct AdminNotificationComposerView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminNotificationComposerViewModel()

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                sovereignNavigationBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.sectionSpacing) {
                        // ZONE 1: Dispatch Readiness Beacon & Live Reach Pulse
                        readinessBeaconAndReachSection

                        // Quick-Fire Flagship Templates Carousel
                        quickTemplatesSection

                        // ZONE 2: Audience Vector Hub (Bento Matrix)
                        audienceVectorSection

                        // Targeted Precision User Tray (if Specific selected)
                        if viewModel.selectedAudience == .specificUsers {
                            targetedRecipientTraySection
                        }

                        // ZONE 3: Payload Studio & Live Apple Simulator
                        payloadStudioSection

                        // Live iOS Lock Screen Simulation Card
                        liveSimulatorSection

                        // Extra bottom spacing so content doesn't collide with bottom dock
                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.md)
                }
            }

            // ZONE 4: Tactical Dispatch Dock (Floating Bottom Rail)
            VStack(spacing: 0) {
                Spacer()
                tacticalDispatchDock
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)

            // Success / Telemetry Receipt Overlay Modal
            if case .success(let receipt) = viewModel.dispatchState {
                AdminNotificationReceiptOverlay(receipt: receipt) {
                    viewModel.resetDraft()
                } onDismissAll: {
                    handleDismiss()
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $viewModel.isUserPickerPresented) {
            AdminRecipientPickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isTemplatesSheetPresented) {
            AdminTemplatesSheet(viewModel: viewModel)
        }
        .alert(
            Language.get("NotificationComposer_Broadcast_Confirm_Title", alter: "تأكيد إرسال إشعار عام"),
            isPresented: $viewModel.isBroadcastConfirmPresented
        ) {
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
            Button(Language.get("NotificationComposer_Action_ConfirmBroadcast", alter: "نعم، بث الإشعار الآن"), role: .destructive) {
                viewModel.executeDispatch()
            }
        } message: {
            Text(Language.get("NotificationComposer_Broadcast_Confirm_Message", alter: "أنت على وشك إرسال إشعار فوري لجميع الأجهزة النشطة في التطبيق. هل ترغب في المتابعة؟"))
        }
    }

    private func handleDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    // MARK: - Sovereign Navigation Bar

    private var sovereignNavigationBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("NotificationComposer_Title", alter: "إنشاء وإرسال الإشعارات"),
            subtitle: viewModel.estimatedReachCountString,
            statusDotColor: viewModel.canDispatch ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning),
            onBack: { handleDismiss() }
        ) {
            HStack(spacing: 8) {
                // Templates Picker Trigger
                Button {
                    viewModel.isTemplatesSheetPresented = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("NotificationComposer_Templates_Button", alter: "القوالب"))
                            .font(AdminType.caption1Bold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    .foregroundStyle(AdminSurface.primary)
                }

                // Reset Action
                Button {
                    viewModel.resetDraft()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.surface, in: Circle())
                        .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 1))
                }
                .accessibilityLabel(Language.get("NotificationComposer_Action_Reset", alter: "إعادة تعيين"))
            }
        }
    }

    // MARK: - Zone 1: Readiness Beacon & Live Reach Pulse

    private var readinessBeaconAndReachSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack(spacing: 12) {
                // Animated Pulsing Beacon
                ZStack {
                    Circle()
                        .fill(beaconColor.opacity(0.20))
                        .frame(width: 36, height: 36)
                    Circle()
                        .fill(beaconColor)
                        .frame(width: 14, height: 14)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.statusMessage)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(viewModel.estimatedReachDescription)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                // Reach Pill
                HStack(spacing: 6) {
                    Image(systemName: reachIconName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(viewModel.estimatedReachCountString)
                        .font(AdminType.caption1Bold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.surface, in: Capsule())
                .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 1))
                .foregroundStyle(AdminSurface.primaryText)
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(beaconColor.opacity(0.28), lineWidth: 1)
            )
        }
    }

    private var beaconColor: Color {
        if viewModel.isSending {
            return Color.blue
        }
        if viewModel.canDispatch {
            return Color(uiColor: .ppSuccess)
        }
        return Color(uiColor: .ppWarning)
    }

    private var reachIconName: String {
        switch viewModel.selectedAudience {
        case .everyone: return "globe.badge.chevron.backward"
        case .allUsers: return "person.2.fill"
        case .admins: return "shield.fill"
        case .specificUsers: return "person.crop.circle.badge.checkmark"
        @unknown default: return "antenna.radiowaves.left.and.right"
        }
    }

    // MARK: - Quick-Fire Flagship Templates Carousel

    private var quickTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Language.get("NotificationComposer_Templates_SectionTitle", alter: "نماذج وقوالب جاهزة"))
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.secondaryText)

                Spacer()

                Button {
                    viewModel.isTemplatesSheetPresented = true
                } label: {
                    Text(Language.get("ViewAll", alter: "عرض الكل"))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.primary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.templates) { template in
                        Button {
                            viewModel.applyTemplate(template)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: template.icon)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(colorForNotificationType(template.type))

                                Text(template.localizedBadge)
                                    .font(AdminType.caption1Bold)
                                    .foregroundStyle(AdminSurface.primaryText)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AdminSurface.hairline, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Zone 2: Audience Vector Hub (Bento Matrix)

    private var audienceVectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                Text(Language.get("NotificationComposer_Audience_SectionTitle", alter: "تحديد الجمهور المستهدف"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                // Bento Card 1: Everyone
                audienceBentoCard(
                    audience: .everyone,
                    title: Language.get("NotificationComposer_Audience_Everyone", alter: "الجميع"),
                    subtitle: Language.get("NotificationComposer_Audience_EveryoneSub", alter: "كافة الأجهزة والمشتركين"),
                    icon: "globe.badge.chevron.backward",
                    accentColor: Color.blue
                )

                // Bento Card 2: All Registered Users
                audienceBentoCard(
                    audience: .allUsers,
                    title: Language.get("NotificationComposer_Audience_AllUsers", alter: "العملاء"),
                    subtitle: Language.get("NotificationComposer_Audience_AllUsersSub", alter: "حسابات المستخدمين المسجلين"),
                    icon: "person.2.fill",
                    accentColor: Color.purple
                )

                // Bento Card 3: Admins & Staff
                audienceBentoCard(
                    audience: .admins,
                    title: Language.get("NotificationComposer_Audience_Admins", alter: "فريق الإدارة"),
                    subtitle: Language.get("NotificationComposer_Audience_AdminsSub", alter: "لوحة التحكم والعمليات"),
                    icon: "shield.lefthalf.filled",
                    accentColor: Color.orange
                )

                // Bento Card 4: Specific Targeted Users
                audienceBentoCard(
                    audience: .specificUsers,
                    title: Language.get("NotificationComposer_Audience_Specific", alter: "مستلمون محددون"),
                    subtitle: Language.get("NotificationComposer_Audience_SpecificSub", alter: "تحديد قائمة مخصصة"),
                    icon: "person.crop.circle.badge.checkmark",
                    accentColor: Color(uiColor: .ppPrimary)
                )
            }
        }
    }

    private func audienceBentoCard(
        audience: PPNotificationAudience,
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color
    ) -> some View {
        let isSelected = viewModel.selectedAudience == audience

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                viewModel.selectedAudience = audience
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? accentColor.opacity(0.20) : AdminSurface.background)
                            .frame(width: 36, height: 36)

                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isSelected ? accentColor : AdminSurface.secondaryText)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(accentColor)
                    } else {
                        Circle()
                            .stroke(AdminSurface.hairline, lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? accentColor.opacity(0.06) : AdminSurface.surface,
                in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(isSelected ? accentColor : AdminSurface.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Targeted Precision User Tray

    private var targetedRecipientTraySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Language.get("NotificationComposer_SelectedRecipients", alter: "المستلمون المختارون"))
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.secondaryText)

                Spacer()

                Text("\(viewModel.selectedUsers.count) / \(AdminNotificationComposerViewModel.maxRecipientsLimit)")
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(viewModel.selectedUsers.isEmpty ? Color(uiColor: .ppWarning) : AdminSurface.primary)
            }

            if viewModel.selectedUsers.isEmpty {
                Button {
                    viewModel.isUserPickerPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)

                        Text(Language.get("NotificationComposer_AddRecipientsPrompt", alter: "اضغط هنا لاختيار المستلمين من دليل المستخدمين"))
                            .font(AdminType.callout)
                            .foregroundStyle(AdminSurface.primaryText)

                        Spacer()
                    }
                    .padding(AdminSpacing.cardPadding)
                    .frame(maxWidth: .infinity)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .stroke(AdminSurface.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    )
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Add more button chip
                            Button {
                                viewModel.isUserPickerPresented = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(Language.get("Add", alter: "إضافة"))
                                        .font(AdminType.caption1Bold)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                                .foregroundStyle(AdminSurface.primary)
                            }

                            // Selected User Chips
                            ForEach(viewModel.selectedUsers, id: \.self) { user in
                                recipientChip(user: user)
                            }
                        }
                    }

                    HStack {
                        Button {
                            viewModel.clearUserSelection()
                        } label: {
                            Text(Language.get("ClearAll", alter: "مسح الكل"))
                                .font(AdminType.caption)
                                .foregroundStyle(Color.red)
                        }

                        Spacer()

                        Button {
                            viewModel.isUserPickerPresented = true
                        } label: {
                            Text(Language.get("NotificationComposer_ManageRecipients", alter: "إدارة القائمة"))
                                .font(AdminType.captionBold)
                                .foregroundStyle(AdminSurface.primary)
                        }
                    }
                }
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func recipientChip(user: UserModel) -> some View {
        let displayName = user.ppBestDisplayName()
        let name = !displayName.isEmpty ? displayName : (user.userName ?? user.displayName ?? "مستخدم")
        let uid = user.uid ?? user.id ?? ""

        return HStack(spacing: 6) {
            Circle()
                .fill(AdminSurface.primary.opacity(0.2))
                .frame(width: 22, height: 22)
                .overlay(
                    Text(String(name.prefix(1)))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                )

            Text(name)
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)

            Button {
                viewModel.removeUser(uid: uid)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(AdminSurface.background, in: Capsule())
        .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 1))
    }

    // MARK: - Zone 3: Payload Studio

    private var payloadStudioSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                Text(Language.get("NotificationComposer_Payload_SectionTitle", alter: "محتوى وتصنيف الإشعار"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()
            }

            // Notification Category Selector Pills
            HStack(spacing: 8) {
                categoryPill(type: .general, title: Language.get("General", alter: "عام"), icon: "bell.badge.fill", color: Color.blue)
                categoryPill(type: .order, title: Language.get("Order", alter: "الطلبات"), icon: "shippingbox.fill", color: Color.green)
                categoryPill(type: .adReview, title: Language.get("AdReview", alter: "الإعلانات"), icon: "doc.text.magnifyingglass", color: Color.purple)
                categoryPill(type: .warning, title: Language.get("Warning", alter: "تنبيه"), icon: "exclamationmark.triangle.fill", color: Color.orange)
            }

            // Title Input Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Language.get("Title", alter: "عنوان الإشعار"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    Spacer()

                    Text("\(viewModel.title.count)/65")
                        .font(AdminType.caption2)
                        .foregroundStyle(viewModel.title.count > 65 ? Color.orange : AdminSurface.secondaryText)
                }

                HStack {
                    TextField(
                        Language.get("NotificationComposer_TitlePlaceholder", alter: "اكتب عنواناً جذاباً ومختصراً..."),
                        text: $viewModel.title
                    )
                    .font(AdminType.bodyBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .submitLabel(.next)

                    if !viewModel.title.isEmpty {
                        Button {
                            viewModel.title = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                }
                .padding(12)
                .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(viewModel.title.isEmpty ? AdminSurface.hairline : AdminSurface.primary.opacity(0.4), lineWidth: 1)
                )
            }

            // Body Multi-line Input Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Language.get("Body", alter: "نص الرسالة"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    Spacer()

                    Text("\(viewModel.bodyText.count)/250")
                        .font(AdminType.caption2)
                        .foregroundStyle(viewModel.bodyText.count > 250 ? Color.orange : AdminSurface.secondaryText)
                }

                ZStack(alignment: .topLeading) {
                    if viewModel.bodyText.isEmpty {
                        Text(Language.get("NotificationComposer_BodyPlaceholder", alter: "اكتب تفاصيل الإشعار بوضوح هنا، ليظهر للعميل عند فتح الإشعار أو على شاشة القفل..."))
                            .font(AdminType.callout)
                            .foregroundStyle(AdminSurface.secondaryText.opacity(0.7))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $viewModel.bodyText)
                        .font(AdminType.body)
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(minHeight: 88)
                        .scrollContentBackground(.hidden)
                }
                .padding(10)
                .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(viewModel.bodyText.isEmpty ? AdminSurface.hairline : AdminSurface.primary.opacity(0.4), lineWidth: 1)
                )
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func categoryPill(
        type: PPNotificationType,
        title: String,
        icon: String,
        color: Color
    ) -> some View {
        let isSelected = viewModel.selectedType == type

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedType = type
            }
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isSelected ? color : AdminSurface.secondaryText)

                Text(title)
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? color.opacity(0.12) : AdminSurface.background,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? color : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func colorForNotificationType(_ type: PPNotificationType) -> Color {
        switch type {
        case .general: return Color.blue
        case .order: return Color.green
        case .adReview: return Color.purple
        case .warning: return Color.orange
        @unknown default: return AdminSurface.primary
        }
    }

    // MARK: - Live Apple Lock Screen Simulator

    private var liveSimulatorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                Text(Language.get("NotificationComposer_Simulator_Title", alter: "محاكي شاشة القفل التفاعلي"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                // Live Indicator Dot
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(Language.get("LivePreview", alter: "معاينة فورية"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            // Apple iOS Lock Screen Simulation Frame
            ZStack {
                // Realistic iOS Wallpaper Blur Simulation Surface
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.10, green: 0.12, blue: 0.20),
                        Color(red: 0.18, green: 0.22, blue: 0.32)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(minHeight: 154)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                // Apple Lock Screen Push Notification Card
                VStack(alignment: .leading, spacing: 8) {
                    // Row 1: App Header + Timestamp
                    HStack(spacing: 8) {
                        // PurePets App Icon Squircle
                        ZStack {
                            LinearGradient(
                                colors: [Color(uiColor: .ppPrimary), Color.indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Text("PURE PETS")
                            .font(.system(size: 12, weight: .bold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .tracking(0.5)

                        Text("•")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.6))

                        Text(Language.isRTL() ? "الآن" : "now")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(Color.white.opacity(0.6))

                        Spacer()

                        // Category Pill in Simulator
                        Text(categoryNameString(viewModel.selectedType))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colorForNotificationType(viewModel.selectedType).opacity(0.35), in: Capsule())
                            .foregroundStyle(Color.white)
                    }

                    // Row 2: Title (Real-time typed)
                    Text(viewModel.title.isEmpty ? (Language.isRTL() ? "عنوان الإشعار يظهر هنا..." : "Notification Title Appears Here...") : viewModel.title)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(viewModel.title.isEmpty ? Color.white.opacity(0.45) : Color.white)
                        .lineLimit(2)

                    // Row 3: Body (Real-time typed)
                    Text(viewModel.bodyText.isEmpty ? (Language.isRTL() ? "نص الرسالة الترويجية أو التنبيهية سيظهر للمستخدم بهذا الشكل على شاشته..." : "Your promotional message or alert content will be rendered on the lock screen...") : viewModel.bodyText)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(viewModel.bodyText.isEmpty ? Color.white.opacity(0.35) : Color.white.opacity(0.85))
                        .lineLimit(3)
                        .lineSpacing(2)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.92)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
                .padding(12)
            }
            .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 5)

            // Simulator Caption
            Text(Language.get("NotificationComposer_Simulator_Hint", alter: "تنعكس الحقول المكتوبة مباشرةً وبدقة البكسل كما ستظهر على هواتف المستخدمين بنظام iOS."))
                .font(AdminType.caption2)
                .foregroundStyle(AdminSurface.secondaryText)
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func categoryNameString(_ type: PPNotificationType) -> String {
        switch type {
        case .general: return Language.isRTL() ? "عام" : "General"
        case .order: return Language.isRTL() ? "طلب" : "Order"
        case .adReview: return Language.isRTL() ? "إعلان" : "Listing"
        case .warning: return Language.isRTL() ? "تنبيه" : "Alert"
        @unknown default: return ""
        }
    }

    // MARK: - Zone 4: Tactical Dispatch Dock

    private var tacticalDispatchDock: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AdminSurface.hairline)

            HStack(spacing: 12) {
                // Live Status Text & Recipient summary
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.statusMessage)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(viewModel.canDispatch ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .lineLimit(1)

                    Text(viewModel.estimatedReachCountString)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                // High-Tactile Dispatch Button
                Button {
                    viewModel.handleDispatchTap()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 15, weight: .bold))
                        }

                        Text(viewModel.isSending ? Language.get("NotificationComposer_Action_Sending", alter: "جارٍ الإرسال...") : Language.get("NotificationComposer_Action_Send", alter: "بث الإشعار الآن"))
                            .font(AdminType.headline)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .background(
                        viewModel.canDispatch ? AdminSurface.primary : AdminSurface.primary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                    )
                    .foregroundStyle(Color.white)
                    .shadow(color: viewModel.canDispatch ? AdminSurface.primary.opacity(0.32) : Color.clear, radius: 8, x: 0, y: 4)
                }
                .disabled(!viewModel.canDispatch)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .background(
                AdminSurface.surface
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }
}

// MARK: - Recipient Picker Modal Sheet

struct AdminRecipientPickerSheet: View {
    @ObservedObject var viewModel: AdminNotificationComposerViewModel
    @Environment(\.dismiss) private var dismiss

    var filteredUsers: [UserModel] {
        let q = viewModel.userSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return viewModel.allUsers }
        return viewModel.allUsers.filter { user in
            let name = (user.ppBestDisplayName()).lowercased()
            let userName = (user.userName ?? "").lowercased()
            let phone = (user.mobileNo ?? "").lowercased()
            let email = (user.userEmail ?? user.email ?? "").lowercased()
            let uid = (user.uid ?? user.id ?? "").lowercased()
            return name.contains(q) || userName.contains(q) || phone.contains(q) || email.contains(q) || uid.contains(q)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AdminSurface.secondaryText)

                        TextField(
                            Language.get("SearchUsers", alter: "بحث بالاسم أو الهاتف أو البريد أو المعرف..."),
                            text: $viewModel.userSearchQuery
                        )
                        .font(AdminType.callout)
                        .foregroundStyle(AdminSurface.primaryText)

                        if !viewModel.userSearchQuery.isEmpty {
                            Button {
                                viewModel.userSearchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                        }
                    }
                    .padding(12)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.vertical, 10)

                    // Selection Control Bar
                    HStack {
                        Text("\(filteredUsers.count) \(Language.get("UsersAvailable", alter: "مستخدم متاح")) • \(viewModel.selectedUsers.count) \(Language.get("Selected", alter: "محدد"))")
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)

                        Spacer()

                        Button {
                            viewModel.selectAllFilteredUsers(filteredUsers)
                        } label: {
                            Text(Language.get("SelectAll", alter: "تحديد الكل"))
                                .font(AdminType.captionBold)
                                .foregroundStyle(AdminSurface.primary)
                        }

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(AdminSurface.secondaryText)

                        Button {
                            viewModel.clearUserSelection()
                        } label: {
                            Text(Language.get("ClearSelection", alter: "إلغاء التحديد"))
                                .font(AdminType.caption)
                                .foregroundStyle(Color.red)
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.bottom, 8)

                    // User List
                    if viewModel.isLoadingUsers {
                        Spacer()
                        ProgressView()
                            .tint(AdminSurface.primary)
                        Spacer()
                    } else if filteredUsers.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 40))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text(Language.get("NoUsersFound", alter: "لم يتم العثور على مستخدمين"))
                                .font(AdminType.calloutBold)
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(filteredUsers, id: \.self) { user in
                                userRow(user: user)
                                    .listRowBackground(AdminSurface.surface)
                                    .listRowSeparatorTint(AdminSurface.hairline)
                            }
                        }
                        .listStyle(.plain)
                    }

                    // Bottom Confirm Action
                    VStack(spacing: 0) {
                        Divider().background(AdminSurface.hairline)

                        Button {
                            dismiss()
                        } label: {
                            Text("\(Language.get("ConfirmRecipients", alter: "تأكيد المستلمين")) (\(viewModel.selectedUsers.count))")
                                .font(AdminType.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                                .foregroundStyle(Color.white)
                        }
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.vertical, 12)
                        .background(AdminSurface.surface.ignoresSafeArea(edges: .bottom))
                    }
                }
            }
            .navigationTitle(Language.get("SelectUsers", alter: "اختيار المستلمين"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Language.get("Done", alter: "تم")) {
                        dismiss()
                    }
                    .font(AdminType.calloutBold)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func userRow(user: UserModel) -> some View {
        let isSelected = viewModel.isUserSelected(user)
        let displayName = user.ppBestDisplayName()
        let name = !displayName.isEmpty ? displayName : (user.userName ?? user.displayName ?? "مستخدم")
        let phone = user.mobileNo ?? ""
        let email = user.userEmail ?? user.email ?? ""

        return Button {
            viewModel.toggleUserSelection(user)
        } label: {
            HStack(spacing: 12) {
                // Avatar / Initials
                Circle()
                    .fill(AdminSurface.primary.opacity(0.14))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(name.prefix(1)))
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primary)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if !phone.isEmpty {
                            Text(phone)
                                .font(AdminType.caption)
                                .foregroundStyle(AdminSurface.secondaryText)
                        }

                        if !phone.isEmpty && !email.isEmpty {
                            Text("•")
                                .font(AdminType.caption2)
                                .foregroundStyle(AdminSurface.secondaryText)
                        }

                        if !email.isEmpty {
                            Text(email)
                                .font(AdminType.caption)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.4))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Curated Templates Modal Sheet

struct AdminTemplatesSheet: View {
    @ObservedObject var viewModel: AdminNotificationComposerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(viewModel.templates) { template in
                            Button {
                                viewModel.applyTemplate(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        ZStack {
                                            Circle()
                                                .fill(AdminSurface.primary.opacity(0.12))
                                                .frame(width: 32, height: 32)
                                            Image(systemName: template.icon)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(AdminSurface.primary)
                                        }

                                        Text(template.localizedBadge)
                                            .font(AdminType.captionBold)
                                            .foregroundStyle(AdminSurface.primary)

                                        Spacer()

                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                    }

                                    Text(template.localizedTitle)
                                        .font(AdminType.calloutBold)
                                        .foregroundStyle(AdminSurface.primaryText)
                                        .lineLimit(2)

                                    Text(template.localizedBody)
                                        .font(AdminType.footnote)
                                        .foregroundStyle(AdminSurface.secondaryText)
                                        .lineLimit(3)
                                }
                                .padding(AdminSpacing.cardPadding)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(AdminSpacing.screenMargin)
                }
            }
            .navigationTitle(Language.get("NotificationComposer_Templates_ModalTitle", alter: "نماذج الإشعارات السريعة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        dismiss()
                    }
                    .font(AdminType.calloutBold)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Telemetry Receipt Modal Overlay

struct AdminNotificationReceiptOverlay: View {
    let receipt: AdminNotificationReceipt
    let onNewDispatch: () -> Void
    let onDismissAll: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            VStack(spacing: 20) {
                // Success Shield Animation Graphic
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .ppSuccess).opacity(0.18))
                        .frame(width: 80, height: 80)

                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                }

                VStack(spacing: 6) {
                    Text(Language.get("NotificationComposer_Receipt_SuccessTitle", alter: "تم بث الإشعار بنجاح!"))
                        .font(AdminType.title2)
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(String(format: Language.get("NotificationComposer_Success_Message", alter: "تمت جدولة وتوصيل الإشعار لـ %ld مستلمين."), receipt.recipientCount))
                        .font(AdminType.callout)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                }

                // Telemetry Details Grid
                VStack(spacing: 8) {
                    telemetryRow(
                        label: Language.get("NotificationComposer_Receipt_Key", alter: "معرف العملية"),
                        value: String(receipt.idempotencyKey.prefix(12)).uppercased()
                    )
                    telemetryRow(
                        label: Language.get("NotificationComposer_Receipt_Recipients", alter: "الأجهزة المستهدفة"),
                        value: "\(receipt.recipientCount)"
                    )
                    if receipt.failureCount > 0 {
                        telemetryRow(
                            label: Language.get("NotificationComposer_Receipt_Pruned", alter: "أجهزة غير نشطة"),
                            value: "\(receipt.failureCount)"
                        )
                    }
                    telemetryRow(
                        label: Language.get("Time", alter: "وقت الإرسال"),
                        value: receipt.dispatchedAt.formatted(date: .omitted, time: .shortened)
                    )
                }
                .padding(14)
                .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Actions
                VStack(spacing: 10) {
                    Button {
                        onNewDispatch()
                    } label: {
                        Text(Language.get("NotificationComposer_Action_SendAnother", alter: "إنشاء إشعار آخر"))
                            .font(AdminType.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                            .foregroundStyle(Color.white)
                    }

                    Button {
                        onDismissAll()
                    } label: {
                        Text(Language.get("NotificationComposer_Action_ReturnToDashboard", alter: "العودة إلى لوحة التحكم"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(24)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 28)
        }
    }

    private func telemetryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
            Spacer()
            Text(value)
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.primaryText)
        }
    }
}
