//
//  ProvidersView.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles for PurePets Flagship Admin.
//

import SwiftUI
import UIKit

extension PPProviderApplication: @unchecked Sendable, Identifiable {
    public var id: String {
        return applicationID.isEmpty ? userId : applicationID
    }
}

extension PPProviderPlan: @unchecked Sendable, Identifiable {
    public var id: String { planID }
}

extension PPProviderCommissionRecord: @unchecked Sendable, Identifiable {
    public var id: String { recordID }
}

// MARK: - Color & Token Constants

private enum ProviderTheme {
    static let pending = Color(red: 0.96, green: 0.62, blue: 0.14) // Amber
    static let approved = Color(red: 0.08, green: 0.74, blue: 0.48) // Emerald
    static let rejected = Color(red: 0.94, green: 0.28, blue: 0.34) // Crimson
    static let changesRequested = Color(red: 0.95, green: 0.45, blue: 0.15) // Warning Tangerine
    static let resubmitted = Color(red: 0.35, green: 0.45, blue: 0.95) // Royal Indigo
    static let brand = AdminSurface.primary
    
    static func tone(for status: String) -> (color: Color, text: String, symbol: String) {
        switch status.lowercased() {
        case "approved":
            return (approved, Language.get("Providers_Approved", alter: "مقبول ومفعّل"), "checkmark.seal.fill")
        case "rejected":
            return (rejected, Language.get("Providers_Rejected", alter: "مرفوض"), "xmark.octagon.fill")
        case "under_review":
            return (Color.indigo, Language.get("Providers_UnderReview", alter: "قيد المراجعة"), "hourglass.circle.fill")
        case "changes_requested":
            return (changesRequested, Language.get("Providers_ChangesRequested", alter: "تعديلات مطلوبة"), "exclamationmark.bubble.fill")
        case "resubmitted":
            return (resubmitted, Language.get("Providers_Resubmitted", alter: "معاد تقديمه"), "arrow.counterclockwise.circle.fill")
        default: // pending / submitted
            return (pending, Language.get("Providers_Pending", alter: "بانتظار القرار"), "clock.arrow.circlepath")
        }
    }
    
    static func localizedType(_ type: String) -> (text: String, icon: String) {
        switch type.lowercased() {
        case "marketplace", "store":
            return (Language.get("Providers_Type_Marketplace", alter: "متجر تجاري"), "bag.fill")
        case "clinic", "vet", "veterinarian":
            return (Language.get("Providers_Type_Clinic", alter: "عيادة بيطرية"), "cross.case.fill")
        case "delivery", "delivery_company":
            return (Language.get("Providers_Type_Delivery", alter: "شركة توصيل"), "shippingbox.fill")
        case "services", "service_provider":
            return (Language.get("Providers_Type_Services", alter: "مقدم خدمات"), "pawprint.fill")
        default:
            return (type.isEmpty ? Language.get("Providers_Type_General", alter: "مزود خدمة") : type, "person.badge.shield.checkmark.fill")
        }
    }
}

// MARK: - Provider Tab Identifier

public enum ProviderTab: String, CaseIterable, Sendable {
    case applications
    case plans
    case features
    case accounting

    var localizedTitle: String {
        switch self {
        case .applications: return Language.get("Providers_Applications_Tab", alter: "الطلبات")
        case .plans: return Language.get("Providers_Plans_Tab", alter: "الباقات")
        case .features: return Language.get("Providers_Features_Tab", alter: "الميزات")
        case .accounting: return Language.get("Providers_Accounting_Tab", alter: "المحاسبة")
        }
    }

    var icon: String {
        switch self {
        case .applications: return "tray.full.fill"
        case .plans: return "sparkles.rectangle.stack.fill"
        case .features: return "slider.horizontal.3"
        case .accounting: return "banknote.fill"
        }
    }
}

// MARK: - Main Providers Hub (Tabbed: Applications · Plans · Features · Accounting)

public struct AdminProvidersView: View {
    public var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedTab: ProviderTab
    @StateObject private var sharedViewModel = ProviderApplicationsViewModel()

    public init(initialTab: ProviderTab = .applications, onDismiss: (() -> Void)? = nil) {
        _selectedTab = State(initialValue: initialTab)
        self.onDismiss = onDismiss
    }

    public var body: some View {
        GeometryReader { geometry in
            let isRegular = geometry.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize
            let containerMaxWidth: CGFloat = isRegular ? 1200 : .infinity

            ZStack(alignment: .top) {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Sovereign Navigation Bar (Hugs status bar with zero excess gap)
                    Color.clear.frame(height: PPStatusBarHelper.statusBarHeight)

                    if isRegular {
                        ipadHeaderBar
                    } else {
                        iphoneHeaderBar
                        providerTabPicker
                            .padding(.top, 4)
                            .padding(.bottom, 6)
                    }

                    // Tab Content
                    providerTabContent(isRegular: isRegular)
                        .frame(maxWidth: containerMaxWidth)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - iPhone Header Bar (Zero Excess Gap)
    private var iphoneHeaderBar: some View {
        HStack(spacing: 12) {
            AdminSquircleBackButton {
                handleDismiss()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Language.get("Providers_Management_Title", alter: "إدارة منظومة المزودين"))
                        .font(PPBrandFont.bold(size: 18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 7, height: 7)
                }

                Text(Language.get("CommandCenter_Operations_Workspace", alter: "مساحة العمليات"))
                    .font(PPBrandFont.medium(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Live Applications Count Badge
            HStack(spacing: 4) {
                Circle()
                    .fill(ProviderTheme.approved)
                    .frame(width: 6, height: 6)
                Text(Language.get("Live", alter: "مباشر"))
                    .font(PPBrandFont.bold(size: 11, relativeTo: .caption2))
                    .foregroundStyle(ProviderTheme.approved)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(ProviderTheme.approved.opacity(0.12), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(ProviderTheme.approved.opacity(0.25), lineWidth: 0.5)
            )
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(AdminSurface.background)
    }

    // MARK: - iPad Aerospace Command Bar
    private var ipadHeaderBar: some View {
        HStack(alignment: .center, spacing: 14) {
            // Wing 1: Back + Brand Title
            HStack(spacing: 10) {
                AdminSquircleBackButton {
                    handleDismiss()
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                    Image(systemName: "storefront.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("Providers_Management_Title", alter: "إدارة منظومة المزودين"))
                        .font(PPBrandFont.bold(size: 18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 6, height: 6)
                        Text(Language.get("CommandCenter_Operations_Workspace", alter: "مساحة العمليات • تفعيل وإشراف المزودين"))
                            .font(PPBrandFont.medium(size: 11, relativeTo: .caption2))
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            // Center: Integrated Workspace Tabs inside Header Bar
            HStack(spacing: 4) {
                ForEach(Array(ProviderTab.allCases.enumerated()), id: \.element) { index, tab in
                    let isSelected = selectedTab == tab
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            Text(tab.localizedTitle)
                                .font(PPBrandFont.bold(size: 12.5, relativeTo: .caption))
                        }
                        .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? AdminSurface.primary : AdminSurface.control,
                            in: Capsule(style: .continuous)
                        )
                    }
                    .buttonStyle(ProviderPressStyle())
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            .padding(4)
            .background(AdminSurface.control, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.75)
            )

            Spacer(minLength: 8)

            // Wing 2: Telemetry Capsule + Refresh Action
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(ProviderTheme.approved)
                        .frame(width: 6, height: 6)
                    Text("\(sharedViewModel.applications.count) " + Language.get("Providers_TotalApps_Short", alter: "طلب مزود"))
                        .font(PPBrandFont.bold(size: 12, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.control, in: Capsule(style: .continuous))

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    sharedViewModel.fetch()
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.control)
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                }
                .buttonStyle(ProviderPressStyle())
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(AdminSurface.background)
    }

    private func handleDismiss() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
            PPAdminNavigationFallback.popOrDismiss()
        }
    }

    // MARK: - iPhone Tab Picker
    private var providerTabPicker: some View {
        HStack(spacing: 6) {
            ForEach(ProviderTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                        Text(tab.localizedTitle)
                            .font(isSelected ? AdminType.captionBold : AdminType.caption1)

                        if tab == .applications && sharedViewModel.pendingCount > 0 {
                            Text("\(sharedViewModel.pendingCount)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    isSelected
                                        ? Color.white.opacity(0.28)
                                        : ProviderTheme.pending,
                                    in: Capsule(style: .continuous)
                                )
                                .foregroundStyle(.white)
                        }
                    }
                    .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(
                        isSelected
                            ? AnyView(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AdminSurface.primary)
                                    .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, x: 0, y: 2)
                            )
                            : AnyView(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AdminSurface.control)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.4),
                                lineWidth: 0.75
                            )
                    )
                }
                .buttonStyle(ProviderPressStyle())
                .accessibilityLabel(tab.localizedTitle)
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
    }

    @ViewBuilder
    private func providerTabContent(isRegular: Bool) -> some View {
        switch selectedTab {
        case .applications:
            AdminProviderApplicationsView(viewModel: sharedViewModel, isRegular: isRegular)
        case .plans:
            AdminLegacyViewControllerWrapper { PPProviderPlansViewController() }
        case .features:
            AdminLegacyViewControllerWrapper { PPProviderFeatureAccessViewController() }
        case .accounting:
            AdminProviderAccountingView(isEmbeddedInTab: true)
        }
    }
}

// MARK: - Reusable Legacy VC Wrapper

private struct AdminLegacyViewControllerWrapper: UIViewControllerRepresentable {
    let factory: () -> UIViewController

    func makeUIViewController(context: Context) -> UIViewController { factory() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// MARK: - Applications View Model

@MainActor
final class ProviderApplicationsViewModel: ObservableObject {
    @Published var applications: [PPProviderApplication] = []
    @Published var searchText: String = ""
    @Published var selectedFilter: AppFilter = .all
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var error: Error?
    @Published var selectedDetailApp: PPProviderApplication?
    @Published var reviewTargetApp: PPProviderApplication?
    private var listenerRegistration: AnyObject? = nil
    
    enum AppFilter: String, CaseIterable {
        case all = "all"
        case pending = "pending"
        case changesRequested = "changes_requested"
        case resubmitted = "resubmitted"
        case approved = "approved"
        case rejected = "rejected"
        
        var localizedTitle: String {
            switch self {
            case .all: return Language.get("All", alter: "الكل")
            case .pending: return Language.get("Providers_Pending", alter: "قيد المراجعة")
            case .changesRequested: return Language.get("Providers_ChangesRequested", alter: "تعديلات مطلوبة")
            case .resubmitted: return Language.get("Providers_Resubmitted", alter: "معاد تقديمه")
            case .approved: return Language.get("Providers_Approved", alter: "مقبول ومفعّل")
            case .rejected: return Language.get("Providers_Rejected", alter: "مرفوض")
            }
        }
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2.fill"
            case .pending: return "clock.fill"
            case .changesRequested: return "exclamationmark.bubble.fill"
            case .resubmitted: return "arrow.counterclockwise.circle.fill"
            case .approved: return "checkmark.seal.fill"
            case .rejected: return "xmark.octagon.fill"
            }
        }
    }
    
    enum ProviderTypeFilter: String, CaseIterable {
        case all = "all"
        case store = "store"
        case clinic = "clinic"
        case delivery = "delivery"
        case service = "service"
        
        var localizedTitle: String {
            switch self {
            case .all: return Language.get("Providers_Filter_AllTypes", alter: "كافة الأنشطة")
            case .store: return Language.get("Providers_Filter_Store", alter: "متاجر ومستلزمات")
            case .clinic: return Language.get("Providers_Filter_Clinic", alter: "عيادات وبيطرة")
            case .delivery: return Language.get("Providers_Filter_Delivery", alter: "شركات التوصيل")
            case .service: return Language.get("Providers_Filter_Service", alter: "خدمات ورعاية")
            }
        }
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .store: return "cart.fill"
            case .clinic: return "cross.case.fill"
            case .delivery: return "shippingbox.fill"
            case .service: return "pawprint.fill"
            }
        }
    }
    
    enum RiskProfileFilter: String, CaseIterable {
        case all = "all"
        case highRisk = "high_risk"
        case expiringDocs = "expiring_docs"
        case unassigned = "unassigned"
        
        var localizedTitle: String {
            switch self {
            case .all: return Language.get("Providers_Risk_All", alter: "كافة الملفات")
            case .highRisk: return Language.get("Providers_Risk_High", alter: "ملفات حرجة / متكررة")
            case .expiringDocs: return Language.get("Providers_Risk_ExpiringDocs", alter: "مستندات قاربت الانتهاء")
            case .unassigned: return Language.get("Providers_Risk_Unassigned", alter: "بانتظار مراجع")
            }
        }
        
        var icon: String {
            switch self {
            case .all: return "shield"
            case .highRisk: return "exclamationmark.triangle.fill"
            case .expiringDocs: return "calendar.badge.exclamationmark"
            case .unassigned: return "person.badge.shield.checkmark.fill"
            }
        }
    }
    
    @Published var selectedTypeFilter: ProviderTypeFilter = .all
    @Published var selectedRiskFilter: RiskProfileFilter = .all
    
    // Batch Mode State
    @Published var isBatchMode: Bool = false
    @Published var selectedBatchIds: Set<String> = []
    @Published var isExecutingBatch: Bool = false
    @Published var batchSuccessMessage: String?
    
    // MARK: - Robust Merchant Display Name Resolver (Never Blank)
    static func resolveDisplayName(for application: PPProviderApplication) -> String {
        let form = application.form
        let candidates: [Any?] = [
            form["businessName"],
            form["fullName"],
            form["companyName"],
            form["legalName"],
            form["storeName"],
            form["name"],
            application.userSummary["displayName"],
            application.userSummary["name"],
            form["phone"],
            application.userId,
            application.applicationID
        ]

        for candidate in candidates {
            if let str = candidate as? String {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return Language.get("Providers_Applications_UnknownApplicant", alter: "طلب مزود خدمة")
    }

    var filteredApps: [PPProviderApplication] {
        let searched = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? applications : applications.filter { app in
            let q = searchText.lowercased()
            let name = Self.resolveDisplayName(for: app)
            let email = (app.form["email"] as? String) ?? (app.userSummary["email"] as? String) ?? ""
            let phone = (app.form["phone"] as? String) ?? (app.userSummary["phone"] as? String) ?? ""
            let city = (app.form["city"] as? String) ?? ""
            let appId = app.applicationID
            let userId = app.userId
            
            return name.localizedCaseInsensitiveContains(q)
                || email.localizedCaseInsensitiveContains(q)
                || phone.localizedCaseInsensitiveContains(q)
                || city.localizedCaseInsensitiveContains(q)
                || appId.localizedCaseInsensitiveContains(q)
                || userId.localizedCaseInsensitiveContains(q)
        }
        
        var result = searched
        
        // 1. Status Filter
        switch selectedFilter {
        case .all:
            break
        case .pending:
            result = result.filter {
                let s = $0.status.lowercased()
                return s == "pending" || s == "under_review" || s == "submitted" || s.isEmpty
            }
        case .changesRequested:
            result = result.filter { $0.status.lowercased() == "changes_requested" }
        case .resubmitted:
            result = result.filter { $0.status.lowercased() == "resubmitted" }
        case .approved:
            result = result.filter { $0.status.lowercased() == "approved" }
        case .rejected:
            result = result.filter { $0.status.lowercased() == "rejected" }
        }
        
        // 2. Provider Type Filter
        switch selectedTypeFilter {
        case .all:
            break
        case .store:
            result = result.filter {
                let t = $0.providerType.lowercased()
                return t == "store" || t == "marketplace" || t == "products" || t == "accessories"
            }
        case .clinic:
            result = result.filter {
                let t = $0.providerType.lowercased()
                return t == "clinic" || t == "vet"
            }
        case .delivery:
            result = result.filter {
                let t = $0.providerType.lowercased()
                return t == "delivery" || t == "delivery_company"
            }
        case .service:
            result = result.filter {
                let t = $0.providerType.lowercased()
                return t == "service" || t == "boarding" || t == "hotel"
            }
        }
        
        // 3. Risk / Attention Filter
        switch selectedRiskFilter {
        case .all:
            break
        case .highRisk:
            result = result.filter { app in
                if app.resubmissionCount >= 2 { return true }
                let cr = (app.form["commercialRegistrationNumber"] as? String) ?? (app.form["crNumber"] as? String) ?? ""
                if cr.isEmpty && (app.providerType == "store" || app.providerType == "marketplace" || app.providerType == "vet") {
                    return true
                }
                return false
            }
        case .expiringDocs:
            result = result.filter { app in
                let now = Date().timeIntervalSince1970
                let docs = app.documents
                for (_, value) in docs {
                    if let docDict = value as? [String: Any], let exp = docDict["expiresAt"] {
                        var expTime: TimeInterval = 0
                        if let s = exp as? String, let d = ISO8601DateFormatter().date(from: s) {
                            expTime = d.timeIntervalSince1970
                        } else if let n = exp as? Double {
                            expTime = n
                        }
                        if expTime > 0 && expTime - now < 30 * 86400 {
                            return true
                        }
                    }
                }
                return false
            }
        case .unassigned:
            result = result.filter {
                $0.reviewedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        
        return result
    }
    
    var pendingCount: Int {
        applications.filter {
            let s = $0.status.lowercased()
            return s == "pending" || s == "under_review" || s == "submitted" || s.isEmpty
        }.count
    }
    
    var changesRequestedCount: Int {
        applications.filter { $0.status.lowercased() == "changes_requested" }.count
    }
    
    var resubmittedCount: Int {
        applications.filter { $0.status.lowercased() == "resubmitted" }.count
    }
    
    var approvedCount: Int {
        applications.filter { $0.status.lowercased() == "approved" }.count
    }
    
    var rejectedCount: Int {
        applications.filter { $0.status.lowercased() == "rejected" }.count
    }
    
    func startListening() {
        guard listenerRegistration == nil else { return }
        if applications.isEmpty {
            isLoading = true
        }
        listenerRegistration = PPProviderService.shared().listenApplications { [weak self] apps, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                self.isRefreshing = false
                if let error = error {
                    self.error = error
                } else {
                    self.applications = apps ?? []
                    // Keep inspector detail fresh with live updates
                    if let current = self.selectedDetailApp,
                       let updated = self.applications.first(where: { $0.id == current.id }) {
                        self.selectedDetailApp = updated
                    }
                }
            }
        }
    }
    
    func stopListening() {
        if let reg = listenerRegistration as? NSObject, reg.responds(to: Selector(("remove"))) {
            reg.perform(Selector(("remove")))
        }
        listenerRegistration = nil
    }
    
    func fetch() {
        if applications.isEmpty {
            isLoading = true
        }
        isRefreshing = true
        error = nil
        
        PPProviderService.shared().fetchApplications { [weak self] apps, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                self.isRefreshing = false
                if let error = error {
                    self.error = error
                } else {
                    self.applications = apps ?? []
                    if let current = self.selectedDetailApp,
                       let updated = self.applications.first(where: { $0.id == current.id }) {
                        self.selectedDetailApp = updated
                    }
                }
            }
        }
    }
    
    func submitReview(
        appID: String,
        decision: String,
        notes: String,
        rejectionCode: String? = nil,
        reviewFindings: [[String: Any]]? = nil,
        expectedVersion: NSNumber? = nil,
        idempotencyKey: String? = nil,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let key = idempotencyKey ?? "rev_\(appID)_\(decision)_\(UUID().uuidString.lowercased())"
        PPProviderService.shared().reviewApplication(
            appID,
            status: decision,
            notes: notes,
            rejectionCode: rejectionCode,
            reviewFindings: reviewFindings,
            expectedVersion: expectedVersion,
            idempotencyKey: key
        ) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error = error {
                    self.error = error
                    completion(false)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.fetch()
                    completion(true)
                }
            }
        }
    }
    
    func toggleBatchMode() {
        isBatchMode.toggle()
        if !isBatchMode {
            selectedBatchIds.removeAll()
        }
    }
    
    func toggleSelect(appId: String) {
        if selectedBatchIds.contains(appId) {
            selectedBatchIds.remove(appId)
        } else {
            selectedBatchIds.insert(appId)
        }
    }
    
    func selectAllFiltered() {
        let ids = filteredApps.map { $0.applicationID }
        selectedBatchIds.formUnion(ids)
    }
    
    func clearSelection() {
        selectedBatchIds.removeAll()
    }
    
    func executeBatchAssignReviewer(reviewerUid: String, completion: @escaping @Sendable (Bool) -> Void) {
        let ids = Array(selectedBatchIds)
        guard !ids.isEmpty else { return }
        isExecutingBatch = true
        PPProviderService.shared().batchAssignReviewer(ids, reviewerUid: reviewerUid) { [weak self] count, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isExecutingBatch = false
                if let error = error {
                    self.error = error
                    completion(false)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.batchSuccessMessage = String(format: Language.get("Providers_Batch_Success", alter: "تم تنفيذ العملية المجمعة على %d طلبات بنجاح."), count)
                    self.clearSelection()
                    self.isBatchMode = false
                    self.fetch()
                    completion(true)
                }
            }
        }
    }
    
