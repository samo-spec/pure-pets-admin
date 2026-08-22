//
//  PPInventoryListView.swift
//  PurePetsAdmin
//
//  NextGen V6 Recreated Inventory Screen
//  Preserves 100% of AccessoryManager, PetAccessory, and Firestore backend.
//

import SwiftUI
import UIKit

// MARK: - Sendable Conformance

extension PetAccessory: @unchecked Sendable {}

// MARK: - Inventory Filter Enum

fileprivate enum InventoryFilter: Int, CaseIterable, Identifiable {
    case all = 0
    case inStock
    case lowStock
    case hasOffer

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "All"
        case .inStock: return "InStock"
        case .lowStock: return "LowStock"
        case .hasOffer: return "Offers"
        }
    }

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .inStock: return "checkmark.circle.fill"
        case .lowStock: return "exclamationmark.triangle.fill"
        case .hasOffer: return "tag.fill"
        }
    }
}

// MARK: - Inventory List View Model

@MainActor
final class PPInventoryListViewModel: ObservableObject {
    @Published private(set) var allItems: [PetAccessory] = []
    @Published private(set) var filteredItems: [PetAccessory] = []
    @Published var searchText: String = ""
    @Published fileprivate var activeFilter: InventoryFilter = .all
    @Published private(set) var isLoading: Bool = true
    @Published var errorMessage: String? = nil

    let kind: AccessKindType
    private var listener: AnyObject?
    private var pendingQuantityDeltas: [String: Int] = [:]
    private var pendingDebounceWorkItems: [String: DispatchWorkItem] = [:]

    var totalCount: Int { allItems.count }
    var inStockCount: Int { allItems.filter { $0.quantity > 0 && !$0.noStock }.count }
    var lowOrNoStockCount: Int { allItems.filter { $0.quantity <= 3 || $0.noStock }.count }
    var offersCount: Int {
        allItems.filter {
            $0.hasOffer || ($0.discountPercent?.doubleValue ?? 0) > 0 || ($0.discountAmount?.doubleValue ?? 0) > 0
        }.count
    }

    init(kind: AccessKindType = .typeAccessory) {
        self.kind = kind
    }

    var navigationTitle: String {
        switch kind {
        case .typeFood:
            let title = Language.get("manageFood", alter: nil)
            return (title.isEmpty || title == "manageFood") ? "إدارة الأطعمة" : title
        case .typeLivePets:
            let title = Language.get("Manage Live Pets", alter: nil)
            return (title.isEmpty || title == "Manage Live Pets") ? "إدارة الحيوانات الأليفة" : title
        default:
            let title = Language.get("Manage Accessories", alter: nil)
            return (title.isEmpty || title == "Manage Accessories") ? "إدارة الإكسسوارات" : title
        }
    }

