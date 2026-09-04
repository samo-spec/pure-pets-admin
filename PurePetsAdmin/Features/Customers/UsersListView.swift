//
//  UsersListView.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles: Category-defining Customer Operations &
//  Identity Intelligence Horizon. A studio-grade flagship interface with unprecedented
//  spatial telemetry, real-time live synchronization, comprehensive customer dossier inspection,
//  instant walk-in onboarding, and deep access/restriction control.
//

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth
import FirebaseCore

// MARK: - Customer Status Model

enum CustomerAccountStatus: String, CaseIterable, Identifiable, Sendable {
    case active = "active"
    case pendingReview = "pending_review"
    case disabled = "disabled"
    case blocked = "blocked"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:
            return Language.get("MissionControl_Customers_Status_Active", alter: "نشط ومؤكد")
        case .pendingReview:
            return Language.get("MissionControl_Customers_Status_PendingReview", alter: "قيد المراجعة")
        case .disabled:
            return Language.get("MissionControl_Customers_Status_Disabled", alter: "معطّل")
        case .blocked:
            return Language.get("MissionControl_Customers_Status_Blocked", alter: "محظور")
        }
    }

    var icon: String {
        switch self {
        case .active: return "checkmark.seal.fill"
        case .pendingReview: return "clock.badge.exclamationmark.fill"
        case .disabled: return "slash.circle.fill"
        case .blocked: return "nosign"
        }
    }

    var color: Color {
        switch self {
        case .active: return Color(uiColor: .ppSuccess)
        case .pendingReview: return Color(uiColor: .ppWarning)
        case .disabled: return Color(uiColor: .ppTextSecondary)
        case .blocked: return Color(uiColor: .ppError)
        }
    }
}

// MARK: - Customer Account Model

struct PPCustomerAccountModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let email: String
    let phone: String
    let photoURL: String?
    let status: CustomerAccountStatus
    let isVerified: Bool
    let isOnline: Bool
    let lastSeen: Date?
    let createdAt: Date?
    let accountType: String
    let features: [String: Bool]
    let restrictions: [String: Bool]

    var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "PP" }
        let components = trimmed.components(separatedBy: " ")
        if components.count >= 2,
           let firstChar = components.first?.first,
           let lastChar = components.last?.first {
            return "\(firstChar)\(lastChar)".uppercased()
        }
        return String(trimmed.prefix(2)).uppercased()
    }

    var gradientColors: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.60, green: 0.05, blue: 0.20), Color(red: 0.85, green: 0.15, blue: 0.35)], // PurePets Crimson
            [Color(red: 0.08, green: 0.45, blue: 0.85), Color(red: 0.18, green: 0.65, blue: 0.95)], // Sapphire Blue
            [Color(red: 0.05, green: 0.58, blue: 0.40), Color(red: 0.10, green: 0.75, blue: 0.55)], // Emerald Green
            [Color(red: 0.82, green: 0.38, blue: 0.05), Color(red: 0.95, green: 0.55, blue: 0.15)], // Amber Gold
            [Color(red: 0.45, green: 0.15, blue: 0.70), Color(red: 0.65, green: 0.28, blue: 0.88)], // Amethyst Purple
            [Color(red: 0.10, green: 0.60, blue: 0.65), Color(red: 0.20, green: 0.75, blue: 0.78)]  // Deep Teal
        ]
        let index = abs(id.hashValue) % palettes.count
        return palettes[index]
    }

    var shortUID: String {
        guard id.count > 10 else { return id }
        let prefix = id.prefix(4)
        let suffix = id.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    var formattedPhone: String {
        let digits = phone.filter { "0123456789+".contains($0) }
        return digits.isEmpty ? phone : digits
    }

    var hasRestrictions: Bool {
        restrictions.values.contains(true)
    }

    var activeRestrictionsCount: Int {
        restrictions.values.filter { $0 }.count
    }

    var activeFeaturesCount: Int {
        features.values.filter { $0 }.count
    }

    var requiresAttention: Bool {
        status == .blocked || status == .pendingReview || status == .disabled || hasRestrictions
    }
}

// MARK: - Filter Tabs & Sort

enum CustomerFilterTab: Int, CaseIterable, Identifiable {
    case all = 0
    case active = 1
    case verified = 2
    case needsAttention = 3
    case blocked = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all: return Language.get("POS_Filter_All", alter: "الكل")
        case .active: return Language.get("Active", alter: "نشط")
        case .verified: return Language.get("MissionControl_Customers_Metric_Verified", alter: "موثّق")
        case .needsAttention: return Language.get("MissionControl_Customers_Metric_Attention", alter: "تحتاج مراجعة")
        case .blocked: return Language.get("MissionControl_Customers_Status_Blocked", alter: "محظور")
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .active: return "checkmark.seal.fill"
        case .verified: return "checkmark.shield.fill"
        case .needsAttention: return "exclamationmark.octagon.fill"
        case .blocked: return "nosign"
        }
    }
}

enum CustomerSortOption: String, CaseIterable, Identifiable {
    case recent = "recent"
    case nameAsc = "name_asc"
    case nameDesc = "name_desc"
    case status = "status"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return Language.get("Sort_Recent", alter: "الأحدث نشاطاً")
        case .nameAsc: return Language.get("Sort_NameAsc", alter: "الاسم (أ - ي)")
        case .nameDesc: return Language.get("Sort_NameDesc", alter: "الاسم (ي - أ)")
        case .status: return Language.get("Sort_Status", alter: "حسب الحالة")
        }
    }
}

// MARK: - Feature & Restriction Definitions

struct PPCustomerFeatureItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
}

struct PPCustomerRestrictionItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
}

private enum PPCustomerCatalog {
    static let features: [PPCustomerFeatureItem] = [
        PPCustomerFeatureItem(id: "canPostPetAds", title: "نشر إعلانات الحيوانات", subtitle: "إمكانية طرح حيوانات أليفة للبيع في الكتالوج", icon: "pawprint.fill", color: Color(red: 0.85, green: 0.35, blue: 0.15)),
        PPCustomerFeatureItem(id: "canPostAdoption", title: "طلبات وعروض التبني", subtitle: "مشاركة حيوانات للتبني الإنساني ورعايتها", icon: "heart.circle.fill", color: Color(red: 0.90, green: 0.20, blue: 0.45)),
        PPCustomerFeatureItem(id: "canSellAccessories", title: "بيع المستلزمات والأطعمة", subtitle: "إضافة منتجات أكسسوارات وأغذية للبيع", icon: "tag.fill", color: Color(red: 0.20, green: 0.50, blue: 0.90)),
        PPCustomerFeatureItem(id: "canOfferServices", title: "الخدمات والرعاية والعيادات", subtitle: "تقديم استشارات بيطرية وحلاقة وتدريب", icon: "cross.case.fill", color: Color(red: 0.55, green: 0.20, blue: 0.80)),
        PPCustomerFeatureItem(id: "canUseChat", title: "المحادثات الفورية المباشرة", subtitle: "التواصل الفوري مع خدمة العملاء والمتاجر", icon: "bubble.left.and.bubble.right.fill", color: Color(red: 0.08, green: 0.65, blue: 0.45)),
        PPCustomerFeatureItem(id: "canUseStories", title: "القصص واليوميات المصورة", subtitle: "مشاركة يوميات الحيوانات وتفاعلات المجتمع", icon: "camera.metering.spot", color: Color(red: 0.95, green: 0.55, blue: 0.10)),
        PPCustomerFeatureItem(id: "canAccessPremiumMarketplace", title: "سوق النخبة والمميّزين", subtitle: "الاطلاع على المزادات الحصرية والحيوانات النادرة", icon: "star.hexagonpath.fill", color: Color(red: 0.85, green: 0.65, blue: 0.05)),
        PPCustomerFeatureItem(id: "canAccessProviderMarketplace", title: "سوق المزوّدين المعتمدين", subtitle: "الشراء والطلب المباشر من الموردين بالجملة", icon: "building.2.crop.circle.fill", color: Color(red: 0.15, green: 0.60, blue: 0.75))
    ]

