import SwiftUI
import FirebaseFirestore

extension PPDeliveryRequestRecord: @unchecked Sendable {}

@MainActor
final class DeliveryListViewModel: ObservableObject {
    @Published private(set) var records: [PPDeliveryRequestRecord] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    var filteredRecords: [PPDeliveryRequestRecord] {
        guard !searchText.isEmpty else { return records }
        let q = searchText.lowercased()
        return records.filter { $0.orderID.lowercased().contains(q) || $0.customerName.lowercased().contains(q) || $0.assignedDriverName.lowercased().contains(q) }
    }
    var activeCount: Int { records.filter { ($0.status ?? "") == "in_transit" || ($0.status ?? "") == "pending" }.count }
    var completedCount: Int { records.filter { ($0.status ?? "") == "completed" }.count }
    func load() {
        isLoading = true; errorMessage = nil
        PPDeliveryService.shared().fetchAllDeliveryRequests { [weak self] recs, err in
            Task { @MainActor in guard let self else { return }
                self.isLoading = false; self.isRefreshing = false
                if let err { self.errorMessage = err.localizedDescription; return }
                self.records = (recs ?? []).sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
            }
        }
    }
    func refresh() { isRefreshing = true; load() }
}
struct AdminDeliveryListView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = DeliveryListViewModel()

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView

                if vm.isLoading && vm.records.isEmpty {
                    Spacer()
                    ProgressView().tint(AdminSurface.primary).scaleEffect(1.2)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            statsRow
                            AdminSearchField(text: $vm.searchText, placeholder: Language.get("Search", alter: "بحث..."))
                                .padding(.horizontal, 20)
                            if let err = vm.errorMessage {
                                AdminErrorBanner(message: err, retry: vm.load)
                                    .padding(.horizontal, 20)
                            }
                            if vm.filteredRecords.isEmpty {
                                AdminEmptyStateView(symbol: "truck.box", title: Language.get("No_Deliveries", alter: "لا توجد طلبات توصيل"))
                            } else {
                                LazyVStack(spacing: 10) {
                                    ForEach(vm.filteredRecords, id: \.requestID) { deliveryCard($0) }
                                }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .refreshable { vm.refresh() }
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear { vm.load() }
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

                if vm.isLoading || vm.isRefreshing {
                    ProgressView()
                        .tint(AdminSurface.primary)
                } else {
                    Button(action: { vm.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AdminSurface.primary)
                            .frame(width: 36, height: 36)
                            .background(AdminSurface.primary.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                }
            }

            Text(Language.get("CommandCenter_Delivery_Workspace", alter: "مساحة التوصيل") + " / " + Language.get("Delivery_Title", alter: "إدارة التوصيل"))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(Language.get("Delivery_Title", alter: "إدارة التوصيل"))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
    }
    private var statsRow: some View {
        HStack(spacing: 16) { AdminCard { statCell(count: vm.records.count, title: Language.get("Total", alter: nil), symbol: "shippingbox.fill", color: AdminSurface.primary) }; AdminCard { statCell(count: vm.activeCount, title: Language.get("Active", alter: nil), symbol: "arrow.triangle.swap", color: .orange) }; AdminCard { statCell(count: vm.completedCount, title: Language.get("Completed", alter: nil), symbol: "checkmark.circle.fill", color: .green) } }.padding(.horizontal, 20)
    }
    private func statCell(count: Int, title: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 6) { Text("\(count)").font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().foregroundColor(AdminSurface.primaryText); Label(title, systemImage: symbol).font(AdminType.captionBold).foregroundColor(color) }.frame(maxWidth: .infinity).padding(.vertical, 16)
    }
    @ViewBuilder private func deliveryCard(_ r: PPDeliveryRequestRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) { HStack { Text(r.orderNumber.isEmpty ? r.orderID : r.orderNumber).font(AdminType.headline).foregroundColor(AdminSurface.primaryText); Spacer(); AdminStatusBadge(text: statusText(r.status), status: statusBadge(r.status)) }; if !r.customerName.isEmpty { Label(r.customerName, systemImage: "person.fill").font(AdminType.subheadline).foregroundColor(AdminSurface.secondaryText) }; Text(String(format: "%.2f SAR", r.deliveryFee.doubleValue)).font(AdminType.captionBold).foregroundColor(AdminSurface.primary); if let date = r.createdAt { Text(date, style: .date).font(AdminType.caption1).foregroundColor(AdminSurface.secondaryText) } }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline)).padding(.horizontal, 20)
    }
    private func statusText(_ s: String?) -> String {
        switch s ?? "" { case "pending": return Language.get("Pending", alter: nil); case "accepted": return Language.get("Accepted", alter: nil); case "in_transit": return Language.get("InTransit", alter: nil); case "completed": return Language.get("Completed", alter: nil); case "cancelled": return Language.get("Cancelled", alter: nil); default: return s ?? "—" }
    }
    private func statusBadge(_ s: String?) -> AdminStatusBadge.Status {
        switch s ?? "" { case "completed": return .success; case "cancelled": return .error; case "in_transit": return .info; case "pending": return .warning; default: return .neutral }
    }
}
