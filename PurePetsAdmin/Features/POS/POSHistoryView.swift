//
//  POSHistoryView.swift
//  PurePetsAdmin
//
//  POS receipts list with date, total, items count, payment method badge.
//

import SwiftUI

// MARK: - Sendable

extension PPPOSReceipt: @unchecked Sendable {}

// MARK: - POS History ViewModel

@MainActor
final class POSHistoryViewModel: ObservableObject {
    @Published private(set) var receipts: [PPPOSReceipt] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private var loadGeneration = UUID()

    func load(branchID: String?) {
        let branchID = branchID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let generation = UUID()
        loadGeneration = generation
        receipts = []
        isLoading = true
        errorMessage = nil
        guard !branchID.isEmpty else {
            isLoading = false
            errorMessage = Language.get("BranchContext_SelectBranch_Prompt", alter: "يرجى تحديد الفرع")
            return
        }
        PPPOSService.shared().fetchPOSHistory(branchID: branchID) { [weak self] receipts, error in
            Task { @MainActor in
                guard let self, self.loadGeneration == generation,
                      BranchContextStore.shared.activeBranch?.branchID == branchID else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.receipts = receipts ?? []
            }
        }
    }

    var totalRevenue: Double {
        receipts.reduce(0) { $0 + $1.total }
    }

    var totalTransactions: Int { receipts.count }

    var totalItemsSold: Int {
        receipts.reduce(0) { $0 + $1.items.count }
    }
}

// MARK: - POS History View

struct AdminPOSHistoryView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var branchStore = BranchContextStore.shared
    @StateObject private var viewModel = POSHistoryViewModel()

    init(session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.session = session
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView
                summaryHeader
                Divider().background(AdminSurface.hairline)

                if viewModel.isLoading {
                    Spacer()
                    ProgressView().tint(AdminSurface.primary).scaleEffect(1.2)
                    Spacer()
                } else if viewModel.receipts.isEmpty {
                    Spacer()
                    AdminEmptyStateView(
                        symbol: "receipt.fill",
                        title: Language.get("POS_History_Empty", alter: "لا توجد سجلات بيع"),
                        subtitle: Language.get("POS_History_Empty_Sub", alter: "ستظهر المعاملات المكتملة هنا")
                    )
                    Spacer()
                } else if let error = viewModel.errorMessage {
                    Spacer()
                    AdminErrorBanner(message: error, retry: { viewModel.load(branchID: branchStore.activeBranch?.branchID) })
                        .padding(.horizontal, AdminSpacing.screenMargin)
                    Spacer()
                } else {
                    receiptsList
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear { viewModel.load(branchID: branchStore.activeBranch?.branchID) }
        .onChange(of: branchStore.activeBranch?.branchID) { branchID in
            viewModel.load(branchID: branchID)
        }
    }

    // MARK: - Sovereign Navigation Bar

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            AdminSovereignNavigationBar(
                title: Language.get("POS_History_Title", alter: "سجل مبيعات نقطة البيع"),
                subtitle: Language.get("CommandCenter_Work_Workspace", alter: "مساحة العمليات"),
                onBack: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
            ) {
                if viewModel.isLoading {
                    ProgressView().tint(AdminSurface.primary)
                } else {
                    Button(action: { viewModel.load(branchID: branchStore.activeBranch?.branchID) }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(width: 44, height: 44)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                            )
                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                }
            }

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error, retry: { viewModel.load(branchID: branchStore.activeBranch?.branchID) })
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 4)
            }
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: AdminSpacing.md) {
            SummaryChip(
                label: Language.get("POS_History_Revenue", alter: "\u{0627}\u{0644}\u{0625}\u{064a}\u{0631}\u{0627}\u{062f}\u{0627}\u{062a}"),
                value: formatCurrency(viewModel.totalRevenue),
                symbol: "dollarsign.circle.fill",
                color: .green
            )
            SummaryChip(
                label: Language.get("POS_History_Transactions", alter: "\u{0627}\u{0644}\u{0645}\u{0639}\u{0627}\u{0645}\u{0644}\u{0627}\u{062a}"),
                value: "\(viewModel.totalTransactions)",
                symbol: "receipt.fill",
                color: AdminSurface.primary
            )
            SummaryChip(
                label: Language.get("POS_History_Items", alter: "\u{0627}\u{0644}\u{0645}\u{0646}\u{062a}\u{062c}\u{0627}\u{062a}"),
                value: "\(viewModel.totalItemsSold)",
                symbol: "shippingbox.fill",
                color: .blue
            )
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.md)
    }

    private var receiptsList: some View {
        ScrollView {
            LazyVStack(spacing: AdminSpacing.sm) {
                ForEach(viewModel.receipts, id: \.receiptID) { receipt in
                    ReceiptCard(receipt: receipt)
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, AdminSpacing.sm)
        }
        .refreshable {
            viewModel.load(branchID: branchStore.activeBranch?.branchID)
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "QAR"
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f %@", value, Language.get("QAR", alter: "ر.ق"))
    }
}

// MARK: - Subviews

private struct SummaryChip: View {
    let label: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: AdminSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
        .accessibilityElement(children: .combine)
    }
}

private struct ReceiptCard: View {
    let receipt: PPPOSReceipt

    var body: some View {
        VStack(spacing: AdminSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(POSReceiptFormat.receiptID(receipt.receiptID))
                        .font(AdminType.headline.monospaced())
                        .foregroundColor(AdminSurface.primaryText)
                    if let date = receipt.createdAt {
                        Text(formattedDate(date))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
                Spacer()
                paymentMethodBadge
            }

            HStack {
                Label(
                    "\(receipt.items.count) \(Language.get("POS_Items", alter: "\u{0639}\u{0646}\u{0627}\u{0635}\u{0631}"))",
                    systemImage: "shippingbox.fill"
                )
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Text(formatCurrency(receipt.total))
                    .font(AdminType.title3)
                    .foregroundColor(AdminSurface.primaryText)
            }
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
        .accessibilityElement(children: .combine)
    }

    private var paymentMethodBadge: some View {
        let isCash = receipt.paymentMethod.lowercased() == "cash"
        return AdminStatusBadge(
            text: isCash
                ? Language.get("POS_Cash", alter: "\u{0646}\u{0642}\u{062f}\u{064a}")
                : Language.get("POS_Card", alter: "\u{0628}\u{0637}\u{0627}\u{0642}\u{0629}"),
            status: isCash ? .success : .info
        )
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "QAR"
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f %@", value, Language.get("QAR", alter: "ر.ق"))
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: Language.currentLanguageCode() == "ar" ? "ar" : "en")
        return formatter.string(from: date)
    }
}