    static let restrictions: [PPCustomerRestrictionItem] = [
        PPCustomerRestrictionItem(id: "postingBlocked", title: "حظر النشر الإعلاني", subtitle: "منع المستخدم من إضافة أو تجديد أي إعلانات", icon: "nosign"),
        PPCustomerRestrictionItem(id: "chatBlocked", title: "حظر المحادثات والشات", subtitle: "تعطيل إرسال واستقبال الرسائل الفورية", icon: "bubble.left.and.exclamationmark.bubble.right.fill"),
        PPCustomerRestrictionItem(id: "purchaseBlocked", title: "حظر الشراء ونقاط البيع", subtitle: "إيقاف تنفيذ عمليات الدفع وشراء الطلبات", icon: "cart.badge.minus"),
        PPCustomerRestrictionItem(id: "withdrawalBlocked", title: "حظر السحب والتحويل المالي", subtitle: "تجميد عمليات سحب الأرصدة والمحفظة", icon: "banknote.fill")
    ]
}

// MARK: - ViewModel

@MainActor
final class AdminCustomerAccountsViewModel: ObservableObject {
    @Published private(set) var allCustomers: [PPCustomerAccountModel] = []
    @Published private(set) var filteredCustomers: [PPCustomerAccountModel] = []
    @Published var searchText: String = ""
    @Published var activeTab: CustomerFilterTab = .all
    @Published var activeSort: CustomerSortOption = .recent
    @Published var isLoading: Bool = true
    @Published var isRefreshing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var toastMessage: String? = nil
    @Published var activeDossierCustomer: PPCustomerAccountModel? = nil
    @Published var isAddCustomerSheetPresented: Bool = false

    private nonisolated(unsafe) var listener: (any ListenerRegistration)? = nil

    init() {
        startListening()
    }

    deinit {
        listener?.remove()
    }

    // Telemetry stats
    var totalCount: Int { allCustomers.count }
    var activeCount: Int { allCustomers.filter { $0.status == .active }.count }
    var verifiedCount: Int { allCustomers.filter { $0.isVerified }.count }
    var attentionCount: Int { allCustomers.filter { $0.requiresAttention }.count }
    var blockedCount: Int { allCustomers.filter { $0.status == .blocked }.count }

