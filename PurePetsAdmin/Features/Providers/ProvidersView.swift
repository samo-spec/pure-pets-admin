//
//  ProvidersView.swift
//  PurePetsAdmin
//

import SwiftUI

extension PPProviderApplication: @unchecked Sendable {}

// MARK: - Providers Hub (Tabbed: Applications · Plans · Features · Accounting)

struct AdminProvidersView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ProviderTab = .applications

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
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

    // MARK: - Dossier Header (PPAccessoryEditorView Pattern)

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack {
                Button(action: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(Language.get("Back", alter: "رجوع"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .frame(minHeight: 44)
                }

                Spacer()
            }

            Text(Language.get("CommandCenter_Operations_Workspace", alter: "مساحة العمليات") + " / " + Language.get("Providers_Title", alter: "المزودين"))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(Language.get("Providers_Title", alter: "إدارة مقدمي الخدمات"))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
    }

    private var providerTabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProviderTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    Text(tab.localizedTitle)
                        .font(AdminType.captionBold)
                        .foregroundColor(selectedTab == tab ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            selectedTab == tab
                                ? AdminSurface.primary.opacity(0.12)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityLabel(tab.localizedTitle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AdminSurface.surface)
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
            AdminLegacyViewControllerWrapper { PPProviderAccountingViewController() }
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
        case .applications: return Language.get("Providers_Applications_Title", alter: nil)
        case .plans: return Language.get("Providers_Plans_Title", alter: nil)
        case .features: return Language.get("Providers_Features_Title", alter: nil)
        case .accounting: return Language.get("Providers_Accounting_Title", alter: nil)
        }
    }
}

// MARK: - Reusable Legacy VC Wrapper

private struct AdminLegacyViewControllerWrapper: UIViewControllerRepresentable {
    let factory: () -> UIViewController

    func makeUIViewController(context: Context) -> UIViewController { factory() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
} 

@MainActor
final class ProviderApplicationsViewModel: ObservableObject {
    @Published var applications: [PPProviderApplication] = []
    @Published var searchText: String = ""
    @Published var selectedFilter: AppFilter = .all
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    enum AppFilter: String, CaseIterable {
        case all = "الكل"
        case pending = "معلق"
        case approved = "مقبول"
        case rejected = "مرفوض"
    }
    
    var filteredApps: [PPProviderApplication] {
        let searched = searchText.isEmpty ? applications : applications.filter {
            let name = ($0.form["businessName"] as? String) ?? ($0.form["fullName"] as? String) ?? $0.userId
            return name.localizedCaseInsensitiveContains(searchText) || $0.userId.localizedCaseInsensitiveContains(searchText)
        }
        
        switch selectedFilter {
        case .all: return searched
        case .pending: return searched.filter { $0.status == "pending" || $0.status == "under_review" }
        case .approved: return searched.filter { $0.status == "approved" }
        case .rejected: return searched.filter { $0.status == "rejected" }
        }
    }
    
    var pendingCount: Int { applications.filter { $0.status == "pending" || $0.status == "under_review" }.count }
    var approvedCount: Int { applications.filter { $0.status == "approved" }.count }
    var rejectedCount: Int { applications.filter { $0.status == "rejected" }.count }
    
    func fetch() {
        isLoading = true
        error = nil
        PPProviderService.shared().fetchApplications { [weak self] apps, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if let error = error {
                    self.error = error
                } else {
                    self.applications = apps ?? []
                }
            }
        }
    }
}

struct AdminProviderApplicationsView: View {
    @StateObject private var viewModel = ProviderApplicationsViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                
                VStack(spacing: 16) {
                    AdminSearchField(text: $viewModel.searchText, placeholder: Language.get("Providers_Search", alter: "ابحث بالاسم أو البريد الإلكتروني أو الجوال أو المعرّف"))
                    
                    filterPicker
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else if viewModel.filteredApps.isEmpty {
                        AdminEmptyStateView(symbol: "doc.text.magnifyingglass", title: Language.get("Empty", alter: "لا يوجد طلبات"), subtitle: nil)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.filteredApps, id: \.applicationID) { app in
                                applicationRow(app)
                                Divider().background(AdminSurface.hairline)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .onAppear {
            viewModel.fetch()
        }
    }
    
    private var headerCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(Language.get("Providers_Applications_HeroTitle", alter: "طلبات المزودين"))
                    .font(AdminType.title)
                    .foregroundColor(AdminSurface.primaryText)
                
                Text(Language.get("Providers_Applications_HeroSubtitle", alter: "راجع طلبات الانضمام، تحقق من الأهلية، واجعل تفعيل المزود معتمداً من الخادم."))
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("\(viewModel.pendingCount) ظاهر. 0 بانتظار القرار")
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primary)
                
                HStack(spacing: 40) {
                    metricItem(count: viewModel.pendingCount, title: "معلق", color: .orange)
                    metricItem(count: viewModel.approvedCount, title: "مقبول", color: .green)
                    metricItem(count: viewModel.rejectedCount, title: "مرفوض", color: .red)
                }
                .padding(.top, 8)
            }
            Spacer()
            
            RoundedRectangle(cornerRadius: 2)
                .fill(AdminSurface.primary)
                .frame(width: 4)
                .padding(.vertical, 8)
        }
        .padding(24)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    
    private func metricItem(count: Int, title: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(AdminType.title3.weight(.bold))
                .foregroundColor(color)
            Text(title)
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
        }
    }
    
    private var filterPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProviderApplicationsViewModel.AppFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation { viewModel.selectedFilter = filter }
                } label: {
                    Text(filter.rawValue)
                        .font(AdminType.captionBold)
                        .foregroundColor(viewModel.selectedFilter == filter ? .white : AdminSurface.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            viewModel.selectedFilter == filter ? AdminSurface.primary : Color.clear
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .padding(4)
        .background(AdminSurface.control, in: Capsule())
    }
    
    private func applicationRow(_ app: PPProviderApplication) -> some View {
        let name = (app.form["businessName"] as? String) ?? (app.form["fullName"] as? String) ?? app.userId
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd · h:mm a"
        let dateString = app.createdAt != nil ? formatter.string(from: app.createdAt!) : ""
        let status = statusString(app.status)
        let statusColor = statusColor(app.status)
        
        return HStack(spacing: 16) {
            Circle()
                .fill(statusColor.opacity(0.1))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundColor(statusColor)
                        .font(.system(size: 20))
                )
                
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                Text("السوق")
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                Text("\(dateString) \n\(app.applicationID)")
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(nil)
            }
            
            Spacer()
            
            Text(status)
                .font(AdminType.captionBold)
                .foregroundColor(statusColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                
            Image(systemName: "chevron.forward")
                .foregroundColor(AdminSurface.secondaryText)
                .font(.system(size: 14, weight: .bold))
                .flipsForRightToLeftLayoutDirection(true)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            // Push legacy detail VC or similar if needed.
        }
    }
    
    private func statusString(_ status: String) -> String {
        switch status {
        case "pending", "under_review": return "معلق"
        case "approved": return "مقبول"
        case "rejected": return "مرفوض"
        default: return status
        }
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "pending", "under_review": return .orange
        case "approved": return .green
        case "rejected": return .red
        default: return AdminSurface.secondaryText
        }
    }
}