    func startListening() {
        isLoading = true
        listener = AccessoryManager.shared().observeAccessories(of: kind) { [weak self] items, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.allItems = items ?? []
                self.applyFilter()
            }
        }
    }

    func stopListening() {
        if let reg = listener as? AnyObject {
            _ = reg.perform(Selector(("remove")))
        }
        listener = nil
        for workItem in pendingDebounceWorkItems.values {
            workItem.cancel()
        }
        pendingDebounceWorkItems.removeAll()
        pendingQuantityDeltas.removeAll()
    }

    func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = allItems.filter { item in
            switch activeFilter {
            case .all:
                break
            case .inStock:
                if item.quantity <= 0 || item.noStock { return false }
            case .lowStock:
                if item.quantity > 3 && !item.noStock { return false }
            case .hasOffer:
                let hasDiscount = (itemDiscountValue(item) > 0) || item.hasOffer
                if !hasDiscount { return false }
            }

            guard !query.isEmpty else { return true }
            let name = item.name.lowercased()
            let desc = item.desc.lowercased()
            let searchTitle = item.searchTitle.lowercased()
            let store = (item.storeName ?? "").lowercased()
            return name.contains(query) || desc.contains(query) || searchTitle.contains(query) || store.contains(query)
        }

        result.sort { a, b in
            // Active items first, then by name
            if a.noStock != b.noStock {
                return !a.noStock && b.noStock
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        filteredItems = result
    }

    private func itemDiscountValue(_ item: PetAccessory) -> Double {
        let percent = item.discountPercent?.doubleValue ?? 0
        let amount = item.discountAmount?.doubleValue ?? 0
        return max(percent, amount)
    }

    func refresh() async {
        await withCheckedContinuation { continuation in
            AccessoryManager.shared().fetchAccessories(of: kind) { [weak self] items, _ in
                DispatchQueue.main.async {
                    self?.allItems = items ?? []
                    self?.applyFilter()
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Quantity Adjustment with Real-time Debounce

    func adjustQuantity(by delta: Int, for item: PetAccessory) {
        let docID = item.accessoryID
        guard !docID.isEmpty else { return }

        // Local optimistic update
        item.quantity = max(0, item.quantity + delta)
        item.noStock = (item.quantity <= 0)
        objectWillChange.send()

        // Batch delta
        let currentPending = pendingQuantityDeltas[docID] ?? 0
        let newPending = currentPending + delta
        pendingQuantityDeltas[docID] = newPending

        // Cancel existing debounce timer for this item
        pendingDebounceWorkItems[docID]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let batchedDelta = self.pendingQuantityDeltas[docID], batchedDelta != 0 else { return }
            self.pendingQuantityDeltas.removeValue(forKey: docID)
            self.pendingDebounceWorkItems.removeValue(forKey: docID)

            AccessoryManager.shared().adjustQuantity(by: batchedDelta, forAccessoryID: docID) { error in
                if let error = error {
                    PPHUD.showError(Language.get("Error", alter: nil), subtitle: error.localizedDescription)
                }
            }
        }

        pendingDebounceWorkItems[docID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    // MARK: - Delete & Status Operations

    func deleteAccessory(_ item: PetAccessory) {
        let docID = item.accessoryID
        guard !docID.isEmpty else { return }
        PPHUD.showIndeterminate(in: nil, title: Language.get("Deleting", alter: nil), subtitle: nil)
        AccessoryManager.shared().deleteAccessory(withID: docID) { error in
            PPHUD.dismiss()
            if let error = error {
                PPHUD.showError(Language.get("Error", alter: nil), subtitle: error.localizedDescription)
            } else {
                PPHUD.showSuccess(Language.get("Deleted", alter: nil), subtitle: Language.get("StockUpdated", alter: nil))
            }
        }
    }

    func toggleActive(_ item: PetAccessory) {
        let docID = item.accessoryID
        guard !docID.isEmpty else { return }
        let newActive = !item.active
        AccessoryManager.shared().setActive(newActive, forAccessoryID: docID) { error in
            if let error = error {
                PPHUD.showError(Language.get("Error", alter: nil), subtitle: error.localizedDescription)
            }
        }
    }
}

// MARK: - Main SwiftUI View

@MainActor
struct PPInventoryListView: View {
    @StateObject private var viewModel: PPInventoryListViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let onPushViewController: (UIViewController) -> Void
    private let onDismiss: (() -> Void)?

    @State private var itemToDelete: PetAccessory?
    @State private var showDeleteConfirmation = false
    @FocusState private var isSearchFocused: Bool

    init(
        kind: AccessKindType = .typeAccessory,
        onPushViewController: @escaping (UIViewController) -> Void = { _ in },
        onDismiss: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: PPInventoryListViewModel(kind: kind))
        self.onPushViewController = onPushViewController
        self.onDismiss = onDismiss
    }

    var body: some View {
        GeometryReader { geometry in
            let safeTop = max(geometry.safeAreaInsets.top, PPStatusBarHelper.statusBarHeight, 44)
            ZStack(alignment: .top) {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header Bar
                    screenHeader
                        .padding(.top, safeTop + 4)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    // Scrollable Content
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            // Search Box
                            searchBar

                            // Stats Bento / Filter Pills
                            statsFilterBento

                            // Product Items List
                            if viewModel.isLoading && viewModel.allItems.isEmpty {
                                loadingSkeletonView
                            } else if viewModel.filteredItems.isEmpty {
                                emptyStateView
                            } else {
                                itemsListView
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 96)
                    }
                    .refreshable {
                        await viewModel.refresh()
                    }
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .onChange(of: viewModel.searchText) { _ in
            viewModel.applyFilter()
        }
        .onChange(of: viewModel.activeFilter) { _ in
            viewModel.applyFilter()
        }
        .confirmationDialog(
            Language.get("Confirm Delete", alter: "تأكيد الحذف"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(Language.get("Delete", alter: "حذف"), role: .destructive) {
                if let item = itemToDelete {
                    viewModel.deleteAccessory(item)
                }
                itemToDelete = nil
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text(Language.get("Are you sure you want to delete this accessory?", alter: "هل أنت متأكد من رغبتك في حذف هذا المنتج؟"))
        }
    }

    // MARK: - Header Bar

    // MARK: - Screen Header (PPAccessoryEditorView Dossier Pattern)

    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let onDismiss = onDismiss {
                        onDismiss()
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

                // Add (+) Button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let addVC = AddAccessoryViewController(accessory: nil)
                    addVC.showTypeRow = false
                    addVC.defaultKind = viewModel.kind
                    onPushViewController(addVC)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text(Language.get("Add", alter: "إضافة"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(AdminSurface.primary, in: Capsule())
                }
                .buttonStyle(V6CardButtonStyle())
                .accessibilityLabel(Language.get("Add", alter: "إضافة"))
            }

            Text(Language.get("CommandCenter_Work_Workspace", alter: "مساحة المخزون") + " / " + viewModel.navigationTitle)
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            HStack {
                Text(viewModel.navigationTitle)
                    .font(AdminType.title2)
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                Text(String(format: Language.get("Total_Items_Format", alter: "%d منتج"), viewModel.totalCount))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) { viewModel.startListening() }
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AdminSurface.secondaryText)

            TextField(
                Language.get("Inventory_Search_Placeholder", alter: "بحث في المخزون..."),
                text: $viewModel.searchText
            )
            .font(AdminType.body)
            .foregroundColor(AdminSurface.primaryText)
            .focused($isSearchFocused)
            .autocorrectionDisabled()

            if !viewModel.searchText.isEmpty {
                Button(action: {
                    viewModel.searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSearchFocused ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSearchFocused ? 1.5 : 1)
        )
    }

    // MARK: - Stats & Filter Bento

    private var statsFilterBento: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    filter: .all,
                    count: viewModel.totalCount,
                    title: Language.get("All", alter: "الكل"),
                    color: AdminSurface.primary
                )

                filterChip(
                    filter: .inStock,
                    count: viewModel.inStockCount,
                    title: Language.get("InStock", alter: "متوفر"),
                    color: Color(uiColor: .ppSuccess)
                )

                filterChip(
                    filter: .lowStock,
                    count: viewModel.lowOrNoStockCount,
                    title: Language.get("LowStock", alter: "منخفض / نفذ"),
                    color: Color(uiColor: .ppWarning)
                )

                filterChip(
                    filter: .hasOffer,
                    count: viewModel.offersCount,
                    title: Language.get("Offers", alter: "العروض"),
                    color: Color(uiColor: .ppError)
                )
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(filter: InventoryFilter, count: Int, title: String, color: Color) -> some View {
        let isSelected = viewModel.activeFilter == filter
        return Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if reduceMotion {
                viewModel.activeFilter = filter
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    viewModel.activeFilter = filter
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: filter.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? .white : color)

                Text(title)
                    .font(isSelected ? AdminType.captionBold : AdminType.caption1)
                    .foregroundColor(isSelected ? .white : AdminSurface.primaryText)

                Text("\(count)")
                    .font(AdminType.caption2Bold)
                    .foregroundColor(isSelected ? .white.opacity(0.90) : color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.white.opacity(0.20) : color.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                isSelected ? AdminSurface.primary : AdminSurface.control,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - Items List

    private var itemsListView: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.filteredItems, id: \.accessoryID) { item in
                InventoryCardView(
                    item: item,
                    onTap: {
                        let editVC = AddAccessoryViewController(accessory: item)
                        editVC.showTypeRow = false
                        editVC.defaultKind = viewModel.kind
                        onPushViewController(editVC)
                    },
                    onAdjustQuantity: { delta in
                        viewModel.adjustQuantity(by: delta, for: item)
                    },
                    onDelete: {
                        itemToDelete = item
                        showDeleteConfirmation = true
                    }
                )
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 28))
                    .foregroundColor(AdminSurface.primary.opacity(0.60))
            }
            .padding(.top, 32)

            Text(Language.get("No Accessories Found", alter: "لا توجد منتجات مطابقة"))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)

            Text(Language.get("Tap + to add your first accessory.", alter: "اضغط على + لإضافة منتج جديد."))
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let addVC = AddAccessoryViewController(accessory: nil)
                addVC.showTypeRow = false
                addVC.defaultKind = viewModel.kind
                onPushViewController(addVC)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(Language.get("Add", alter: "إضافة منتج"))
                }
                .font(AdminType.calloutBold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(V6CardButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Loading Skeleton

    private var loadingSkeletonView: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.control)
                        .frame(width: 74, height: 74)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AdminSurface.hairline)
                            .frame(width: 140, height: 16)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AdminSurface.hairline)
                            .frame(width: 80, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AdminSurface.hairline)
                            .frame(width: 100, height: 14)
                    }
                    Spacer()
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

// MARK: - NextGen V6 Inventory Item Card

private struct InventoryCardView: View {
    let item: PetAccessory
    let onTap: () -> Void
    let onAdjustQuantity: (Int) -> Void
    let onDelete: () -> Void

    private var imageURL: URL? {
        PetAccessory.firstImageURL(for: item)
    }

    private var hasDiscount: Bool {
        let percent = item.discountPercent?.doubleValue ?? 0
        let amount = item.discountAmount?.doubleValue ?? 0
        return percent > 0 || amount > 0 || item.hasOffer
    }

    private var finalPriceFormatted: String {
        PetAccessory.formatCurrency(item.finalPrice)
    }

    private var originalPriceFormatted: String? {
        guard hasDiscount, item.price.doubleValue > item.finalPrice.doubleValue else {
            return nil
        }
        return PetAccessory.formatCurrency(item.price)
    }

    private var stockTone: Color {
        if item.quantity <= 0 || item.noStock {
            return Color(uiColor: .ppError)
        } else if item.quantity <= 3 {
            return Color(uiColor: .ppWarning)
        } else {
            return Color(uiColor: .ppSuccess)
        }
    }

    private var stockText: String {
        if item.quantity <= 0 || item.noStock {
            return Language.get("OutOfStock", alter: "نفذ من المخزون")
        } else if item.quantity <= 3 {
            return String(format: Language.get("LowStock_Qty_Format", alter: "منخفض (%d)"), item.quantity)
        } else {
            return String(format: Language.get("InStock_Qty_Format", alter: "متوفر (%d)"), item.quantity)
        }
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            HStack(alignment: .top, spacing: 12) {
                // Leading Image with Discount Pill
                ZStack(alignment: .topLeading) {
                    productThumbnail
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 1)
                        )

                    if hasDiscount, let percent = item.discountPercent, percent.intValue > 0 {
                        Text("-\(percent.intValue)%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(uiColor: .ppError), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(4)
                    }
                }

                // Middle Content Info
                VStack(alignment: .leading, spacing: 4) {
                    // Category / Store Tag
                    HStack(spacing: 4) {
                        if let store = item.storeName, !store.isEmpty {
                            Text(store)
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }

                        let condText = PetAccessory.conditionText(for: item)
                        if !condText.isEmpty {
                            Text(condText)
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }

                        Spacer()

                        // Stock Status Badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(stockTone)
                                .frame(width: 6, height: 6)
                            Text(stockText)
                                .font(AdminType.caption2Bold)
                                .foregroundColor(stockTone)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(stockTone.opacity(0.10), in: Capsule())
                    }

                    // Product Name
                    Text(item.name)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    // Bottom Row: Price & Quantity Stepper
                    HStack(alignment: .bottom, spacing: 8) {
                        // Price
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(finalPriceFormatted)
                                .font(AdminType.title3)
                                .foregroundColor(AdminSurface.primary)
                                .monospacedDigit()

                            if let original = originalPriceFormatted {
                                Text(original)
                                    .font(AdminType.caption1)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .strikethrough()
                            }
                        }

                        Spacer()

                        // Real-Time Quantity Stepper
                        quantityStepper
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onTap) {
                Label(Language.get("Edit", alter: "تعديل"), systemImage: "pencil")
            }

            Button(action: {
                if let root = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                    PetAccessory.share(item, from: root)
                }
            }) {
                Label(Language.get("Share", alter: "مشاركة"), systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label(Language.get("Delete", alter: "حذف"), systemImage: "trash")
            }
        }
    }

    // MARK: - Quantity Stepper

    private var quantityStepper: some View {
        HStack(spacing: 2) {
            // Decrement (-)
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onAdjustQuantity(-1)
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(item.quantity > 0 ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.40))
                    .frame(width: 28, height: 28)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(V6CardButtonStyle())
            .disabled(item.quantity <= 0)

            // Value Display
            Text("\(item.quantity)")
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
                .monospacedDigit()
                .frame(minWidth: 26)
                .multilineTextAlignment(.center)

            // Increment (+)
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onAdjustQuantity(1)
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 28, height: 28)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(V6CardButtonStyle())
        }
        .padding(3)
        .background(AdminSurface.surface.opacity(0.70), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
    }

    // MARK: - Product Thumbnail

    @ViewBuilder
    private var productThumbnail: some View {
        if let imageURL = imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderThumbnail
                case .empty:
                    ZStack {
                        AdminSurface.surface
                        ProgressView()
                            .tint(AdminSurface.primary)
                    }
                @unknown default:
                    placeholderThumbnail
                }
            }
        } else {
            placeholderThumbnail
        }
    }

    private var placeholderThumbnail: some View {
        ZStack {
            AdminSurface.surface
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 24))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.40))
        }
    }
}