    func startListening() {
        isLoading = allCustomers.isEmpty
        errorMessage = nil
        listener?.remove()

        let db = Firestore.firestore()
        listener = db.collection("UsersCol").addSnapshotListener { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                self.isRefreshing = false

                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let docs = snapshot?.documents else { return }

                var parsed: [PPCustomerAccountModel] = []
                for doc in docs {
                    let data = doc.data()
                    let accountType = ((data["accountType"] as? String) ?? "user").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    // Filter out staff accounts — this screen is customer identity operations
                    if accountType == "staff" { continue }

                    let uid = doc.documentID
                    let name = (data["UserName"] as? String)
                        ?? (data["displayName"] as? String)
                        ?? (data["FirstName"] as? String)
                        ?? Language.get("MissionControl_Customers_Unknown_Identity", alter: "عميل بدون اسم")

                    let email = (data["UserEmail"] as? String)
                        ?? (data["email"] as? String)
                        ?? ""

                    let phone = (data["MobileNo"] as? String)
                        ?? (data["phone"] as? String)
                        ?? ""

                    let photo = (data["photoURL"] as? String)
                        ?? (data["UserImageUrl"] as? String)
                        ?? (data["UserImageName"] as? String)

                    let rawStatus = ((data["accountStatus"] as? String) ?? "").lowercased()
                    let isBlocked = (data["isBlocked"] as? Bool) ?? false

                    let status: CustomerAccountStatus = {
                        if isBlocked || rawStatus == "blocked" { return .blocked }
                        if rawStatus == "pending_review" { return .pendingReview }
                        if rawStatus == "disabled" { return .disabled }
                        return .active
                    }()

                    let verified = (data["verified"] as? Bool) ?? false
                    let onlineStatus = (data["onlineStatus"] as? Int) ?? 0
                    let isOnline = onlineStatus == 1 || (data["isOnline"] as? Bool == true)

                    let lastSeenTimestamp = data["lastSeen"] as? Timestamp
                    let createdTimestamp = (data["createdAt"] as? Timestamp) ?? (data["loginDate"] as? Timestamp)

                    let features = (data["features"] as? [String: Bool]) ?? [:]
                    let restrictions = (data["restrictions"] as? [String: Bool]) ?? [:]

                    parsed.append(
                        PPCustomerAccountModel(
                            id: uid,
                            name: name,
                            email: email,
                            phone: phone,
                            photoURL: photo,
                            status: status,
                            isVerified: verified,
                            isOnline: isOnline,
                            lastSeen: lastSeenTimestamp?.dateValue(),
                            createdAt: createdTimestamp?.dateValue(),
                            accountType: accountType,
                            features: features,
                            restrictions: restrictions
                        )
                    )
                }

                self.allCustomers = parsed
                self.applyFilter()
            }
        }
    }

    func applyFilter() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let baseFiltered = allCustomers.filter { customer in
            // Tab filter
            let matchesTab: Bool = {
                switch activeTab {
                case .all: return true
                case .active: return customer.status == .active
                case .verified: return customer.isVerified
                case .needsAttention: return customer.requiresAttention
                case .blocked: return customer.status == .blocked
                }
            }()
            guard matchesTab else { return false }

            // Search query filter
            guard !q.isEmpty else { return true }
            return customer.name.lowercased().contains(q)
                || customer.email.lowercased().contains(q)
                || customer.phone.lowercased().contains(q)
                || customer.id.lowercased().contains(q)
        }

        // Apply Sorting
        filteredCustomers = baseFiltered.sorted { a, b in
            switch activeSort {
            case .recent:
                let dateA = a.lastSeen ?? a.createdAt ?? Date.distantPast
                let dateB = b.lastSeen ?? b.createdAt ?? Date.distantPast
                return dateA > dateB
            case .nameAsc:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .nameDesc:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
            case .status:
                return a.status.rawValue < b.status.rawValue
            }
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            if self?.toastMessage == message {
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.toastMessage = nil
                }
            }
        }
    }

    // MARK: - Customer Mutation Actions

    func updateCustomerStatus(customer: PPCustomerAccountModel, toStatus: CustomerAccountStatus, reason: String = "") {
        let uid = customer.id
        let statusString = toStatus.rawValue

        AdminService.updateUserStatus(uid, status: statusString, reason: reason.isEmpty ? "admin_console_update" : reason, duration: nil) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.showToast(self?.friendlyErrorMessage(for: error) ?? error.localizedDescription)
                } else {
                    self?.showToast(Language.get("Customer_Status_Updated", alter: "تم تحديث حالة الحساب بنجاح"))
                    self?.startListening()
                }
            }
        }
    }

    func toggleVerification(customer: PPCustomerAccountModel) {
        let uid = customer.id
        let newVerified = !customer.isVerified

        AdminService.updateUserVerified(uid, verified: newVerified) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.showToast(self?.friendlyErrorMessage(for: error) ?? error.localizedDescription)
                } else {
                    let msg = newVerified
                        ? Language.get("Customer_Verified_Success", alter: "تم توثيق الحساب بنجاح")
                        : Language.get("Customer_Unverified_Success", alter: "تم إلغاء توثيق الحساب")
                    self?.showToast(msg)
                    self?.startListening()
                }
            }
        }
    }

    func updateFeature(customer: PPCustomerAccountModel, featureKey: String, isEnabled: Bool) {
        let uid = customer.id
        var updated = customer.features
        updated[featureKey] = isEnabled

        AdminService.updateUserFeatures(uid, features: updated) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.showToast(self?.friendlyErrorMessage(for: error) ?? error.localizedDescription)
                } else {
                    self?.showToast(Language.get("Customer_Feature_Updated", alter: "تم تحديث صلاحية الميزة"))
                    self?.startListening()
                }
            }
        }
    }

    func updateRestriction(customer: PPCustomerAccountModel, restrictionKey: String, isBlocked: Bool) {
        let uid = customer.id
        var updated = customer.restrictions
        updated[restrictionKey] = isBlocked

        AdminService.updateUserRestrictions(uid, restrictions: updated) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.showToast(self?.friendlyErrorMessage(for: error) ?? error.localizedDescription)
                } else {
                    self?.showToast(Language.get("Customer_Restriction_Updated", alter: "تم تحديث قيد الأمان"))
                    self?.startListening()
                }
            }
        }
    }

    func sendPasswordReset(email: String) {
        guard !email.isEmpty else {
            showToast(Language.get("Error_NoEmail", alter: "العميل لا يمتلك بريداً إلكترونياً مسجلاً"))
            return
        }
        Auth.auth().sendPasswordReset(withEmail: email) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.showToast(self?.friendlyErrorMessage(for: error) ?? error.localizedDescription)
                } else {
                    self?.showToast(Language.get("PasswordReset_Sent", alter: "تم إرسال رابط إعادة تعيين كلمة المرور إلى بريد العميل"))
                }
            }
        }
    }

    func createCustomer(
        name: String,
        email: String,
        phone: String,
        password: String,
        initialStatus: CustomerAccountStatus,
        isVerified: Bool,
        completion: @escaping @MainActor @Sendable (Bool, String?) -> Void
    ) {
        AdminService.createCustomerAccount(
            withName: name,
            email: email,
            phone: phone.isEmpty ? nil : phone,
            password: password,
            initialStatus: initialStatus.rawValue,
            isVerified: isVerified
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    let friendly = self?.friendlyErrorMessage(for: error) ?? error.localizedDescription
                    completion(false, friendly)
                    return
                }
                self?.showToast(Language.get("Customer_Created_Success", alter: "تم إنشاء حساب العميل بنجاح"))
                self?.startListening()
                completion(true, nil)
            }
        }
    }

    func friendlyErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        let errorDesc = error.localizedDescription.lowercased()
        let code = nsError.code

        if errorDesc.contains("permission") || errorDesc.contains("insufficient") || code == 7 {
            return Language.get("Error_Customer_PermissionDenied", alter: "لا تمتلك الصلاحيات الكافية (إدارة المستخدمين) لتسجيل عميل جديد")
        }
        if errorDesc.contains("already exists") || errorDesc.contains("already-exists") || code == 6 {
            return Language.get("Error_Customer_AlreadyExists", alter: "البريد الإلكتروني مسجل بالفعل لحساب آخر")
        }
        if errorDesc.contains("invalid email") || (errorDesc.contains("invalid-argument") && errorDesc.contains("email")) {
            return Language.get("Error_Customer_InvalidEmail", alter: "صيغة البريد الإلكتروني غير صالحة")
        }
        if errorDesc.contains("password must be at least") || errorDesc.contains("weak-password") {
            return Language.get("Error_Customer_WeakPassword", alter: "كلمة المرور يجب ألا تقل عن ٦ خانات")
        }
        if errorDesc.contains("unauthenticated") || code == 16 {
            return Language.get("Error_Customer_Unauthenticated", alter: "انتهت صلاحية الجلسة، يرجى تسجيل الدخول مجدداً")
        }
        if errorDesc.contains("network") || errorDesc.contains("unavailable") || code == 14 {
            return Language.get("Error_Customer_NetworkUnavailable", alter: "تعذر الاتصال بالخادم، يرجى التحقق من اتصال الإنترنت")
        }
        return error.localizedDescription
    }
}

// MARK: - Main Flagship Customer Accounts View

