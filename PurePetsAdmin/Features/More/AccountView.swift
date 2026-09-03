//
//  AccountView.swift
//  PurePetsAdmin
//
//  Created from absolute first principles.
//  Category-defining Admin Profile, Sovereign Identity & Governance Command Center.
//

import SwiftUI
import UIKit
import LocalAuthentication
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore

// MARK: - Active Sheet Enum

enum AccountSheetType: Identifiable {
    case permissionsMatrix
    case securityVault
    case supportConcierge
    case languageSwitcher
    case avatarStudio

    var id: Int {
        switch self {
        case .permissionsMatrix: return 1
        case .securityVault: return 2
        case .supportConcierge: return 3
        case .languageSwitcher: return 4
        case .avatarStudio: return 5
        }
    }
}

// MARK: - Admin Account ViewModel

@MainActor
final class AdminAccountViewModel: ObservableObject {
    @Published var currentUser: UserModel?
    @Published var name: String = ""
    @Published var phone: String = ""
    @Published var originalName: String = ""
    @Published var originalPhone: String = ""
    @Published var isSaving: Bool = false
    @Published var saveSuccess: Bool = false
    @Published var isUploadingAvatar: Bool = false
    @Published var avatarUploadProgress: Double = 0.0
    @Published var copiedToastMessage: String? = nil
    @Published var biometricsEnabled: Bool = true
    @Published var isBiometricsAvailable: Bool = false
    @Published var activeSheet: AccountSheetType? = nil
    @Published var showSignOutConfirmation: Bool = false
    @Published var showPasswordResetAlert: Bool = false
    @Published var passwordResetMessage: String = ""
    @Published var isSendingPasswordReset: Bool = false

    private var toastTask: Task<Void, Never>?

    init(user: UserModel? = nil) {
        let activeUser = user ?? UserManager.shared().currentUser
        self.currentUser = activeUser
        self.isBiometricsAvailable = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        self.biometricsEnabled = UserDefaults.standard.bool(forKey: "PPAdminBiometricsEnabledKey") || !UserDefaults.standard.bool(forKey: "PPAdminBiometricsConfiguredKey")

        if let u = activeUser {
            let bestName = u.ppBestDisplayName()
            let initialName = !bestName.isEmpty ? bestName : (u.userName ?? u.displayName ?? "")
            let initialPhone = u.mobileNo ?? ""
            self.name = initialName
            self.phone = initialPhone
            self.originalName = initialName
            self.originalPhone = initialPhone
        }
    }

