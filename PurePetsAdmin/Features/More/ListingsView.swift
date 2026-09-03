//
//  ListingsView.swift
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed.
//  Updated for Category-Defining Listings & Moderation Command Center.
//

import SwiftUI

struct AdminListingsView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        PPListingsCommandCenterScreen(
            viewModel: PPListingsCommandCenterViewModel(
                onDismiss: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
            )
        )
    }
}