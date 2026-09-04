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
    static let brand = AdminSurface.primary
    
    static func tone(for status: String) -> (color: Color, text: String, symbol: String) {
        switch status.lowercased() {
        case "approved":
            return (approved, Language.get("Providers_Approved", alter: "مقبول ومفعّل"), "checkmark.seal.fill")
        case "rejected":
            return (rejected, Language.get("Providers_Rejected", alter: "مرفوض"), "xmark.octagon.fill")
        case "under_review":
            return (pending, Language.get("Providers_UnderReview", alter: "قيد المراجعة"), "hourglass.circle.fill")
        default: // pending
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

// MARK: - Main Providers Hub (Tabbed: Applications · Plans · Features · Accounting)

public struct AdminProvidersView: View {
    public var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ProviderTab = .applications

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView
                providerTabPicker
                providerTabContent
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Sovereign Header

    private var dossierHeaderView: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Providers_Management_Title", alter: "إدارة منظومة المزودين"),
            subtitle: Language.get("CommandCenter_Operations_Workspace", alter: "مساحة العمليات"),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        )
    }

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
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        Text(tab.localizedTitle)
                            .font(isSelected ? AdminType.captionBold : AdminType.caption1)
                    }
                    .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 40)
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
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var providerTabContent: some View {
        switch selectedTab {
        case .applications:
            AdminProviderApplicationsView()
        case .plans:
            AdminLegacyViewControllerWrapper { PPProviderPlansViewController() }
        case .features:
            AdminLegacyViewControllerWrapper { PPProviderFeatureAccessViewController() }
        case .accounting:
            AdminProviderAccountingView(isEmbeddedInTab: true)
        }
    }
}

private enum ProviderTab: String, CaseIterable {
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
    
    enum AppFilter: String, CaseIterable {
        case all = "all"
        case pending = "pending"
        case approved = "approved"
        case rejected = "rejected"
        