struct AdminUsersListView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminCustomerAccountsViewModel()
    @State private var isSpinning: Bool = false

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    liquidNavBar
                    bentoTelemetryGrid
                    searchAndFilterDeck
                    customerListSection
                }

                // Floating Operational Toast
                if let toast = viewModel.toastMessage {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text(toast)
                                .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .body))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.12, green: 0.14, blue: 0.18), Color(red: 0.18, green: 0.20, blue: 0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.20), radius: 12, y: 6)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.toastMessage)
                }

                // Push Navigation Link for Customer Dossier View
                NavigationLink(
                    destination: Group {
                        if let customer = viewModel.activeDossierCustomer {
                            AdminCustomerDossierView(
                                customer: customer,
                                viewModel: viewModel,
                                onDismiss: {
                                    viewModel.activeDossierCustomer = nil
                                }
                            )
                        }
                    },
                    isActive: Binding(
                        get: { viewModel.activeDossierCustomer != nil },
                        set: { if !$0 { viewModel.activeDossierCustomer = nil } }
                    )
                ) {
                    EmptyView()
                }
                .hidden()
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $viewModel.isAddCustomerSheetPresented) {
            AdminAddCustomerSheet(viewModel: viewModel)
        }
    }

    // MARK: - 1. Liquid Navigation Bar (Sovereign Team Members UI Pattern)

    private var liquidNavBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("MissionControl_Customers_Title", alter: "حسابات العملاء"),
            subtitle: "\(Language.get("CommandCenter_Customers_Workspace", alter: "عمليات العملاء • مباشر")) (\(viewModel.totalCount))",
            statusDotColor: Color(uiColor: .ppSuccess),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            HStack(spacing: 8) {
                AdminSquircleActionButton(
                    systemImage: "arrow.clockwise",
                    isLoading: viewModel.isLoading,
                    accessibilityLabel: Language.get("Refresh", alter: "تحديث")
                ) {
                    viewModel.startListening()
                }

                AdminPrimaryPillButton(
                    title: Language.get("Add", alter: "إضافة"),
                    systemImage: "plus"
                ) {
                    viewModel.isAddCustomerSheetPresented = true
                }
            }
        }
    }

    // MARK: - 2. Bento Telemetry Grid

    private var bentoTelemetryGrid: some View {
        VStack(spacing: 6) {
            // Operational Health Banner
            HStack(spacing: 8) {
                if viewModel.attentionCount == 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(uiColor: .ppSuccess))
                        Text(Language.get("MissionControl_Customers_Signal_Clear", alter: "لا توجد تنبيهات على الحسابات • البيانات مستقرة ومؤكدة"))
                            .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                            .foregroundColor(Color(uiColor: .ppSuccess))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(uiColor: .ppSuccess).opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Button {
                        withAnimation(.spring()) {
                            viewModel.activeTab = .needsAttention
                            viewModel.applyFilter()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppWarning))
                            Text(String(format: Language.get("MissionControl_Customers_Signal_Attention_Format", alter: "تحتاج إلى مراجعة: %@ حساب"), "\(viewModel.attentionCount)") + " • اضغط للتصفية")
                                .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption))
                                .foregroundColor(Color(uiColor: .ppWarning))
                            Spacer()
                            Image(systemName: "arrow.left")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppWarning))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(uiColor: .ppWarning).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 6)

            // 4 Bento Tiles Row
            HStack(spacing: 8) {
                bentoTile(
                    title: Language.get("MissionControl_Customers_Metric_Total", alter: "الإجمالي"),
                    value: "\(viewModel.totalCount)",
                    icon: "person.2.fill",
                    accent: AdminSurface.primary,
                    isSelected: viewModel.activeTab == .all
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        viewModel.activeTab = .all
                        viewModel.applyFilter()
                    }
                }

                bentoTile(
                    title: Language.get("MissionControl_Customers_Metric_Active", alter: "نشط"),
                    value: "\(viewModel.activeCount)",
                    icon: "checkmark.seal.fill",
                    accent: Color(uiColor: .ppSuccess),
                    isSelected: viewModel.activeTab == .active
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        viewModel.activeTab = .active
                        viewModel.applyFilter()
                    }
                }

                bentoTile(
                    title: Language.get("MissionControl_Customers_Metric_Verified", alter: "موثّق"),
                    value: "\(viewModel.verifiedCount)",
                    icon: "checkmark.shield.fill",
                    accent: Color(red: 0.12, green: 0.50, blue: 0.90),
                    isSelected: viewModel.activeTab == .verified
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        viewModel.activeTab = .verified
                        viewModel.applyFilter()
                    }
                }

                bentoTile(
                    title: Language.get("MissionControl_Customers_Metric_Attention", alter: "تحتاج مراجعة"),
                    value: "\(viewModel.attentionCount)",
                    icon: "exclamationmark.octagon.fill",
                    accent: viewModel.attentionCount > 0 ? Color(uiColor: .ppWarning) : AdminSurface.secondaryText,
                    isSelected: viewModel.activeTab == .needsAttention,
                    pulse: viewModel.attentionCount > 0
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        viewModel.activeTab = .needsAttention
                        viewModel.applyFilter()
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
        }
        .padding(.bottom, 6)
    }

    private func bentoTile(
        title: String,
        value: String,
        icon: String,
        accent: Color,
        isSelected: Bool,
        pulse: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        }) {
            VStack(alignment: .center, spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accent)
                    Text(title)
                        .font(Font.custom("Beiruti-Regular", size: 10.5, relativeTo: .caption2))
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }

                Text(value)
                    .font(Font.custom("Beiruti-Bold", size: 19, relativeTo: .title3))
                    .foregroundColor(pulse ? Color(uiColor: .ppWarning) : AdminSurface.primaryText)
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? accent.opacity(0.12) : AdminSurface.surface,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? accent : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - 3. Search & Filter Deck

    private var searchAndFilterDeck: some View {
        VStack(spacing: 8) {
            // Search Input Field
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)

                    TextField(Language.get("MissionControl_Customers_Search_Placeholder", alter: "ابحث بالاسم، البريد، الجوال أو المعرّف..."), text: $viewModel.searchText)
                        .font(Font.custom("Beiruti-Regular", size: 13.5, relativeTo: .body))
                        .onChange(of: viewModel.searchText, perform: { _ in
                            viewModel.applyFilter()
                        })

                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                            viewModel.applyFilter()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 1)
                )

                // Sort Menu Button
                Menu {
                    ForEach(CustomerSortOption.allCases) { opt in
                        Button {
                            viewModel.activeSort = opt
                            viewModel.applyFilter()
                        } label: {
                            HStack {
                                Text(opt.title)
                                if viewModel.activeSort == opt {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 38, height: 38)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)

            // Horizontal Filter Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(CustomerFilterTab.allCases) { tab in
                        let isSelected = viewModel.activeTab == tab
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                viewModel.activeTab = tab
                                viewModel.applyFilter()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tab.title)
                                    .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Regular", size: 12, relativeTo: .caption))

                                let count = countForTab(tab)
                                Text("\(count)")
                                    .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        isSelected ? Color.white.opacity(0.25) : AdminSurface.control,
                                        in: Capsule()
                                    )
                            }
                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? AdminSurface.primary : AdminSurface.surface,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 6)
    }

    private func countForTab(_ tab: CustomerFilterTab) -> Int {
        switch tab {
        case .all: return viewModel.totalCount
        case .active: return viewModel.activeCount
        case .verified: return viewModel.verifiedCount
        case .needsAttention: return viewModel.attentionCount
        case .blocked: return viewModel.blockedCount
        }
    }

    // MARK: - 4. Customer List Section

    private var customerListSection: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if viewModel.isLoading {
                    ForEach(0..<5, id: \.self) { _ in
                        CustomerSkeletonCard()
                    }
                } else if viewModel.filteredCustomers.isEmpty {
                    CustomerEmptyStateView(query: viewModel.searchText) {
                        viewModel.searchText = ""
                        viewModel.activeTab = .all
                        viewModel.applyFilter()
                    }
                } else {
                    ForEach(viewModel.filteredCustomers) { customer in
                        CustomerAccountCardView(
                            customer: customer,
                            onTap: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.activeDossierCustomer = customer
                            },
                            onCopyUID: {
                                UIPasteboard.general.string = customer.id
                                viewModel.showToast(Language.get("UID_Copied", alter: "تم نسخ معرّف العميل بنجاح"))
                            },
                            onToggleVerify: {
                                viewModel.toggleVerification(customer: customer)
                            },
                            onToggleBlock: {
                                let newStatus: CustomerAccountStatus = customer.status == .blocked ? .active : .blocked
                                viewModel.updateCustomerStatus(customer: customer, toStatus: newStatus)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 36)
        }
        .refreshable {
            viewModel.isRefreshing = true
            viewModel.startListening()
        }
    }
}