    func executeBatchAddTag(tag: String, completion: @escaping @Sendable (Bool) -> Void) {
        let ids = Array(selectedBatchIds)
        guard !ids.isEmpty else { return }
        isExecutingBatch = true
        PPProviderService.shared().batchAddTag(ids, tag: tag) { [weak self] count, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isExecutingBatch = false
                if let error = error {
                    self.error = error
                    completion(false)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.batchSuccessMessage = String(format: Language.get("Providers_Batch_Success", alter: "تم تنفيذ العملية المجمعة على %d طلبات بنجاح."), count)
                    self.clearSelection()
                    self.isBatchMode = false
                    self.fetch()
                    completion(true)
                }
            }
        }
    }
}

// MARK: - Reimagined Provider Applications Queue Screen

struct AdminProviderApplicationsView: View {
    @ObservedObject var viewModel: ProviderApplicationsViewModel
    var isRegular: Bool = false
    @State private var spinAngle: Double = 0
    @State private var showAssignReviewerAlert = false
    @State private var reviewerUidInput = ""
    @State private var showAddTagAlert = false
    @State private var tagInput = ""
    
    init(viewModel: ProviderApplicationsViewModel? = nil, isRegular: Bool = false) {
        if let vm = viewModel {
            self.viewModel = vm
        } else {
            self.viewModel = ProviderApplicationsViewModel()
        }
        self.isRegular = isRegular
    }
    
    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()
            
