//
//  ListingsView.swift
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed.
//  Updated for Category-Defining Listings & Moderation Command Center.
//

import SwiftUI

struct AdminListingsView: View {
    var onDismiss: (@Sendable () -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    init(onDismiss: (@Sendable () -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        let dismissAction = dismiss
        let customDismiss = onDismiss
        NavigationView {
            PPListingsCommandCenterScreen(
                viewModel: PPListingsCommandCenterViewModel(
                    onDismiss: {
                        Task { @MainActor in
                            if let customDismiss {
                                customDismiss()
                            } else {
                                dismissAction()
                            }
                        }
                    }
                )
            )
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}