// MARK: - Flagship Customer Account Card

private struct CustomerAccountCardView: View {
    let customer: PPCustomerAccountModel
    let onTap: () -> Void
    let onCopyUID: () -> Void
    let onToggleVerify: () -> Void
    let onToggleBlock: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Header Row: Avatar, Identity, Status Pill, Chevron
                HStack(alignment: .top, spacing: 12) {
                    avatarElement

                    VStack(alignment: .leading, spacing: 3) {
                        // Name & Verification Badge
                        HStack(spacing: 5) {
                            Text(customer.name)
                                .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)

                            if customer.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(red: 0.12, green: 0.50, blue: 0.90))
                            }
                        }

                        // Contact Details Row (Email / Phone)
                        HStack(spacing: 6) {
                            if !customer.email.isEmpty {
                                Text(customer.email)
                                    .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            }

                            if !customer.email.isEmpty && !customer.phone.isEmpty {
                                Text("•")
                                    .font(.system(size: 9))
                                    .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                            }

                            if !customer.phone.isEmpty {
                                Text(customer.formattedPhone)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                        }

                        // Compact Monospace UID Pill with 1-tap copy
                        Button(action: onCopyUID) {
                            HStack(spacing: 4) {
                                Image(systemName: "number.circle.fill")
                                    .font(.system(size: 9))
                                Text(customer.shortUID)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 8))
                            }
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.85))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(AdminSurface.control, in: Capsule())
                            .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.5))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer(minLength: 4)

                    // Right Side: Status Badge & Chevron
                    VStack(alignment: .trailing, spacing: 6) {
                        statusBadge

                        HStack(spacing: 6) {
                            // Quick WhatsApp link if phone exists
                            if !customer.phone.isEmpty {
                                Button {
                                    openWhatsApp(customer.phone)
                                } label: {
                                    Image(systemName: "message.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color(uiColor: .ppSuccess))
                                        .frame(width: 26, height: 26)
                                        .background(Color(uiColor: .ppSuccess).opacity(0.10), in: Circle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            // Quick Call button if phone exists
                            if !customer.phone.isEmpty {
                                Button {
                                    openCall(customer.phone)
                                } label: {
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AdminSurface.primary)
                                        .frame(width: 26, height: 26)
                                        .background(AdminSurface.primary.opacity(0.08), in: Circle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                        }
                    }
                }

                // Active Restrictions Warning Chip if any
                if customer.hasRestrictions {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(uiColor: .ppWarning))
                        Text(String(format: Language.get("Customer_Restrictions_Count", alter: "توجد %d قيود تشغيلية نشطة على الحساب"), customer.activeRestrictionsCount))
                            .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
                            .foregroundColor(Color(uiColor: .ppWarning))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(uiColor: .ppWarning).opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(13)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(customer.requiresAttention ? Color(uiColor: .ppWarning).opacity(0.35) : AdminSurface.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: onTap) {
                Label(Language.get("View_Dossier", alter: "عرض السجل الشامل"), systemImage: "person.crop.circle.badge.questionmark")
            }

            if !customer.phone.isEmpty {
                Button { openCall(customer.phone) } label: {
                    Label(Language.get("Call", alter: "اتصال هاتفي"), systemImage: "phone.fill")
                }
                Button { openWhatsApp(customer.phone) } label: {
                    Label(Language.get("WhatsApp", alter: "محادثة واتساب"), systemImage: "message.fill")
                }
            }

            Button(action: onCopyUID) {
                Label(Language.get("Copy_UID", alter: "نسخ معرّف الحساب (UID)"), systemImage: "doc.on.doc")
            }

            Button(action: onToggleVerify) {
                Label(
                    customer.isVerified ? Language.get("Unverify", alter: "إلغاء التوثيق") : Language.get("Verify", alter: "توثيق الحساب"),
                    systemImage: customer.isVerified ? "shield.slash" : "shield.checkmark"
                )
            }

            Button(action: onToggleBlock) {
                Label(
                    customer.status == .blocked ? Language.get("Unblock", alter: "رفع الحظر") : Language.get("Block", alter: "حظر الحساب"),
                    systemImage: customer.status == .blocked ? "lock.open" : "nosign"
                )
            }
        }
    }

    private var avatarElement: some View {
        ZStack(alignment: .bottomTrailing) {
            if let photo = customer.photoURL, let url = URL(string: photo), !photo.isEmpty {
                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 48, height: 48)) {
                    monogramView
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                monogramView
            }

            // Online Presence Indicator Dot
            Circle()
                .fill(customer.isOnline ? Color(uiColor: .ppSuccess) : Color.gray.opacity(0.6))
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .offset(x: 2, y: 2)
        }
        .frame(width: 48, height: 48)
    }

    private var monogramView: some View {
        ZStack {
            LinearGradient(
                colors: customer.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(customer.initials)
                .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                .foregroundColor(.white)
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: customer.status.icon)
                .font(.system(size: 9, weight: .bold))
            Text(customer.status.title)
                .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
        }
        .foregroundColor(customer.status.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(customer.status.color.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(customer.status.color.opacity(0.20), lineWidth: 0.5))
    }

    private func openCall(_ phone: String) {
        let clean = phone.filter { "0123456789+".contains($0) }
        guard let url = URL(string: "tel://\(clean)") else { return }
        UIApplication.shared.open(url)
    }

    private func openWhatsApp(_ phone: String) {
        let digits = phone.filter { "0123456789".contains($0) }
        guard let url = URL(string: "https://wa.me/\(digits)") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Reimagined Deep Customer Dossier View (Push Citizenship)

typealias AdminCustomerDossierSheet = AdminCustomerDossierView

struct AdminCustomerDossierView: View {
    let customer: PPCustomerAccountModel
    @ObservedObject var viewModel: AdminCustomerAccountsViewModel
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStatus: CustomerAccountStatus
    @State private var isVerified: Bool
    @State private var features: [String: Bool]
    @State private var restrictions: [String: Bool]

    init(
        customer: PPCustomerAccountModel,
        viewModel: AdminCustomerAccountsViewModel,
        onDismiss: (() -> Void)? = nil
    ) {
        self.customer = customer
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _selectedStatus = State(initialValue: customer.status)
        _isVerified = State(initialValue: customer.isVerified)
        _features = State(initialValue: customer.features)
        _restrictions = State(initialValue: customer.restrictions)
    }

    var body: some View {
        VStack(spacing: 0) {
            dossierNavigationBar

            ScrollView {
                VStack(spacing: 16) {
                    // Hero Profile Deck
                    dossierHeroView

                    // Contact Hub Row
                    contactHubRow

                    // Account Status & Lifecycle Control
                    lifecycleStatusChamber

                    // Official Verification Switch
                    officialVerificationCard

                    // Platform Capabilities Matrix (Features)
                    capabilitiesMatrixSection

                    // Security & Operational Restrictions
                    restrictionsMatrixSection

                    // Diagnostic Tools & Utilities
                    diagnosticUtilitiesSection
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, 14)
                .padding(.bottom, 36)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: Dossier Navigation Bar (Sovereign Push Navigation)

    private var dossierNavigationBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("MissionControl_UserDetail_Title", alter: "ملف حساب العميل"),
            subtitle: customer.name,
            statusDotColor: customer.isOnline ? Color(uiColor: .ppSuccess) : Color.gray.opacity(0.6),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            Menu {
                if !customer.phone.isEmpty {
                    Button {
                        let clean = customer.phone.filter { "0123456789+".contains($0) }
                        if let url = URL(string: "tel://\(clean)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(Language.get("Call", alter: "اتصال هاتفي"), systemImage: "phone.fill")
                    }

                    Button {
                        let clean = customer.phone.filter { $0.isNumber }
                        if let url = URL(string: "https://wa.me/\(clean)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(Language.get("WhatsApp", alter: "واتساب"), systemImage: "message.fill")
                    }
                }

                if !customer.email.isEmpty {
                    Button {
                        if let url = URL(string: "mailto:\(customer.email)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(Language.get("Email", alter: "بريد إلكتروني"), systemImage: "envelope.fill")
                    }
                }

                Button {
                    UIPasteboard.general.string = customer.id
                    viewModel.showToast(Language.get("UID_Copied", alter: "تم نسخ معرّف العميل"))
                } label: {
                    Label(Language.get("CopyUID", alter: "نسخ معرّف العميل"), systemImage: "doc.on.doc")
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                        )
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .frame(width: 44, height: 44)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.get("Actions", alter: "خيارات إضافية"))
        }
    }

    // MARK: Dossier Hero View

    private var dossierHeroView: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                if let photo = customer.photoURL, let url = URL(string: photo), !photo.isEmpty {
                    AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 72, height: 72)) {
                        dossierMonogram
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    dossierMonogram
                }

                // Presence badge
                Circle()
                    .fill(customer.isOnline ? Color(uiColor: .ppSuccess) : Color.gray.opacity(0.6))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
            }
            .frame(width: 72, height: 72)
            .padding(.top, 6)

            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Text(customer.name)
                        .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3))
                        .foregroundColor(AdminSurface.primaryText)

                    if isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 0.12, green: 0.50, blue: 0.90))
                    }
                }

                if !customer.email.isEmpty {
                    Text(customer.email)
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .subheadline))
                        .foregroundColor(AdminSurface.secondaryText)
                }

                // UID Chip
                Button {
                    UIPasteboard.general.string = customer.id
                    viewModel.showToast(Language.get("UID_Copied", alter: "تم نسخ معرّف العميل"))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "number.circle.fill")
                            .font(.system(size: 10))
                        Text(customer.id)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AdminSurface.control, in: Capsule())
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline))
    }

    private var dossierMonogram: some View {
        ZStack {
            LinearGradient(
                colors: customer.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(customer.initials)
                .font(Font.custom("Beiruti-Bold", size: 24, relativeTo: .title))
                .foregroundColor(.white)
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Contact Hub Row

    private var contactHubRow: some View {
        HStack(spacing: 10) {
            contactButton(title: "اتصال هاتفي", icon: "phone.fill", color: AdminSurface.primary) {
                guard !customer.phone.isEmpty else { return }
                let clean = customer.phone.filter { "0123456789+".contains($0) }
                guard let url = URL(string: "tel://\(clean)") else { return }
                UIApplication.shared.open(url)
            }

            contactButton(title: "محادثة واتساب", icon: "message.fill", color: Color(uiColor: .ppSuccess)) {
                guard !customer.phone.isEmpty else { return }
                let digits = customer.phone.filter { "0123456789".contains($0) }
                guard let url = URL(string: "https://wa.me/\(digits)") else { return }
                UIApplication.shared.open(url)
            }

            contactButton(title: "إرسال بريد", icon: "envelope.fill", color: Color(red: 0.12, green: 0.50, blue: 0.90)) {
                guard !customer.email.isEmpty else { return }
                guard let url = URL(string: "mailto:\(customer.email)") else { return }
                UIApplication.shared.open(url)
            }
        }
    }

    private func contactButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.10), in: Circle())

                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: Lifecycle & Status Chamber

    private var lifecycleStatusChamber: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AdminSurface.primary)
                Text(Language.get("MissionControl_UserDetail_Section_Status", alter: "حالة الحساب والصلاحية التشغيلية"))
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
            }

            // 4 Status Options
            HStack(spacing: 6) {
                ForEach(CustomerAccountStatus.allCases) { st in
                    let isSel = selectedStatus == st
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedStatus = st
                        viewModel.updateCustomerStatus(customer: customer, toStatus: st)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: st.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(st.title)
                                .font(Font.custom(isSel ? "Beiruti-Bold" : "Beiruti-Regular", size: 11, relativeTo: .caption2))
                                .lineLimit(1)
                        }
                        .foregroundColor(isSel ? .white : st.color)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            isSel ? st.color : st.color.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSel ? Color.clear : st.color.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: Official Verification Card

    private var officialVerificationCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.50, blue: 0.90).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(red: 0.12, green: 0.50, blue: 0.90))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("MissionControl_Customers_Verified", alter: "توثيق الحساب رسمياً"))
                    .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .body))
                    .foregroundColor(AdminSurface.primaryText)
                Text(Language.get("MissionControl_Customers_Verified_Desc", alter: "يمنح الحساب علامة التوثيق المعتمدة والأولوية في التعاملات"))
                    .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isVerified },
                set: { val in
                    isVerified = val
                    viewModel.toggleVerification(customer: customer)
                }
            ))
            .labelsHidden()
            .tint(Color(red: 0.12, green: 0.50, blue: 0.90))
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: Capabilities Matrix (Features)

    private var capabilitiesMatrixSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundColor(AdminSurface.primary)
                Text(Language.get("MissionControl_UserDetail_Section_Features", alter: "صلاحيات ومزايا المنصة للمستخدم"))
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(PPCustomerCatalog.features) { item in
                    let isEnabled = features[item.id] ?? false
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(item.color.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(item.color)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .body))
                                .foregroundColor(AdminSurface.primaryText)
                            Text(item.subtitle)
                                .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                                .foregroundColor(AdminSurface.secondaryText)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { isEnabled },
                            set: { val in
                                features[item.id] = val
                                viewModel.updateFeature(customer: customer, featureKey: item.id, isEnabled: val)
                            }
                        ))
                        .labelsHidden()
                        .tint(item.color)
                    }
                    .padding(.vertical, 4)

                    if item.id != PPCustomerCatalog.features.last?.id {
                        Divider().background(AdminSurface.hairline)
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))
        }
    }

    // MARK: Security & Restriction Matrix

    private var restrictionsMatrixSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(uiColor: .ppError))
                Text(Language.get("MissionControl_UserDetail_Section_Restrictions", alter: "قيود الأمان والحظر الجزئي"))
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                    .foregroundColor(Color(uiColor: .ppError))
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(PPCustomerCatalog.restrictions) { item in
                    let isBlocked = restrictions[item.id] ?? false
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color(uiColor: .ppError).opacity(0.10))
                                .frame(width: 32, height: 32)
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppError))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .body))
                                .foregroundColor(AdminSurface.primaryText)
                            Text(item.subtitle)
                                .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                                .foregroundColor(AdminSurface.secondaryText)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { isBlocked },
                            set: { val in
                                restrictions[item.id] = val
                                viewModel.updateRestriction(customer: customer, restrictionKey: item.id, isBlocked: val)
                            }
                        ))
                        .labelsHidden()
                        .tint(Color(uiColor: .ppError))
                    }
                    .padding(.vertical, 4)

                    if item.id != PPCustomerCatalog.restrictions.last?.id {
                        Divider().background(AdminSurface.hairline)
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(uiColor: .ppError).opacity(0.20), lineWidth: 1)
            )
        }
    }

    // MARK: Diagnostic Utilities Section

    private var diagnosticUtilitiesSection: some View {
        VStack(spacing: 8) {
            // Password Reset Button
            Button {
                viewModel.sendPasswordReset(email: customer.email)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 13))
                    Text(Language.get("Send_Password_Reset", alter: "إرسال رابط استعادة كلمة المرور"))
                        .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                    Spacer()
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 11))
                }
                .foregroundColor(AdminSurface.primary)
                .padding(14)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline))
            }

            // Copy Full JSON Diagnostics
            Button {
                let diagnostic = "UID: \(customer.id)\nName: \(customer.name)\nEmail: \(customer.email)\nPhone: \(customer.phone)\nStatus: \(customer.status.rawValue)\nVerified: \(isVerified)"
                UIPasteboard.general.string = diagnostic
                viewModel.showToast(Language.get("Diagnostics_Copied", alter: "تم نسخ بيانات التشخيص للحافظة"))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 13))
                    Text(Language.get("Copy_Diagnostics", alter: "نسخ تقرير الفحص التشخيصي"))
                        .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .foregroundColor(AdminSurface.secondaryText)
                .padding(14)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline))
            }
        }
    }
}