            if isRegular {
                // MARK: - iPad Aerospace Split Review Workspace
                HStack(alignment: .top, spacing: 0) {
                    // Left Wing: Master Applications Queue (410pt)
                    VStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                apexHealthHero
                                searchAndFilterDeck
                                masterQueueListSection
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 48)
                        }
                    }
                    .frame(width: 410)
                    .background(AdminSurface.background)
                    .overlay(
                        Rectangle()
                            .fill(Color(uiColor: .ppSurfaceBorder).opacity(0.65))
                            .frame(width: 1),
                        alignment: Language.isRTL() ? .leading : .trailing
                    )

                    // Right Wing: Live Application Dossier Inspector
                    Group {
                        if let selectedApp = viewModel.selectedDetailApp {
                            AdminProviderApplicationDetailView(
                                application: selectedApp,
                                viewModel: viewModel,
                                isPushMode: false,
                                onBack: {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        viewModel.selectedDetailApp = nil
                                    }
                                }
                            )
                            .id(selectedApp.id)
                            .transition(.opacity.combined(with: .move(edge: Language.isRTL() ? .leading : .trailing)))
                        } else {
                            emptyInspectorPlaceholder
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AdminSurface.background)
                }
            } else {
                // MARK: - iPhone High-Velocity Single-Column Stack
                ScrollView {
                    LazyVStack(spacing: 16) {
                        apexHealthHero
                        searchAndFilterDeck
                        applicationsListSection
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
                }
                .refreshable {
                    await withCheckedContinuation { continuation in
                        viewModel.fetch()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            continuation.resume()
                        }
                    }
                }
            }
            
            // Batch Mode Floating Action Bar
            if viewModel.isBatchMode {
                VStack {
                    Spacer()
                    batchFloatingActionBar
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .background(
            Group {
                if !isRegular {
                    NavigationLink(
                        destination: Group {
                            if let app = viewModel.selectedDetailApp {
                                AdminProviderApplicationDetailView(
                                    application: app,
                                    viewModel: viewModel,
                                    isPushMode: true,
                                    onBack: {
                                        viewModel.selectedDetailApp = nil
                                    }
                                )
                                .navigationBarHidden(true)
                            } else {
                                EmptyView()
                            }
                        },
                        isActive: Binding(
                            get: { !isRegular && viewModel.selectedDetailApp != nil },
                            set: { if !$0 && !isRegular { viewModel.selectedDetailApp = nil } }
                        )
                    ) {
                        EmptyView()
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }
            }
        )
        .sheet(item: $viewModel.reviewTargetApp) { app in
            ProviderReviewDecisionSheet(application: app, viewModel: viewModel)
        }
        .alert(Language.get("Providers_Batch_AssignReviewer", alter: "تعيين مراجع"), isPresented: $showAssignReviewerAlert) {
            TextField(Language.get("Providers_Batch_EnterReviewerUid", alter: "معرّف المراجع"), text: $reviewerUidInput)
            Button(Language.get("Confirm", alter: "تأكيد")) {
                let uid = reviewerUidInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !uid.isEmpty {
                    viewModel.executeBatchAssignReviewer(reviewerUid: uid) { _ in }
                    reviewerUidInput = ""
                }
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                reviewerUidInput = ""
            }
        }
        .alert(Language.get("Providers_Batch_AddTag", alter: "إضافة وسم"), isPresented: $showAddTagAlert) {
            TextField(Language.get("Providers_Batch_EnterTag", alter: "الوسم (مثال: عاجل)"), text: $tagInput)
            Button(Language.get("Confirm", alter: "تأكيد")) {
                let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tag.isEmpty {
                    viewModel.executeBatchAddTag(tag: tag) { _ in }
                    tagInput = ""
                }
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                tagInput = ""
            }
        }
        .onAppear {
            viewModel.startListening()
            if isRegular && viewModel.selectedDetailApp == nil {
                if let firstPending = viewModel.filteredApps.first(where: {
                    let s = $0.status.lowercased()
                    return s == "pending" || s == "under_review" || s == "changes_requested" || s == "resubmitted"
                }) ?? viewModel.filteredApps.first {
                    viewModel.selectedDetailApp = firstPending
                }
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }
    
    // MARK: - Apex Health & Metrics Hero
    
    private var apexHealthHero: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ProviderTheme.pending)
                            .frame(width: 8, height: 8)
                            .shadow(color: ProviderTheme.pending.opacity(0.8), radius: 4, x: 0, y: 0)
                        Text(Language.get("Providers_Telemetry_Radar", alter: "رصد طلبات الانضمام • تحديث فوري"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(ProviderTheme.pending)
                    }
                    
                    Text(Language.get("Providers_Applications_HeroTitle", alter: "طلبات انضمام المزودين"))
                        .font(PPBrandFont.bold(size: isRegular ? 24 : 20, relativeTo: .title2))
                        .foregroundColor(AdminSurface.primaryText)
                    
                    Text(Language.get("Providers_Applications_HeroSubtitle", alter: "فحص الأهلية التجارية، تدقيق التراخيص والمستندات، واعتماد تفعيل المتاجر والعيادات."))
                        .font(AdminType.caption1)
                        .foregroundColor(AdminCommandInk.secondary)
                        .lineLimit(isRegular ? 1 : 2)
                }
                
                Spacer(minLength: 8)
                
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.6)) {
                        spinAngle += 360
                    }
                    viewModel.fetch()
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.control)
                            .frame(width: 38, height: 38)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                            .rotationEffect(.degrees(spinAngle))
                    }
                }
                .buttonStyle(ProviderPressStyle())
                .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
            }
            
            // 3-Metric Horizontal Deck (Interactive Triage Stations)
            HStack(spacing: 10) {
                interactiveMetricTile(
                    title: Language.get("Providers_Pending", alter: "بانتظار القرار"),
                    subtitle: Language.get("Providers_Pending_Sub", alter: "تحتاج مراجعة"),
                    count: viewModel.pendingCount,
                    color: ProviderTheme.pending,
                    icon: "hourglass",
                    targetFilter: .pending
                )
                interactiveMetricTile(
                    title: Language.get("Providers_Approved", alter: "مقبول ومفعّل"),
                    subtitle: Language.get("Providers_Approved_Sub", alter: "متاجر نشطة"),
                    count: viewModel.approvedCount,
                    color: ProviderTheme.approved,
                    icon: "checkmark.seal.fill",
                    targetFilter: .approved
                )
                interactiveMetricTile(
                    title: Language.get("Providers_Rejected", alter: "مرفوض"),
                    subtitle: Language.get("Providers_Rejected_Sub", alter: "غير مستوفٍ"),
                    count: viewModel.rejectedCount,
                    color: ProviderTheme.rejected,
                    icon: "xmark.octagon.fill",
                    targetFilter: .rejected
                )
            }
            
            // Proportional Distribution Spectrum
            if !viewModel.applications.isEmpty {
                distributionSpectrum
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.60), lineWidth: 0.75)
        )
    }
    
    private func interactiveMetricTile(title: String, subtitle: String, count: Int, color: Color, icon: String, targetFilter: ProviderApplicationsViewModel.AppFilter) -> some View {
        let isFilterActive = viewModel.selectedFilter == targetFilter
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.selectedFilter = isFilterActive ? .all : targetFilter
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(PPBrandFont.regular(size: 10, relativeTo: .caption2))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(isFilterActive ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(color.opacity(isFilterActive ? 0.70 : 0.25), lineWidth: isFilterActive ? 1.5 : 0.75)
            )
        }
        .buttonStyle(ProviderPressStyle())
    }
    
    private var distributionSpectrum: some View {
        let total = max(1, viewModel.applications.count)
        let pendingFrac = CGFloat(viewModel.pendingCount) / CGFloat(total)
        let approvedFrac = CGFloat(viewModel.approvedCount) / CGFloat(total)
        let rejectedFrac = CGFloat(viewModel.rejectedCount) / CGFloat(total)
        
        return VStack(spacing: 4) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    if pendingFrac > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ProviderTheme.pending)
                            .frame(width: max(4, proxy.size.width * pendingFrac))
                    }
                    if approvedFrac > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ProviderTheme.approved)
                            .frame(width: max(4, proxy.size.width * approvedFrac))
                    }
                    if rejectedFrac > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ProviderTheme.rejected)
                            .frame(width: max(4, proxy.size.width * rejectedFrac))
                    }
                }
            }
            .frame(height: 5)
            .clipShape(Capsule())
            .background(AdminSurface.control, in: Capsule())
            
            HStack {
                Text(Language.get("Providers_TotalApps_Format", alter: "\(viewModel.applications.count) طلب انضمام إجمالي"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.tertiary)
                Spacer()
                Text(Language.get("Providers_Visible_Format", alter: "\(viewModel.filteredApps.count) معروض"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)
            }
        }
        .padding(.top, 2)
    }
    
    // MARK: - Search & Filter Deck
    
    private var searchAndFilterDeck: some View {
        VStack(spacing: 10) {
            // Liquid Search Field + Batch Select Toggle
            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AdminCommandInk.secondary)
                    
                    TextField(
                        Language.get("Providers_Search_Placeholder", alter: "ابحث بالاسم، المتجر، الجوال، المدينة، أو المعرّف..."),
                        text: $viewModel.searchText
                    )
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.primaryText)
                    
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AdminCommandInk.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AdminSurface.surface)
                        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                )
                
                // Batch Mode Toggle Button
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        viewModel.toggleBatchMode()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isBatchMode ? "checkmark.circle.fill" : "checklist")
                            .font(.system(size: 13, weight: .bold))
                        Text(viewModel.isBatchMode ? Language.get("Providers_Batch_Done", alter: "إلغاء التحديد") : Language.get("Providers_Batch_Mode", alter: "تحديد"))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundStyle(viewModel.isBatchMode ? Color.white : AdminSurface.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 11)
                    .background(
                        viewModel.isBatchMode ? AdminSurface.primary : AdminSurface.primary.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(ProviderPressStyle())
            }
            
            // Primary Status Filter Pills (Horizontal Scroll)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ProviderApplicationsViewModel.AppFilter.allCases, id: \.self) { filter in
                        let isSelected = viewModel.selectedFilter == filter
                        let count: Int = {
                            switch filter {
                            case .all: return viewModel.applications.count
                            case .pending: return viewModel.pendingCount
                            case .changesRequested: return viewModel.changesRequestedCount
                            case .resubmitted: return viewModel.resubmittedCount
                            case .approved: return viewModel.approvedCount
                            case .rejected: return viewModel.rejectedCount
                            }
                        }()
                        
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                viewModel.selectedFilter = filter
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(filter.localizedTitle)
                                    .font(isSelected ? AdminType.captionBold : AdminType.caption1)
                                
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        isSelected
                                            ? Color.white.opacity(0.25)
                                            : AdminSurface.primary.opacity(0.12),
                                        in: Capsule(style: .continuous)
                                    )
                            }
                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                isSelected
                                    ? AnyView(Capsule(style: .continuous).fill(AdminSurface.primary))
                                    : AnyView(Capsule(style: .continuous).fill(AdminSurface.control))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.5),
                                        lineWidth: 0.75
                                    )
                            )
                        }
                        .buttonStyle(ProviderPressStyle())
                    }
                }
                .padding(.horizontal, 1)
            }
            
            // Secondary Smart Filter Row: Provider Types & Risk Profiles
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Type Pills
                    ForEach(ProviderApplicationsViewModel.ProviderTypeFilter.allCases, id: \.self) { typeFilter in
                        let isSelected = viewModel.selectedTypeFilter == typeFilter
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                viewModel.selectedTypeFilter = typeFilter
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: typeFilter.icon)
                                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                Text(typeFilter.localizedTitle)
                                    .font(isSelected ? AdminType.caption2Bold : AdminType.caption2)
                            }
                            .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? AdminSurface.primary : AdminSurface.surface,
                                in: Capsule(style: .continuous)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(isSelected ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(ProviderPressStyle())
                    }

                    // Divider
                    Rectangle()
                        .fill(Color(uiColor: .ppSurfaceBorder).opacity(0.6))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 2)

                    // Risk Profile Pills
                    ForEach(ProviderApplicationsViewModel.RiskProfileFilter.allCases, id: \.self) { riskFilter in
                        let isSelected = viewModel.selectedRiskFilter == riskFilter
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                viewModel.selectedRiskFilter = riskFilter
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: riskFilter.icon)
                                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                Text(riskFilter.localizedTitle)
                                    .font(isSelected ? AdminType.caption2Bold : AdminType.caption2)
                            }
                            .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? (riskFilter == .highRisk ? Color(uiColor: .ppError) : AdminSurface.primary) : AdminSurface.surface,
                                in: Capsule(style: .continuous)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(isSelected ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(ProviderPressStyle())
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
    
    // MARK: - Master Queue List Section (Dedicated iPad Master Pane)
    
    @ViewBuilder
    private var masterQueueListSection: some View {
        if viewModel.isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(AdminSurface.primary)
                Text(Language.get("Loading", alter: "جاري جلب طلبات المزودين..."))
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if viewModel.filteredApps.isEmpty {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.primary.opacity(0.10))
                        .frame(width: 52, height: 52)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }
                Text(Language.get("Empty", alter: "لا توجد طلبات مطابقة"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.filteredApps, id: \.applicationID) { app in
                    PPProviderApplicationCard(
                        application: app,
                        isRegular: true,
                        isSelected: viewModel.selectedDetailApp?.id == app.id,
                        isBatchMode: viewModel.isBatchMode,
                        isBatchSelected: viewModel.selectedBatchIds.contains(app.applicationID),
                        onToggleBatchSelect: {
                            viewModel.toggleSelect(appId: app.applicationID)
                        }
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            viewModel.selectedDetailApp = app
                        }
                    } onReviewAction: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.reviewTargetApp = app
                    }
                }
            }
        }
    }

    // MARK: - Empty Inspector Placeholder (iPad Right Pane)

    private var emptyInspectorPlaceholder: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
            }
            
            VStack(spacing: 6) {
                Text(Language.get("Providers_SelectToInspect", alter: "اختر طلباً من قائمة الانتظار"))
                    .font(PPBrandFont.bold(size: 20, relativeTo: .title3))
                    .foregroundStyle(AdminSurface.primaryText)
                
                Text(Language.get("Providers_SelectToInspect_Sub", alter: "حدد أحد طلبات المزودين لمعاينة الملف التجاري، فحص التراخيص والمستندات، وإصدار القرارات."))
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            
            if let firstPending = viewModel.filteredApps.first(where: {
                let s = $0.status.lowercased()
                return s == "pending" || s == "under_review" || s == "changes_requested" || s == "resubmitted"
            }) ?? viewModel.filteredApps.first {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        viewModel.selectedDetailApp = firstPending
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("Providers_InspectFirstPending", alter: "معاينة أول طلب معلق"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(AdminSurface.primary, in: Capsule(style: .continuous))
                }
                .buttonStyle(ProviderPressStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(AdminSurface.background)
    }

    // MARK: - Applications List Section (iPhone Stack)
    
    @ViewBuilder
    private var applicationsListSection: some View {
        if viewModel.isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(AdminSurface.primary)
                Text(Language.get("Loading", alter: "جاري جلب طلبات المزودين..."))
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if viewModel.filteredApps.isEmpty {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.primary.opacity(0.10))
                        .frame(width: 64, height: 64)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }
                
                Text(Language.get("Empty", alter: "لا توجد طلبات مطابقة"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                
                Text(Language.get("Providers_Empty_Subtitle", alter: "جرب تغيير معايير البحث أو تصفية الحالة لعرض الطلبات."))
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                if !viewModel.searchText.isEmpty || viewModel.selectedFilter != .all {
                    Button {
                        viewModel.searchText = ""
                        viewModel.selectedFilter = .all
                    } label: {
                        Text(Language.get("ResetFilters", alter: "إعادة ضبط الفلاتر"))
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredApps, id: \.applicationID) { app in
                    PPProviderApplicationCard(
                        application: app,
                        isRegular: false,
                        isSelected: false,
                        isBatchMode: viewModel.isBatchMode,
                        isBatchSelected: viewModel.selectedBatchIds.contains(app.applicationID),
                        onToggleBatchSelect: {
                            viewModel.toggleSelect(appId: app.applicationID)
                        }
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.selectedDetailApp = app
                    } onReviewAction: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.reviewTargetApp = app
                    }
                }
            }
        }
    }
    
    // MARK: - Batch Floating Action Bar
    private var batchFloatingActionBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Count badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(AdminSurface.primary)
                        .frame(width: 8, height: 8)
                    Text(String(format: Language.get("Providers_Batch_SelectedCount", alter: "تم تحديد %d طلبات"), viewModel.selectedBatchIds.count))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AdminSurface.control, in: Capsule())
                
                Spacer()
                
                // Select All / Clear Button
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    if viewModel.selectedBatchIds.count == viewModel.filteredApps.count {
                        viewModel.clearSelection()
                    } else {
                        viewModel.selectAllFiltered()
                    }
                } label: {
                    Text(viewModel.selectedBatchIds.count == viewModel.filteredApps.count ? Language.get("Providers_Batch_Clear", alter: "مسح التحديد") : Language.get("Providers_Batch_SelectAll", alter: "تحديد الكل"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primary)
                }
                
                // Batch Assign Reviewer Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showAssignReviewerAlert = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(Language.get("Providers_Batch_AssignReviewer", alter: "تعيين مراجع"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(viewModel.selectedBatchIds.isEmpty ? Color.gray : AdminSurface.primary, in: Capsule())
                }
                .disabled(viewModel.selectedBatchIds.isEmpty || viewModel.isExecutingBatch)
                
                // Batch Add Tag Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showAddTagAlert = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(Language.get("Providers_Batch_AddTag", alter: "إضافة وسم"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(viewModel.selectedBatchIds.isEmpty ? Color.gray : ProviderTheme.approved, in: Capsule())
                }
                .disabled(viewModel.selectedBatchIds.isEmpty || viewModel.isExecutingBatch)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AdminSurface.surface)
                    .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AdminSurface.primary.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, isRegular ? 24 : 16)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Flagship Provider Application Card