// MARK: - UIViewController Hosting Bridge for ObjC Routing

@objc public final class PPInventoryListHostingController: UIViewController {
    private let kind: AccessKindType
    private var hostingController: UIHostingController<PPInventoryListView>?

    @objc public init(kind: AccessKindType = .typeAccessory) {
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        self.kind = .typeAccessory
        super.init(coder: coder)
    }

    @objc public static func makeForAccessories() -> UIViewController {
        return PPInventoryListHostingController(kind: .typeAccessory)
    }

    @objc public static func makeForFood() -> UIViewController {
        return PPInventoryListHostingController(kind: .typeFood)
    }

    @objc public static func makeForLivePets() -> UIViewController {
        return PPInventoryListHostingController(kind: .typeLivePets)
    }

    @objc public static func make(kind: AccessKindType) -> UIViewController {
        return PPInventoryListHostingController(kind: kind)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.ppBackground

        let swiftUIView = PPInventoryListView(
            kind: kind,
            onPushViewController: { [weak self] targetVC in
                self?.navigationController?.pushViewController(targetVC, animated: true)
            },
            onDismiss: { [weak self] in
                if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                    nav.popViewController(animated: true)
                } else {
                    self?.dismiss(animated: true)
                }
            }
        )

        let host = UIHostingController(rootView: swiftUIView)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}