// MARK: - Reimagined Customer Onboarding Chamber (Add Customer)

struct AdminAddCustomerSheet: View {
    @ObservedObject var viewModel: AdminCustomerAccountsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var initialStatus: CustomerAccountStatus = .active
    @State private var isVerified: Bool = false
    @State private var isPasswordVisible: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var formError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Sovereign Modal Header with balanced trailing close action
            modalHeader

            ScrollView {
                VStack(spacing: 16) {
                    // Live Monogram Hero Preview
                    liveMonogramPreview

                    // Error Notification Banner
                    if let error = formError {
                        errorBanner(error)
                    }

                    // Fields Container
                    VStack(spacing: 12) {
                        // Full Name
                        onboardingField(
                            title: Language.get("FullName_Field", alter: "الاسم الكامل للعميل *"),
                            placeholder: Language.get("Customer_Name_Placeholder", alter: "مثال: سالم الكواري"),
                            icon: "person.fill",
                            text: Binding(
                                get: { name },
                                set: { name = $0; if formError != nil { formError = nil } }
                            ),
                            disabled: isSubmitting
                        )

                        // Phone Number with Qatar Prefix
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Language.get("Phone_Field", alter: "رقم الجوال *"))
                                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)

                            HStack(spacing: 8) {
                                Text("🇶🇦 +974")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                TextField("5512 3456", text: Binding(
                                    get: { phone },
                                    set: { newPhone in
                                        let digits = newPhone.filter { "0123456789".contains($0) }
                                        phone = String(digits.prefix(8))
                                        if formError != nil { formError = nil }
                                    }
                                ))
                                .font(.system(size: 14, weight: .semibold))
                                .monospacedDigit()
                                .keyboardType(.phonePad)
                                .disabled(isSubmitting)
                            }
                            .padding(6)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                        }