private struct PPProviderApplicationCard: View {
    let application: PPProviderApplication
    var isRegular: Bool = false
    var isSelected: Bool = false
    var isBatchMode: Bool = false
    var isBatchSelected: Bool = false
    var onToggleBatchSelect: (() -> Void)? = nil
    let onTap: () -> Void
    let onReviewAction: () -> Void
    
    var body: some View {
        let statusTone = ProviderTheme.tone(for: application.status)
        let typeInfo = ProviderTheme.localizedType(application.providerType)
        let name = resolvedName
        let dateText = resolvedDateText
        let isPending = application.status.lowercased() == "pending" || application.status.lowercased() == "under_review" || application.status.isEmpty
        
        Button(action: {
            if isBatchMode {
                onToggleBatchSelect?()
            } else {
                onTap()
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Top Header Row: (Batch Checkbox) + Emblem + Name + Type + Status Pill
                HStack(alignment: .center, spacing: 12) {
                    if isBatchMode {
                        Button {
                            onToggleBatchSelect?()
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(isBatchSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder), lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                                if isBatchSelected {
                                    Circle()
                                        .fill(AdminSurface.primary)
                                        .frame(width: 22, height: 22)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(statusTone.color.opacity(0.12))
                            .frame(width: 46, height: 46)
                        Image(systemName: typeInfo.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(statusTone.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(PPBrandFont.bold(size: 16, relativeTo: .headline))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text(typeInfo.text)
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))
                            
                            if let city = resolvedCity, !city.isEmpty {
                                Text("•")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(AdminCommandInk.tertiary)
                                Text(city)
                                    .font(AdminType.caption2)
                                    .foregroundStyle(AdminCommandInk.secondary)
                            }
                        }
                    }
                    
                    Spacer(minLength: 4)
                    
                    // Status Badge
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusTone.color)
                            .frame(width: 6, height: 6)
                        Text(statusTone.text)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(statusTone.color)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(statusTone.color.opacity(0.12), in: Capsule(style: .continuous))
                }
                
                // Telemetry Badges (Tags, Reviewer, High Resubmissions)
                if !application.tags.isEmpty || !application.reviewedBy.isEmpty || application.resubmissionCount > 1 {
                    HStack(spacing: 5) {
                        if application.resubmissionCount > 1 {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 9, weight: .bold))
                                Text("\(application.resubmissionCount)x")
                                    .font(AdminType.caption2Bold)
                            }
                            .foregroundStyle(Color(uiColor: .ppWarning))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(uiColor: .ppWarning).opacity(0.12), in: Capsule())
                        }
                        if !application.reviewedBy.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "person.badge.shield.checkmark.fill")
                                    .font(.system(size: 9))
                                Text(application.reviewedBy)
                                    .font(AdminType.caption2)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.primary.opacity(0.08), in: Capsule())
                        }
                        ForEach(application.tags.prefix(2), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.control, in: Capsule())
                        }
                    }
                }
                
                Divider()
                    .background(Color(uiColor: .ppSurfaceBorder).opacity(0.5))
                
                // Bottom Telemetry Row: ID Pill + Date + Chevron / Review CTA
                HStack(alignment: .center, spacing: 8) {
                    // ID Pill with 1-tap copy
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AdminCommandInk.tertiary)
                        Text(shortenedID)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    
                    Text("•")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AdminCommandInk.tertiary)
                    
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                            .foregroundStyle(AdminCommandInk.tertiary)
                        Text(dateText)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                    
                    Spacer()
                    
                    if isPending {
                        Button {
                            onReviewAction()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal")
                                    .font(.system(size: 11, weight: .bold))
                                Text(Language.get("Providers_Decide", alter: "اتخاذ القرار"))
                                    .font(AdminType.caption2Bold)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(ProviderTheme.pending, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(ProviderPressStyle())
                    } else {
                        HStack(spacing: 4) {
                            Text(Language.get("ViewDossier", alter: "عرض الملف"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primary)
                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AdminSurface.primary)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AdminSurface.primary.opacity(0.08) : AdminSurface.surface)
                    .shadow(color: isSelected ? AdminSurface.primary.opacity(0.12) : Color.black.opacity(0.03), radius: isSelected ? 8 : 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: isSelected ? 1.75 : 0.75)
            )
        }
        .buttonStyle(ProviderPressStyle())
        .accessibilityElement(children: .combine)
    }
    
    private var resolvedName: String {
        ProviderApplicationsViewModel.resolveDisplayName(for: application)
    }
    
    private var resolvedCity: String? {
        (application.form["city"] as? String)
    }
    
    private var resolvedDateText: String {
        let date = application.submittedAt ?? application.createdAt ?? application.updatedAt
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Language.currentLanguageCode())
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private var shortenedID: String {
        let id = application.applicationID.isEmpty ? application.userId : application.applicationID
        if id.count > 16 {
            let prefix = id.prefix(6)
            let suffix = id.suffix(6)
            return "\(prefix)...\(suffix)"
        }
        return id
    }
}

// MARK: - Document Inspection Model

public struct PPDocumentInspectionItem: Identifiable, Sendable {
    public var id: String { type }
    public let type: String
    public let localizedTitle: String
    public let fileUrl: String
    public let fileName: String
    public var status: String
    public var reviewFinding: String?
    public var verifiedByUid: String?
    public var verifiedAt: String?
    public var expiryDate: String?
    public var checksum: String?
}

// MARK: - Reimagined Provider Application Detail / Dossier View (Zero Gap & Full iPad Support)

public struct AdminProviderApplicationDetailView: View {
    let application: PPProviderApplication
    @ObservedObject var viewModel: ProviderApplicationsViewModel
    var isPushMode: Bool = true
    var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingReviewSheet = false
    @State private var copiedField: String? = nil
    @State private var selectedInspectionDoc: PPDocumentInspectionItem? = nil
    
