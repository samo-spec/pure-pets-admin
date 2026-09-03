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

            AdminLegacyViewControllerWrapper {
                let vc = PPSettingsViewController()
                vc.onDismissBlock = {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
                return vc
            }
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

private struct AdminLegacyViewControllerWrapper: UIViewControllerRepresentable {
    let factory: () -> UIViewController
    func makeUIViewController(context: Context) -> UIViewController { factory() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}