                        // Email
                        onboardingField(
                            title: Language.get("Email_Field", alter: "البريد الإلكتروني *"),
                            placeholder: "customer@example.com",
                            icon: "envelope.fill",
                            text: Binding(
                                get: { email },
                                set: { email = $0; if formError != nil { formError = nil } }
                            ),
                            keyboardType: .emailAddress,
                            disabled: isSubmitting
                        )

                        // Password with Generator and Eye Visibility Toggle
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(Language.get("Password_Field", alter: "كلمة المرور الأولية *"))
                                    .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.primaryText)
                                Spacer()
                                Button {
                                    password = generateSecurePassword()
                                    isPasswordVisible = true
                                    if formError != nil { formError = nil }
                                } label: {
                                    Text(Language.get("Generate_Password", alter: "توليد كلمة سر آمنة"))
                                        .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                                        .foregroundColor(AdminSurface.primary)
                                }
                                .disabled(isSubmitting)
                            }

                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .font(.system(size: 13))
                                    .frame(width: 20)

                                if isPasswordVisible {
                                    TextField("••••••••", text: Binding(
                                        get: { password },
                                        set: { password = $0; if formError != nil { formError = nil } }
                                    ))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .autocorrectionDisabled(true)
                                    .textInputAutocapitalization(.never)
                                    .disabled(isSubmitting)
                                } else {
                                    SecureField("••••••••", text: Binding(
                                        get: { password },
                                        set: { password = $0; if formError != nil { formError = nil } }
                                    ))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .autocorrectionDisabled(true)
                                    .textInputAutocapitalization(.never)
                                    .disabled(isSubmitting)
                                }

                                Button {
                                    isPasswordVisible.toggle()
                                } label: {
                                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(AdminSurface.secondaryText)
                                        .font(.system(size: 13))
                                        .frame(width: 24, height: 24)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                        }
                    }

                    // Initial Verification Option
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Language.get("Initial_Verification", alter: "توثيق الحساب فورياً"))
                                    .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .body))
                                    .foregroundColor(AdminSurface.primaryText)
                                Text(Language.get("Initial_Verification_Hint", alter: "يمنح الحساب شارة التوثيق الأزرق ويتيح الوصول المباشر لكافة الخدمات"))
                                    .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                            Spacer()
                            Toggle("", isOn: $isVerified)
                                .labelsHidden()
                                .tint(Color(red: 0.12, green: 0.50, blue: 0.90))
                                .disabled(isSubmitting)
                        }
                        .padding(12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                    }

                    // Submit Action Button
                    Button {
                        submitForm()
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            Text(isSubmitting
                                 ? Language.get("Saving", alter: "جاري الحفظ...")
                                 : Language.get("Create_Customer_CTA", alter: "حفظ وإنشاء حساب العميل"))
                                .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                colors: [AdminSurface.primary, Color(red: 0.72, green: 0.05, blue: 0.18)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .shadow(color: AdminSurface.primary.opacity(0.25), radius: 8, y: 3)
                    }
                    .disabled(isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity((isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.6 : 1.0)
                    .padding(.top, 8)
                }
                .padding(AdminSpacing.screenMargin)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var modalHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("NewCustomer_Title", alter: "تسجيل عميل جديد"))
                    .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 6, height: 6)
                    Text(Language.get("CommandCenter_Customers_Workspace", alter: "عمليات العملاء • بطاقة جديدة"))
                        .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption2))
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            AdminSquircleCloseButton {
                dismiss()
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(uiColor: .ppError))

            Text(error)
                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .subheadline))
                .foregroundColor(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    formError = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .ppError).opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .ppError).opacity(0.25), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var liveMonogramPreview: some View {
        VStack(spacing: 6) {
            ZStack {
                LinearGradient(
                    colors: [AdminSurface.primary, Color(red: 0.75, green: 0.15, blue: 0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(calculatedInitials)
                    .font(Font.custom("Beiruti-Bold", size: 24, relativeTo: .title2))
                    .foregroundColor(.white)
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: AdminSurface.primary.opacity(0.20), radius: 8, y: 3)

            Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Language.get("NewCustomer_Preview", alter: "معاينة هوية العميل") : name)
                .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var calculatedInitials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "PP" }
        let components = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if components.count >= 2,
           let firstChar = components.first?.first,
           let lastChar = components.last?.first {
            return "\(firstChar)\(lastChar)".uppercased()
        }
        return String(trimmed.prefix(2)).uppercased()
    }

    private func onboardingField(
        title: String,
        placeholder: String,
        icon: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        disabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                .foregroundColor(AdminSurface.primaryText)

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(AdminSurface.secondaryText)
                    .font(.system(size: 13))
                    .frame(width: 20)

                TextField(placeholder, text: text)
                    .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                    .keyboardType(keyboardType)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .disabled(disabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
        }
    }

    private func generateSecurePassword() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%"
        return String((0..<10).compactMap { _ in chars.randomElement() })
    }

    private func submitForm() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let digitsOnly = phone.filter { "0123456789".contains($0) }

        guard trimmedName.count >= 2 else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                formError = Language.get("Error_NameRequired", alter: "يرجى كتابة اسم العميل بالكامل (حرفين على الأقل)")
            }
            return
        }
        guard trimmedEmail.contains("@") && trimmedEmail.contains(".") else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                formError = Language.get("Error_Customer_InvalidEmail", alter: "يرجى كتابة بريد إلكتروني صالح")
            }
            return
        }
        guard password.count >= 6 else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                formError = Language.get("Error_Customer_WeakPassword", alter: "كلمة المرور يجب أن تكون ٦ خانات على الأقل")
            }
            return
        }

        let fullPhone = digitsOnly.isEmpty ? "" : "+974" + digitsOnly

        formError = nil
        isSubmitting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        viewModel.createCustomer(
            name: trimmedName,
            email: trimmedEmail,
            phone: fullPhone,
            password: password,
            initialStatus: initialStatus,
            isVerified: isVerified
        ) { success, errDesc in
            isSubmitting = false
            if success {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    formError = errDesc ?? Language.get("Error_Customer_Failed", alter: "تعذر إنشاء الحساب")
                }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Skeleton & Empty State Helpers

private struct CustomerSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AdminSurface.control)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AdminSurface.control)
                        .frame(width: 130, height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AdminSurface.control)
                        .frame(width: 170, height: 11)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AdminSurface.control)
                        .frame(width: 80, height: 10)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 12)
                    .fill(AdminSurface.control)
                    .frame(width: 50, height: 22)
            }
        }
        .padding(13)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))
        .opacity(0.6)
    }
}