        var localizedTitle: String {
            switch self {
            case .all: return Language.get("All", alter: "الكل")
            case .pending: return Language.get("Providers_Pending", alter: "معلق")
            case .approved: return Language.get("Providers_Approved", alter: "مقبول")
            case .rejected: return Language.get("Providers_Rejected", alter: "مرفوض")
            }
        }
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2.fill"
            case .pending: return "clock.fill"
            case .approved: return "checkmark.seal.fill"
            case .rejected: return "xmark.octagon.fill"
            }
        }
    }
    
    var filteredApps: [PPProviderApplication] {
        let searched = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? applications : applications.filter { app in
            let q = searchText.lowercased()
            let name = (app.form["businessName"] as? String)
                ?? (app.form["fullName"] as? String)
                ?? (app.form["companyName"] as? String)
                ?? (app.form["legalName"] as? String)
                ?? (app.userSummary["displayName"] as? String)
                ?? app.userId
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
        
        switch selectedFilter {
        case .all:
            return searched
        case .pending:
            return searched.filter { $0.status.lowercased() == "pending" || $0.status.lowercased() == "under_review" || $0.status.isEmpty }
        case .approved:
            return searched.filter { $0.status.lowercased() == "approved" }
        case .rejected:
            return searched.filter { $0.status.lowercased() == "rejected" }
        }
    }
    
    var pendingCount: Int {
        applications.filter { $0.status.lowercased() == "pending" || $0.status.lowercased() == "under_review" || $0.status.isEmpty }.count
    }
    
    var approvedCount: Int {
        applications.filter { $0.status.lowercased() == "approved" }.count
    }
    
    var rejectedCount: Int {
        applications.filter { $0.status.lowercased() == "rejected" }.count
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
                }
            }
        }
    }
    
    func submitReview(appID: String, decision: String, notes: String, completion: @escaping @Sendable (Bool) -> Void) {
        PPProviderService.shared().reviewApplication(appID, status: decision, notes: notes) { [weak self] result, error in
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
}

// MARK: - Reimagined Provider Applications Queue Screen

public struct AdminProviderApplicationsView: View {
    @StateObject private var viewModel = ProviderApplicationsViewModel()
    @State private var spinAngle: Double = 0
    
    public init() {}
    
    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()
            
            ScrollView {
                LazyVStack(spacing: 16) {
                    apexHealthHero
                    searchAndFilterDeck
                    applicationsListSection
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, 10)
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
        .sheet(item: $viewModel.selectedDetailApp) { app in
            AdminProviderApplicationDetailView(application: app, viewModel: viewModel)
        }
        .sheet(item: $viewModel.reviewTargetApp) { app in
            ProviderReviewDecisionSheet(application: app, viewModel: viewModel)
        }
        .onAppear {
            viewModel.fetch()
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
                        .font(AdminType.title2)
                        .foregroundColor(AdminSurface.primaryText)
                    
                    Text(Language.get("Providers_Applications_HeroSubtitle", alter: "فحص الأهلية التجارية، تدقيق التراخيص والمستندات، واعتماد تفعيل المتاجر والعيادات."))
                        .font(AdminType.caption1)
                        .foregroundColor(AdminCommandInk.secondary)
                        .lineLimit(2)
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
            
            // 3-Metric Horizontal Deck
            HStack(spacing: 10) {
                metricTile(
                    title: Language.get("Providers_Pending", alter: "بانتظار القرار"),
                    count: viewModel.pendingCount,
                    color: ProviderTheme.pending,
                    icon: "hourglass"
                )
                metricTile(
                    title: Language.get("Providers_Approved", alter: "مقبول ومفعّل"),
                    count: viewModel.approvedCount,
                    color: ProviderTheme.approved,
                    icon: "checkmark.seal.fill"
                )
                metricTile(
                    title: Language.get("Providers_Rejected", alter: "مرفوض"),
                    count: viewModel.rejectedCount,
                    color: ProviderTheme.rejected,
                    icon: "xmark.octagon.fill"
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
    
    private func metricTile(title: String, count: Int, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 0.75)
        )
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
            // Liquid Search Field
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
            
            // Filter Pills
            HStack(spacing: 6) {
                ForEach(ProviderApplicationsViewModel.AppFilter.allCases, id: \.self) { filter in
                    let isSelected = viewModel.selectedFilter == filter
                    let count: Int = {
                        switch filter {
                        case .all: return viewModel.applications.count
                        case .pending: return viewModel.pendingCount
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Applications List
    
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
                    PPProviderApplicationCard(application: app) {
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
}

// MARK: - Flagship Provider Application Card

private struct PPProviderApplicationCard: View {
    let application: PPProviderApplication
    let onTap: () -> Void
    let onReviewAction: () -> Void
    
    var body: some View {
        let statusTone = ProviderTheme.tone(for: application.status)
        let typeInfo = ProviderTheme.localizedType(application.providerType)
        let name = resolvedName
        let dateText = resolvedDateText
        let isPending = application.status.lowercased() == "pending" || application.status.lowercased() == "under_review" || application.status.isEmpty
        
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Top Header Row: Monogram + Name + Type + Status Pill
                HStack(alignment: .center, spacing: 12) {
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
                            .font(AdminType.headline)
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
                    .fill(AdminSurface.surface)
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
            )
        }
        .buttonStyle(ProviderPressStyle())
        .accessibilityElement(children: .combine)
    }
    
    private var resolvedName: String {
        (application.form["businessName"] as? String)
            ?? (application.form["fullName"] as? String)
            ?? (application.form["companyName"] as? String)
            ?? (application.form["legalName"] as? String)
            ?? (application.userSummary["displayName"] as? String)
            ?? application.userId
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

// MARK: - Reimagined Provider Application Detail / Dossier View

public struct AdminProviderApplicationDetailView: View {
    let application: PPProviderApplication
    @ObservedObject var viewModel: ProviderApplicationsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingReviewSheet = false
    @State private var copiedField: String? = nil
    
    init(application: PPProviderApplication, viewModel: ProviderApplicationsViewModel) {
        self.application = application
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                dossierHeaderNav
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .background(AdminSurface.background)

                ScrollView {
                    LazyVStack(spacing: 16) {
                        heroDossierCard
                        identifiersMatrix
                        applicantAndBusinessSection
                        commercialSection
                        planSection
                        reviewHistorySection
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 10)
                    .padding(.bottom, 90)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isPending {
                decisionDock
            }
        }
        .sheet(isPresented: $showingReviewSheet) {
            ProviderReviewDecisionSheet(application: application, viewModel: viewModel)
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
    
    // MARK: - Sovereign Dossier Navigation Header
    
    private var dossierHeaderNav: some View {
        AdminSovereignNavigationBar(
            title: resolvedName,
            subtitle: Language.get("Providers_Dossier_Breadcrumb", alter: "ملف طلب المزود"),
            onBack: { dismiss() }
        )
    }
    
    // MARK: - Hero Dossier Card
    
    private var heroDossierCard: some View {
        let statusTone = ProviderTheme.tone(for: application.status)
        let typeInfo = ProviderTheme.localizedType(application.providerType)
        let name = resolvedName
        
        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(statusTone.color.opacity(0.14))
                        .frame(width: 58, height: 58)
                    Image(systemName: typeInfo.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(statusTone.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
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
                        .font(.system(size: 22, weight: .bold, design: .rounded))
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
            .padding(.vertical, 10)
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
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                        Text("\(String(format: "%.0f", price)) \(currency)")
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
        return s == "pending" || s == "under_review" || s.isEmpty
    }
    
    private var resolvedName: String {
        (application.form["businessName"] as? String)
            ?? (application.form["fullName"] as? String)
            ?? (application.form["companyName"] as? String)
            ?? (application.form["legalName"] as? String)
            ?? (application.userSummary["displayName"] as? String)
            ?? application.userId
    }
    
    private var nextMoveIcon: String {
        switch application.status.lowercased() {
        case "approved": return "checkmark.circle.fill"
        case "rejected": return "exclamationmark.octagon.fill"
        default: return "clock.arrow.circlepath"
        }
    }
    
    private var nextMoveText: String {
        switch application.status.lowercased() {
        case "approved":
            return Language.get("Providers_NextMove_Approved", alter: "تمت الموافقة وتفعيل حساب المزود بنجاح. لا يلزم أي إجراء مراجعة آخر.")
        case "rejected":
            return Language.get("Providers_NextMove_Rejected", alter: "تم رفض الطلب لعدم استيفاء الشروط المطلوبة. يمكن للمزود تقديم طلب جديد.")
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

// MARK: - Provider Review Decision Modal Sheet

private struct ProviderReviewDecisionSheet: View {
    let application: PPProviderApplication
    @ObservedObject var viewModel: ProviderApplicationsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDecision: String = "approved"
    @State private var notesText: String = ""
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
                                id: "rejected",
                                title: Language.get("Providers_Reject_Option", alter: "رفض الطلب"),
                                subtitle: Language.get("Providers_Reject_Desc", alter: "رفض الانضمام مع إرسال سبب الرفض إلى المتقدم."),
                                color: ProviderTheme.rejected,
                                icon: "xmark.octagon.fill"
                            )
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
        default: return ProviderTheme.pending
        }
    }
    
    private func submitDecision() {
        if selectedDecision == "rejected" && notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            alertMessage = Language.get("Providers_RejectReasonRequired", alter: "يرجى كتابة سبب الرفض لتوضيحه لمقدم الطلب.")
            return
        }
        
        isSubmitting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        viewModel.submitReview(
            appID: application.applicationID,
            decision: selectedDecision,
            notes: notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { success in
            isSubmitting = false
            if success {
                dismiss()
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
        
        let host = UIHostingController(rootView: AdminProvidersView { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        })
        
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
