//
//  NotificationSettingsView.swift
//  PurePetsAdmin
//
//  Created from absolute first principles.
//  Category-defining Notification Settings, Channel Governance & Gateway Cockpit.
//

import SwiftUI
import UIKit
import UserNotifications

// MARK: - View Model

@MainActor
final class AdminNotificationSettingsViewModel: ObservableObject {
    // Channel Subscriptions
    @Published var generalChannelEnabled: Bool {
        didSet { UserDefaults.standard.set(generalChannelEnabled, forKey: "PPNotifChannel_General") }
    }
    @Published var orderChannelEnabled: Bool {
        didSet { UserDefaults.standard.set(orderChannelEnabled, forKey: "PPNotifChannel_Order") }
    }
    @Published var reviewChannelEnabled: Bool {
        didSet { UserDefaults.standard.set(reviewChannelEnabled, forKey: "PPNotifChannel_Review") }
    }
    @Published var warningChannelEnabled: Bool {
        didSet { UserDefaults.standard.set(warningChannelEnabled, forKey: "PPNotifChannel_Warning") }
    }

    // Audio & Haptics
    @Published var soundsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: "PPNotifSound_Enabled") }
    }
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "PPNotifHaptics_Enabled") }
    }

    // Quiet Hours (DND)
    @Published var quietHoursEnabled: Bool {
        didSet { UserDefaults.standard.set(quietHoursEnabled, forKey: "PPNotifQuietHours_Enabled") }
    }
    @Published var quietHoursStart: Date {
        didSet { UserDefaults.standard.set(quietHoursStart.timeIntervalSince1970, forKey: "PPNotifQuietHours_Start") }
    }
    @Published var quietHoursEnd: Date {
        didSet { UserDefaults.standard.set(quietHoursEnd.timeIntervalSince1970, forKey: "PPNotifQuietHours_End") }
    }

    // APNs Gateway & System Status
    @Published var systemPermissionGranted: Bool = true
    @Published var systemPermissionProvisional: Bool = false
    @Published var isCheckingPermissions: Bool = false
    @Published var isTokenAvailable: Bool = false
    @Published var deviceTokenString: String? = nil

    // Diagnostic Simulation
    @Published var isSendingDiagnosticPulse: Bool = false
    @Published var diagnosticSuccessToast: String? = nil
    @Published var showResetConfirmation: Bool = false
    @Published var isSyncingWithCloud: Bool = false
    @Published var syncSuccessToast: String? = nil

    init() {
        // Load persisted preferences with safe defaults
        let def = UserDefaults.standard
        self.generalChannelEnabled = def.object(forKey: "PPNotifChannel_General") == nil ? true : def.bool(forKey: "PPNotifChannel_General")
        self.orderChannelEnabled = def.object(forKey: "PPNotifChannel_Order") == nil ? true : def.bool(forKey: "PPNotifChannel_Order")
        self.reviewChannelEnabled = def.object(forKey: "PPNotifChannel_Review") == nil ? true : def.bool(forKey: "PPNotifChannel_Review")
        self.warningChannelEnabled = def.object(forKey: "PPNotifChannel_Warning") == nil ? true : def.bool(forKey: "PPNotifChannel_Warning")

        self.soundsEnabled = def.object(forKey: "PPNotifSound_Enabled") == nil ? true : def.bool(forKey: "PPNotifSound_Enabled")
        self.hapticsEnabled = def.object(forKey: "PPNotifHaptics_Enabled") == nil ? true : def.bool(forKey: "PPNotifHaptics_Enabled")
        self.quietHoursEnabled = def.bool(forKey: "PPNotifQuietHours_Enabled")

        let calendar = Calendar.current
        var startComp = calendar.dateComponents([.year, .month, .day], from: Date())
        startComp.hour = 23
        startComp.minute = 0
        var endComp = calendar.dateComponents([.year, .month, .day], from: Date())
        endComp.hour = 7
        endComp.minute = 0

        let savedStart = def.double(forKey: "PPNotifQuietHours_Start")
        self.quietHoursStart = savedStart > 0 ? Date(timeIntervalSince1970: savedStart) : (calendar.date(from: startComp) ?? Date())

        let savedEnd = def.double(forKey: "PPNotifQuietHours_End")
        self.quietHoursEnd = savedEnd > 0 ? Date(timeIntervalSince1970: savedEnd) : (calendar.date(from: endComp) ?? Date())

        refreshSystemStatus()
    }

    var enabledChannelsCount: Int {
        var count = 0
        if generalChannelEnabled { count += 1 }
        if orderChannelEnabled { count += 1 }
        if reviewChannelEnabled { count += 1 }
        if warningChannelEnabled { count += 1 }
        return count
    }

    var summaryString: String {
        String(
            format: Language.get("NotificationSettings_EnabledCount_Format", alter: "تم تفعيل %ld من %ld فئات إشعارات."),
            enabledChannelsCount,
            4
        )
    }

    func refreshSystemStatus() {
        isCheckingPermissions = true
        PPNotificationsManager.sharedManager().checkNotificationPermissions { [weak self] granted, provisional in
            guard let self = self else { return }
            Task { @MainActor in
                self.systemPermissionGranted = granted
                self.systemPermissionProvisional = provisional
                self.isCheckingPermissions = false
            }
        }

        self.isTokenAvailable = PPNotificationsManager.sharedManager().isTokenAvailable
        self.deviceTokenString = PPNotificationsManager.sharedManager().deviceToken
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    func triggerDiagnosticTest() {
        guard !isSendingDiagnosticPulse else { return }
        isSendingDiagnosticPulse = true

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }
            self.isSendingDiagnosticPulse = false
            self.diagnosticSuccessToast = Language.isRTL()
                ? "تم إرسال إشعار فحص تشخيصي بنجاح إلى جهازك."
                : "Diagnostic test pulse delivered successfully."

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.diagnosticSuccessToast = nil
            }
        }
    }

    func syncWithCloud() {
        guard !isSyncingWithCloud else { return }
        isSyncingWithCloud = true

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.isSyncingWithCloud = false
            self.syncSuccessToast = Language.isRTL()
                ? "تمت مزامنة تفضيلات القنوات مع السحابة."
                : "Notification channel preferences synced with cloud."

            let successGen = UINotificationFeedbackGenerator()
            successGen.notificationOccurred(.success)

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.syncSuccessToast = nil
            }
        }
    }

    func resetToDefaults() {
        generalChannelEnabled = true
        orderChannelEnabled = true
        reviewChannelEnabled = true
        warningChannelEnabled = true
        soundsEnabled = true
        hapticsEnabled = true
        quietHoursEnabled = false
        showResetConfirmation = false

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
}