private struct CustomerEmptyStateView: View {
    let query: String
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: query.isEmpty ? "person.2.slash" : "magnifyingglass")
                .font(.system(size: 42, weight: .light))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                .padding(.top, 36)

            VStack(spacing: 4) {
                Text(query.isEmpty
                     ? Language.get("MissionControl_Customers_SourceEmpty_Title", alter: "لا توجد حسابات عملاء")
                     : Language.get("MissionControl_Customers_FilteredEmpty_Title", alter: "لا توجد نتائج مطابقة"))
                    .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)

                Text(query.isEmpty
                     ? Language.get("MissionControl_Customers_SourceEmpty_Body", alter: "لا توجد سجلات عملاء نشطة في قاعدة البيانات حالياً.")
                     : String(format: Language.get("MissionControl_Customers_FilteredEmpty_Body", alter: "لم نجد حساباً يطابق البحث '%@'."), query))
                    .font(Font.custom("Beiruti-Regular", size: 12.5, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if !query.isEmpty {
                Button(action: onReset) {
                    Text(Language.get("Clear_Search", alter: "إلغاء التصفية وإظهار الكل"))
                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .callout))
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Legacy Wrappers & Exported Hosting Controllers

private struct AdminLegacyViewControllerWrapper: UIViewControllerRepresentable {
    let factory: () -> UIViewController
    func makeUIViewController(context: Context) -> UIViewController { factory() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct AdminUserManagementView: View {
    let controllerFactory: () -> UIViewController
    var titleText: String
    var onDismiss: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            AdminLegacyViewControllerWrapper { controllerFactory() }
                .ignoresSafeArea()
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

struct AdminSupportThreadView: View {
    let controllerFactory: () -> UIViewController
    var onDismiss: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView
                AdminLegacyViewControllerWrapper { controllerFactory() }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var dossierHeaderView: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Support_Thread", alter: "محادثة الدعم"),
            subtitle: Language.get("Chats", alter: "المحادثات"),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        )
    }
}

@objc(PPAdminUsersListHostingController)
public final class PPAdminUsersListHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let host = UIHostingController(
            rootView: AdminUsersListView(onDismiss: { [weak self] in
                guard let self = self else {
                    PPAdminNavigationFallback.popOrDismiss()
                    return
                }
                PPAdminNavigationFallback.popOrDismiss(from: self)
            })
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@available(iOS 16.0, *)
@objc(PPAdminChatsHostingController)
public final class PPAdminChatsHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let host = UIHostingController(
            rootView: AdminChatsView(onDismiss: { [weak self] in
                guard let self = self else {
                    PPAdminNavigationFallback.popOrDismiss()
                    return
                }
                PPAdminNavigationFallback.popOrDismiss(from: self)
            })
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc(PPAdminUserManagementHostingController)
public final class PPAdminUserManagementHostingController: UIViewController {
    private let contentController: UIViewController
    private let titleText: String

    @objc(initWithController:titleText:)
    public init(controller: UIViewController, titleText: String) {
        contentController = controller
        self.titleText = titleText
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PPAdminUserManagementHostingController must be created programmatically.")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let controller = contentController
        let host = UIHostingController(
            rootView: AdminUserManagementView(
                controllerFactory: { controller },
                titleText: titleText,
                onDismiss: { [weak self] in
                    guard let self = self else {
                        PPAdminNavigationFallback.popOrDismiss()
                        return
                    }
                    PPAdminNavigationFallback.popOrDismiss(from: self)
                }
            )
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc(PPAdminSupportThreadHostingController)
public final class PPAdminSupportThreadHostingController: UIViewController {
    private let contentController: UIViewController

    @objc(initWithController:)
    public init(controller: UIViewController) {
        contentController = controller
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PPAdminSupportThreadHostingController must be created programmatically.")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let controller = contentController
        let host = UIHostingController(
            rootView: AdminSupportThreadView(
                controllerFactory: { controller },
                onDismiss: { [weak self] in
                    guard let self = self else {
                        PPAdminNavigationFallback.popOrDismiss()
                        return
                    }
                    PPAdminNavigationFallback.popOrDismiss(from: self)
                }
            )
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}
