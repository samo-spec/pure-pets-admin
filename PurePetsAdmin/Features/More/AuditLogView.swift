//
//  AuditLogView.swift
//  PurePetsAdmin
//
//  Created from absolute first principles.
//  Category-defining Sovereign Audit & Forensic Command Center SwiftUI Bridge.
//

import SwiftUI

struct AdminAuditLogView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        AdminAuditLogViewControllerWrapper(onDismiss: {
            if let onDismiss {
                onDismiss()
            } else {
                dismiss()
            }
        })
        .ignoresSafeArea()
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

private struct AdminAuditLogViewControllerWrapper: UIViewControllerRepresentable {
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        return PPAuditLogViewController(onDismiss: onDismiss)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}