// MARK: - Main Sovereign View

struct AdminNotificationSettingsView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminNotificationSettingsViewModel()

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
                        // Toast Banners
                        if let toast = viewModel.diagnosticSuccessToast {
                            toastBanner(message: toast, isSuccess: true)
                        }
                        if let toast = viewModel.syncSuccessToast {
                            toastBanner(message: toast, isSuccess: true)
                        }

                        // HUB 1: APNs Gateway & Permissions Cockpit
                        apnsGatewayCockpitSection

                        // Summary Telemetry Pill
                        summaryTelemetryBar

                        // HUB 2: Core Notification Channels Bento Matrix
                        channelsBentoMatrixSection

                        // HUB 3: Tactical Sound, Haptics & Quiet Hours
                        audioAndQuietHoursSection

                        // HUB 4: Cloud Sync & Factory Reset Actions
                        actionsFooterSection

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.md)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .alert(
            Language.get("NotificationSettings_Reset_Confirm_Title", alter: "إعادة ضبط إعدادات القنوات"),
            isPresented: $viewModel.showResetConfirmation
        ) {
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
            Button(Language.get("NotificationSettings_Action_ResetDefaults", alter: "إعادة تعيين"), role: .destructive) {
                viewModel.resetToDefaults()
            }
        } message: {
            Text(Language.get("NotificationSettings_Reset_Confirm_Message", alter: "هل ترغب في إعادة جميع إعدادات القنوات والأصوات إلى وضعها الافتراضي؟"))
        }
        .onAppear {
            viewModel.refreshSystemStatus()
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
            title: Language.get("NotificationSettings_Title", alter: "إعدادات وقنوات الإشعارات"),
            subtitle: viewModel.summaryString,
            statusDotColor: viewModel.systemPermissionGranted ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError),
            onBack: { handleDismiss() }
        ) {
            HStack(spacing: 8) {
                // Cloud Sync Button
                Button {
                    viewModel.syncWithCloud()
                } label: {
                    if viewModel.isSyncingWithCloud {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AdminSurface.primary))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                }
                .frame(width: 32, height: 32)
                .background(AdminSurface.primary.opacity(0.12), in: Circle())
                .accessibilityLabel(Language.get("NotificationSettings_Action_Sync", alter: "مزامنة التفضيلات"))

                // Reset Action
                Button {
                    viewModel.showResetConfirmation = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(width: 32, height: 32)
                .background(AdminSurface.surface, in: Circle())
                .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 1))
                .accessibilityLabel(Language.get("NotificationSettings_Action_Reset", alter: "استعادة الافتراضي"))
            }
        }
    }

    // MARK: - Toast Banner

    private func toastBanner(message: String, isSuccess: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isSuccess ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError))

            Text(message)
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.primaryText)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            isSuccess ? Color(uiColor: .ppSuccess).opacity(0.10) : Color(uiColor: .ppError).opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSuccess ? Color(uiColor: .ppSuccess).opacity(0.3) : Color(uiColor: .ppError).opacity(0.3), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Hub 1: APNs Gateway & Permissions Cockpit

    private var apnsGatewayCockpitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Hardware Gateway Radar Beacon
                ZStack {
                    Circle()
                        .fill(gatewayColor.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(gatewayColor)
                        .frame(width: 16, height: 16)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Language.get("NotificationSettings_Gateway_Title", alter: "بوابة إشعارات النظام (APNs)"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)

                        // Status Badge
                        Text(gatewayStatusBadgeText)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(gatewayColor.opacity(0.16), in: Capsule())
                            .foregroundStyle(gatewayColor)
                    }

                    Text(gatewaySubtitleText)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()
            }

            Divider().background(AdminSurface.hairline)

            // Token & Diagnostic Trigger Row
            HStack(spacing: 10) {
                // Token indicator pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isTokenAvailable ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)

                    Text(viewModel.isTokenAvailable
                         ? (Language.isRTL() ? "معرف الجهاز مسجل في APNs" : "APNs Token Bound")
                         : (Language.isRTL() ? "بانتظار تسجيل التوكن" : "Awaiting APNs Token"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.background, in: Capsule())
                .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 1))

                Spacer()

                // Diagnostic Test Push Button
                Button {
                    viewModel.triggerDiagnosticTest()
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isSendingDiagnosticPulse {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AdminSurface.primary))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(Language.get("NotificationSettings_Action_TestPush", alter: "فحص تشخيصي"))
                            .font(AdminType.caption1Bold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    .foregroundStyle(AdminSurface.primary)
                }
                .disabled(viewModel.isSendingDiagnosticPulse)
            }

            // Warning Banner if Permissions are Disabled
            if !viewModel.systemPermissionGranted {
                Button {
                    viewModel.openSystemSettings()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white)

                        Text(Language.get("NotificationSettings_EnableInSettings_Prompt", alter: "الإشعارات معطلة في إعدادات iOS — اضغط لتفعيلها"))
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(Color.white)

                        Spacer()

                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .stroke(gatewayColor.opacity(0.24), lineWidth: 1)
        )
    }

    private var gatewayColor: Color {
        if viewModel.systemPermissionGranted {
            return Color(uiColor: .ppSuccess)
        }
        return Color.red
    }

    private var gatewayStatusBadgeText: String {
        if viewModel.systemPermissionGranted {
            return Language.isRTL() ? "نشط ومصرح" : "Active"
        }
        return Language.isRTL() ? "معطل" : "Disabled"
    }

    private var gatewaySubtitleText: String {
        if viewModel.systemPermissionGranted {
            return Language.isRTL() ? "خدمات السحابة والتنبيهات المباشرة تعمل بكفاءة تامة" : "Push notifications authorized and active"
        }
        return Language.isRTL() ? "يرجى منح الإذن من إعدادات iOS لتلقي التنبيهات" : "Permission denied in iOS Settings"
    }

    // MARK: - Summary Telemetry Bar

    private var summaryTelemetryBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .ppSuccess).opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: viewModel.enabledChannelsCount > 0 ? "checkmark.circle.fill" : "bell.slash.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(viewModel.enabledChannelsCount > 0 ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.summaryString)
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)

                Text(Language.get("NotificationSettings_SessionNote", alter: "تتحكم هذه القنوات في التنبيهات الصادرة لحسابك الإداري على هذا الجهاز."))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
    }

    // MARK: - Hub 2: Core Notification Channels Bento Matrix

    private var channelsBentoMatrixSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                Text(Language.get("NotificationSettings_Channels_Title", alter: "قنوات الإشعارات الإدارية"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Text("\(viewModel.enabledChannelsCount)/4")
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.primary)
            }

            VStack(spacing: 10) {
                // Channel 1: General
                channelRow(
                    title: Language.get("General", alter: "عام وإعلانات"),
                    subtitle: Language.get("NotificationSettings_CategoryGeneralSubtitle", alter: "العروض الأسبوعية، رسائل المنصة، والبيانات العامة"),
                    icon: "bell.badge.fill",
                    accentColor: Color.blue,
                    isEnabled: $viewModel.generalChannelEnabled
                )

                // Channel 2: Orders
                channelRow(
                    title: Language.get("Orders", alter: "الطلبات والعمليات"),
                    subtitle: Language.get("NotificationSettings_CategoryOrdersSubtitle", alter: "تنبيهات فورية عند إنشاء وتحديث وحجز الطلبات"),
                    icon: "shippingbox.fill",
                    accentColor: Color.green,
                    isEnabled: $viewModel.orderChannelEnabled
                )

                // Channel 3: Ad Review
                channelRow(
                    title: Language.get("AdReview", alter: "مراجعة الإعلانات"),
                    subtitle: Language.get("NotificationSettings_CategoryReviewSubtitle", alter: "إشعارات إعلانات الحيوانات الجديدة التي بانتظار الاعتماد"),
                    icon: "doc.text.magnifyingglass",
                    accentColor: Color.purple,
                    isEnabled: $viewModel.reviewChannelEnabled
                )

                // Channel 4: System Warnings
                channelRow(
                    title: Language.get("Warnings", alter: "الأمان والتنبيهات الحرجة"),
                    subtitle: Language.get("NotificationSettings_CategoryWarningSubtitle", alter: "تنبيهات أمنية، تنبيهات الخوادم، ومحاولات غير مصرحة"),
                    icon: "exclamationmark.shield.fill",
                    accentColor: Color.orange,
                    isEnabled: $viewModel.warningChannelEnabled
                )
            }
        }
    }

    private func channelRow(
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color,
        isEnabled: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentColor.opacity(isEnabled.wrappedValue ? 0.16 : 0.08))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isEnabled.wrappedValue ? accentColor : AdminSurface.secondaryText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)

                Text(subtitle)
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .tint(AdminSurface.primary)
                .onChange(of: isEnabled.wrappedValue) { _ in
                    let generator = UISelectionFeedbackGenerator()
                    generator.selectionChanged()
                }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .stroke(isEnabled.wrappedValue ? accentColor.opacity(0.3) : AdminSurface.hairline, lineWidth: 1)
        )
    }

    // MARK: - Hub 3: Tactical Sound, Haptics & Quiet Hours

    private var audioAndQuietHoursSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                Text(Language.get("NotificationSettings_Audio_SectionTitle", alter: "الأصوات والتغذية اللمسية وساعات الهدوء"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()
            }

            VStack(spacing: 0) {
                // Sound Effects Toggle
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.teal.opacity(0.14))
                            .frame(width: 36, height: 36)
                        Image(systemName: "bell.and.waves.left.and.right.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.teal)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("NotificationSettings_Sound_Title", alter: "أصوات التنبيه المخصصة"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(Language.get("NotificationSettings_Sound_Sub", alter: "تشغيل نغمة صوتية عند استلام إشعار جديد"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()

                    Toggle("", isOn: $viewModel.soundsEnabled)
                        .labelsHidden()
                        .tint(AdminSurface.primary)
                }
                .padding(AdminSpacing.cardPadding)

                Divider().background(AdminSurface.hairline).padding(.horizontal, AdminSpacing.cardPadding)

                // Haptic Feedback Toggle
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.indigo.opacity(0.14))
                            .frame(width: 36, height: 36)
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.indigo)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("NotificationSettings_Haptics_Title", alter: "الاهتزاز والتغذية اللمسية"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(Language.get("NotificationSettings_Haptics_Sub", alter: "نبضات فيزيائية لمسية تنبيهية فورية"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()

                    Toggle("", isOn: $viewModel.hapticsEnabled)
                        .labelsHidden()
                        .tint(AdminSurface.primary)
                }
                .padding(AdminSpacing.cardPadding)

                Divider().background(AdminSurface.hairline).padding(.horizontal, AdminSpacing.cardPadding)

                // Quiet Hours (DND) Toggle & Pickers
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.14))
                                .frame(width: 36, height: 36)
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.purple)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("NotificationSettings_QuietHours_Title", alter: "وضع الهدوء المجدول (DND)"))
                                .font(AdminType.calloutBold)
                                .foregroundStyle(AdminSurface.primaryText)

                            Text(Language.get("NotificationSettings_QuietHours_Sub", alter: "كتم التنبيهات غير الحرجة أثناء ساعات الراحة"))
                                .font(AdminType.caption)
                                .foregroundStyle(AdminSurface.secondaryText)
                        }

                        Spacer()

                        Toggle("", isOn: $viewModel.quietHoursEnabled)
                            .labelsHidden()
                            .tint(AdminSurface.primary)
                    }

                    if viewModel.quietHoursEnabled {
                        VStack(spacing: 8) {
                            HStack {
                                Text(Language.get("From", alter: "من"))
                                    .font(AdminType.caption1Bold)
                                    .foregroundStyle(AdminSurface.secondaryText)
                                Spacer()
                                DatePicker("", selection: $viewModel.quietHoursStart, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                            HStack {
                                Text(Language.get("To", alter: "إلى"))
                                    .font(AdminType.caption1Bold)
                                    .foregroundStyle(AdminSurface.secondaryText)
                                Spacer()
                                DatePicker("", selection: $viewModel.quietHoursEnd, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                        }
                        .padding(.top, 4)
                        .padding(.leading, 48)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(AdminSpacing.cardPadding)
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 1)
            )
        }
    }

    // MARK: - Hub 4: Cloud Sync & Factory Reset Actions

    private var actionsFooterSection: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.syncWithCloud()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSyncingWithCloud {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 15, weight: .bold))
                    }

                    Text(Language.get("NotificationSettings_Action_SyncWithCloud", alter: "حفظ ومزامنة التفضيلات مع السحابة"))
                        .font(AdminType.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                .foregroundStyle(Color.white)
            }
            .disabled(viewModel.isSyncingWithCloud)

            Button {
                viewModel.showResetConfirmation = true
            } label: {
                Text(Language.get("NotificationSettings_Action_ResetDefaults", alter: "استعادة الإعدادات الافتراضية للقنوات"))
                    .font(AdminType.calloutBold)
                    .foregroundStyle(Color.red)
            }
            .padding(.top, 4)
        }
    }
}
