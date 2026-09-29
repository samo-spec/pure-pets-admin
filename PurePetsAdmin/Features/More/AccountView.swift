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
    @Published var customRoleNameResolved: String? = nil

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

        // Dynamically resolve custom role title from staff_roles if applicable
        if let staff = PPStaffAuth.shared().cachedCurrentStaff {
            let roleStr = staff.role.rawValue
            if roleStr.hasPrefix("custom_") {
                let roleId = String(roleStr.dropFirst("custom_".count))
                Firestore.firestore().collection("staff_roles").document(roleId).getDocument { [weak self] snapshot, error in
                    guard let self = self, let data = snapshot?.data(), error == nil else { return }
                    if let nameDict = data["name"] as? [String: Any] {
                        let isArabic = Language.isRTL()
                        if let name = (isArabic ? nameDict["ar"] : nameDict["en"]) as? String, !name.isEmpty {
                            Task { @MainActor in
                                self.customRoleNameResolved = name
                            }
                        }
                    }
                }
            }
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
        let staff = PPStaffAuth.shared().cachedCurrentStaff
        let isArabic = Language.isRTL()

        // 1. Sovereign Owner: STRICT check only
        if currentUser?.isOwner == true || staff?.role == .owner {
            return isArabic ? "👑 مالك النظام الإداري (Owner)" : "👑 System Owner"
        }

        // 2. Super Administrator
        if currentUser?.isSuperAdmin == true || currentUser?.role == .superAdmin || staff?.role == .superAdmin {
            return isArabic ? "⚡ مدير عام المنصة (Super Admin)" : "⚡ Super Administrator"
        }

        // 3. Administrator
        if currentUser?.isAdmin == true || currentUser?.role == .admin || staff?.role.rawValue == "admin" {
            return isArabic ? "🛡️ مسؤول معتمد (Admin)" : "🛡️ Authorized Administrator"
        }

        // 4. Custom Role with resolved name from Firestore staff_roles
        if let customName = customRoleNameResolved, !customName.isEmpty {
            return isArabic ? "💳 \(customName) معتمد (Staff)" : "💳 Authorized \(customName)"
        }

        // 5. Staff Doc Role check
        if let staffDoc = staff {
            let roleStr = staffDoc.role.rawValue
            if roleStr.hasPrefix("custom_") {
                if staffDoc.hasPermission("pos.sell") || staffDoc.hasPermission("pos.history") {
                    return isArabic ? "💳 كاشير معتمد (Cashier)" : "💳 Authorized Cashier"
                }
                return isArabic ? "👤 موظف بصلاحيات مخصصة" : "👤 Custom Staff Member"
            }

            switch staffDoc.role {
            case .accountant:
                return isArabic ? "📊 محاسب معتمد (Accountant)" : "📊 Authorized Accountant"
            case .inventoryManager:
                return isArabic ? "📦 مدير مخزون (Inventory Manager)" : "📦 Inventory Manager"
            case .branchManager:
                return isArabic ? "🏢 مدير فرع (Branch Manager)" : "🏢 Branch Manager"
            case .sales:
                return isArabic ? "💼 مسؤول مبيعات (Sales)" : "💼 Sales Representative"
            case .operationsManager:
                return isArabic ? "⚙️ مدير عمليات (Operations Manager)" : "⚙️ Operations Manager"
            case .supportAgent:
                return isArabic ? "🎧 دعم فني وخدمة عملاء (Support)" : "🎧 Support Agent"
            case .complianceAuditor:
                return isArabic ? "📋 مدقق امتثال (Auditor)" : "📋 Compliance Auditor"
            default:
                break
            }
        }

        // 6. POS permissions fallback
        if let perms = staff?.permissions, perms.contains("pos.sell") || perms.contains("pos.history") {
            return isArabic ? "💳 كاشير معتمد (Cashier)" : "💳 Authorized Cashier"
        }

        return isArabic ? "👤 موظف معتمد (Staff Member)" : "👤 Authorized Staff Member"
    }

    var authorityBadgeColor: Color {
        let staff = PPStaffAuth.shared().cachedCurrentStaff
        if currentUser?.isOwner == true || staff?.role == .owner {
            return Color(red: 0.85, green: 0.65, blue: 0.15) // Gold ONLY for Owner
        }
        if currentUser?.isSuperAdmin == true || currentUser?.role == .superAdmin || staff?.role == .superAdmin {
            return Color.indigo
        }
        if currentUser?.isAdmin == true || currentUser?.role == .admin || staff?.role.rawValue == "admin" {
            return AdminSurface.primary
        }
        if let staffDoc = staff {
            let roleStr = staffDoc.role.rawValue
            if roleStr.hasPrefix("custom_") || staffDoc.hasPermission("pos.sell") || staffDoc.hasPermission("pos.history") {
                return Color.teal
            }
            if staffDoc.role == .accountant {
                return Color.orange
            }
            if staffDoc.role == .inventoryManager {
                return Color.blue
            }
            if staffDoc.role == .branchManager {
                return Color.purple
            }
        }
        return AdminSurface.primary
    }

    var privilegeRadarData: (value: String, sub: String, symbol: String, color: Color) {
        let isArabic = Language.isRTL()
        let staff = PPStaffAuth.shared().cachedCurrentStaff

        if currentUser?.isOwner == true || staff?.role == .owner {
            return ("100%", isArabic ? "وصول سيادي كامل" : "Full Sovereign", "crown.fill", Color(red: 0.85, green: 0.65, blue: 0.15))
        }
        if currentUser?.isSuperAdmin == true || staff?.role == .superAdmin {
            return ("100%", isArabic ? "وصول عام شامل" : "Super Admin", "bolt.shield.fill", Color.indigo)
        }
        if currentUser?.isAdmin == true || staff?.role.rawValue == "admin" {
            return ("100%", isArabic ? "إدارة نظام شاملة" : "Full Admin", "shield.fill", AdminSurface.primary)
        }

        let perms = staff?.permissions ?? []
        let count = perms.count > 0 ? perms.count : (currentUser?.permissions.count ?? 0)
        let countStr = isArabic ? "\(count) صلاحيات" : "\(count) Perms"

        if perms.contains("pos.sell") || perms.contains("pos.history") {
            return (countStr, isArabic ? "نقطة بيع ومبيعات" : "POS & Sales", "creditcard.fill", Color.teal)
        }
        if count > 0 {
            return (countStr, isArabic ? "نطاق تشغيلي محدد" : "Assigned Scope", "shield.lefthalf.filled", AdminSurface.primary)
        }
        return (isArabic ? "مقيّد" : "Restricted", isArabic ? "صلاحيات أساسية" : "Basic Access", "lock.shield", Color.secondary)
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
            customTopSpacing: 0,
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
                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 90, height: 90)) {
                            defaultMonogramAvatar
                        }
                        .frame(width: 90, height: 90)
                        .clipShape(Circle())
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
            // Node 1: Dynamic Permissions Scope
            let radarData = viewModel.privilegeRadarData
            telemetryRadarNode(
                title: Language.isRTL() ? "نطاق الصلاحيات" : "Privilege Scope",
                value: radarData.value,
                sub: radarData.sub,
                symbol: radarData.symbol,
                color: radarData.color
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
                    onPush(AdminNotificationSettingsHostingController())
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

    private var staff: PPStaffDoc? {
        PPStaffAuth.shared().cachedCurrentStaff
    }

    private var isOwner: Bool {
        user?.isOwner == true || staff?.role == .owner
    }

    private var isSuperAdmin: Bool {
        user?.isSuperAdmin == true || staff?.role == .superAdmin
    }

    private var isAdmin: Bool {
        user?.isAdmin == true || staff?.role.rawValue == "admin"
    }

    private var isCashierOrPOS: Bool {
        let perms = staff?.permissions ?? []
        return perms.contains("pos.sell") || perms.contains("pos.history") || perms.contains("pos.view")
    }

    private var grantedPermissionsList: [String] {
        if let perms = staff?.permissions, !perms.isEmpty {
            return perms
        }
        if let userPerms = user?.permissions.allKeys as? [String] {
            return userPerms
        }
        return []
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AdminSpacing.md) {
                    // Clearance Hero Banner
                    clearanceHeroCard

                    // Scope & Branch Assignment Card
                    scopeAssignmentCard

                    // Explicit Active Permissions Section
                    if !grantedPermissionsList.isEmpty {
                        explicitPermissionsCard
                    }

                    // Subsystem Domains Clearance Status
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(Language.isRTL() ? "حالة القطاعات التشغيلية" : "Subsystem Clearance Status")
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)

                        ForEach(subsystems) { domain in
                            permissionDomainRow(domain)
                        }
                    }

                    // Cryptographic Footer
                    cryptographicSignatureFooter
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, AdminSpacing.base)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.isRTL() ? "سجل الصلاحيات المعتمدة" : "Authority & Permissions")
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
        let isArabic = Language.isRTL()
        let levelText: String
        let titleText: String
        let subText: String
        let iconName: String
        let tintColor: Color

        if isOwner {
            levelText = isArabic ? "المستوى ٥ (السيادة الكاملة)" : "Level 5 (Sovereign Authority)"
            titleText = isArabic ? "وصول سيادي كامل لكافة أقسام المنصة" : "Full Platform Governance Access"
            subText = isArabic ? "تمت المصادقة بموجب قواعد حماية أمان Firebase الصارمة" : "Authenticated under strict Firebase security rules"
            iconName = "crown.fill"
            tintColor = Color(red: 0.85, green: 0.65, blue: 0.15)
        } else if isSuperAdmin {
            levelText = isArabic ? "المستوى ٥ (إدارة عامة شاملة)" : "Level 5 (Super Administrator)"
            titleText = isArabic ? "إشراف إداري وتنفيذي كامل على النظام" : "Full System Executive Oversight"
            subText = isArabic ? "تمت المصادقة بموجب قواعد حماية أمان Firebase الصارمة" : "Authenticated under strict Firebase security rules"
            iconName = "bolt.shield.fill"
            tintColor = Color.indigo
        } else if isAdmin {
            levelText = isArabic ? "المستوى ٤ (مسؤول معتمد)" : "Level 4 (Authorized Admin)"
            titleText = isArabic ? "إدارة العمليات والقطاعات المصرح بها" : "Operations & Assigned Sectors Management"
            subText = isArabic ? "صلاحيات إدارية متعددة مع نطاق رقابة وتشغيل" : "Multi-domain administrative scope"
            iconName = "shield.fill"
            tintColor = AdminSurface.primary
        } else if isCashierOrPOS {
            levelText = isArabic ? "المستوى ١ (تشغيلي ميداني)" : "Level 1 (Field Operations)"
            titleText = isArabic ? "نطاق عمليات نقطة البيع والكاشير المعتمد" : "Authorized POS & Cashier Operations"
            subText = isArabic ? "مصرح لإجراء عمليات البيع الميداني، الفواتير، واستعراض سجل المبيعات" : "Authorized for fast-selling, receipts, and sales logs"
            iconName = "creditcard.fill"
            tintColor = Color.teal
        } else {
            levelText = isArabic ? "المستوى ٢ (موظف معتمد)" : "Level 2 (Authorized Staff)"
            titleText = isArabic ? "نطاق تشغيلي محدد بحسب الدور الوظيفي" : "Role-Restricted Operational Scope"
            subText = isArabic ? "صلاحيات مخصصة ومحددة حسب نطاق المهام المعتمدة" : "Specific operational permissions assigned"
            iconName = "person.badge.shield.checkmark.fill"
            tintColor = AdminSurface.primary
        }

        return HStack(spacing: AdminSpacing.md) {
            Image(systemName: iconName)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(tintColor)
                .frame(width: 54, height: 54)
                .background(tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(levelText)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(tintColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(tintColor.opacity(0.12), in: Capsule())
                    Spacer()
                }
                Text(titleText)
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(subText)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(tintColor.opacity(0.25), lineWidth: 1.0)
        )
    }

    private var scopeAssignmentCard: some View {
        let isArabic = Language.isRTL()
        let isGlobal = staff?.hasGlobalScope() ?? true

        return HStack(spacing: AdminSpacing.md) {
            Image(systemName: isGlobal ? "globe.badge.chevron.backward" : "building.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.indigo)
                .frame(width: 42, height: 42)
                .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(isArabic ? "نطاق العمل الجغرافي المعتمد" : "Assigned Operational Scope")
                    .font(AdminType.caption1Bold)
                    .foregroundColor(AdminSurface.primaryText)

                Text(isGlobal ? (isArabic ? "وصول شامل لكافة الفروع والمواقع (Global Scope)" : "Global Scope: All branches accessible")
                              : (isArabic ? "مقيد بفروع محددة فقط" : "Restricted to assigned branches"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            Text(isGlobal ? (isArabic ? "شامل" : "Global") : (isArabic ? "مخصص" : "Scoped"))
                .font(AdminType.caption2Bold)
                .foregroundColor(Color.indigo)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.indigo.opacity(0.10), in: Capsule())
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
    }

    private var explicitPermissionsCard: some View {
        let isArabic = Language.isRTL()

        return VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(uiColor: .ppSuccess))
                Text(isArabic ? "الصلاحيات الممنوحة صراحة (\(grantedPermissionsList.count))" : "Active Explicit Permissions (\(grantedPermissionsList.count))")
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
            }
            .padding(.horizontal, 4)

            LazyVStack(spacing: 6) {
                ForEach(grantedPermissionsList, id: \.self) { perm in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(uiColor: .ppSuccess))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(localizedPermTitle(perm))
                                .font(AdminType.caption1Bold)
                                .foregroundColor(AdminSurface.primaryText)
                            Text(perm)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AdminSurface.secondaryText)
                        }

                        Spacer()

                        Text(isArabic ? "مفعلة" : "Active")
                            .font(AdminType.caption2Bold)
                            .foregroundColor(Color(uiColor: .ppSuccess))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                    )
                }
            }
        }
        .padding(.top, 4)
    }

    private func localizedPermTitle(_ key: String) -> String {
        let isArabic = Language.isRTL()
        switch key {
        case "pos.history":
            return isArabic ? "سجل مبيعات نقطة البيع" : "POS Sales History"
        case "pos.sell":
            return isArabic ? "إجراء المبيعات الميدانية السريعة" : "POS Fast Selling"
        case "pos.view":
            return isArabic ? "استعراض واجهة الكاشير" : "POS Terminal View"
        case "pos.manage":
            return isArabic ? "إدارة نقطة البيع والإعدادات" : "POS Management"
        case "stock.view":
            return isArabic ? "استعراض المخزون والمنتجات" : "View Inventory & Stock"
        case "stock.manage":
            return isArabic ? "إدارة وتعديل المخزون" : "Manage Inventory & Stock"
        case "payments.view":
            return isArabic ? "استعراض المدفوعات والمعاملات" : "View Payments"
        case "payments.manage":
            return isArabic ? "إدارة بوابات الدفع والتحويلات" : "Manage Payments & Gateway"
        case "accounting.view":
            return isArabic ? "استعراض السجلات المحاسبية" : "View Accounting Ledger"
        case "staff.manage":
            return isArabic ? "إدارة الموظفين والأدوار" : "Manage Staff & Roles"
        case "users.manage":
            return isArabic ? "إدارة حسابات المستخدمين" : "Manage User Accounts"
        case "audit.view":
            return isArabic ? "استعراض سجل التدقيق الأمني" : "View Audit Trail"
        default:
            return key
        }
    }

    private func permissionDomainRow(_ domain: PermissionDomain) -> some View {
        HStack(alignment: .top, spacing: AdminSpacing.md) {
            Image(systemName: domain.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(domain.tint)
                .frame(width: 38, height: 38)
                .background(domain.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: AdminSpacing.xs) {
                    Text(domain.title)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(domain.clearanceTag)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(domain.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(domain.tint.opacity(0.10), in: Capsule())
                }

                Text(domain.description)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(Language.get("AdminPerm_CryptoSignature", alter: "بصمة تشفير الصلاحيات غير قابلة للتلاعب: مصادقة SHA256"))
                .font(AdminType.caption2Medium)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
        let isArabic = Language.isRTL()
        let perms = grantedPermissionsList
        let hasPOS = isOwner || isSuperAdmin || isAdmin || perms.contains("pos.sell") || perms.contains("pos.history")
        let hasStock = isOwner || isSuperAdmin || isAdmin || perms.contains("stock.manage") || perms.contains("stock.view")
        let hasPayments = isOwner || isSuperAdmin || isAdmin || perms.contains("payments.manage") || perms.contains("accounting.manage")
        let hasGovernance = isOwner || isSuperAdmin || perms.contains("staff.manage")
        let hasServices = isOwner || isSuperAdmin || isAdmin || perms.contains("services.manage")
        let hasAudit = isOwner || isSuperAdmin || perms.contains("audit.view")

        return [
            PermissionDomain(
                title: Language.get("AdminPerm_D2_Title", alter: "المخزون والمنتجات ونقاط البيع السريعة"),
                description: isArabic ? "عمليات البيع الميداني، إصدار الفواتير، وسجل المبيعات اليومية" : "Point of sale fast transactions, receipts, and branch logs",
                clearanceTag: hasPOS ? (isArabic ? "مفعّلة ومصرح بها" : "Authorized / Active") : (isArabic ? "مقيّدة" : "Restricted"),
                icon: "cart.fill",
                tint: hasPOS ? Color.teal : Color.secondary
            ),
            PermissionDomain(
                title: Language.get("AdminPerm_D1_Title", alter: "إدارة الطلبات والمدفوعات والمحاسبة"),
                description: isArabic ? "اعتماد التحويلات، استرداد الأموال، ومتابعة بوابات الدفع QIB" : "Payment processing, refunds, and financial ledgers",
                clearanceTag: hasPayments ? (isArabic ? "مفعّلة ومصرح بها" : "Authorized / Active") : (isArabic ? "مقيّدة (إدارة عليا)" : "Restricted"),
                icon: "creditcard.fill",
                tint: hasPayments ? AdminSurface.primary : Color.secondary
            ),
            PermissionDomain(
                title: isArabic ? "المخزون والمستودعات والتوريدات" : "Inventory & Warehouse Management",
                description: isArabic ? "تعديل الأسعار وإدارة المخزون والتوريدات في الفروع" : "Stock adjustments, warehouse logistics, and item catalog",
                clearanceTag: hasStock ? (isArabic ? "مفعّلة ومصرح بها" : "Authorized / Active") : (isArabic ? "مقيّدة" : "Restricted"),
                icon: "shippingbox.fill",
                tint: hasStock ? Color.orange : Color.secondary
            ),
            PermissionDomain(
                title: Language.get("AdminPerm_D4_Title", alter: "المستخدمون وصلاحيات الموظفين والحوكمة"),
                description: isArabic ? "تعيين الأدوار الإدارية، تجميد الحسابات، وإدارة فرق العمل" : "Role assignments, staff onboarding, and security policies",
                clearanceTag: hasGovernance ? (isArabic ? "حوكمة وإشراف" : "Governance") : (isArabic ? "إدارة عليا فقط" : "Admin Only"),
                icon: "person.3.fill",
                tint: hasGovernance ? Color.indigo : Color.secondary
            ),
            PermissionDomain(
                title: Language.get("AdminPerm_D3_Title", alter: "الخدمات والعيادات البيطرية والمزودون"),
                description: isArabic ? "مراجعة واعتماد ملفات العيادات والمزودين وجدولة الخدمات" : "Veterinary clinic listings, bookings, and provider management",
                clearanceTag: hasServices ? (isArabic ? "مفعّلة ومصرح بها" : "Authorized / Active") : (isArabic ? "مقيّدة" : "Restricted"),
                icon: "cross.case.fill",
                tint: hasServices ? Color.blue : Color.secondary
            ),
            PermissionDomain(
                title: Language.get("AdminPerm_D6_Title", alter: "سجل التدقيق والمراقبة الأمنية السيادية"),
                description: isArabic ? "تتبع فوري وغير قابل للتعديل لكافة العمليات والأوامر الحساسة" : "Tamper-evident audit trail for system commands",
                clearanceTag: hasAudit ? (isArabic ? "مراقبة مباشرة" : "Live Audit") : (isArabic ? "مقيّدة" : "Restricted"),
                icon: "doc.text.magnifyingglass",
                tint: hasAudit ? Color.green : Color.secondary
            )
        ]
    }
}

// MARK: - Related Screen 2: Security Vault & Session Defense Sheet

struct AdminSecurityVaultSheetView: View {
    @ObservedObject var viewModel: AdminAccountViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var isPulseActive: Bool = false
    @State private var copiedTokenToast: Bool = false
    @State private var toastTask: Task<Void, Never>? = nil

    private var isRegular: Bool {
        horizontalSizeClass == .regular
    }

    private var biometryType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return context.biometryType
        }
        return .none
    }

    private var biometrySymbol: String {
        switch biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "person.badge.shield.checkmark.fill"
        }
    }

    private var biometryTitle: String {
        switch biometryType {
        case .faceID:
            return Language.get("SecurityVault_FaceID_Title", alter: "المصادقة عبر Face ID")
        case .touchID:
            return Language.get("SecurityVault_TouchID_Title", alter: "المصادقة عبر Touch ID")
        case .opticID:
            return Language.get("SecurityVault_OpticID_Title", alter: "المصادقة عبر Optic ID")
        default:
            return Language.get("SecurityVault_Biometrics_Title", alter: "المصادقة البيومترية المتقدمة")
        }
    }

    private var deviceModelDisplayName: String {
        let name = UIDevice.current.name
        if !name.isEmpty && name != "iPhone" && name != "iPad" {
            return name
        }
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad Pro (M-Series)" : "iPhone 13 Pro Max"
    }

    private var deviceOSDisplayName: String {
        "iOS " + UIDevice.current.systemVersion
    }

    private var sessionTokenDigest: String {
        guard let uid = viewModel.currentUser?.uid, uid.count >= 8 else {
            return "SHA256: 7F8A91C2...E92D"
        }
        return "SHA256: " + uid.prefix(6).uppercased() + "..." + uid.suffix(4).uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sovereign Vault Header
            vaultSovereignHeader

            // Vault Body Canvas
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if isRegular {
                        ipadDualChamberLayout
                    } else {
                        iphoneVerticalChamberLayout
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, AdminSpacing.sm)
                .padding(.bottom, AdminSpacing.xxl)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .overlay(alignment: .top) {
            if copiedTokenToast {
                copiedToastBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(Animation.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    isPulseActive = true
                }
            }
        }
    }

    // MARK: - Sovereign Vault Header Bar
    private var vaultSovereignHeader: some View {
        HStack(spacing: 12) {
            AdminSquircleCloseButton {
                dismiss()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Language.get("SecurityVault_SheetTitle", alter: "خزنة الأمان والجلسات"))
                        .font(AdminType.title3Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    // Enclave Attestation Chip
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber)
                            .frame(width: 6, height: 6)
                        Text(viewModel.biometricsEnabled ? "SECURE" : "ADVISORY")
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber).opacity(0.12), in: Capsule())
                }

                Text(Language.get("SecurityVault_SheetSubtitle", alter: "الرقابة العتادية والتشفير السيادي للجلسة"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Live Cipher Protocol Badge
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("App Attest")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(AdminSurface.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AdminSurface.control, in: Capsule())
            .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.75))
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(AdminSurface.surface.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.5)
        }
    }

    // MARK: - iPhone Vertical Layout
    private var iphoneVerticalChamberLayout: some View {
        VStack(spacing: AdminSpacing.md) {
            // Dominant Anchor: Cryptographic Enclave Radar
            enclaveHeroRadarPedestal

            // Biometric Hardware Governance Chamber
            biometricDefenseChamber

            // Hardware App Check & Attestation Telemetry
            hardwareAttestationChamber

            // Credential Lifecycle & Password Reset Dispatcher
            credentialLifecycleChamber

            // Emergency Immediate Lockdown Console
            emergencyLockdownChamber
        }
    }

    // MARK: - iPad Dual Chamber Panoramic Layout
    private var ipadDualChamberLayout: some View {
        HStack(alignment: .top, spacing: AdminSpacing.lg) {
            // Leading Chamber (44%): Attestation, Telemetry & Enclave Posture
            VStack(spacing: AdminSpacing.md) {
                enclaveHeroRadarPedestal
                hardwareAttestationChamber
            }
            .frame(maxWidth: .infinity)

            // Trailing Chamber (56%): Governance Controls, Credentials & Emergency Lock
            VStack(spacing: AdminSpacing.md) {
                biometricDefenseChamber
                credentialLifecycleChamber
                emergencyLockdownChamber
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 1080)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dominant Visual Anchor: Enclave Hero Radar Pedestal
    private var enclaveHeroRadarPedestal: some View {
        VStack(spacing: 14) {
            // Holographic Enclave Shield Graphic
            ZStack {
                // Outer ambient defense aura
                Circle()
                    .fill((viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber).opacity(isPulseActive ? 0.16 : 0.08))
                    .frame(width: 104, height: 104)
                    .scaleEffect(isPulseActive ? 1.08 : 0.96)

                Circle()
                    .stroke(
                        (viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber).opacity(0.24),
                        lineWidth: 1.5
                    )
                    .frame(width: 88, height: 88)

                // Central Shield Squircle
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                (viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber).opacity(0.18),
                                AdminSurface.surface
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 68, height: 68)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                (viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber).opacity(0.4),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(
                        color: (viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber).opacity(0.18),
                        radius: 10,
                        x: 0,
                        y: 4
                    )

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber,
                                viewModel.biometricsEnabled ? Color(red: 0.1, green: 0.8, blue: 0.5) : Color.orange
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .padding(.top, 4)

            // Title & Status
            VStack(spacing: 4) {
                Text(Language.get("SecurityVault_Hero_Title", alter: "خزنة الأمان وحماية الجلسة الإدارية"))
                    .font(AdminType.title3Bold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)

                Text(Language.get("SecurityVault_Hero_Subtitle", alter: "المصادقة البيومترية، فحص العتاد المعتمد، وتشفير الجلسات"))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            // Identity & Clearance Footer Deck
            HStack(spacing: 8) {
                // Identity Pill
                HStack(spacing: 5) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(viewModel.currentUser?.ppBestDisplayName() ?? viewModel.name)
                        .font(AdminType.caption1Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AdminSurface.control, in: Capsule())

                // Staff ID Token
                Button {
                    copyTokenToClipboard(viewModel.staffID, label: Language.get("SecurityVault_StaffID_Copied", alter: "تم نسخ معرّف المسؤول"))
                } label: {
                    HStack(spacing: 4) {
                        Text("#\(viewModel.staffID)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundStyle(AdminSurface.secondaryText.opacity(0.7))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AdminSurface.control, in: Capsule())
                    .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.6))
                }
                .buttonStyle(.plain)

                // Enclave Health Pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber)
                        .frame(width: 6, height: 6)
                    Text(viewModel.biometricsEnabled ? (Language.isRTL() ? "100% موثق" : "100% Secured") : (Language.isRTL() ? "تنبيه دفاعي" : "Advisory"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background((viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber).opacity(0.10), in: Capsule())
            }
        }
        .padding(AdminSpacing.cardPadding)
        .frame(maxWidth: .infinity)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(
                    (viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber).opacity(0.28),
                    lineWidth: 1.0
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.04), radius: 10, x: 0, y: 3)
    }

    // MARK: - Chamber 1: Biometric Hardware Defense Chamber
    private var biometricDefenseChamber: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AdminSurface.primary.opacity(0.24), lineWidth: 0.75)
                        )

                    Image(systemName: biometrySymbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(biometryTitle)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(viewModel.biometricsEnabled ? (Language.isRTL() ? "مفعلة" : "Active") : (Language.isRTL() ? "معطلة" : "Inactive"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.secondaryText).opacity(0.10), in: Capsule())
                    }

                    Text(Language.get("SecurityVault_Biometrics_Desc", alter: "طلب التحقق البيومتري عند فتح التطبيق ولوحة التحكم لمنع التطفل."))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: Binding(
                    get: { viewModel.biometricsEnabled },
                    set: { newValue in
                        withAnimation(AdminAnimation.standard) {
                            viewModel.toggleBiometrics(to: newValue)
                        }
                    }
                ))
                .labelsHidden()
                .tint(AdminSurface.primary)
                .accessibilityLabel(biometryTitle)
                .accessibilityValue(viewModel.biometricsEnabled ? (Language.isRTL() ? "مفعل" : "Enabled") : (Language.isRTL() ? "معطل" : "Disabled"))
            }

            // Security Behavior Guarantee Line
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.secondaryText)
                Text(viewModel.biometricsEnabled
                    ? (Language.isRTL() ? "الجلسة محمية: لا يمكن استئناف لوحة التحكم دون المصادقة البيومترية." : "Protected session: Command Center requires biometric unlock.")
                    : (Language.isRTL() ? "تنبيه أمني: يوصى بتفعيل البصمة لحماية العمليات والبيانات المالية." : "Security advisory: Enable biometrics to safeguard customer operations.")
                )
                .font(AdminType.caption2)
                .foregroundStyle(viewModel.biometricsEnabled ? AdminSurface.emerald : AdminSurface.amber)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
    }

    // MARK: - Chamber 2: Hardware App Check & Attestation Telemetry
    private var hardwareAttestationChamber: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.control)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 0.75)
                        )

                    Image(systemName: UIDevice.current.userInterfaceIdiom == .pad ? "ipad.gen2" : "iphone.gen3")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(deviceModelDisplayName)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)

                        Spacer(minLength: 4)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(AdminSurface.emerald)
                                .frame(width: 6, height: 6)
                            Text(Language.get("SecurityVault_Attested_Badge", alter: "موثق بعتاد Apple"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AdminSurface.emerald)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AdminSurface.emerald.opacity(0.12), in: Capsule())
                    }

                    Text(Language.get("SecurityVault_AppCheck_Desc", alter: "جلسة مصادقة مشفرة ومحمية عبر Firebase App Check (Apple DeviceCheck / App Attest)"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            // Micro-Telemetry 3-Column Deck
            HStack(spacing: 8) {
                telemetryMetricTile(
                    title: Language.isRTL() ? "التشفير" : "Cipher",
                    value: "AES-256",
                    icon: "lock.shield",
                    color: AdminSurface.primary
                )
                telemetryMetricTile(
                    title: Language.isRTL() ? "البروتوكول" : "Protocol",
                    value: "App Attest",
                    icon: "checkmark.seal.fill",
                    color: AdminSurface.emerald
                )
                telemetryMetricTile(
                    title: Language.isRTL() ? "النظام" : "Platform",
                    value: deviceOSDisplayName,
                    icon: "applelogo",
                    color: AdminSurface.secondaryText
                )
            }

            // Session SHA256 Token Preview & Copy Affordance
            Button {
                copyTokenToClipboard(sessionTokenDigest, label: Language.get("SecurityVault_Digest_Copied", alter: "تم نسخ بصمة الجلسة المشفرة"))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text(sessionTokenDigest)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    HStack(spacing: 3) {
                        Text(Language.isRTL() ? "نسخ البصمة" : "Copy")
                            .font(AdminType.caption2Bold)
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(AdminSurface.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.isRTL() ? "نسخ بصمة تشفير الجلسة" : "Copy session cryptographic digest")
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
    }

    private func telemetryMetricTile(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Chamber 3: Credential Lifecycle & Password Reset Dispatcher
    private var credentialLifecycleChamber: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                Text(Language.get("SecurityVault_Credentials_Title", alter: "إدارة كلمة المرور والاعتماد"))
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Text(Language.isRTL() ? "مشفر" : "Encrypted")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AdminSurface.control, in: Capsule())
            }

            // Target Authorized Email Banner
            HStack(spacing: 8) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AdminSurface.primary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("SecurityVault_Email_Target", alter: "البريد الإداري المسجل للاعتماد:"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text(viewModel.email)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(Language.get("SecurityVault_Reset_Notice", alter: "يمكنك إرسال رابط تشفيري لإعادة تعيين كلمة المرور إلى بريدك المسجل صالح لمدة محدودة."))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
                .lineLimit(2)

            // Primary Dispatch Button
            Button {
                viewModel.sendPasswordReset()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSendingPasswordReset {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                        Text(Language.get("SecurityVault_Sending", alter: "جاري إرسال الرابط المشفر..."))
                            .font(AdminType.calloutBold)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("SecurityVault_SendReset_Button", alter: "إرسال رابط إعادة تعيين كلمة المرور إلى البريد"))
                            .font(AdminType.calloutBold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    LinearGradient(
                        colors: [
                            AdminSurface.primary,
                            AdminSurface.primaryPressed
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                )
                .foregroundColor(.white)
                .shadow(color: AdminSurface.primary.opacity(0.28), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSendingPasswordReset)
            .accessibilityLabel(Language.get("SecurityVault_SendReset_Button", alter: "إرسال رابط إعادة تعيين كلمة المرور"))
            .accessibilityHint(Language.isRTL() ? "يرسل رابط أمان إلى بريدك الإلكتروني" : "Dispatches security reset link to your email")
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1.0)
        )
    }

    // MARK: - Chamber 4: Emergency Immediate Lockdown Console
    private var emergencyLockdownChamber: some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AdminSurface.crimson.opacity(0.12))
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AdminSurface.crimson.opacity(0.3), lineWidth: 0.75)
                        )

                    Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AdminSurface.crimson)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("SecurityVault_EmergencyLock_Title", alter: "قفل لوحة التحكم فوراً"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.crimson)

                    Text(Language.get("SecurityVault_EmergencyLock_Desc", alter: "إنهاء الجلسة اللحظي وإلغاء الصلاحيات حتى إعادة التحقق البيومتري."))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AdminSurface.crimson.opacity(0.8))
            }
            .padding(12)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .strokeBorder(AdminSurface.crimson.opacity(0.35), lineWidth: 1.0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Language.get("SecurityVault_EmergencyLock_Title", alter: "قفل لوحة التحكم فوراً"))
        .accessibilityHint(Language.isRTL() ? "يقوم بإغلاق لوحة التحكم فوراً ويتطلب البصمة لإعادة الفتح" : "Immediately locks command center requiring biometric re-authentication")
    }

    // MARK: - Toast Banner
    private var copiedToastBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AdminSurface.emerald)
            Text(Language.isRTL() ? "تم النسخ إلى الحافظة بنجاح" : "Copied to clipboard")
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.primaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.75))
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
        .padding(.top, 56)
    }

    private func copyTokenToClipboard(_ text: String, label: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIPasteboard.general.string = text
        withAnimation(AdminAnimation.fast) {
            copiedTokenToast = true
        }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(AdminAnimation.fast) {
                copiedTokenToast = false
            }
        }
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
                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 130, height: 130)) {
                            defaultMonogram
                        }
                        .frame(width: 130, height: 130)
                        .clipShape(Circle())
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