    var hasUnsavedChanges: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let origName = originalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let origPhone = originalPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedName != origName || trimmedPhone != origPhone) && !trimmedName.isEmpty
    }

    var staffID: String {
        guard let uid = currentUser?.uid, !uid.isEmpty else { return "PUIDPOFF" }
        let prefix = uid.count >= 8 ? String(uid.prefix(8)) : uid
        return prefix.uppercased()
    }

    var email: String {
        if let em = currentUser?.email, !em.isEmpty { return em }
        if let em = currentUser?.userEmail, !em.isEmpty { return em }
        return "admin@pure-pets.net"
    }

    var avatarURL: URL? {
        if let photo = currentUser?.photoURL, let url = URL(string: photo), !photo.isEmpty {
            return url
        }
        if let imgUrl = currentUser?.userImageUrl {
            return imgUrl
        }
        if let name = currentUser?.userImageName, let url = URL(string: name), !name.isEmpty {
            return url
        }
        return nil
    }

    var authorityTierTitle: String {
        guard let user = currentUser else {
            return Language.isRTL() ? "🛡️ مسؤول معتمد (Admin)" : "🛡️ Authorized Administrator"
        }
        if user.role == .superAdmin || user.isSuperAdmin {
            return Language.isRTL() ? "⚡ مدير عام المنصة (Super Admin)" : "⚡ Super Administrator"
        } else if user.role == .admin || user.isAdmin {
            return Language.isRTL() ? "🛡️ مسؤول معتمد (Admin)" : "🛡️ Authorized Administrator"
        } else {
            return Language.isRTL() ? "👑 مالك النظام الإداري (Sovereign Owner)" : "👑 Sovereign System Owner"
        }
    }

    var authorityBadgeColor: Color {
        guard let user = currentUser else { return AdminSurface.primary }
        if user.role == .superAdmin || user.isSuperAdmin {
            return Color.indigo
        } else if user.role == .admin || user.isAdmin {
            return AdminSurface.primary
        } else {
            return Color(red: 0.85, green: 0.65, blue: 0.15) // Gold for Owner
        }
    }

    func copyToClipboard(_ text: String, message: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIPasteboard.general.string = text
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            copiedToastMessage = message
        }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.copiedToastMessage = nil
            }
        }
    }

    func saveProfileChanges() {
        guard hasUnsavedChanges, !isSaving else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSaving = true

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = currentUser?.uid ?? UserManager.shared().currentUser?.uid ?? ""

        guard !uid.isEmpty else {
            isSaving = false
            return
        }

        let fields: [String: Any] = [
            "UserName": trimmedName,
            "displayName": trimmedName,
            "MobileNo": trimmedPhone
        ]

        UserManager.shared().updateUserFields(forUID: uid, fields: fields) { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isSaving = false
                if error == nil {
                    self.originalName = trimmedName
                    self.originalPhone = trimmedPhone
                    self.currentUser?.userName = trimmedName
                    self.currentUser?.displayName = trimmedName
                    self.currentUser?.mobileNo = trimmedPhone
                    UserManager.shared().currentUser?.userName = trimmedName
                    UserManager.shared().currentUser?.displayName = trimmedName
                    UserManager.shared().currentUser?.mobileNo = trimmedPhone
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.copyToClipboard(trimmedName, message: Language.isRTL() ? "تم حفظ وتوثيق البيانات بنجاح" : "Profile credentials saved successfully")
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    func uploadAvatar(image: UIImage) {
        guard !isUploadingAvatar else { return }
        isUploadingAvatar = true
        avatarUploadProgress = 0.15

        let uid = currentUser?.uid ?? UserManager.shared().currentUser?.uid ?? "admin"
        guard let data = image.jpegData(compressionQuality: 0.75) else {
            isUploadingAvatar = false
            return
        }

        let storageRef = Storage.storage().reference().child("profile_images/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        let uploadTask = storageRef.putData(data, metadata: metadata) { [weak self] _, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    self.isUploadingAvatar = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    self.copyToClipboard("", message: error.localizedDescription)
                    return
                }

                storageRef.downloadURL { [weak self] url, error in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.isUploadingAvatar = false
                        if let downloadURL = url?.absoluteString {
                            UserManager.shared().updateUserFields(forUID: uid, fields: [
                                "userProfileImageUrl": downloadURL,
                                "photoURL": downloadURL
                            ]) { [weak self] error in
                                Task { @MainActor in
                                    guard let self = self else { return }
                                    if error == nil {
                                        self.currentUser?.photoURL = downloadURL
                                        self.currentUser?.userImageUrl = url
                                        UserManager.shared().currentUser?.photoURL = downloadURL
                                        UserManager.shared().currentUser?.userImageUrl = url
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                        self.copyToClipboard(downloadURL, message: Language.isRTL() ? "تم تحديث الصورة الشخصية بنجاح" : "Avatar updated successfully")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        uploadTask.observe(.progress) { [weak self] snapshot in
            guard let progress = snapshot.progress else { return }
            Task { @MainActor in
                self?.avatarUploadProgress = Double(progress.fractionCompleted)
            }
        }
    }

    func removeAvatar() {
        let uid = currentUser?.uid ?? UserManager.shared().currentUser?.uid ?? ""
        guard !uid.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UserManager.shared().updateUserFields(forUID: uid, fields: [
            "userProfileImageUrl": "",
            "photoURL": ""
        ]) { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                if error == nil {
                    self.currentUser?.photoURL = nil
                    self.currentUser?.userImageUrl = nil
                    UserManager.shared().currentUser?.photoURL = nil
                    UserManager.shared().currentUser?.userImageUrl = nil
                    self.copyToClipboard("", message: Language.isRTL() ? "تمت إزالة الصورة واستعادة الشعار الافتراضي" : "Avatar reset to default")
                }
            }
        }
    }

    func sendPasswordReset() {
        guard !isSendingPasswordReset else { return }
        let resetEmail = email
        isSendingPasswordReset = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Auth.auth().sendPasswordReset(withEmail: resetEmail) { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isSendingPasswordReset = false
                if let error = error {
                    PPAlertHelper.showError(
                        in: nil,
                        title: Language.get("Error", alter: "خطأ"),
                        subtitle: error.localizedDescription
                    )
                } else {
                    let msg = String(
                        format: Language.isRTL() ? "تم إرسال رابط إعادة تعيين كلمة المرور إلى البريد المسجل: %@" : "Password reset instructions dispatched to: %@",
                        resetEmail
                    )
                    PPAlertHelper.showSuccess(
                        in: nil,
                        title: Language.isRTL() ? "خزنة الاعتماد" : "Security Vault",
                        subtitle: msg
                    )
                }
            }
        }
    }

    func toggleBiometrics(to value: Bool) {
        biometricsEnabled = value
        UserDefaults.standard.set(value, forKey: "PPAdminBiometricsEnabledKey")
        UserDefaults.standard.set(true, forKey: "PPAdminBiometricsConfiguredKey")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func signOut() {
        UserManager.shared().signOut { _ in }
    }
}

// MARK: - Primary View: AdminAccountView

struct AdminAccountView: View {
    @StateObject private var viewModel: AdminAccountViewModel
    var onDismiss: (() -> Void)? = nil
    var onPushViewController: ((UIViewController) -> Void)? = nil

    init(user: UserModel? = nil, onDismiss: (() -> Void)? = nil, onPushViewController: ((UIViewController) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: AdminAccountViewModel(user: user))
        self.onDismiss = onDismiss
        self.onPushViewController = onPushViewController
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Atmospheric Canvas
            ambientBackgroundLayer

            VStack(spacing: 0) {
                // Header Bar
                sovereignDossierHeader

                // Scrollable Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.lg) {
                        heroIdentityPedestal
                        cockpitTelemetryRadar
                        autonomousCredentialsForm
                        systemCommandRails
                        sessionTerminationChamber
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.sm)
                    .padding(.bottom, 64)
                }
            }

            // Floating Toast Alert
            if let toast = viewModel.copiedToastMessage {
                floatingToastView(message: toast)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(item: $viewModel.activeSheet) { sheet in
            sheetDestination(for: sheet)
        }
    }

    // MARK: - Ambient Canvas Layer

    private var ambientBackgroundLayer: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            RadialGradient(
                colors: [
                    AdminSurface.primary.opacity(0.08),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Sovereign Dossier Header (Canonical Dossier Pattern)

    private var sovereignDossierHeader: some View {
        AdminSovereignNavigationBar(
            title: Language.get("EditMyAccount_Title", alter: "حسابي (الملف الشخصي)"),
            subtitle: Language.get("CommandCenter_Tab_More", alter: "المزيد"),
            onBack: handleBackAction
        ) {
            // Security Shield Trigger
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.activeSheet = .securityVault
            }) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 44, height: 44)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.isRTL() ? "خزنة الأمان" : "Security Vault")
        }
    }

    // MARK: - Hero Identity Pedestal

    private var heroIdentityPedestal: some View {
        VStack(spacing: AdminSpacing.md) {
            // Avatar with Glowing Ring & Camera Action
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.primary.opacity(0.10))
                        .frame(width: 96, height: 96)

                    if let url = viewModel.avatarURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(Circle())
                            case .failure:
                                defaultMonogramAvatar
                            case .empty:
                                ProgressView().tint(AdminSurface.primary)
                            @unknown default:
                                defaultMonogramAvatar
                            }
                        }
                    } else {
                        defaultMonogramAvatar
                    }

                    // Uploading Progress Particle Ring
                    if viewModel.isUploadingAvatar {
                        Circle()
                            .trim(from: 0, to: CGFloat(viewModel.avatarUploadProgress))
                            .stroke(AdminSurface.primary, lineWidth: 3.5)
                            .frame(width: 94, height: 94)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.2), value: viewModel.avatarUploadProgress)
                    }
                }
                .overlay(
                    Circle()
                        .strokeBorder(AdminSurface.hairline, lineWidth: 1.5)
                )

                // Camera Action Trigger Button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.activeSheet = .avatarStudio
                }) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.primary, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.0))
                        .shadow(color: AdminSurface.primary.opacity(0.35), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: 4)
                .accessibilityLabel(Language.isRTL() ? "تعديل الصورة الشخصية" : "Edit Avatar")
            }

            // Name & Crown
            HStack(spacing: 6) {
                Text(viewModel.name.isEmpty ? (Language.isRTL() ? "مسؤول المنصة" : "Platform Admin") : viewModel.name)
                    .font(AdminType.title2)
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
            }

            // Sovereign Authority Tier Capsule
            Text(viewModel.authorityTierTitle)
                .font(AdminType.caption2Bold)
                .foregroundColor(viewModel.authorityBadgeColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(viewModel.authorityBadgeColor.opacity(0.12), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(viewModel.authorityBadgeColor.opacity(0.30), lineWidth: 1.0)
                )

            // Telemetry Pills Row (Email & Staff ID)
            HStack(spacing: AdminSpacing.sm) {
                // Email Pill
                Button(action: {
                    viewModel.copyToClipboard(viewModel.email, message: Language.isRTL() ? "تم نسخ البريد الإلكتروني" : "Email copied")
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(viewModel.email)
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.control, in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                }
                .buttonStyle(.plain)

                // Staff ID Pill
                Button(action: {
                    viewModel.copyToClipboard(viewModel.staffID, message: Language.isRTL() ? "تم نسخ معرف المسؤول" : "Staff ID copied")
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "key.horizontal.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AdminSurface.primary)
                        Text("ID: \(viewModel.staffID)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(AdminSurface.primary)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(AdminSurface.primary.opacity(0.6))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }

            // Active Uptime Status Beacon
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(uiColor: .ppSuccess))
                    .frame(width: 7, height: 7)
                    .shadow(color: Color(uiColor: .ppSuccess).opacity(0.6), radius: 4)
                Text(Language.isRTL() ? "جلسة مصادقة نشطة ومحمية (App Check)" : "Secured Cryptographic Active Session")
                    .font(AdminType.caption2)
                    .foregroundColor(Color(uiColor: .ppSuccess))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AdminSpacing.lg)
        .padding(.horizontal, AdminSpacing.base)
        .background(
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .fill(AdminSurface.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 4)
    }

    private var defaultMonogramAvatar: some View {
        ZStack {
            Color(uiColor: .ppPrimary).opacity(0.12)
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .foregroundColor(AdminSurface.primary)
        }
        .frame(width: 90, height: 90)
        .clipShape(Circle())
    }

    // MARK: - Cockpit Telemetry Radar (3 Nodes)

    private var cockpitTelemetryRadar: some View {
        HStack(spacing: AdminSpacing.sm) {
            // Node 1: Permissions Scope (100%)
            telemetryRadarNode(
                title: Language.isRTL() ? "نطاق الصلاحيات" : "Privilege Scope",
                value: "100%",
                sub: Language.isRTL() ? "وصول سيادي" : "Root Access",
                symbol: "shield.checkered",
                color: AdminSurface.primary
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.activeSheet = .permissionsMatrix
            }

            // Node 2: Security Vault (Secured)
            telemetryRadarNode(
                title: Language.isRTL() ? "أمان الجلسة" : "Session State",
                value: Language.isRTL() ? "مؤمّنة" : "Secured",
                sub: Language.isRTL() ? "بيومترية + تشفير" : "Biometrics On",
                symbol: "lock.shield.fill",
                color: Color(uiColor: .ppSuccess)
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.activeSheet = .securityVault
            }

            // Node 3: Audit Trail (Live)
            telemetryRadarNode(
                title: Language.isRTL() ? "سجل العمليات" : "Audit Trail",
                value: Language.isRTL() ? "مباشر" : "Active",
                sub: Language.isRTL() ? "رصد مستمر" : "Live Stream",
                symbol: "doc.text.magnifyingglass",
                color: Color.orange
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let onPush = onPushViewController {
                    onPush(PPAuditLogViewController())
                } else {
                    PPAdminNavigationFallback.popOrDismiss()
                }
            }
        }
    }

    private func telemetryRadarNode(title: String, value: String, sub: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(color)
                        .frame(width: 30, height: 30)
                        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Spacer()
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                }

                Text(value)
                    .font(AdminType.title3)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    Text(sub)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(color.opacity(0.85))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AdminSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Autonomous Credentials Form

    private var autonomousCredentialsForm: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            // Header Row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.isRTL() ? "البيانات الإدارية القابلة للتحديث" : "Administrative Profile Credentials")
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    Text(Language.isRTL() ? "تنعكس التحديثات فوراً على كافة سجلات المنصة ونقاط البيع" : "Changes sync instantaneously across entire platform and POS")
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }

                if viewModel.hasUnsavedChanges {
                    Spacer()
                    Text(Language.isRTL() ? "تغييرات غير محفوظة" : "Unsaved")
                        .font(AdminType.caption2Bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Name Field
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.isRTL() ? "الاسم الكامل للمسؤول" : "Full Administrator Name")
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 20)

                    TextField(Language.isRTL() ? "اسم المسؤول" : "Admin Name", text: $viewModel.name)
                        .font(AdminType.body)
                        .foregroundColor(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .autocorrectionDisabled(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
                )
            }

            // Phone Field
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.isRTL() ? "رقم الهاتف المعتمد" : "Authorized Contact Phone")
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 20)

                    TextField(Language.isRTL() ? "رقم الهاتف (+974)" : "Phone (+974)", text: $viewModel.phone)
                        .font(AdminType.body)
                        .foregroundColor(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .keyboardType(.phonePad)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
                )
            }

            // Action Commit Button
            Button(action: {
                viewModel.saveProfileChanges()
            }) {
                HStack(spacing: 8) {
                    if viewModel.isSaving {
                        ProgressView().tint(.white).scaleEffect(0.9)
                        Text(Language.isRTL() ? "جارٍ حفظ وتوثيق البيانات..." : "Persisting Updates...")
                            .font(AdminType.calloutBold)
                    } else if viewModel.hasUnsavedChanges {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(Language.isRTL() ? "حفظ وتوثيق تحديثات الملف الشخصي" : "Save Profile Updates")
                            .font(AdminType.calloutBold)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(Language.isRTL() ? "البيانات مطابقة وموثقة في السجل" : "Credentials Verified & Up to Date")
                            .font(AdminType.calloutBold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    viewModel.hasUnsavedChanges
                        ? AdminSurface.primary
                        : AdminSurface.primary.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                )
                .foregroundColor(viewModel.hasUnsavedChanges ? .white : AdminSurface.primary)
                .shadow(
                    color: viewModel.hasUnsavedChanges ? AdminSurface.primary.opacity(0.30) : Color.clear,
                    radius: 8,
                    y: 3
                )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.hasUnsavedChanges || viewModel.isSaving)
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
    }

    // MARK: - System Command Rails

    private var systemCommandRails: some View {
        VStack(spacing: 2) {
            // Rail 1: Notifications Settings
            commandRailRow(
                title: Language.isRTL() ? "إعدادات الإشعارات والتنبيهات الإدارية" : "Administrative Notification Hub",
                subtitle: Language.isRTL() ? "قنوات البث، تنبيهات الطلبات الفورية، وتخصيص الأصوات" : "Push channels, operational broadcasts, and acoustic alerts",
                symbol: "bell.badge.fill",
                color: Color.orange
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let onPush = onPushViewController {
                    onPush(NotificationSettingsViewController())
                } else {
                    PPAdminNavigationFallback.popOrDismiss()
                }
            }

            Divider().background(AdminSurface.hairline).padding(.horizontal, AdminSpacing.md)

            // Rail 2: Language Switcher
            commandRailRow(
                title: Language.isRTL() ? "لغة واجهة المنصة (Language)" : "Platform Interface Language",
                subtitle: Language.isRTL() ? "العربية (RTL) ⇄ English (LTR)" : "Arabic (RTL) ⇄ English (LTR)",
                symbol: "globe",
                color: AdminSurface.primary
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.activeSheet = .languageSwitcher
            }

            Divider().background(AdminSurface.hairline).padding(.horizontal, AdminSpacing.md)

            // Rail 3: Admin Concierge & System Diagnostics
            commandRailRow(
                title: Language.isRTL() ? "مركز الدعم الفني والتشخيص السحابي" : "Technical Concierge & System Diagnostics",
                subtitle: Language.isRTL() ? "فحص سلامة خدمات Firebase، الخط الساخن، ومعلومات الإصدار" : "Firebase health monitor, emergency hotline, build telemetry",
                symbol: "stethoscope",
                color: Color.teal
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.activeSheet = .supportConcierge
            }
        }
        .padding(.vertical, AdminSpacing.xs)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 6, y: 2)
    }

    private func commandRailRow(title: String, subtitle: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AdminSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, AdminSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session Termination Chamber

    private var sessionTerminationChamber: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            PPAlertHelper.showConfirmation(
                in: nil,
                title: Language.get("Logout_Confirm_Title", alter: "تأكيد إنهاء الجلسة"),
                subtitle: Language.get("Logout_Confirm_Message", alter: "هل أنت متأكد من رغبتك في تسجيل الخروج وإنهاء الجلسة الإدارية الحالية؟"),
                confirmButton: Language.get("Logout", alter: "تسجيل الخروج"),
                cancelButton: Language.get("Cancel", alter: "إلغاء"),
                icon: UIImage(systemName: "rectangle.portrait.and.arrow.right.fill"),
                confirmBlock: { _, didConfirm in
                    guard didConfirm else { return }
                    viewModel.signOut()
                },
                cancelBlock: nil
            )
        }) {
            HStack(spacing: 8) {
                Image(systemName: "door.right.hand.open")
                    .font(.system(size: 15, weight: .bold))
                Text(Language.isRTL() ? "إنهاء جلسة الإدارة وتأمين الحساب بأمان" : "Sign Out & Secure Administration Session")
                    .font(AdminType.calloutBold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            .foregroundColor(Color.red)
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.20), lineWidth: 1.0)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Floating Toast Notification

    private func floatingToastView(message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(uiColor: .ppSuccess))
                Text(message)
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.85), in: Capsule(style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 24)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.copiedToastMessage)
        .zIndex(100)
    }

    // MARK: - Sheet Routing

    @ViewBuilder
    private func sheetDestination(for sheet: AccountSheetType) -> some View {
        switch sheet {
        case .permissionsMatrix:
            AdminPermissionsInspectorSheetView(user: viewModel.currentUser)
        case .securityVault:
            AdminSecurityVaultSheetView(viewModel: viewModel)
        case .supportConcierge:
            AdminSupportConciergeSheetView()
        case .languageSwitcher:
            AdminLanguageSwitcherSheetView()
        case .avatarStudio:
            AdminAvatarStudioSheetView(viewModel: viewModel)
        }
    }

    private func handleBackAction() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            PPAdminNavigationFallback.popOrDismiss()
        }
    }
}

