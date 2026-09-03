//
//  InventoryView.swift
//  PurePetsAdmin
//
//  Single view handling accessories, food, livePets via an enum kind parameter.
//  Uses AccessoryManager.shared(). List with image thumbnails, name, price,
//  stock, edit/delete swipe actions. Add button.
//

import SwiftUI

// MARK: - Inventory Kind

enum InventoryKind: String, CaseIterable {
    case accessories
    case food
    case livePets

    var accessKind: AccessKindType {
        switch self {
        case .accessories: return .typeAccessory
        case .food: return .typeFood
        case .livePets: return .typeLivePets
        }
    }

    var titleKey: String {
        switch self {
        case .accessories: return "Manage Accessories"
        case .food: return "manageFood"
        case .livePets: return "Manage Live Pets"
        }
    }

    var defaultTitle: String {
        switch self {
        case .accessories: return "\u{0625}\u{062f}\u{0627}\u{0631}\u{0629} \u{0627}\u{0644}\u{0625}\u{0643}\u{0633}\u{0633}\u{0648}\u{0627}\u{0631}\u{0627}\u{062a}"
        case .food: return "\u{0625}\u{062f}\u{0627}\u{0631}\u{0629} \u{0627}\u{0644}\u{0623}\u{0637}\u{0639}\u{0645}\u{0629}"
        case .livePets: return "\u{0625}\u{062f}\u{0627}\u{0631}\u{0629} \u{0627}\u{0644}\u{062d}\u{064a}\u{0648}\u{0627}\u{0646}\u{0627}\u{062a} \u{0627}\u{0644}\u{0623}\u{0644}\u{064a}\u{0641}\u{0629}"
        }
    }

    var emptySymbol: String {
        switch self {
        case .accessories: return "shippingbox.fill"
        case .food: return "fork.knife"
        case .livePets: return "pawprint.fill"
        }
    }
}

// MARK: - Inventory ViewModel

@MainActor
final class InventoryViewModel: ObservableObject {
    @Published private(set) var items: [PetAccessory] = []
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?
    @Published var searchText: String = ""
    @Published var showInStockOnly = false
    @Published var showLowStockOnly = false

    let kind: InventoryKind
    private var listener: AnyObject?