    init(
        application: PPProviderApplication,
        viewModel: ProviderApplicationsViewModel,
        isPushMode: Bool = true,
        onBack: (() -> Void)? = nil
    ) {
        self.application = application
        self.viewModel = viewModel
        self.isPushMode = isPushMode
        self.onBack = onBack
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let isRegular = geometry.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize
            let containerMaxWidth: CGFloat = isRegular ? 1200 : .infinity

            ZStack(alignment: .top) {
                AdminSurface.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Nav with zero gap above status bar
                    dossierHeaderNav
                    
                    ScrollView {
                        if isRegular {
                            // iPad 2-Column Asymmetric Flight Deck
                            ipadDossierLayout
                                .padding(.horizontal, AdminSpacing.screenMargin)
                                .padding(.top, 10)
                                .padding(.bottom, 60)
                                .frame(maxWidth: containerMaxWidth)
                                .frame(maxWidth: .infinity)
                        } else {
                            // iPhone High-Velocity Executive Stack
                            iphoneDossierLayout
                                .padding(.horizontal, AdminSpacing.screenMargin)
                                .padding(.top, 10)
                                .padding(.bottom, isPending ? 90 : 40)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isPending && !isRegular {
                    decisionDock
                }
            }
        }
        .sheet(isPresented: $showingReviewSheet) {
            ProviderReviewDecisionSheet(application: application, viewModel: viewModel)
        }
        .sheet(item: $selectedInspectionDoc) { docItem in
            PPDocumentInspectionSheet(application: application, documentItem: docItem, viewModel: viewModel)
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
    
    // MARK: - Sovereign Dossier Navigation Header (Zero Top Gap)
    
    private var dossierHeaderNav: some View {
        let statusTone = ProviderTheme.tone(for: application.status)
        return HStack(spacing: 12) {
            if isPushMode {
                AdminSquircleBackButton {
                    if let onBack = onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                }
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onBack?()
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.control)
                            .frame(width: 32, height: 32)
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
                .buttonStyle(ProviderPressStyle())
                .accessibilityLabel(Language.get("Close", alter: "إغلاق"))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(resolvedName)
                    .font(PPBrandFont.bold(size: 17, relativeTo: .headline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusTone.color)
                        .frame(width: 6, height: 6)
                    Text(Language.get("Providers_Dossier_Breadcrumb", alter: "ملف طلب المزود"))
                        .font(PPBrandFont.medium(size: 11.5, relativeTo: .caption))
                        .foregroundStyle(AdminCommandInk.secondary)
                }
            }
            
            Spacer(minLength: 4)
            
            // Status Tag in Navigation Header
            HStack(spacing: 5) {
                Circle()
                    .fill(statusTone.color)
                    .frame(width: 6, height: 6)
                Text(statusTone.text)
                    .font(PPBrandFont.bold(size: 11, relativeTo: .caption2))
                    .foregroundStyle(statusTone.color)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusTone.color.opacity(0.12), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(statusTone.color.opacity(0.25), lineWidth: 0.5)
            )
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(AdminSurface.background)
    }

    // MARK: - iPhone Layout Stack
    private var iphoneDossierLayout: some View {
        LazyVStack(spacing: 16) {
            heroDossierCard
            identifiersMatrix
            applicantAndBusinessSection
            commercialSection
            documentsInspectionSection
            planSection
            reviewHistorySection
        }
    }

    // MARK: - iPad 2-Column Asymmetric Flight Deck
    private var ipadDossierLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            // Leading Wing (410pt): Identity, Quick Contact, Review History & Action Dock
            VStack(spacing: 16) {
                heroDossierCard
                if isPending {
                    decisionCardIPad
                }
                reviewHistorySection
            }
            .frame(width: 410)

            // Trailing Wing (Flexible): Identifiers, Commercial Credentials, Documents, Plans & Contact Details
            VStack(spacing: 16) {
                identifiersMatrix
                commercialSection
                documentsInspectionSection
                planSection
                applicantAndBusinessSection
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var decisionCardIPad: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ProviderTheme.pending)
                Text(Language.get("Providers_Decision_Title", alter: "اتخاذ القرار الإداري"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingReviewSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(Language.get("Providers_TakeDecision_CTA", alter: "إصدار القرار الإداري الآن"))
                        .font(AdminType.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    LinearGradient(
                        colors: [ProviderTheme.pending, ProviderTheme.pending.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: ProviderTheme.pending.opacity(0.30), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(ProviderPressStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ProviderTheme.pending.opacity(0.35), lineWidth: 0.75)
        )
    }
    
    // MARK: - Hero Dossier Card
    
    private var heroDossierCard: some View {
        let statusTone = ProviderTheme.tone(for: application.status)
        let typeInfo = ProviderTheme.localizedType(application.providerType)
        let name = resolvedName
        let phone = (application.form["phone"] as? String) ?? (application.userSummary["phone"] as? String) ?? ""
        let email = (application.form["email"] as? String) ?? (application.userSummary["email"] as? String) ?? ""
        
        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(statusTone.color.opacity(0.14))
                        .frame(width: 58, height: 58)
                    Image(systemName: typeInfo.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(statusTone.color)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(Language.get("Providers_Applicant_Title", alter: "طلب انضمام مقدم خدمة"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminCommandInk.secondary)
                        
                        if application.status.lowercased() == "approved" {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(ProviderTheme.approved)
                        }
                    }
                    
                    Text(name)
                        .font(PPBrandFont.bold(size: 20, relativeTo: .title3))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                    
                    Text(typeInfo.text)
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminSurface.primary)
                }
                
                Spacer(minLength: 4)
            }
            
            // Status Banner Capsule
            HStack(spacing: 8) {
                Circle()
                    .fill(statusTone.color)
                    .frame(width: 8, height: 8)
                Text(statusTone.text)
                    .font(AdminType.headline)
                    .foregroundStyle(statusTone.color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(statusTone.color.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(statusTone.color.opacity(0.30), lineWidth: 0.75)
            )
            
            // Next Move Guidance Banner
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: nextMoveIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusTone.color)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("NextAction", alter: "الإجراء والخطوة التالية:"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    Text(nextMoveText)
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Direct Contact Launchpad (Call, WhatsApp, Email)
            HStack(spacing: 8) {
                if !phone.isEmpty && phone != "—" {
                    let cleanPhone = phone.replacingOccurrences(of: " ", with: "")
                    if let telURL = URL(string: "tel://\(cleanPhone)") {
                        Link(destination: telURL) {
                            HStack(spacing: 5) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(Language.get("Call", alter: "اتصال"))
                                    .font(AdminType.caption2Bold)
                            }
                            .foregroundStyle(ProviderTheme.approved)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(ProviderTheme.approved.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    let waClean = cleanPhone.replacingOccurrences(of: "+", with: "")
                    if let waURL = URL(string: "https://wa.me/\(waClean)") {
                        Link(destination: waURL) {
                            HStack(spacing: 5) {
                                Image("whatsapp")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                Text("WhatsApp")
                                    .font(AdminType.caption2Bold)
                            }
                            .foregroundStyle(Color(red: 0.15, green: 0.70, blue: 0.35))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(Color(red: 0.15, green: 0.70, blue: 0.35).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }

                if !email.isEmpty && email != "—", let mailURL = URL(string: "mailto:\(email)") {
                    Link(destination: mailURL) {
                        HStack(spacing: 5) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(Language.get("Email", alter: "بريد"))
                                .font(AdminType.caption2Bold)
                        }
                        .foregroundStyle(AdminSurface.primary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(statusTone.color.opacity(0.25), lineWidth: 0.75)
        )
    }
    
    // MARK: - System Identifiers Matrix
    
    private var identifiersMatrix: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: Language.get("Overview", alter: "نظرة عامة والرموز المرجعية"),
                detail: Language.get("Overview_Detail", alter: "المعرفات المرجعية الأساسية الخاصة بالطلب على السحابة.")
            )
            
            VStack(spacing: 8) {
                idRow(title: Language.get("Providers_ApplicationID", alter: "معرّف الطلب"), value: application.applicationID)
                idRow(title: Language.get("Providers_UserID", alter: "معرّف حساب المستخدم"), value: application.userId)
                if !application.profileId.isEmpty {
                    idRow(title: Language.get("Providers_ProfileID", alter: "معرّف ملف المزود"), value: application.profileId)
                }
                if !application.deliveryCompanyId.isEmpty {
                    idRow(title: Language.get("Providers_DeliveryID", alter: "معرّف شركة التوصيل"), value: application.deliveryCompanyId)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AdminSurface.surface)
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
            )
        }
    }
    
    private func idRow(title: String, value: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .environment(\.layoutDirection, .leftToRight)
            }
            
            Spacer()
            
            Button {
                UIPasteboard.general.string = value
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation { copiedField = title }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { copiedField = nil }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copiedField == title ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .bold))
                    Text(copiedField == title ? Language.get("Copied", alter: "تم النسخ") : Language.get("Copy", alter: "نسخ"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(copiedField == title ? ProviderTheme.approved : AdminSurface.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    (copiedField == title ? ProviderTheme.approved : AdminSurface.primary).opacity(0.10),
                    in: Capsule(style: .continuous)
                )
            }
            .buttonStyle(ProviderPressStyle())
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Applicant & Business Contact
    
    private var applicantAndBusinessSection: some View {
        let fullName = (application.form["fullName"] as? String) ?? (application.userSummary["displayName"] as? String) ?? "—"
        let phone = (application.form["phone"] as? String) ?? (application.userSummary["phone"] as? String) ?? "—"
        let email = (application.form["email"] as? String) ?? (application.userSummary["email"] as? String) ?? "—"
        let city = (application.form["city"] as? String) ?? "—"
        let address = (application.form["address"] as? String) ?? "—"
        
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: Language.get("Providers_Contact_Title", alter: "مقدم الطلب والتواصل"),
                detail: Language.get("Providers_Contact_Detail", alter: "بيانات الهوية الشخصية وقنوات التواصل المعتمدة.")
            )
            
            VStack(spacing: 12) {
                contactRow(title: Language.get("FullName", alter: "الاسم الكامل"), value: fullName, icon: "person.fill")
                
                // Phone with 1-tap call & WhatsApp
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Language.get("PhoneNumber", alter: "رقم الهاتف"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminCommandInk.secondary)
                        Text(phone)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    Spacer()
                    if phone != "—" {
                        HStack(spacing: 8) {
                            if let telURL = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
                                Link(destination: telURL) {
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(ProviderTheme.approved)
                                        .frame(width: 32, height: 32)
                                        .background(ProviderTheme.approved.opacity(0.12), in: Circle())
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                // Email with 1-tap mailto
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Language.get("Email", alter: "البريد الإلكتروني"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminCommandInk.secondary)
                        Text(email)
                            .font(AdminType.callout)
                            .foregroundStyle(AdminSurface.primaryText)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    Spacer()
                    if email != "—", let mailURL = URL(string: "mailto:\(email)") {
                        Link(destination: mailURL) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AdminSurface.primary)
                                .frame(width: 32, height: 32)
                                .background(AdminSurface.primary.opacity(0.12), in: Circle())
                        }
                    }
                }
                
                Divider()
                
                contactRow(title: Language.get("City", alter: "المدينة"), value: city, icon: "mappin.and.ellipse")
                
                if address != "—" {
                    Divider()
                    contactRow(title: Language.get("Address", alter: "العنوان التفصيلي"), value: address, icon: "building.2.fill")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AdminSurface.surface)
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
            )
        }
    }
    
    private func contactRow(title: String, value: String, icon: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                Text(value)
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)
            }
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AdminCommandInk.tertiary)
        }
    }
    
    // MARK: - Commercial & Regulatory Credentials
    
    @ViewBuilder
    private var commercialSection: some View {
        let crNumber = (application.form["commercialRegistrationNumber"] as? String) ?? (application.form["crNumber"] as? String)
        let licenseNumber = (application.form["licenseNumber"] as? String)
        let taxNumber = (application.form["taxNumber"] as? String)
        let iban = (application.form["bankIban"] as? String) ?? (application.form["iban"] as? String)
        
        if crNumber != nil || licenseNumber != nil || taxNumber != nil || iban != nil {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: Language.get("Providers_Commercial_Title", alter: "البيانات التجارية والترخيص"),
                    detail: Language.get("Providers_Commercial_Detail", alter: "معلومات السجل التجاري والاعتمادات الرسمية.")
                )
                
                VStack(spacing: 12) {
                    if let cr = crNumber, !cr.isEmpty {
                        credentialTile(title: Language.get("CommercialRegistrationNo", alter: "رقم السجل التجاري"), value: cr, icon: "building.columns.fill")
                    }
                    if let lic = licenseNumber, !lic.isEmpty {
                        credentialTile(title: Language.get("LicenseNo", alter: "رقم رخصة المزاولة"), value: lic, icon: "doc.text.fill")
                    }
                    if let tax = taxNumber, !tax.isEmpty {
                        credentialTile(title: Language.get("TaxNo", alter: "الرقم الضريبي"), value: tax, icon: "percent")
                    }
                    if let bankIban = iban, !bankIban.isEmpty {
                        credentialTile(title: Language.get("BankIBAN", alter: "الحساب البنكي (IBAN)"), value: bankIban, icon: "creditcard.fill")
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AdminSurface.surface)
                        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
                )
            }
        }
    }
    
    private func credentialTile(title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 32, height: 32)
                .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(AdminSurface.primaryText)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Spacer()
        }
    }
    
    // MARK: - Documents Inspection & Verification Section
    
    private var documentsInspectionSection: some View {
        let items = documentItems
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: Language.get("Providers_Documents_Title", alter: "فحص وتوثيق المستندات الرسمية"),
                detail: Language.get("Providers_Documents_Detail", alter: "معاينة التراخيص والسجلات، التحقق المشفر، وإصدار قرارات الفحص.")
            )
            