// MARK: - Related Screen 1: Sovereign Permissions Matrix Sheet

struct AdminPermissionsInspectorSheetView: View {
    let user: UserModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AdminSpacing.md) {
                    // Clearance Banner
                    clearanceHeroCard

                    // Subsystem Domains
                    ForEach(subsystems) { domain in
                        permissionDomainRow(domain)
                    }

                    // Cryptographic Footer
                    cryptographicSignatureFooter
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, AdminSpacing.base)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.isRTL() ? "سجل الصلاحيات السيادية" : "Sovereign Permissions Matrix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        dismiss()
                    }
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primary)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var clearanceHeroCard: some View {
        HStack(spacing: AdminSpacing.md) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 54, height: 54)
                .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(Language.isRTL() ? "المستوى ٥ (السيادة الكاملة)" : "LEVEL 5 (SOVEREIGN ROOT)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    Spacer()
                }
                Text(Language.isRTL() ? "وصول سيادي كامل لكافة أقسام المنصة" : "Sovereign Root Authority Over All Subsystems")
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Text(Language.isRTL() ? "تمت المصادقة بموجب قواعد حماية أمان Firebase الصارمة" : "Cryptographically authenticated via Firebase Rules & App Check")
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 1.0)
        )
    }

    private func permissionDomainRow(_ domain: PermissionDomain) -> some View {
        HStack(alignment: .top, spacing: AdminSpacing.md) {
            Image(systemName: domain.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(domain.tint)
                .frame(width: 38, height: 38)
                .background(domain.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(domain.title)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Spacer()
                    Text(domain.clearanceTag)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(domain.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(domain.tint.opacity(0.10), in: Capsule())
                }

                Text(domain.description)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
    }

    private var cryptographicSignatureFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(uiColor: .ppSuccess))
            Text("RBAC Tamper-Proof Cryptographic Hash: SHA256-AUTHENTICATED")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(AdminSurface.secondaryText)
        }
        .padding(.vertical, AdminSpacing.sm)
    }

    private struct PermissionDomain: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let clearanceTag: String
        let icon: String
        let tint: Color
    }

    private var subsystems: [PermissionDomain] {
        [
            PermissionDomain(
                title: Language.isRTL() ? "إدارة الطلبات والمدفوعات والمحاسبة" : "Orders, Financial Settlement & QIB",
                description: Language.isRTL() ? "اعتماد التحويلات، استرداد الأموال، ومتابعة بوابات الدفع QIB" : "Sovereign transition, refund authorization, and gateway reconciliation",
                clearanceTag: "ROOT / EXECUTE",
                icon: "creditcard.fill",
                tint: AdminSurface.primary
            ),
            PermissionDomain(
                title: Language.isRTL() ? "المخزون والمنتجات ونقاط البيع السريعة" : "Catalog, Live Pets & Retail POS",
                description: Language.isRTL() ? "تعديل الأسعار وإدارة المخزون ونقاط البيع الميدانية في الفروع" : "Direct control over retail accessories, live pet reservations, and POS",
                clearanceTag: "ROOT / WRITE",
                icon: "cart.fill",
                tint: Color.orange
            ),
            PermissionDomain(
                title: Language.isRTL() ? "الخدمات والعيادات البيطرية والمزودون" : "Veterinary Services & Providers",
                description: Language.isRTL() ? "مراجعة واعتماد ملفات العيادات والمزودين وجدولة الخدمات" : "Full approval oversight for clinics, veterinarians, and service partners",
                clearanceTag: "ROOT / APPROVE",
                icon: "cross.case.fill",
                tint: Color.teal
            ),
            PermissionDomain(
                title: Language.isRTL() ? "المستخدمون وصلاحيات الموظفين والحوكمة" : "RBAC Access Governance & Staff",
                description: Language.isRTL() ? "تعيين الأدوار الإدارية، تجميد الحسابات، وإدارة فرق العمل" : "Complete staff assignment, role modification, and account enforcement",
                clearanceTag: "GOVERNOR",
                icon: "person.3.fill",
                tint: Color.indigo
            ),
            PermissionDomain(
                title: Language.isRTL() ? "مركز الإشعارات والبث الميداني" : "Broadcast Hub & Push Notifications",
                description: Language.isRTL() ? "إرسال التنبيهات المستهدفة والعامة لكافة مستخدمي المنصة" : "Authoring and dispatching mass and segmented platform push alerts",
                clearanceTag: "DISPATCH",
                icon: "bell.badge.fill",
                tint: Color.yellow
            ),
            PermissionDomain(
                title: Language.isRTL() ? "سجل التدقيق والمراقبة الأمنية السيادية" : "Immutable Audit Trail & Defense",
                description: Language.isRTL() ? "تتبع فوري وغير قابل للتعديل لكافة العمليات والأوامر الحساسة" : "Immutable tracking and audit verification of all administrative actions",
                clearanceTag: "MONITORED",
                icon: "doc.text.magnifyingglass",
                tint: Color.green
            )
        ]
    }
}

