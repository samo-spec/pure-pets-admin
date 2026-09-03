//
//  SettingsView.swift
//  PurePetsAdmin
//

import SwiftUI

struct AdminSettingsView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView

                AdminLegacyViewControllerWrapper { PPSettingsViewController() }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Sovereign Navigation Bar

    private var dossierHeaderView: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Settings_Title", alter: "إعدادات التطبيق والنظام"),
            subtitle: Language.get("CommandCenter_Tab_More", alter: "المزيد"),
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

private struct AdminLegacyViewControllerWrapper: UIViewControllerRepresentable {
    let factory: () -> UIViewController
    func makeUIViewController(context: Context) -> UIViewController { factory() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}