//
//  ProvidersView.swift
//  PurePetsAdmin
//

import SwiftUI

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
            AdminLegacyViewControllerWrapper { PPProviderApplicationsViewController() }
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