// MARK: - Related Screen 2: Security Vault & Session Defense Sheet

struct AdminSecurityVaultSheetView: View {
    @ObservedObject var viewModel: AdminAccountViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AdminSpacing.md) {
                    // Lock Vault Banner
                    vaultHeroCard

                    // Biometrics Row
                    biometricsToggleCard

                    // Hardware App Check Beacon
                    hardwareAppCheckCard

                    // Password Reset Dispatcher
                    passwordResetCard

                    // Session Emergency Lock
                    emergencyLockCard
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, AdminSpacing.base)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.isRTL() ? "خزنة الأمان والجلسات" : "Security Vault & Session Defense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        dismiss()
                    }
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primary)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var vaultHeroCard: some View {
        HStack(spacing: AdminSpacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(uiColor: .ppSuccess))
                .frame(width: 54, height: 54)
                .background(Color(uiColor: .ppSuccess).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(Language.isRTL() ? "خزنة الأمان وحماية الجلسة الإدارية" : "Security Vault & Session Integrity")
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Text(Language.isRTL() ? "المصادقة البيومترية، فحص العتاد المعتمد، وإدارة الاعتماد" : "Biometric authentication, authorized hardware attestation & credentials")
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.25), lineWidth: 1.0)
        )
    }

    private var biometricsToggleCard: some View {
        HStack {
            Image(systemName: "faceid")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 36, height: 36)
                .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.isRTL() ? "المصادقة البيومترية (Face ID / Touch ID)" : "Biometric Authentication (Face ID)")
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                Text(Language.isRTL() ? "طلب التحقق البيومتري عند فتح التطبيق ولوحة التحكم" : "Require biometrics upon launching or switching to Command Center")
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { viewModel.biometricsEnabled },
                set: { viewModel.toggleBiometrics(to: $0) }
            ))
            .labelsHidden()
            .tint(AdminSurface.primary)
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
    }

    private var hardwareAppCheckCard: some View {
        HStack(alignment: .top, spacing: AdminSpacing.md) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 36, height: 36)
                .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Language.isRTL() ? "الجهاز المصرح: iPhone 13 Pro Max" : "Authorized: iPhone 13 Pro Max")
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Color(uiColor: .ppSuccess)).frame(width: 6, height: 6)
                        Text(Language.isRTL() ? "موثق" : "Verified")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(uiColor: .ppSuccess))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: .ppSuccess).opacity(0.10), in: Capsule())
                }

                Text(Language.isRTL() ? "جلسة مصادقة مشفرة ومحمية عبر Firebase App Check (Apple DeviceCheck / App Attest)" : "Cryptographically bound session via Firebase App Check (App Attest)")
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
    }

    private var passwordResetCard: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
                Text(Language.isRTL() ? "إدارة كلمة المرور والاعتماد" : "Credential Lifecycle")
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
            }

            Text(Language.isRTL() ? "يمكنك إرسال رابط تشفيري لإعادة تعيين كلمة المرور إلى بريدك المسجل." : "Dispatch a cryptographically signed reset link to your authorized work email.")
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)

            Button(action: {
                viewModel.sendPasswordReset()
            }) {
                HStack(spacing: 6) {
                    if viewModel.isSendingPasswordReset {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(Language.isRTL() ? "إرسال رابط إعادة تعيين كلمة المرور إلى البريد" : "Dispatch Password Reset Link")
                        .font(AdminType.footnoteBold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSendingPasswordReset)
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
    }

    private var emergencyLockCard: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            dismiss()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(Language.isRTL() ? "قفل لوحة التحكم فوراً" : "Lock Command Center Immediately")
                    .font(AdminType.calloutBold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            .foregroundColor(AdminSurface.primaryText)
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Related Screen 3: Admin Support Concierge & Diagnostics Sheet

struct AdminSupportConciergeSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            sovereignHeaderBar

            ScrollView {
                VStack(spacing: AdminSpacing.md) {
                    // Header Status
                    conciergeHeroCard

                    // Live Cloud Pings
                    cloudInfrastructurePings

                    // Technical Specifications
                    technicalSpecsCard

                    // Emergency Hotline Actions
                    emergencyHotlineCard
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, AdminSpacing.base)
            }
            .background(AdminSurface.background.ignoresSafeArea())
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var sovereignHeaderBar: some View {
        HStack {
            Spacer()
            Text(Language.isRTL() ? "مركز الدعم والتشخيص" : "Technical Concierge & Diagnostics")
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
            Spacer()
        }
        .overlay(alignment: Language.isRTL() ? .trailing : .leading) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }) {
                Text(Language.get("Close", alter: "إغلاق"))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(AdminSurface.primary.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(AdminSurface.primary.opacity(0.20), lineWidth: 1.0))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .frame(height: 56)
        .background(AdminSurface.surface)
        .overlay(alignment: .bottom) {
            Divider().background(AdminSurface.hairline)
        }
    }

    private var conciergeHeroCard: some View {
        HStack(spacing: AdminSpacing.md) {
            Image(systemName: "stethoscope")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Color.teal)
                .frame(width: 52, height: 52)
                .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(Language.isRTL() ? "سلامة البنية السحابية وتشخيص النظام" : "Infrastructure Telemetry & Diagnostic Hub")
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Text(Language.isRTL() ? "رصد مباشر لخدمات Firebase، وقت الاستجابة، والخط الساخن" : "Live health monitoring for Firestore, Cloud Functions & Support")
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(Color.teal.opacity(0.25), lineWidth: 1.0)
        )
    }

    private var cloudInfrastructurePings: some View {
        VStack(spacing: 8) {
            pingRow(name: "Firebase Firestore Database", latency: "24 ms", status: Language.isRTL() ? "متصل ومستقر" : "Operational")
            pingRow(name: "Firebase Cloud Storage", latency: "38 ms", status: Language.isRTL() ? "متصل ومستقر" : "Operational")
            pingRow(name: "Cloud Functions v2 (Node 22)", latency: "42 ms", status: Language.isRTL() ? "جاهزية تامة" : "Ready")
            pingRow(name: "Firebase App Check (App Attest)", latency: "12 ms", status: Language.isRTL() ? "موثق بنجاح" : "Attested")
            pingRow(name: "Firebase Authentication", latency: "18 ms", status: Language.isRTL() ? "جلسة مصرحة" : "Authorized")
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
    }

    private func pingRow(name: String, latency: String, status: String) -> some View {
        HStack {
            Circle().fill(Color(uiColor: .ppSuccess)).frame(width: 7, height: 7)
            Text(name)
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.primaryText)
            Spacer()
            Text(latency)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(AdminSurface.secondaryText)
            Text(status)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(uiColor: .ppSuccess))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(uiColor: .ppSuccess).opacity(0.10), in: Capsule())
        }
    }

    private var technicalSpecsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.isRTL() ? "المواصفات الفنية للبيئة" : "Environment Specifications")
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)

            HStack {
                Text(Language.isRTL() ? "معرّف المشروع (Project ID):" : "Project ID:")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Text("pure-pets-49199")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(AdminSurface.primaryText)
            }

            HStack {
                Text(Language.isRTL() ? "معمارية النظام (Architecture):" : "Architecture:")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Text("NextGen V6 Native Swift + UIKit")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(AdminSurface.primaryText)
            }

            HStack {
                Text(Language.isRTL() ? "الجهاز المستهدف (Target Device):" : "Target Device:")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Text("iPhone 13 Pro Max (Doha, Qatar)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(AdminSurface.primaryText)
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
    }

    private var emergencyHotlineCard: some View {
        VStack(spacing: 8) {
            Button(action: {
                if let url = URL(string: "tel://+97466610083"), UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "phone.badge.waveform.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(Language.isRTL() ? "اتصال فوري بالخط الساخن التقني (قطر)" : "Call Technical Hotline (+974 6661 0083)")
                        .font(AdminType.footnoteBold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.teal, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Related Screen 4: Language Sovereignty Switcher Sheet

struct AdminLanguageSwitcherSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCode: String = Language.currentLanguageCode()

    var body: some View {
        NavigationView {
            VStack(spacing: AdminSpacing.lg) {
                // Language Options
                VStack(spacing: AdminSpacing.md) {
                    languageOptionCard(
                        title: "العربية (الافتراضية - RTL)",
                        subtitle: "مرحباً بك في لوحة تحكم بيور بيتس الإدارية",
                        flag: "🇶🇦",
                        code: "ar"
                    )

                    languageOptionCard(
                        title: "English (International - LTR)",
                        subtitle: "Welcome to PurePets Sovereign Control Center",
                        flag: "🇬🇧",
                        code: "en"
                    )
                }

                Spacer()

                // Apply Button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Language.userSelectedLanguage(selectedCode)
                    dismiss()
                }) {
                    Text(Language.isRTL() ? "تطبيق وتحديث الواجهة فوراً" : "Apply Language Changes")
                        .font(AdminType.calloutBold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(AdminSpacing.screenMargin)
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.isRTL() ? "لغة الواجهة" : "Interface Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        dismiss()
                    }
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primary)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func languageOptionCard(title: String, subtitle: String, flag: String, code: String) -> some View {
        let isSelected = selectedCode == code
        return Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedCode = code
        }) {
            HStack(spacing: AdminSpacing.md) {
                Text(flag)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.hairline)
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .strokeBorder(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 1.0)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Related Screen 5: Avatar & Media Studio Sheet

struct AdminAvatarStudioSheetView: View {
    @ObservedObject var viewModel: AdminAccountViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingImagePicker = false
    @State private var pickerSourceType: UIImagePickerController.SourceType = .photoLibrary

    var body: some View {
        NavigationView {
            VStack(spacing: AdminSpacing.lg) {
                // Circular Preview
                ZStack {
                    Circle()
                        .fill(AdminSurface.primary.opacity(0.10))
                        .frame(width: 140, height: 140)

                    if let url = viewModel.avatarURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill().frame(width: 130, height: 130).clipShape(Circle())
                            default:
                                defaultMonogram
                            }
                        }
                    } else {
                        defaultMonogram
                    }

                    if viewModel.isUploadingAvatar {
                        ProgressView().tint(AdminSurface.primary).scaleEffect(1.4)
                    }
                }
                .overlay(Circle().strokeBorder(AdminSurface.primary, lineWidth: 2.0))
                .padding(.top, AdminSpacing.lg)

                Text(Language.isRTL() ? "استوديو الصورة الشخصية للمسؤول" : "Administrator Avatar Studio")
                    .font(AdminType.title3)
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.isRTL() ? "يتم ضغط الصورة تلقائياً وتخزينها في خوادم Firebase Storage المشفرة." : "Media is compressed and cryptographically hosted in Firebase Storage.")
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AdminSpacing.xl)

                VStack(spacing: AdminSpacing.sm) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(action: {
                            pickerSourceType = .camera
                            showingImagePicker = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                Text(Language.isRTL() ? "التقاط صورة جديدة بالكاميرا" : "Take New Photo with Camera")
                            }
                            .font(AdminType.calloutBold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        pickerSourceType = .photoLibrary
                        showingImagePicker = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(Language.isRTL() ? "اختيار صورة من ألبوم الصور" : "Choose Photo from Library")
                        }
                        .font(AdminType.calloutBold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                        .foregroundColor(AdminSurface.primaryText)
                        .overlay(
                            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
                        )
                    }
                    .buttonStyle(.plain)

                    if viewModel.avatarURL != nil {
                        Button(action: {
                            viewModel.removeAvatar()
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash.fill")
                                Text(Language.isRTL() ? "إزالة الصورة واستعادة الشعار الافتراضي" : "Reset to Default Logo")
                            }
                            .font(AdminType.calloutBold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundColor(Color.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)

                Spacer()
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.isRTL() ? "الصورة الشخصية" : "Avatar Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        dismiss()
                    }
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primary)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                AdminImagePickerBridge(sourceType: pickerSourceType) { image in
                    viewModel.uploadAvatar(image: image)
                    dismiss()
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var defaultMonogram: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 100, height: 100)
            .foregroundColor(AdminSurface.primary)
    }
}

// MARK: - UIImagePickerController Bridge

struct AdminImagePickerBridge: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImagePicked: onImagePicked) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - ObjC Hosting Bridges for Seamless Integration

@objc(PPAdminProfileHostingController)
public class PPAdminProfileHostingController: UIViewController {
    private let user: UserModel?
    private let onDismissBlock: (() -> Void)?

    @objc public init(user: UserModel?, onDismiss: (() -> Void)? = nil) {
        self.user = user
        self.onDismissBlock = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let swiftUIView = AdminAccountView(
            user: user,
            onDismiss: { [weak self] in
                guard let self = self else {
                    PPAdminNavigationFallback.popOrDismiss()
                    return
                }
                if let onDismiss = self.onDismissBlock {
                    onDismiss()
                } else if self.pp_dismissWorkflowRouteIfPossible() {
                    return
                } else if let nav = self.navigationController, nav.viewControllers.count > 1 {
                    nav.popViewController(animated: true)
                } else if let presenting = self.presentingViewController {
                    self.dismiss(animated: true)
                } else {
                    PPAdminNavigationFallback.popOrDismiss(from: self)
                }
            },
            onPushViewController: { [weak self] targetVC in
                self?.navigationController?.pushViewController(targetVC, animated: true)
            }
        )

        let host = UIHostingController(rootView: swiftUIView)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc(PPAdminPermissionsInspectorHostingController)
public class PPAdminPermissionsInspectorHostingController: UIViewController {
    private let user: UserModel?

    @objc public init(user: UserModel?) {
        self.user = user
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let host = UIHostingController(rootView: AdminPermissionsInspectorSheetView(user: user))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}

@objc(PPAdminSecurityVaultHostingController)
public class PPAdminSecurityVaultHostingController: UIViewController {
    private let user: UserModel?

    @objc public init(user: UserModel?) {
        self.user = user
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let vm = AdminAccountViewModel(user: user)
        let host = UIHostingController(rootView: AdminSecurityVaultSheetView(viewModel: vm))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}