            if items.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AdminCommandInk.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Providers_NoDocs_Title", alter: "لا توجد مستندات مرفقة"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(Language.get("Providers_NoDocs_Detail", alter: "لم يقم المزود برفع مستندات رسمية أو لم يتم تسجيلها بعد."))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { doc in
                        documentRowCard(for: doc)
                    }
                }
            }
        }
    }
    
    private func documentRowCard(for doc: PPDocumentInspectionItem) -> some View {
        let statusTone = documentStatusTone(for: doc.status)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(statusTone.color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: statusTone.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(statusTone.color)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.localizedTitle)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                    
                    Text(doc.fileName)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Status Chip
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusTone.color)
                        .frame(width: 6, height: 6)
                    Text(statusTone.text)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(statusTone.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusTone.color.opacity(0.12), in: Capsule())
            }
            
            // Verification Stamp Banner if Verified
            if doc.status.lowercased() == "verified", let checksum = doc.checksum, !checksum.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ProviderTheme.approved)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Providers_Doc_StampLabel", alter: "بصمة التحقق المشفرة (SHA-256):"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminCommandInk.secondary)
                        Text(String(checksum.prefix(16)) + "..." + String(checksum.suffix(8)))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    Spacer()
                    if let expiry = doc.expiryDate, !expiry.isEmpty {
                        Text(Language.get("Expires", alter: "ينتهي: ") + String(expiry.prefix(10)))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
                .padding(8)
                .background(ProviderTheme.approved.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            
            // Finding Banner if Changes Required or Rejected
            if let finding = doc.reviewFinding, !finding.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: doc.status.lowercased() == "rejected" ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(statusTone.color)
                        .padding(.top, 1)
                    Text(finding)
                        .font(AdminType.caption1)
                        .foregroundStyle(statusTone.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(statusTone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            
            // Action button to inspect
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                selectedInspectionDoc = doc
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(Language.get("Providers_Doc_InspectCTA", alter: "معاينة وتدقيق المستند"))
                        .font(AdminType.captionBold)
                    Spacer()
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(AdminSurface.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(ProviderPressStyle())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }
    
    private func documentStatusTone(for status: String) -> (color: Color, text: String, icon: String) {
        switch status.lowercased() {
        case "verified":
            return (ProviderTheme.approved, Language.get("Doc_Status_Verified", alter: "موثّق ومعتمد"), "checkmark.shield.fill")
        case "changes_required":
            return (ProviderTheme.changesRequested, Language.get("Doc_Status_ChangesRequired", alter: "مطلوب تعديل"), "exclamationmark.triangle.fill")
        case "rejected":
            return (ProviderTheme.rejected, Language.get("Doc_Status_Rejected", alter: "مرفوض"), "xmark.seal.fill")
        case "under_review":
            return (Color.indigo, Language.get("Doc_Status_UnderReview", alter: "قيد الفحص"), "hourglass.circle.fill")
        case "uploaded":
            return (ProviderTheme.pending, Language.get("Doc_Status_Uploaded", alter: "مرفوع جديد"), "arrow.up.doc.fill")
        default:
            return (AdminCommandInk.secondary, Language.get("Doc_Status_Missing", alter: "غير مرفق"), "doc.questionmark.fill")
        }
    }
    
    private var documentItems: [PPDocumentInspectionItem] {
        var items: [PPDocumentInspectionItem] = []
        let rawDocs = application.documents
        let form = application.form
        
        // 1. Commercial Registration
        let crDict = rawDocs["commercial_registration"] as? [String: Any]
        let crUrl = (crDict?["fileUrl"] as? String) ?? (form["commercialRegistrationDocumentURL"] as? String) ?? (form["commercialRegDocument"] as? String) ?? ""
        if !crUrl.isEmpty || crDict != nil {
            items.append(makeDocItem(
                type: "commercial_registration",
                title: Language.get("Doc_CR", alter: "السجل التجاري"),
                dict: crDict,
                fallbackUrl: crUrl,
                fallbackName: "commercial_registration.pdf"
            ))
        }
        
        // 2. License / Trade License / Pharmacy License
        let licKey = application.providerType.lowercased() == "pharmacy" ? "pharmacy_license" : "license"
        let licDict = (rawDocs[licKey] as? [String: Any]) ?? (rawDocs["license"] as? [String: Any]) ?? (rawDocs["trade_license"] as? [String: Any])
        let licUrl = (licDict?["fileUrl"] as? String) ?? (form["licenseDocumentURL"] as? String) ?? (form["licenseDocument"] as? String) ?? ""
        if !licUrl.isEmpty || licDict != nil {
            let licTitle = application.providerType.lowercased() == "pharmacy"
                ? Language.get("Doc_PharmacyLicense", alter: "رخصة المنشأة الصيدلانية")
                : Language.get("Doc_License", alter: "رخصة المزاولة التجارية")
            items.append(makeDocItem(
                type: licKey,
                title: licTitle,
                dict: licDict,
                fallbackUrl: licUrl,
                fallbackName: "\(licKey).pdf"
            ))
        }
        
        // 3. Other explicit keys in rawDocs
        for (rawKey, val) in rawDocs {
            guard let key = rawKey as? String,
                  !["commercial_registration", "license", "trade_license", "pharmacy_license"].contains(key) else { continue }
            if let dict = val as? [String: Any] {
                let title = localizedDocTitle(for: key)
                let url = (dict["fileUrl"] as? String) ?? ""
                let name = (dict["fileName"] as? String) ?? "\(key).pdf"
                items.append(makeDocItem(type: key, title: title, dict: dict, fallbackUrl: url, fallbackName: name))
            }
        }
        
        // 4. Any documentRefs in form not covered
        if let refs = form["documentRefs"] as? [String] {
            for (idx, ref) in refs.enumerated() where !ref.isEmpty && !items.contains(where: { $0.fileUrl == ref }) {
                items.append(PPDocumentInspectionItem(
                    type: "document_\(idx + 1)",
                    localizedTitle: "\(Language.get("Doc_Attachment", alter: "مرفق ترخيص إضافي")) #\(idx + 1)",
                    fileUrl: ref,
                    fileName: "attachment_\(idx + 1).pdf",
                    status: "uploaded",
                    reviewFinding: nil,
                    verifiedByUid: nil,
                    verifiedAt: nil,
                    expiryDate: nil,
                    checksum: nil
                ))
            }
        }
        
        return items
    }
    
    private func makeDocItem(type: String, title: String, dict: [String: Any]?, fallbackUrl: String, fallbackName: String) -> PPDocumentInspectionItem {
        let status = (dict?["status"] as? String) ?? (!fallbackUrl.isEmpty ? "uploaded" : "missing")
        let url = (dict?["fileUrl"] as? String) ?? fallbackUrl
        let name = (dict?["fileName"] as? String) ?? fallbackName
        let finding = dict?["reviewFinding"] as? String
        let reviewedBy = dict?["reviewedByUid"] as? String
        let reviewedAt = dict?["reviewedAt"] as? String
        let expiry = dict?["expiryDate"] as? String
        let stamp = dict?["verificationStamp"] as? [String: Any]
        let checksum = stamp?["checksum"] as? String
        
        return PPDocumentInspectionItem(
            type: type,
            localizedTitle: title,
            fileUrl: url,
            fileName: name,
            status: status,
            reviewFinding: finding,
            verifiedByUid: reviewedBy,
            verifiedAt: reviewedAt,
            expiryDate: expiry,
            checksum: checksum
        )
    }
    
    private func localizedDocTitle(for type: String) -> String {
        switch type.lowercased() {
        case "commercial_registration":
            return Language.get("Doc_CR", alter: "السجل التجاري")
        case "license", "trade_license":
            return Language.get("Doc_License", alter: "رخصة المزاولة التجارية")
        case "pharmacy_license":
            return Language.get("Doc_PharmacyLicense", alter: "رخصة المنشأة الصيدلانية")
        case "veterinary_health_clearance":
            return Language.get("Doc_VetClearance", alter: "شهادة المنشأة البيطرية")
        case "transport_license":
            return Language.get("Doc_TransportLicense", alter: "ترخيص النقل والتوصيل")
        case "tax_certificate":
            return Language.get("Doc_TaxCert", alter: "البطاقة الضريبية")
        default:
            return Language.get("Doc_Attachment", alter: "مستند رسمي") + " (\(type))"
        }
    }
    
    // MARK: - Plan & Commercial Terms
    
    private var planSection: some View {
        let planSnapshot = application.planSnapshot
        let planName = (planSnapshot["name"] as? String)
            ?? ((planSnapshot["name"] as? NSDictionary)?["ar"] as? String)
            ?? application.planId
        let commission = (planSnapshot["commissionRate"] as? Double) ?? 0
        let price = (planSnapshot["price"] as? Double) ?? (planSnapshot["price"] as? NSNumber)?.doubleValue ?? 0
        let currency = (planSnapshot["currency"] as? String) ?? "QAR"
        
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: Language.get("Providers_Plan_Title", alter: "باقة الاشتراك والشروط التجارية"),
                detail: Language.get("Providers_Plan_Detail", alter: "الباقة المحددة وعمولة المنصة المعتمدة.")
            )
            
            VStack(spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(planName.isEmpty ? Language.get("StandardPlan", alter: "الباقة القياسية") : planName)
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(Language.get("ActiveTerms", alter: "الشروط والعمولة النشطة"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                    
                    Spacer()
                    
                    if commission > 0 {
                        Text("\(String(format: "%.1f", commission))% " + Language.get("Commission", alter: "عمولة"))
                            .font(AdminType.captionBold)
                            .foregroundStyle(ProviderTheme.approved)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ProviderTheme.approved.opacity(0.12), in: Capsule(style: .continuous))
                    } else if price > 0 {
                        Text("\(String(format: "%.2f", price)) \(currency)")
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AdminSurface.primary.opacity(0.12), in: Capsule(style: .continuous))
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AdminSurface.surface)
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
            )
        }
    }
    
    // MARK: - Review History
    
    @ViewBuilder
    private var reviewHistorySection: some View {
        if application.reviewedAt != nil || !application.reviewNotes.isEmpty || !application.rejectionReason.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: Language.get("Providers_ReviewHistory_Title", alter: "سجل التدقيق والملاحظات"),
                    detail: Language.get("Providers_ReviewHistory_Detail", alter: "سجل القرارات الإدارية السابقة الصادرة على الطلب.")
                )
                
                VStack(alignment: .leading, spacing: 10) {
                    if let date = application.reviewedAt {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 13))
                                .foregroundStyle(AdminCommandInk.secondary)
                            Text(Language.get("ReviewedAt", alter: "تاريخ القرار: ") + formatDate(date))
                                .font(AdminType.caption1)
                                .foregroundStyle(AdminCommandInk.secondary)
                        }
                    }
                    
                    if !application.reviewedBy.isEmpty {
                        HStack {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(AdminSurface.primary)
                            Text(Language.get("ReviewedBy", alter: "المشرف: ") + application.reviewedBy)
                                .font(AdminType.caption1)
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                    }
                    
                    if !application.reviewNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Language.get("ReviewNotes", alter: "ملاحظات المراجعة:"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminCommandInk.secondary)
                            Text(application.reviewNotes)
                                .font(AdminType.callout)
                                .foregroundStyle(AdminSurface.primaryText)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AdminSurface.surface)
                        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
                )
            }
        }
    }
    
    // MARK: - Tactical Decision Dock
    
    private var decisionDock: some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingReviewSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(Language.get("Providers_TakeDecision_CTA", alter: "اتخاذ القرار الإداري"))
                        .font(AdminType.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    LinearGradient(
                        colors: [
                            ProviderTheme.pending,
                            ProviderTheme.pending.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: ProviderTheme.pending.opacity(0.35), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(ProviderPressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    Divider()
                        .background(Color(uiColor: .ppSurfaceBorder).opacity(0.7))
                }
        )
    }
    
    // MARK: - Helpers
    
    private var isPending: Bool {
        let s = application.status.lowercased()
        return s == "pending" || s == "under_review" || s == "submitted" || s == "changes_requested" || s == "resubmitted" || s.isEmpty
    }
    
    private var resolvedName: String {
        ProviderApplicationsViewModel.resolveDisplayName(for: application)
    }
    
    private var nextMoveIcon: String {
        switch application.status.lowercased() {
        case "approved": return "checkmark.circle.fill"
        case "rejected": return "exclamationmark.octagon.fill"
        case "changes_requested": return "exclamationmark.bubble.fill"
        case "resubmitted": return "arrow.counterclockwise.circle.fill"
        case "under_review": return "hourglass.circle.fill"
        default: return "clock.arrow.circlepath"
        }
    }
    
    private var nextMoveText: String {
        switch application.status.lowercased() {
        case "approved":
            return Language.get("Providers_NextMove_Approved", alter: "تمت الموافقة وتفعيل حساب المزود بنجاح. لا يلزم أي إجراء مراجعة آخر.")
        case "rejected":
            return Language.get("Providers_NextMove_Rejected", alter: "تم رفض الطلب لعدم استيفاء الشروط المطلوبة. يمكن للمزود تقديم طلب جديد.")
        case "changes_requested":
            return Language.get("Providers_NextMove_ChangesRequested", alter: "تم إرسال طلب تعديلات ومستندات للمزود. بانتظار قيام المزود بتحديث بياناته وإعادة التقديم.")
        case "resubmitted":
            return Language.get("Providers_NextMove_Resubmitted", alter: "قام المزود بإعادة تقديم الطلب بعد معالجة الملاحظات. يرجى مراجعة التحديثات وإصدار القرار.")
        case "under_review":
            return Language.get("Providers_NextMove_UnderReview", alter: "الطلب قيد التدقيق الإداري. قم بفحص التراخيص والاتصال بالمتقدم لإصدار القرار.")
        default:
            return Language.get("Providers_NextMove_Pending", alter: "الطلب بانتظار اتخاذ القرار الإداري. راجع الملف واضغط زر اتخاذ القرار أدناه.")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Language.currentLanguageCode())
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Structured Findings & Rejection Taxonomy Models

private struct QuickFindingTemplate: Identifiable {
    let id: String
    let targetType: String
    let targetKey: String
    let titleAr: String
    let titleEn: String
    let descriptionAr: String
    let descriptionEn: String
    let remedyAr: String
    let remedyEn: String
    
    var localizedTitle: String {
        Language.isRTL() ? titleAr : titleEn
    }
    
    var localizedDescription: String {
        Language.isRTL() ? descriptionAr : descriptionEn
    }
    
    var localizedRemedy: String {
        Language.isRTL() ? remedyAr : remedyEn
    }
}

private struct RejectionTaxonomyItem: Identifiable {
    let code: String
    let titleAr: String
    let titleEn: String
    let descriptionAr: String
    let descriptionEn: String
    
    var id: String { code }
    
    var localizedTitle: String {
        Language.isRTL() ? titleAr : titleEn
    }
    
    var localizedDescription: String {
        Language.isRTL() ? descriptionAr : descriptionEn
    }
}

private let standardFindingTemplates: [QuickFindingTemplate] = [
    QuickFindingTemplate(
        id: "CLARITY_BLURRY_SCAN",
        targetType: "document",
        targetKey: "commercial_registration",
        titleAr: "المستند غير واضح أو مطموس",
        titleEn: "Document scan is blurry",
        descriptionAr: "المستند المرفوع غير واضح أو تظهر فيه أختام غير مقروءة تعذر التحقق منها رسميًا.",
        descriptionEn: "The uploaded document is blurry, cut off, or contains unreadable official stamps.",
        remedyAr: "يرجى إعادة رفع نسخة ممسوحة ضوئيًا واضحة لكامل الصفحة والأختام.",
        remedyEn: "Please upload a high-resolution scan showing full page and stamps clearly."
    ),
    QuickFindingTemplate(
        id: "EXPIRY_EXPIRED_DOCUMENT",
        targetType: "document",
        targetKey: "license",
        titleAr: "انتهاء صلاحية الرخصة أو السجل",
        titleEn: "Document or license has expired",
        descriptionAr: "تاريخ صلاحية المستند المرفوع منتهي ولا يمكن اعتماده لتفعيل المنشأة.",
        descriptionEn: "The validity date of the submitted document has passed and cannot be approved.",
        remedyAr: "يرجى تجديد الرخصة ورفع وثيقة التجديد سارية المفعول.",
        remedyEn: "Please renew the license with competent authority and upload the valid document."
    ),
    QuickFindingTemplate(
        id: "MISMATCH_NAME_OR_CR",
        targetType: "document",
        targetKey: "commercial_registration",
        titleAr: "عدم تطابق الاسم التجاري أو رقم السجل",
        titleEn: "Trade name or CR number mismatch",
        descriptionAr: "الاسم أو رقم السجل التجاري المدخل في بيانات الطلب لا يتطابق تمامًا مع الوثيقة الرسمية المرفقة.",
        descriptionEn: "The business trade name or CR number does not match the official document.",
        remedyAr: "يرجى تصحيح الاسم التجاري ورقم السجل ليتطابق مع السجل التجاري الرسمي.",
        remedyEn: "Please correct trade name and CR number to match your official registration."
    ),
    QuickFindingTemplate(
        id: "REGULATORY_MISSING_VET_CLEARANCE",
        targetType: "document",
        targetKey: "veterinary_health_clearance",
        titleAr: "شهادة المنشأة البيطرية غير مرفقة",
        titleEn: "Veterinary clearance missing",
        descriptionAr: "تتطلب خدمات الرعاية والعيادات البيطرية إرفاق ترخيص المنشأة البيطرية المعتمد من وزارة البلدية والبيئة.",
        descriptionEn: "Veterinary care services require a certified facility clearance from the Ministry.",
        remedyAr: "يرجى إرفاق ترخيص المنشأة البيطرية ساري المفعول لإتمام اعتماد القدرة البيطرية.",
        remedyEn: "Please upload your valid veterinary facility license to enable vet capabilities."
    ),
    QuickFindingTemplate(
        id: "REGULATORY_MISSING_PHARMACY_LICENSE",
        targetType: "document",
        targetKey: "pharmacy_license",
        titleAr: "ترخيص الصيدلية البيطرية مطلوب",
        titleEn: "Veterinary pharmacy license required",
        descriptionAr: "بيع وصرف الأدوية البيطرية يستلزم ترخيص صيدلية بيطرية معتمد من وزارة الصحة العامة.",
        descriptionEn: "Dispensing veterinary medicines requires a certified pharmacy license from MoPH.",
        remedyAr: "يرجى إرفاق رخصة الصيدلية البيطرية الصادرة من الجهة المختصة.",
        remedyEn: "Please attach the official veterinary pharmacy license issued by health authority."
    ),
    QuickFindingTemplate(
        id: "FINANCIAL_INVALID_IBAN",
        targetType: "field",
        targetKey: "bankIban",
        titleAr: "الحساب البنكي (IBAN) غير مطابق",
        titleEn: "Bank IBAN does not match",
        descriptionAr: "يجب أن يكون الحساب البنكي المخصص للتسويات باسم المنشأة أو المالك المسجل في السجل التجاري.",
        descriptionEn: "Bank account for settlements must be under company or registered owner's name.",
        remedyAr: "يرجى تحديث الآيبان البنكي أو إرفاق شهادة الحساب البنكي الرسمية.",
        remedyEn: "Please update the IBAN or provide an official bank certificate."
    ),
    QuickFindingTemplate(
        id: "IDENTITY_SIGNATORY_AUTHORITY",
        targetType: "document",
        targetKey: "establishment_card",
        titleAr: "بطاقة قيد المنشأة مطلوبة",
        titleEn: "Establishment card required",
        descriptionAr: "يرجى تقديم بطاقة قيد المنشأة للتأكد من صلاحية المفوض بالتوقيع والتعاقد.",
        descriptionEn: "Please provide establishment card to verify authorized signatory authority.",
        remedyAr: "يرجى رفع صورة من بطاقة قيد المنشأة سارية المفعول.",
        remedyEn: "Please upload a clear copy of valid establishment card."
    ),
]

private let standardRejectionTaxonomy: [RejectionTaxonomyItem] = [
    RejectionTaxonomyItem(
        code: "REGULATORY_NON_COMPLIANCE",
        titleAr: "مخالفة للاشتراطات التنظيمية",
        titleEn: "Regulatory non-compliance",
        descriptionAr: "الطلب أو النشاط المقدم لا يستوفي الشروط القانونية المنظمة لوزارة التجارة أو وزارة الصحة.",
        descriptionEn: "The application or activity does not meet statutory regulations of the relevant ministries."
    ),
    RejectionTaxonomyItem(
        code: "DOCUMENT_FRAUD_OR_ALTERATION",
        titleAr: "اشتباه في صحة المستندات",
        titleEn: "Document authenticity concern",
        descriptionAr: "تعذر التحقق من مصداقية الوثائق المرفقة أو ثبوت تعديل وتلاعب رقمي في الأختام.",
        descriptionEn: "Document authenticity could not be verified or digital tampering was detected."
    ),
    RejectionTaxonomyItem(
        code: "INELIGIBLE_BUSINESS_ACTIVITY",
        titleAr: "نشاط تجاري غير مؤهل",
        titleEn: "Ineligible business activity",
        descriptionAr: "طبيعة السلع أو الخدمات الممارسة خارج نطاق وأهلية منظومة بيور بيتس.",
        descriptionEn: "The business operations fall outside the eligibility scope of PurePets."
    ),
    RejectionTaxonomyItem(
        code: "PROHIBITED_GOODS_OR_SERVICES",
        titleAr: "سلع أو خدمات غير مصرح بها",
        titleEn: "Prohibited goods or services",
        descriptionAr: "يتضمن المتجر بيع حيوانات برية محظورة أو أدوية مقيدة دون ترخيص صيدلي معتمد.",
        descriptionEn: "Offering prohibited wildlife or restricted pharmaceuticals without proper licensing."
    ),
    RejectionTaxonomyItem(
        code: "IDENTITY_MISMATCH",
        titleAr: "عدم تطابق الهوية أو الملكية",
        titleEn: "Identity mismatch",
        descriptionAr: "بيانات مقدم الطلب لا تتوافق مع هوية المالك أو المفوض بالتوقيع في السجل الرسمي.",
        descriptionEn: "Applicant details do not match the registered owner or authorized signatory."
    ),
    RejectionTaxonomyItem(
        code: "POLICY_VIOLATION",
        titleAr: "مخالفة سياسات وقواعد المنصة",
        titleEn: "Platform policy violation",
        descriptionAr: "الطلب يخالف شروط الاستخدام أو سياسات النزاهة وحماية المستهلك المعتمدة.",
        descriptionEn: "The application violates PurePets terms of service or consumer protection standards."
    ),
    RejectionTaxonomyItem(
        code: "OTHER",
        titleAr: "أسباب أخرى",
        titleEn: "Other reasons",
        descriptionAr: "عدم استيفاء المعايير الفنية أو التشغيلية المطلوبة لاعتماد الشراكة.",
        descriptionEn: "Does not meet operational or technical standards required for partnership."
    ),
]

// MARK: - Provider Review Decision Modal Sheet

private struct ProviderReviewDecisionSheet: View {
    let application: PPProviderApplication
    @ObservedObject var viewModel: ProviderApplicationsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDecision: String = "approved"
    @State private var notesText: String = ""
    @State private var selectedRejectionCode: String = "REGULATORY_NON_COMPLIANCE"
    @State private var selectedTemplateIds: Set<String> = []
    @State private var structuredFindings: [[String: Any]] = []
    @State private var isSubmitting = false
    @State private var alertMessage: String? = nil
    
    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header Guidance
                        VStack(spacing: 6) {
                            Text(Language.get("Providers_Decision_Title", alter: "إصدار القرار الإداري"))
                                .font(AdminType.title2)
                                .foregroundStyle(AdminSurface.primaryText)
                            
                            Text(Language.get("Providers_Decision_Subtitle", alter: "اختر حالة الاعتماد وأدخل الملاحظات التي ستسجل في سجل التدقيق السحابي."))
                                .font(AdminType.caption1)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 10)
                        
                        // Decision Targets
                        VStack(spacing: 10) {
                            decisionOptionTile(
                                id: "approved",
                                title: Language.get("Providers_Approve_Option", alter: "اعتماد وتفعيل المزود"),
                                subtitle: Language.get("Providers_Approve_Desc", alter: "تفعيل المتجر في التطبيق ومنح صلاحيات مزود الخدمة."),
                                color: ProviderTheme.approved,
                                icon: "checkmark.seal.fill"
                            )
                            
                            decisionOptionTile(
                                id: "under_review",
                                title: Language.get("Providers_UnderReview_Option", alter: "تعيين قيد التدقيق"),
                                subtitle: Language.get("Providers_UnderReview_Desc", alter: "الإبقاء على الطلب قيد الفحص الإضافي والتواصل."),
                                color: ProviderTheme.pending,
                                icon: "hourglass.circle.fill"
                            )
                            
                            decisionOptionTile(
                                id: "changes_requested",
                                title: Language.get("Providers_ChangesRequested_Option", alter: "طلب تعديلات ومستندات"),
                                subtitle: Language.get("Providers_ChangesRequested_Desc", alter: "إرجاع الطلب للمزود مع تسجيل الملاحظات والنواقص المطلوبة."),
                                color: ProviderTheme.changesRequested,
                                icon: "exclamationmark.bubble.fill"
                            )
                            
                            decisionOptionTile(
                                id: "rejected",
                                title: Language.get("Providers_Reject_Option", alter: "رفض الطلب"),
                                subtitle: Language.get("Providers_Reject_Desc", alter: "رفض الانضمام مع إرسال سبب الرفض إلى المتقدم."),
                                color: ProviderTheme.rejected,
                                icon: "xmark.octagon.fill"
                            )
                        }
                        
                        // Contextual Templates / Taxonomy Bar
                        if selectedDecision == "changes_requested" {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(ProviderTheme.changesRequested)
                                    Text(Language.get("Providers_QuickFindings_Title", alter: "نماذج وملاحظات سريعة جاهزة للتعديل:"))
                                        .font(AdminType.caption2Bold)
                                        .foregroundStyle(AdminSurface.primaryText)
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(standardFindingTemplates) { template in
                                            let isSelected = selectedTemplateIds.contains(template.id)
                                            Button {
                                                applyFindingTemplate(template)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                                                        .font(.system(size: 11, weight: .bold))
                                                    Text(template.localizedTitle)
                                                        .font(AdminType.caption2Bold)
                                                }
                                                .foregroundStyle(isSelected ? .white : ProviderTheme.changesRequested)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    isSelected ? ProviderTheme.changesRequested : ProviderTheme.changesRequested.opacity(0.12),
                                                    in: Capsule()
                                                )
                                            }
                                            .buttonStyle(ProviderPressStyle())
                                        }
                                    }
                                }
                            }
                        } else if selectedDecision == "rejected" {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "shield.slash.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(ProviderTheme.rejected)
                                    Text(Language.get("Providers_RejectionTaxonomy_Title", alter: "التصنيف الرسمي لسبب الرفض:"))
                                        .font(AdminType.caption2Bold)
                                        .foregroundStyle(AdminSurface.primaryText)
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(standardRejectionTaxonomy) { item in
                                            let isSelected = selectedRejectionCode == item.code
                                            Button {
                                                applyRejectionTaxonomy(item)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    if isSelected {
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 10, weight: .bold))
                                                    }
                                                    Text(item.localizedTitle)
                                                        .font(AdminType.caption2Bold)
                                                }
                                                .foregroundStyle(isSelected ? .white : ProviderTheme.rejected)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    isSelected ? ProviderTheme.rejected : ProviderTheme.rejected.opacity(0.12),
                                                    in: Capsule()
                                                )
                                            }
                                            .buttonStyle(ProviderPressStyle())
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Notes Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Language.get("ReviewNotes", alter: "ملاحظات القرار / سبب الرفض"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                            
                            TextEditor(text: $notesText)
                                .font(AdminType.callout)
                                .frame(minHeight: 100)
                                .padding(8)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                                // Submit Button
                                )
                        }
                        
                        // Submit Button
                        Button {
                            submitDecision()
                        } label: {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 15, weight: .bold))
                                    Text(Language.get("ConfirmDecision", alter: "تأكيد وتسجيل القرار"))
                                        .font(AdminType.headline)
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(decisionButtonColor)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: decisionButtonColor.opacity(0.35), radius: 8, x: 0, y: 3)
                        }
                        .buttonStyle(ProviderPressStyle())
                        .disabled(isSubmitting)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(Language.get("Providers_Decision_NavTitle", alter: "القرار الإداري"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .alert(isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Alert(
                title: Text(Language.get("Attention", alter: "تنبيه")),
                message: Text(alertMessage ?? ""),
                dismissButton: .default(Text(Language.get("OK", alter: "حسناً")))
            )
        }
    }
    
    private func decisionOptionTile(id: String, title: String, subtitle: String, color: Color, icon: String) -> some View {
        let isSelected = selectedDecision == id
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedDecision = id
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(isSelected ? 0.20 : 0.10))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? color : AdminCommandInk.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? color.opacity(0.08) : AdminSurface.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? color.opacity(0.6) : Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: isSelected ? 1.5 : 0.75)
            )
        }
        .buttonStyle(ProviderPressStyle())
    }
    
    private var decisionButtonColor: Color {
        switch selectedDecision {
        case "approved": return ProviderTheme.approved
        case "rejected": return ProviderTheme.rejected
        case "changes_requested": return ProviderTheme.changesRequested
        default: return ProviderTheme.pending
        }
    }
    
    private func applyFindingTemplate(_ template: QuickFindingTemplate) {
        UISelectionFeedbackGenerator().selectionChanged()
        if selectedTemplateIds.contains(template.id) {
            selectedTemplateIds.remove(template.id)
            structuredFindings.removeAll { ($0["id"] as? String) == template.id }
            notesText = structuredFindings.compactMap { $0["description"] as? String }.joined(separator: "\n\n")
        } else {
            selectedTemplateIds.insert(template.id)
            let findingDict: [String: Any] = [
                "id": template.id,
                "targetType": template.targetType,
                "targetKey": template.targetKey,
                "severity": "blocking",
                "title": template.localizedTitle,
                "description": template.localizedDescription,
                "suggestedRemedy": template.localizedRemedy,
                "resolved": false,
                "createdAt": ISO8601DateFormatter().string(from: Date())
            ]
            structuredFindings.append(findingDict)
            let bullet = "\(template.localizedTitle):\n- \(template.localizedDescription)\n- \(template.localizedRemedy)"
            if notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notesText = bullet
            } else {
                notesText += "\n\n\(bullet)"
            }
        }
    }
    
    private func applyRejectionTaxonomy(_ item: RejectionTaxonomyItem) {
        UISelectionFeedbackGenerator().selectionChanged()
        selectedRejectionCode = item.code
        let textToSet = "\(item.localizedTitle): \(item.localizedDescription)"
        if notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || standardRejectionTaxonomy.contains(where: { notesText.contains($0.localizedTitle) }) {
            notesText = textToSet
        }
    }
    
    private func submitDecision() {
        let trimmed = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedDecision == "rejected" && trimmed.isEmpty {
            alertMessage = Language.get("Providers_RejectReasonRequired", alter: "يرجى كتابة سبب الرفض لتوضيحه لمقدم الطلب.")
            return
        }
        if selectedDecision == "changes_requested" && trimmed.isEmpty {
            alertMessage = Language.get("Providers_ChangesReasonRequired", alter: "يرجى كتابة الملاحظات والتعديلات المطلوبة لمقدم الطلب.")
            return
        }
        
        isSubmitting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        let currentVersion = NSNumber(value: application.version > 0 ? application.version : 1)
        viewModel.submitReview(
            appID: application.applicationID,
            decision: selectedDecision,
            notes: trimmed,
            rejectionCode: selectedDecision == "rejected" ? selectedRejectionCode : nil,
            reviewFindings: selectedDecision == "changes_requested" && !structuredFindings.isEmpty ? structuredFindings : nil,
            expectedVersion: currentVersion
        ) { success in
            Task { @MainActor in
                isSubmitting = false
                if success {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Document Inspection & Verification Sheet

private struct PPDocumentInspectionSheet: View {
    let application: PPProviderApplication
    let documentItem: PPDocumentInspectionItem
    @ObservedObject var viewModel: ProviderApplicationsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentZoom: CGFloat = 1.0
    @State private var rotationAngle: Double = 0.0
    @State private var activeDecisionMode: DecisionMode? = nil
    @State private var findingText: String = ""
    @State private var expiryDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    
    private enum DecisionMode {
        case verify
        case requestChanges
        case reject
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Document Toolbar: Zoom, Rotate, External View
                    inspectionToolbar
                    
                    // Main Document Canvas
                    ScrollView([.horizontal, .vertical]) {
                        documentVisualCanvas
                    }
                    
                    // Status / Stamp Callout if verified, changes_required, or rejected
                    documentMetadataCallout
                    
                    // Inline Decision Dock
                    decisionActionDock
                }
            }
            .navigationTitle(documentItem.localizedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !documentItem.fileUrl.isEmpty, let url = URL(string: documentItem.fileUrl) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AdminSurface.primary)
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .alert(isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Alert(
                title: Text(Language.get("Notice", alter: "تنبيه")),
                message: Text(errorMessage ?? ""),
                dismissButton: .default(Text(Language.get("OK", alter: "حسنًا")))
            )
        }
    }
    
    private var inspectionToolbar: some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3)) {
                    rotationAngle += 90
                    if rotationAngle >= 360 { rotationAngle = 0 }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rotate.right.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(Language.get("Rotate", alter: "تدوير"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(AdminSurface.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
            }
            .buttonStyle(ProviderPressStyle())
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3)) {
                    currentZoom = (currentZoom == 1.0) ? 2.0 : 1.0
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: currentZoom > 1.0 ? "minus.magnifyingglass" : "plus.magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                    Text(currentZoom > 1.0 ? Language.get("ResetZoom", alter: "إعادة الضبط") : Language.get("Zoom", alter: "تكبير"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(AdminSurface.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
            }
            .buttonStyle(ProviderPressStyle())
            
            Spacer()
            
            Text(documentItem.fileName)
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AdminSurface.surface)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
    
    private var documentVisualCanvas: some View {
        ZStack {
            if documentItem.fileUrl.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.questionmark.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AdminCommandInk.tertiary)
                    Text(Language.get("Providers_Doc_NoUrl", alter: "رابط المستند غير متوفر في السجل"))
                        .font(AdminType.callout)
                        .foregroundStyle(AdminCommandInk.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            } else if isImageURL(documentItem.fileUrl) {
                AdminRemoteImage(
                    urlString: documentItem.fileUrl,
                    contentMode: .fit
                ) {
                    documentFallbackPreview
                }
                .scaleEffect(currentZoom)
                .rotationEffect(.degrees(rotationAngle))
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in currentZoom = max(0.8, min(val, 4.0)) }
                )
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                documentFallbackPreview
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .background(AdminSurface.background)
    }
    
    private var documentFallbackPreview: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AdminSurface.surface)
                    .frame(width: 140, height: 180)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
                VStack(spacing: 8) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AdminSurface.primary)
                    Text("PDF / DOC")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            .scaleEffect(currentZoom)
            .rotationEffect(.degrees(rotationAngle))
            
            if let url = URL(string: documentItem.fileUrl) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("Providers_Doc_OpenExternal", alter: "فتح الوثيقة في المستعرض الكامل"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AdminSurface.primary, in: Capsule())
                }
            }
        }
        .padding(32)
    }
    
    @ViewBuilder
    private var documentMetadataCallout: some View {
        if documentItem.status.lowercased() == "verified" {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(ProviderTheme.approved)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Providers_Doc_VerifiedBanner", alter: "مستند موثق ومعتمد رسميًا"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(ProviderTheme.approved)
                    if let stamp = documentItem.checksum, !stamp.isEmpty {
                        Text("SHA-256: \(stamp)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(AdminCommandInk.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(ProviderTheme.approved.opacity(0.10))
        } else if documentItem.status.lowercased() == "changes_required" {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ProviderTheme.changesRequested)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Providers_Doc_ChangesBanner", alter: "مطلوب إجراء تعديل من المزود"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(ProviderTheme.changesRequested)
                    if let f = documentItem.reviewFinding, !f.isEmpty {
                        Text(f)
                            .font(AdminType.caption1)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(ProviderTheme.changesRequested.opacity(0.10))
        } else if documentItem.status.lowercased() == "rejected" {
            HStack(spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ProviderTheme.rejected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Providers_Doc_RejectedBanner", alter: "تم رفض هذا المستند رسميًا"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(ProviderTheme.rejected)
                    if let f = documentItem.reviewFinding, !f.isEmpty {
                        Text(f)
                            .font(AdminType.caption1)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(ProviderTheme.rejected.opacity(0.10))
        }
    }
    
    private var decisionActionDock: some View {
        VStack(spacing: 12) {
            Divider()
            
            if let mode = activeDecisionMode {
                // Interactive Form according to mode
                VStack(alignment: .leading, spacing: 10) {
                    switch mode {
                    case .verify:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Language.get("Providers_Doc_ExpiryTitle", alter: "تاريخ انتهاء صلاحية الترخيص (اختياري)"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                            DatePicker(
                                "",
                                selection: $expiryDate,
                                in: Date()...,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        }
                    case .requestChanges:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Language.get("Providers_Doc_FindingRequired", alter: "سبب طلب التعديل (مطلوب):"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(quickDocFindingChips, id: \.self) { chip in
                                        Button {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            findingText = chip
                                        } label: {
                                            Text(chip)
                                                .font(AdminType.caption2)
                                                .foregroundStyle(findingText == chip ? .white : ProviderTheme.changesRequested)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    findingText == chip ? ProviderTheme.changesRequested : ProviderTheme.changesRequested.opacity(0.12),
                                                    in: Capsule()
                                                )
                                        }
                                        .buttonStyle(ProviderPressStyle())
                                    }
                                }
                            }
                            
                            TextField(
                                Language.get("Providers_Doc_FindingPlaceholder", alter: "مثال: الصورة غير واضحة أو الختم منتهي..."),
                                text: $findingText
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    case .reject:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Language.get("Providers_Doc_RejectionRequired", alter: "سبب رفض المستند (مطلوب):"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(quickDocRejectionChips, id: \.self) { chip in
                                        Button {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            findingText = chip
                                        } label: {
                                            Text(chip)
                                                .font(AdminType.caption2)
                                                .foregroundStyle(findingText == chip ? .white : ProviderTheme.rejected)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    findingText == chip ? ProviderTheme.rejected : ProviderTheme.rejected.opacity(0.12),
                                                    in: Capsule()
                                                )
                                        }
                                        .buttonStyle(ProviderPressStyle())
                                    }
                                }
                            }
                            
                            TextField(
                                Language.get("Providers_Doc_RejectionPlaceholder", alter: "مثال: المستند مزور أو لا يطابق السجلات الرسمية..."),
                                text: $findingText
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    HStack(spacing: 10) {
                        Button {
                            withAnimation { activeDecisionMode = nil }
                        } label: {
                            Text(Language.get("Cancel", alter: "إلغاء"))
                                .font(AdminType.captionBold)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(AdminSurface.control, in: Capsule())
                        }
                        
                        Spacer()
                        
                        Button {
                            submitDecision(for: mode)
                        } label: {
                            HStack(spacing: 6) {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(Language.get("Confirm", alter: "تأكيد وتنفيذ القرار"))
                                        .font(AdminType.captionBold)
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(decisionColor(for: mode), in: Capsule())
                        }
                        .disabled(isSubmitting)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            } else {
                // 3 Action Buttons
                HStack(spacing: 10) {
                    // Verify
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation { activeDecisionMode = .verify }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Verify", alter: "اعتماد وتوثيق"))
                                .font(AdminType.captionBold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(ProviderTheme.approved, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(ProviderPressStyle())
                    
                    // Request Changes
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation { activeDecisionMode = .requestChanges }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("RequestChanges", alter: "طلب تعديل"))
                                .font(AdminType.captionBold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(ProviderTheme.changesRequested, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(ProviderPressStyle())
                    
                    // Reject
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation { activeDecisionMode = .reject }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Reject", alter: "رفض"))
                                .font(AdminType.captionBold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(ProviderTheme.rejected, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(ProviderPressStyle())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(AdminSurface.surface)
    }
    
    private func decisionColor(for mode: DecisionMode) -> Color {
        switch mode {
        case .verify: return ProviderTheme.approved
        case .requestChanges: return ProviderTheme.changesRequested
        case .reject: return ProviderTheme.rejected
        }
    }
    
    private func isImageURL(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return lower.contains(".png") || lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".webp")
    }
    
    private var quickDocFindingChips: [String] {
        [
            Language.get("Providers_DocChip_Blurry", alter: "الصورة غير واضحة أو مطموسة الأختام"),
            Language.get("Providers_DocChip_Expired", alter: "صلاحية الترخيص منتهية ويلزم تجديدها"),
            Language.get("Providers_DocChip_Mismatch", alter: "الاسم أو رقم السجل لا يطابق بيانات النموذج"),
            Language.get("Providers_DocChip_Incomplete", alter: "الملف ناقص صفحات أو توقيعات رسمية")
        ]
    }
    
    private var quickDocRejectionChips: [String] {
        [
            Language.get("Providers_DocRejectChip_Tampered", alter: "اشتباه في صحة أو تزوير المستند والأختام"),
            Language.get("Providers_DocRejectChip_Ineligible", alter: "ترخيص غير صالح أو غير معتمد لنشاط المنصة"),
            Language.get("Providers_DocRejectChip_IdentityMismatch", alter: "عدم تطابق هوية المالك أو المفوض بالتوقيع"),
            Language.get("Providers_DocRejectChip_InvalidAuthority", alter: "جهة إصدار الترخيص غير معترف بها رسميًا")
        ]
    }
    
    private func submitDecision(for mode: DecisionMode) {
        let decision: String
        var finding: String? = nil
        var expiryISO: String? = nil
        
        switch mode {
        case .verify:
            decision = "verified"
            let formatter = ISO8601DateFormatter()
            expiryISO = formatter.string(from: expiryDate)
        case .requestChanges:
            decision = "changes_required"
            let cleanFinding = findingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanFinding.isEmpty {
                errorMessage = Language.get("Providers_Doc_FindingError", alter: "يجب كتابة سبب أو ملاحظة طلب التعديل للمزود.")
                return
            }
            finding = cleanFinding
        case .reject:
            decision = "rejected"
            let cleanFinding = findingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanFinding.isEmpty {
                errorMessage = Language.get("Providers_Doc_RejectError", alter: "يجب كتابة سبب رفض المستند للمزود.")
                return
            }
            finding = cleanFinding
        }
        
        isSubmitting = true
        let appId = application.applicationID.isEmpty ? application.userId : application.applicationID
        PPProviderService.shared().reviewApplicationDocument(
            appId,
            documentType: documentItem.type,
            decision: decision,
            finding: finding,
            expiryDate: expiryISO
        ) { result, error in
            DispatchQueue.main.async {
                isSubmitting = false
                if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    viewModel.fetch()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Press Style

private struct ProviderPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Hosting Controller Bridges

@objc public final class PPProviderApplicationsHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all
        
        let host = UIHostingController(rootView: AdminProvidersView { [weak self] in
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
        }.ignoresSafeArea())
        host.view.backgroundColor = .clear
        host.extendedLayoutIncludesOpaqueBars = true
        host.edgesForExtendedLayout = .all
        
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}
