//
//  NotificationSettingsView.swift
//  PurePetsAdmin
//

import SwiftUI

struct AdminNotificationSettingsView: View {
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

                AdminLegacyViewControllerWrapper { NotificationSettingsViewController() }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Sovereign Navigation Bar

    private var dossierHeaderView: some View {
        AdminSovereignNavigationBar(
            title: Language.get("NotificationSettings_Title", alter: "إعدادات وقنوات الإشعارات"),
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