    var filteredItems: [PetAccessory] {
        var result = items
        if showInStockOnly {
            result = result.filter { $0.quantity > 0 && !$0.noStock }
        }
        if showLowStockOnly {
            result = result.filter { $0.quantity <= 3 || $0.noStock }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                ($0.accessoryCategoryID ?? "").lowercased().contains(q)
            }
        }
        result.sort { a, b in
            let dateA = a.createdAt
            let dateB = b.createdAt
            if dateA != dateB {
                return dateA > dateB
            }
            return a.accessoryID > b.accessoryID
        }
        return result
    }

    var totalCount: Int { items.count }
    var inStockCount: Int { items.filter { $0.quantity > 0 && !$0.noStock }.count }
    var lowStockCount: Int { items.filter { $0.quantity <= 3 || $0.noStock }.count }

    var navigationTitle: String {
        let title = Language.get(kind.titleKey, alter: nil)
        return (title.isEmpty || title == kind.titleKey) ? kind.defaultTitle : title
    }

    init(kind: InventoryKind) {
        self.kind = kind
    }

    func startListening() {
        isLoading = true
        errorMessage = nil
        listener = AccessoryManager.shared().observeAccessories(
            of: kind.accessKind
        ) { [weak self] items, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.items = (items ?? []).sorted { a, b in
                    let dateA = a.createdAt
                    let dateB = b.createdAt
                    if dateA != dateB {
                        return dateA > dateB
                    }
                    return a.accessoryID > b.accessoryID
                }
            }
        }
    }

    func stopListening() {
        if let reg = listener as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(reg)
        }
        listener = nil
    }

    func deleteItem(_ accessory: PetAccessory) {
        let docID = accessory.accessoryID
        AccessoryManager.shared().deleteAccessory(withID: docID) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func updateQuantity(_ qty: Int, for accessory: PetAccessory) {
        let docID = accessory.accessoryID
        AccessoryManager.shared().updateQuantity(qty, forAccessoryID: docID) { [weak self] error in
            Task { @MainActor in
                if let error { self?.errorMessage = error.localizedDescription }
            }
        }
    }

    func toggleNoStock(for accessory: PetAccessory) {
        let docID = accessory.accessoryID
        AccessoryManager.shared().setNoStock(!accessory.noStock, forAccessoryID: docID) { [weak self] error in
            Task { @MainActor in
                if let error { self?.errorMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - Inventory View

struct AdminInventoryView: View {
    let kind: InventoryKind
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: InventoryViewModel
    @State private var editingItem: PetAccessory?
    @State private var showingDeleteAlert = false
    @State private var itemToDelete: PetAccessory?

    init(kind: InventoryKind, session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.kind = kind
        self.session = session
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: InventoryViewModel(kind: kind))
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView
                statsRow
                searchAndFilters
                Divider().background(AdminSurface.hairline)

                if viewModel.isLoading {
                    Spacer()
                    ProgressView().tint(AdminSurface.primary).scaleEffect(1.2)
                    Spacer()
                } else if viewModel.filteredItems.isEmpty && !viewModel.items.isEmpty {
                    Spacer()
                    AdminEmptyStateView(
                        symbol: "magnifyingglass",
                        title: Language.get("Inventory_No_Results", alter: "لا توجد نتائج"),
                        subtitle: Language.get("Inventory_No_Results_Sub", alter: "جرّب تغيير معايير البحث")
                    )
                    Spacer()
                } else if viewModel.items.isEmpty && !viewModel.isLoading {
                    Spacer()
                    AdminEmptyStateView(
                        symbol: kind.emptySymbol,
                        title: Language.get("Inventory_Empty", alter: "لا توجد عناصر"),
                        subtitle: Language.get("Inventory_Empty_Sub", alter: "اضغط + لإضافة عنصر جديد")
                    )
                    Spacer()
                } else if let error = viewModel.errorMessage {
                    Spacer()
                    AdminErrorBanner(message: error, retry: { viewModel.startListening() })
                        .padding(.horizontal, AdminSpacing.screenMargin)
                    Spacer()
                } else {
                    inventoryList
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
        .alert(
            Language.get("Inventory_Delete_Confirm", alter: "تأكيد الحذف"),
            isPresented: $showingDeleteAlert
        ) {
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
            Button(Language.get("Delete", alter: "حذف"), role: .destructive) {
                if let item = itemToDelete {
                    viewModel.deleteItem(item)
                }
            }
        } message: {
            Text(Language.get("Inventory_Delete_Message", alter: "هل أنت متأكد من حذف هذا العنصر؟"))
        }
    }

    // MARK: - Sovereign Navigation Bar

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            AdminSovereignNavigationBar(
                title: viewModel.navigationTitle,
                subtitle: Language.get("CommandCenter_Work_Workspace", alter: "مساحة المخزون"),
                onBack: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
            ) {
                AdminPrimaryPillButton(
                    title: Language.get("Add", alter: "إضافة"),
                    systemImage: "plus"
                ) {
                    let addVC = AddAccessoryViewController()
                    addVC.defaultKind = kind.accessKind
                    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let root = scene.windows.first?.rootViewController,
                          let nav = root as? UINavigationController ?? root.navigationController
                    else { return }
                    nav.pushViewController(addVC, animated: true)
                }
            }

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) { viewModel.startListening() }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 4)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: AdminSpacing.md) {
            QuickStat(
                label: Language.get("Inventory_Total", alter: "\u{0627}\u{0644}\u{0643}\u{0644}"),
                value: "\(viewModel.totalCount)",
                symbol: "cube.box.fill",
                color: AdminSurface.primary
            )
            QuickStat(
                label: Language.get("Inventory_In_Stock", alter: "\u{0645}\u{062a}\u{0648}\u{0641}\u{0631}"),
                value: "\(viewModel.inStockCount)",
                symbol: "checkmark.circle.fill",
                color: .green
            )
            QuickStat(
                label: Language.get("Inventory_Low_Stock", alter: "\u{0645}\u{0646}\u{062e}\u{0641}\u{0636}"),
                value: "\(viewModel.lowStockCount)",
                symbol: "exclamationmark.triangle.fill",
                color: .orange
            )
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.md)
    }

    private var searchAndFilters: some View {
        VStack(spacing: AdminSpacing.sm) {
            AdminSearchField(
                text: $viewModel.searchText,
                placeholder: Language.get("Inventory_Search", alter: "\u{0627}\u{0628}\u{062d}\u{062b}...")
            )
            .padding(.horizontal, AdminSpacing.screenMargin)

            HStack(spacing: AdminSpacing.sm) {
                FilterToggle(
                    title: Language.get("Inventory_In_Stock", alter: "\u{0645}\u{062a}\u{0648}\u{0641}\u{0631}"),
                    isOn: $viewModel.showInStockOnly
                )
                FilterToggle(
                    title: Language.get("Inventory_Low_Stock", alter: "\u{0645}\u{0646}\u{062e}\u{0641}\u{0636}"),
                    isOn: $viewModel.showLowStockOnly
                )
                Spacer()
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
        }
        .padding(.vertical, AdminSpacing.sm)
    }

    private var inventoryList: some View {
        ScrollView {
            LazyVStack(spacing: AdminSpacing.sm) {
                ForEach(viewModel.filteredItems, id: \.accessoryID) { item in
                    InventoryItemRow(item: item, kind: viewModel.kind)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                itemToDelete = item
                                showingDeleteAlert = true
                            } label: {
                                Label(Language.get("Delete", alter: "\u{062d}\u{0630}\u{0641}"), systemImage: "trash.fill")
                            }

                            Button {
                                editingItem = item
                            } label: {
                                Label(Language.get("Edit", alter: "\u{062a}\u{0639}\u{062f}\u{064a}\u{0644}"), systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button {
                                viewModel.toggleNoStock(for: item)
                            } label: {
                                Label(
                                    item.noStock
                                        ? Language.get("Inventory_Mark_In_Stock", alter: "\u{062a}\u{0648}\u{0641}\u{0631}")
                                        : Language.get("Inventory_Mark_No_Stock", alter: "\u{0646}\u{0641}\u{0627}\u{062f}"),
                                    systemImage: item.noStock ? "checkmark.circle" : "xmark.circle"
                                )
                            }
                        }
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, AdminSpacing.sm)
        }
        .refreshable {
            viewModel.stopListening()
            viewModel.startListening()
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }
}

// MARK: - Subviews

private struct QuickStat: View {
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

private struct FilterToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(AdminType.captionBold)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isOn ? AdminSurface.primary : AdminSurface.control, in: Capsule())
                .foregroundColor(isOn ? .white : AdminSurface.secondaryText)
                .overlay(Capsule().stroke(isOn ? Color.clear : AdminSurface.hairline, lineWidth: 1))
        }
        .frame(minHeight: AdminTouchTarget.minimum)
    }
}

private struct InventoryItemRow: View {
    let item: PetAccessory
    let kind: InventoryKind

    var body: some View {
        HStack(spacing: AdminSpacing.md) {
            thumbnailView
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: AdminRadius.medium))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                if let category = item.accessoryCategoryID, !category.isEmpty {
                    Text(category)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                HStack(spacing: AdminSpacing.sm) {
                    Label(
                        "\(item.quantity)",
                        systemImage: "cube.box.fill"
                    )
                    .font(AdminType.caption2Bold)
                    .foregroundColor(
                        item.noStock || item.quantity <= 0 ? .red :
                        item.quantity <= 3 ? .orange : AdminSurface.secondaryText
                    )

                    if item.noStock {
                        Text(Language.get("Inventory_No_Stock", alter: "\u{0646}\u{0641}\u{0627}\u{062f}"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.10), in: Capsule())
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatPrice(item.finalPrice.doubleValue))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)

                if item.finalPrice != item.price {
                    Text(formatPrice(item.price.doubleValue))
                        .font(AdminType.caption2)
                        .foregroundColor(.green)
                        .strikethrough(false)
                }
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let urlString = item.imageURLsArray.first,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipped()
                    case .failure:
                        placeholderIcon
                    case .empty:
                        ProgressView().tint(AdminSurface.primary)
                    @unknown default:
                        placeholderIcon
                    }
                }
                .frame(width: 56, height: 56)
                .clipped()
            } else {
                placeholderIcon
            }
        }
        .frame(width: 56, height: 56)
        .clipped()
    }

    private var placeholderIcon: some View {
        ZStack {
            AdminSurface.control
            Image(systemName: kind.emptySymbol)
                .font(.system(size: 20))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.4))
        }
    }

    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "QAR"
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f %@", value, Language.get("QAR", alter: "ر.ق"))
    }
}
