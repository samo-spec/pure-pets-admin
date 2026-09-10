//
//  InventoryView.swift
//  PurePetsAdmin
//
//  Single view handling accessories, food, livePets via an enum kind parameter.
//  Uses AccessoryManager.shared(). List with image thumbnails, name, price,
//  stock, edit/delete swipe actions. Add button.
//

import SwiftUI
import Combine
import FirebaseFirestore

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
    private var listener: (any ListenerRegistration)?
    private var cancellables = Set<AnyCancellable>()

    private var branchScopedItems: [PetAccessory] {
        guard PPBranchInventoryService.shared.currentBranchId?.isEmpty == false else { return [] }
        let productIDs = Set(PPBranchInventoryService.shared.inventoryMap.keys)
        return items.filter { productIDs.contains($0.accessoryID) }
    }

    var filteredItems: [PetAccessory] {
        var result = branchScopedItems
        if showInStockOnly {
            result = result.filter {
                let stock = PPBranchInventoryService.shared.availableStock(for: $0.accessoryID, fallback: $0.quantity)
                return stock > 0 && !$0.noStock
            }
        }
        if showLowStockOnly {
            result = result.filter {
                let stock = PPBranchInventoryService.shared.availableStock(for: $0.accessoryID, fallback: $0.quantity)
                return stock <= 3 || $0.noStock
            }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                ($0.accessoryCategoryID ?? "").lowercased().contains(q) ||
                ($0.sku ?? "").lowercased().contains(q) ||
                ($0.barcode ?? "").lowercased().contains(q)
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

    var totalCount: Int { branchScopedItems.count }
    var inStockCount: Int {
        branchScopedItems.filter {
            let stock = PPBranchInventoryService.shared.availableStock(for: $0.accessoryID, fallback: $0.quantity)
            return stock > 0 && !$0.noStock
        }.count
    }
    var lowStockCount: Int {
        branchScopedItems.filter {
            let stock = PPBranchInventoryService.shared.availableStock(for: $0.accessoryID, fallback: $0.quantity)
            return stock <= 3 || $0.noStock
        }.count
    }

    var navigationTitle: String {
        let title = Language.get(kind.titleKey, alter: nil)
        return (title.isEmpty || title == kind.titleKey) ? kind.defaultTitle : title
    }

    init(kind: InventoryKind) {
        self.kind = kind
    }

    func startListening() {
        listener?.remove()
        listener = nil
        cancellables.removeAll()
        isLoading = true
        errorMessage = nil

        PPBranchInventoryService.shared.startListeningIfNeeded()
        PPBranchInventoryService.shared.$inventoryMap
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        PPBranchInventoryService.shared.$settingsMap
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

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
                self.items = (items ?? []).filter { !$0.isDeleted }.sorted { a, b in
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
        listener?.remove()
        listener = nil
        cancellables.removeAll()
    }

    func deleteItem(_ accessory: PetAccessory) {
        let docID = accessory.accessoryID
        guard !docID.isEmpty else { return }
        if accessory.isLivePet {
            Task { @MainActor in
                do {
                    _ = try await PPLivePetInventoryService.callInventory(
                        action: "delete",
                        productID: docID,
                        payload: ["reason": "admin_ios_soft_delete"]
                    )
                    self.items.removeAll { $0.accessoryID == docID }
                    PPAlertHelper.showSuccess(
                        in: nil,
                        title: Language.get("Success", alter: "تم بنجاح"),
                        subtitle: Language.get("Inventory_Item_Deleted", alter: "تم حذف الصنف بنجاح")
                    )
                } catch {
                    let msg = PPLivePetInventoryService.localizedMessage(for: error)
                    self.errorMessage = msg
                    await PPAlertHelper.showError(
                        in: nil,
                        title: Language.get("Error", alter: "خطأ"),
                        subtitle: msg
                    )
                }
            }
            return
        }
        AccessoryManager.shared().deleteAccessory(withID: docID) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = error.localizedDescription
                    await PPAlertHelper.showError(
                        in: nil,
                        title: Language.get("Error", alter: "خطأ"),
                        subtitle: error.localizedDescription
                    )
                } else {
                    self?.items.removeAll { $0.accessoryID == docID }
                    PPAlertHelper.showSuccess(
                        in: nil,
                        title: Language.get("Success", alter: "تم بنجاح"),
                        subtitle: Language.get("Inventory_Item_Deleted", alter: "تم حذف الصنف بنجاح")
                    )
                }
            }
        }
    }

    func updateQuantity(_ qty: Int, for accessory: PetAccessory) {
        let current = PPBranchInventoryService.shared.availableStock(for: accessory.accessoryID, fallback: accessory.quantity)
        let delta = qty - current
        guard delta != 0 else { return }

        if let branchId = BranchContextStore.shared.activeBranch?.branchID, !branchId.isEmpty {
            PPBranchInventoryService.shared.adjustStock(
                productId: accessory.accessoryID,
                branchId: branchId,
                delta: delta,
                type: delta > 0 ? "purchase" : "adjustment",
                referenceId: "admin_inventory_view",
                reason: "manual_adjustment",
                notes: "Adjusted from admin inventory view"
            ) { [weak self] result in
                Task { @MainActor in
                    if case .failure(let error) = result {
                        self?.errorMessage = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                    }
                }
            }
        } else {
            let docID = accessory.accessoryID
            AccessoryManager.shared().updateQuantity(qty, forAccessoryID: docID) { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.errorMessage = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                    }
                }
            }
        }
    }

    func toggleNoStock(for accessory: PetAccessory) {
        let docID = accessory.accessoryID
        let newNoStock = !accessory.noStock
        AccessoryManager.shared().setNoStock(newNoStock, forAccessoryID: docID) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                }
            }
        }

        if let branchId = BranchContextStore.shared.activeBranch?.branchID, !branchId.isEmpty {
            let currentBranchStock = PPBranchInventoryService.shared.availableStock(for: docID, fallback: accessory.quantity)
            if newNoStock && currentBranchStock > 0 {
                PPBranchInventoryService.shared.adjustStock(
                    productId: docID,
                    branchId: branchId,
                    delta: -currentBranchStock,
                    type: "adjustment",
                    referenceId: "admin_toggle_stock",
                    reason: "marked_no_stock",
                    notes: "Marked out of stock from inventory view"
                ) { [weak self] result in
                    Task { @MainActor in
                        if case .failure(let error) = result {
                            self?.errorMessage = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                        }
                    }
                }
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
    @State private var itemForStockAction: PetAccessory?
    @State private var itemForDamage: PetAccessory?
    @State private var itemForLots: PetAccessory?
    @State private var itemForQuarantine: PetAccessory?
    @State private var showingCycleCountStudio = false
    @State private var showingStockActionSheet = false

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
                PPAdminBranchSwitcherBar(style: .compact)
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.vertical, 4)
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
        .confirmationDialog(
            Language.get("Inventory_Stock_Action_Title", alter: "إدارة مخزون الصنف"),
            isPresented: $showingStockActionSheet,
            titleVisibility: .visible
        ) {
            Button(Language.get("Inventory_Action_Manage_Lots", alter: "إدارة التشغيلات والصلاحية (FEFO)")) {
                if let item = itemForStockAction {
                    itemForLots = item
                }
            }
            Button(Language.get("Inventory_Action_Quarantine_Studio", alter: "استوديو الفحص والتصرف (الحجر)")) {
                if let item = itemForStockAction {
                    itemForQuarantine = item
                }
            }
            Button(Language.get("Inventory_Action_Record_Damage", alter: "تسجيل إتلاف مخزون")) {
                if let item = itemForStockAction {
                    itemForDamage = item
                }
            }
            Button(Language.get("Inventory_Action_Cycle_Count", alter: "استوديو جرد وتسوية المخزون")) {
                showingCycleCountStudio = true
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
        }
        .fullScreenCover(item: $itemForLots) { item in
            InventoryLotsSheet(
                item: item,
                branchId: BranchContextStore.shared.activeBranch?.branchID ?? session.branchId ?? item.resolvedBranchID(),
                onLotsChanged: {
                    viewModel.startListening()
                }
            )
        }
        .fullScreenCover(item: $itemForQuarantine) { item in
            QuarantineStudioSheet(
                item: item,
                branchId: BranchContextStore.shared.activeBranch?.branchID ?? session.branchId ?? item.resolvedBranchID(),
                onResolved: {
                    viewModel.startListening()
                }
            )
        }
        .fullScreenCover(item: $itemForDamage) { item in
            DamageStockSheet(
                item: item,
                branchId: BranchContextStore.shared.activeBranch?.branchID ?? session.branchId ?? item.resolvedBranchID()
            )
        }
        .fullScreenCover(isPresented: $showingCycleCountStudio) {
            CycleCountStudioView(
                branchId: BranchContextStore.shared.activeBranch?.branchID ?? session.branchId ?? ""
            ) {
                viewModel.startListening()
            }
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
                HStack(spacing: 8) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showingCycleCountStudio = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checklist")
                                .font(.system(size: 14, weight: .bold))
                            Text(Language.get("Inventory_Action_Cycle_Count_Short", alter: "جرد وتسوية"))
                                .font(AdminFont.captionBold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Color.indigo, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.indigo.opacity(0.32), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Inventory_Action_Cycle_Count", alter: "استوديو جرد وتسوية المخزون"))

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
                value: viewModel.totalCount.englishDigits,
                symbol: "cube.box.fill",
                color: AdminSurface.primary
            )
            QuickStat(
                label: Language.get("Inventory_In_Stock", alter: "\u{0645}\u{062a}\u{0648}\u{0641}\u{0631}"),
                value: viewModel.inStockCount.englishDigits,
                symbol: "checkmark.circle.fill",
                color: .green
            )
            QuickStat(
                label: Language.get("Inventory_Low_Stock", alter: "\u{0645}\u{0646}\u{062e}\u{0641}\u{0636}"),
                value: viewModel.lowStockCount.englishDigits,
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
                placeholder: Language.get("Inventory_Search", alter: "\u{0627}\u{0628}\u{062d}\u{062b}..."),
                showBarcodeScanner: true
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
                    InventoryItemRow(
                        item: item,
                        kind: viewModel.kind,
                        onStockAction: {
                            itemForStockAction = item
                            showingStockActionSheet = true
                        },
                        onQuarantineAction: {
                            itemForQuarantine = item
                        }
                    )
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            itemForStockAction = item
                            showingStockActionSheet = true
                        } label: {
                            Label(Language.get("Inventory_Stock_Actions", alter: "المخزون"), systemImage: "shippingbox.fill")
                        }
                        .tint(.red)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            promptDeleteConfirmation(for: item)
                        } label: {
                            Label(Language.get("Delete", alter: "حذف"), systemImage: "trash.fill")
                        }

                        Button {
                            editingItem = item
                        } label: {
                            Label(Language.get("Edit", alter: "تعديل"), systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button {
                            itemForLots = item
                        } label: {
                            Label(
                                Language.get("Inventory_Action_Manage_Lots", alter: "إدارة التشغيلات والصلاحية (FEFO)"),
                                systemImage: "calendar.badge.clock"
                            )
                        }

                        Button {
                            itemForQuarantine = item
                        } label: {
                            Label(
                                Language.get("Inventory_Action_Quarantine_Studio", alter: "استوديو الفحص والتصرف (الحجر)"),
                                systemImage: "shield.lefthalf.filled"
                            )
                        }

                        Button {
                            itemForDamage = item
                        } label: {
                            Label(
                                Language.get("Inventory_Action_Record_Damage", alter: "تسجيل إتلاف مخزون"),
                                systemImage: "exclamationmark.octagon.fill"
                            )
                        }

                        Button {
                            viewModel.toggleNoStock(for: item)
                        } label: {
                            Label(
                                item.noStock
                                    ? Language.get("Inventory_Mark_In_Stock", alter: "توفر")
                                    : Language.get("Inventory_Mark_No_Stock", alter: "نفاد"),
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

    private func promptDeleteConfirmation(for item: PetAccessory) {
        let title = Language.get("Inventory_Delete_Confirm", alter: "تأكيد الحذف")
        let message = Language.get("Inventory_Delete_Message", alter: "هل أنت متأكد من حذف هذا العنصر؟")
        let vm = viewModel
        PPAlertHelper.showConfirmation(
            in: nil,
            title: title,
            subtitle: "\(message)\n(\(item.name))",
            confirmButton: Language.get("Delete", alter: "حذف"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "trash.fill"),
            confirmBlock: { [weak vm] _, didConfirm in
                guard didConfirm else { return }
                vm?.deleteItem(item)
            },
            cancelBlock: nil
        )
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
                Text(verbatim: value.normalizedEnglishDigits)
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
    var onStockAction: (() -> Void)? = nil
    var onQuarantineAction: (() -> Void)? = nil

    private var branchRecord: PPBranchInventory? {
        PPBranchInventoryService.shared.inventory(for: item.accessoryID)
    }

    private var availableStock: Int {
        PPBranchInventoryService.shared.availableStock(for: item.accessoryID, fallback: item.quantity)
    }

    private var onHandStock: Int {
        branchRecord?.onHandQuantity ?? item.quantity
    }

    private var needsAttentionCount: Int {
        branchRecord?.needsAttentionQuantity ?? 0
    }

    private var displayPrice: Double {
        PPBranchInventoryService.shared.effectiveSellingPrice(for: item.accessoryID, fallbackPrice: item.finalPrice.doubleValue)
    }

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

                HStack(spacing: 6) {
                    if let category = item.accessoryCategoryID, !category.isEmpty {
                        Text(category)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    if let sku = item.sku, !sku.isEmpty {
                        Text(verbatim: "SKU: \(sku)".normalizedEnglishDigits)
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 4))
                    }

                    if let size = item.size, !size.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "ruler.fill")
                                .font(.system(size: 8))
                            Text(size)
                                .font(AdminType.caption2Bold)
                        }
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    }
                }

                // Inventory Buckets Row: Available (Primary), On-Hand (Secondary), Needs Attention (Badge)
                HStack(spacing: AdminSpacing.sm) {
                    HStack(spacing: 3) {
                        Image(systemName: "cube.box.fill")
                            .font(.system(size: 11))
                        Text(verbatim: "\(Language.get("Inventory_Available", alter: "متوفر")): \(availableStock)".normalizedEnglishDigits)
                    }
                    .font(AdminType.caption2Bold)
                    .foregroundColor(
                        item.noStock || availableStock <= 0 ? .red :
                        availableStock <= 3 ? .orange : AdminSurface.secondaryText
                    )

                    Text(verbatim: "\(Language.get("Inventory_On_Hand", alter: "في الموقع")): \(onHandStock)".normalizedEnglishDigits)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.8))

                    if needsAttentionCount > 0 {
                        Button {
                            onQuarantineAction?()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.system(size: 10))
                                Text(verbatim: "\(needsAttentionCount)".normalizedEnglishDigits)
                            }
                            .font(AdminType.caption2Bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if item.noStock || availableStock <= 0 {
                        Text(Language.get("Inventory_No_Stock", alter: "نفاد"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.10), in: Capsule())
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: formatPrice(displayPrice).normalizedEnglishDigits)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)

                if displayPrice != item.price.doubleValue {
                    Text(verbatim: formatPrice(item.price.doubleValue).normalizedEnglishDigits)
                        .font(AdminType.caption2)
                        .foregroundColor(.green)
                        .strikethrough(false)
                }

                if let onStockAction = onStockAction {
                    Button {
                        onStockAction()
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(2)
                    }
                    .buttonStyle(.borderless)
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
                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 56, height: 56)) {
                    placeholderIcon
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
        let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f %@", value, Language.get("QAR", alter: "ر.ق"))
        return formatted.normalizedEnglishDigits
    }
}

// MARK: - Damage Stock Sheet (NextGen V6 Dual-Architecture Studio)

struct DamageStockSheet: View {
    let item: PetAccessory
    let branchId: String
    var onDamageRecorded: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var quantity: Int = 1
    @State private var selectedReason: String = "packaging_damage"
    @State private var notes: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isManualQuantityEditing: Bool = false
    @State private var manualQuantityText: String = "1"

    private var isIPadLayout: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }

    private var availableStock: Int {
        PPBranchInventoryService.shared.availableStock(for: item.accessoryID, fallback: item.quantity)
    }

    private var unitCost: Double {
        let cost = item.costPrice?.doubleValue ?? 0.0
        return cost > 0 ? cost : item.price.doubleValue
    }

    private var totalCostLoss: Double {
        Double(quantity) * unitCost
    }

    private var remainingHealthyStock: Int {
        max(0, availableStock - quantity)
    }

    private var shrinkagePercent: Double {
        guard availableStock > 0 else { return 0.0 }
        return min(100.0, (Double(quantity) / Double(availableStock)) * 100.0)
    }

    private let reasonOptions: [DamageReasonModel] = [
        DamageReasonModel(
            code: "packaging_damage",
            key: "Damage_Reason_Packaging",
            titleAlter: "تلف في التغليف",
            subtitleAlter: "علبة ممزقة أو غلاف متضرر غير صالح للعرض",
            icon: "shippingbox.and.arrow.backward.fill",
            badgeColor: .orange
        ),
        DamageReasonModel(
            code: "product_damage",
            key: "Damage_Reason_Product",
            titleAlter: "تلف في المنتج",
            subtitleAlter: "كسر، تسريب، تشوه، أو عطب مباشر بالصنف",
            icon: "exclamationmark.triangle.fill",
            badgeColor: AdminSurface.crimson
        ),
        DamageReasonModel(
            code: "manufacturing_defect",
            key: "Damage_Reason_Defect",
            titleAlter: "عيب مصنعي",
            subtitleAlter: "خلل تقني أو عدم مطابقة لمواصفات المصنع",
            icon: "gearshape.badge.exclamationmark",
            badgeColor: .purple
        ),
        DamageReasonModel(
            code: "handling_damage",
            key: "Damage_Reason_Handling",
            titleAlter: "تلف أثناء المناولة",
            subtitleAlter: "سقوط أو اصطدام أثناء النقل والترتيب",
            icon: "arrow.up.and.down.and.sparkles",
            badgeColor: .blue
        ),
        DamageReasonModel(
            code: "other",
            key: "Damage_Reason_Other",
            titleAlter: "أسباب استثنائية أخرى",
            subtitleAlter: "سبب خاص يتم تفصيله بدقة في تقرير الملاحظات",
            icon: "doc.text.magnifyingglass",
            badgeColor: AdminSurface.secondaryText
        )
    ]

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdminSurface.background
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }

                DamageKeyboardDismissOverlay()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)

                if isIPadLayout {
                    // iPad 2-Column Split Studio
                    HStack(alignment: .top, spacing: AdminSpacing.lg) {
                        // Left Column (42%): Telemetry & Quarantine Pass Cockpit
                        ScrollView {
                            IPadDamageDispositionCockpit(
                                item: item,
                                branchId: branchId,
                                availableStock: availableStock,
                                quantity: quantity,
                                unitCost: unitCost,
                                totalCostLoss: totalCostLoss,
                                remainingStock: remainingHealthyStock,
                                shrinkagePercent: shrinkagePercent,
                                selectedReason: selectedReasonModel
                            )
                            .padding(.top, AdminSpacing.md)
                            .padding(.bottom, AdminSpacing.xl)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .frame(maxWidth: .infinity)

                        // Vertical Divider
                        Rectangle()
                            .fill(AdminSurface.hairline)
                            .frame(width: 1)
                            .ignoresSafeArea(edges: .vertical)

                        // Right Column (58%): Precision Intake Deck
                        ScrollView {
                            VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                                intakeFormFields
                                submitButton
                                    .padding(.top, AdminSpacing.sm)
                            }
                            .padding(AdminSpacing.lg)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, AdminSpacing.md)
                } else {
                    // iPhone Fluid Tactical Flow
                    ScrollView {
                        VStack(alignment: .leading, spacing: AdminSpacing.base) {
                            // Hero Impact Card
                            DamageHeroImpactCard(
                                item: item,
                                availableStock: availableStock,
                                quantity: quantity,
                                unitCost: unitCost,
                                totalCostLoss: totalCostLoss,
                                remainingStock: remainingHealthyStock,
                                shrinkagePercent: shrinkagePercent
                            )
                            .padding(.top, AdminSpacing.xs)

                            intakeFormFields
                        }
                        .padding(AdminSpacing.screenMargin)
                        .padding(.bottom, 90) // Room for sticky bottom bar
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) {
                        iphoneFloatingActionBar
                    }
                }
            }
            .navigationTitle(Language.get("Damage_Sheet_Title", alter: "تسجيل إتلاف مخزون"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .foregroundColor(AdminSurface.primary)
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if availableStock > 0 {
                        Button {
                            selectAllStock()
                        } label: {
                            Text(Language.get("Damage_Max", alter: "الكل"))
                                .font(AdminType.caption1Bold)
                                .foregroundColor(AdminSurface.primary)
                        }
                        .keyboardShortcut("a", modifiers: .command)
                    }
                }
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    private var selectedReasonModel: DamageReasonModel {
        reasonOptions.first { $0.code == selectedReason } ?? reasonOptions[0]
    }

    private func selectAllStock() {
        guard availableStock > 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        quantity = availableStock
        manualQuantityText = "\(quantity)"
    }

    // MARK: - Subviews & Form Fields

    @ViewBuilder
    private var intakeFormFields: some View {
        // Section 1: Quantity Controller & Quick Batch Chips
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Language.get("Damage_Quantity_Title", alter: "الكمية التالفة *"))
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Text("المتاح للصرف: \(availableStock) وحدة")
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            // Primary Tactile Stepper
            HStack(spacing: AdminSpacing.md) {
                Button {
                    if quantity > 1 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        quantity -= 1
                        manualQuantityText = "\(quantity)"
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(quantity > 1 ? AdminSurface.crimson : AdminSurface.secondaryText.opacity(0.25))
                }
                .disabled(quantity <= 1)

                Spacer()

                if isManualQuantityEditing {
                    TextField("1", text: $manualQuantityText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(width: 80)
                        .onSubmit {
                            if let parsed = Int(manualQuantityText), parsed > 0 {
                                quantity = min(parsed, max(1, availableStock))
                            }
                            isManualQuantityEditing = false
                        }
                } else {
                    VStack(spacing: 2) {
                        Text(verbatim: "\(quantity)".normalizedEnglishDigits)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(AdminSurface.crimson)
                        Text(Language.get("Tap_To_Type", alter: "انقر للإدخال الرقمي"))
                            .font(.system(size: 10))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.8))
                    }
                    .frame(minWidth: 70)
                    .onTapGesture {
                        manualQuantityText = "\(quantity)"
                        isManualQuantityEditing = true
                    }
                }

                Spacer()

                Button {
                    if quantity < max(1, availableStock) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        quantity += 1
                        manualQuantityText = "\(quantity)"
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(quantity < availableStock ? AdminSurface.crimson : AdminSurface.secondaryText.opacity(0.25))
                }
                .disabled(quantity >= availableStock)
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, 10)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

            // Quick Batch Allocation Chips
            HStack(spacing: 6) {
                ForEach([1, 2, 5, 10, 25], id: \.self) { amount in
                    if amount <= availableStock {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            quantity = amount
                            manualQuantityText = "\(quantity)"
                        } label: {
                            Text("\(amount)")
                                .font(AdminType.caption1Bold)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(quantity == amount ? AdminSurface.crimson.opacity(0.12) : AdminSurface.control, in: Capsule())
                                .foregroundColor(quantity == amount ? AdminSurface.crimson : AdminSurface.primaryText)
                                .overlay(Capsule().stroke(quantity == amount ? AdminSurface.crimson : Color.clear, lineWidth: 1))
                        }
                    }
                }

                Spacer()

                if availableStock > 0 {
                    Button {
                        selectAllStock()
                    } label: {
                        Text(Language.get("Damage_Max", alter: "الكل (\(availableStock))"))
                            .font(AdminType.caption1Bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(quantity == availableStock ? AdminSurface.crimson : AdminSurface.control, in: Capsule())
                            .foregroundColor(quantity == availableStock ? .white : AdminSurface.primaryText)
                    }
                }
            }
        }

        // Section 2: Semantic Reason Cards Grid
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("Damage_Reason_Title", alter: "سبب الإتلاف والتصنيف *"))
                .font(AdminType.subheadlineBold)
                .foregroundColor(AdminSurface.primaryText)

            VStack(spacing: 8) {
                ForEach(reasonOptions) { option in
                    let isSelected = selectedReason == option.code
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedReason = option.code
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(option.badgeColor.opacity(isSelected ? 0.20 : 0.10))
                                    .frame(width: 38, height: 38)
                                Image(systemName: option.icon)
                                    .font(.system(size: 17))
                                    .foregroundColor(option.badgeColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(Language.get(option.key, alter: option.titleAlter))
                                    .font(AdminType.subheadlineBold)
                                    .foregroundColor(isSelected ? AdminSurface.crimson : AdminSurface.primaryText)

                                Text(option.subtitleAlter)
                                    .font(AdminType.caption)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            }

                            Spacer()

                            ZStack {
                                Circle()
                                    .stroke(isSelected ? AdminSurface.crimson : AdminSurface.hairline, lineWidth: 1.5)
                                    .frame(width: 20, height: 20)
                                if isSelected {
                                    Circle()
                                        .fill(AdminSurface.crimson)
                                        .frame(width: 11, height: 11)
                                }
                            }
                        }
                        .padding(AdminSpacing.md)
                        .background(
                            isSelected ? AdminSurface.crimson.opacity(0.06) : AdminSurface.surface,
                            in: RoundedRectangle(cornerRadius: AdminRadius.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AdminRadius.card)
                                .stroke(isSelected ? AdminSurface.crimson.opacity(0.7) : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                }
            }
        }

        // Section 3: Inspection Notes & Quick Hashtags
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("Notes", alter: "ملاحظات الفحص والمعاينة (اختياري)"))
                .font(AdminType.subheadlineBold)
                .foregroundColor(AdminSurface.primaryText)

            // Quick Hashtag Tag Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["#كسر_شحن", "#تسريب_سائل", "#تلف_كرتون", "#عيب_مصنعي", "#سقوط_ترتيب"], id: \.self) { tag in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if notes.isEmpty {
                                notes = tag
                            } else if !notes.contains(tag) {
                                notes += " \(tag)"
                            }
                        } label: {
                            Text(tag)
                                .font(AdminType.caption2Bold)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(AdminSurface.control, in: Capsule())
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }
            }

            TextField(Language.get("Damage_Notes_Placeholder", alter: "اكتب تفاصيل إضافية إن وجدت..."), text: $notes, axis: .vertical)
                .lineLimit(3...5)
                .font(AdminType.body)
                .padding(AdminSpacing.md)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
        }

        if let error = errorMessage {
            AdminErrorBanner(message: error, retry: nil)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var submitButton: some View {
        Button {
            promptDamageConfirmation()
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView().tint(.white).padding(.trailing, 4)
                } else {
                    Image(systemName: "exclamationmark.octagon.fill")
                }
                Text(Language.get("Damage_Submit", alter: "تأكيد عزل التالف وتحديث المخزون"))
                    .font(AdminType.calloutBold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                canSubmit
                    ? AdminSurface.crimson
                    : AdminSurface.crimson.opacity(0.35),
                in: RoundedRectangle(cornerRadius: AdminRadius.card)
            )
            .foregroundColor(.white)
        }
        .disabled(!canSubmit || isSubmitting)
        .keyboardShortcut("s", modifiers: .command)
    }

    private var canSubmit: Bool {
        quantity > 0 && availableStock > 0 && quantity <= availableStock
    }

    @ViewBuilder
    private var iphoneFloatingActionBar: some View {
        VStack(spacing: 8) {
            submitButton
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            AdminSurface.background.opacity(0.88)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    private func promptDamageConfirmation() {
        guard canSubmit else { return }
        let formatStr = Language.get("Damage_Confirm_Subtitle_Format", alter: "هل أنت متأكد من استبعاد وتوثيق إتلاف %d وحدات من هذا الصنف ونقلها إلى التوالف؟")
        let subtitleText = String(format: formatStr, quantity)
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("Damage_Confirm_Title", alter: "تأكيد تسجيل إتلاف المخزون"),
            subtitle: subtitleText,
            confirmButton: Language.get("Damage_Confirm_Action", alter: "تأكيد الإتلاف"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "exclamationmark.triangle.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                self.submitDamage()
            },
            cancelBlock: nil
        )
    }

    private func submitDamage() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil

        PPBranchInventoryService.shared.recordDamage(
            productId: item.accessoryID,
            branchId: branchId,
            quantity: quantity,
            reasonCode: selectedReason,
            notes: notes
        ) { result in
            isSubmitting = false
            switch result {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                PPAlertHelper.showSuccess(
                    in: nil,
                    title: Language.get("Damage_Success_Title", alter: "تم تسجيل الإتلاف بنجاح"),
                    subtitle: Language.get("Damage_Success_Subtitle", alter: "تم عزل الكمية ونقلها إلى سجل التوالف بنجاح")
                )
                onDamageRecorded?()
                dismiss()
            case .failure(let error):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                let errorMsg = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                errorMessage = errorMsg
                PPAlertHelper.showError(
                    in: nil,
                    title: Language.get("Error", alter: "خطأ"),
                    subtitle: errorMsg
                )
            }
        }
    }
}

// MARK: - Keyboard Dismiss Overlay

private struct DamageKeyboardDismissOverlay: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private var dismissTap: UITapGestureRecognizer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            setupTap()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setupTap()
        }

        private func setupTap() {
            guard dismissTap == nil, let hostView = parent?.view else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            hostView.addGestureRecognizer(tap)
            dismissTap = tap
        }

        @objc private func handleTap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var current = touch.view
            while let v = current {
                if v is UITextField || v is UITextView {
                    return false
                }
                current = v.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

// MARK: - Reason Model

private struct DamageReasonModel: Identifiable {
    let code: String
    let key: String
    let titleAlter: String
    let subtitleAlter: String
    let icon: String
    let badgeColor: Color
    var id: String { code }
}

// MARK: - Hero Impact Card

private struct DamageHeroImpactCard: View {
    let item: PetAccessory
    let availableStock: Int
    let quantity: Int
    let unitCost: Double
    let totalCostLoss: Double
    let remainingStock: Int
    let shrinkagePercent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Row: Product Identity & Isolation Tag
            HStack(alignment: .top, spacing: 10) {
                if let urlStr = item.imageURLsArray.first, let url = URL(string: urlStr) {
                    AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 52, height: 52)) {
                        Color.gray.opacity(0.1)
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AdminSurface.crimson.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 22))
                            .foregroundColor(AdminSurface.crimson)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(AdminType.headlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text("المتاح: \(availableStock) وحدة")
                            .font(AdminType.captionBold)
                            .foregroundColor(availableStock > 0 ? AdminSurface.emerald : AdminSurface.crimson)

                        if let sku = item.sku, !sku.isEmpty {
                            Text("• SKU: \(sku)")
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }

                Spacer()

                // Isolation Tag
                HStack(spacing: 4) {
                    Circle()
                        .fill(AdminSurface.crimson)
                        .frame(width: 6, height: 6)
                    Text("عزل فوري")
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.crimson)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AdminSurface.crimson.opacity(0.12), in: Capsule())
            }

            Divider().background(AdminSurface.hairline)

            // Shrinkage Progress Bar
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("أثر الإتلاف على المخزون:")
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text(String(format: "-%d وحدة (%.1f%%)", quantity, shrinkagePercent))
                        .font(AdminType.caption1Bold)
                        .foregroundColor(AdminSurface.crimson)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AdminSurface.emerald.opacity(0.3))
                            .frame(height: 6)

                        Capsule()
                            .fill(AdminSurface.crimson)
                            .frame(width: max(6, geo.size.width * CGFloat(min(1.0, shrinkagePercent / 100.0))), height: 6)
                    }
                }
                .frame(height: 6)
            }

            // Bottom Telemetry Pills
            HStack(spacing: 8) {
                // Remaining Stock Pill
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AdminSurface.emerald)
                    Text("المتبقي السليم: \(remainingStock)")
                        .font(AdminType.caption1Bold)
                        .foregroundColor(AdminSurface.primaryText)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AdminSurface.control, in: Capsule())

                Spacer()

                // Total Loss Pill
                if totalCostLoss > 0 {
                    HStack(spacing: 4) {
                        Text("الخسارة:")
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(String(format: "-%.2f ر.ق", totalCostLoss))
                            .font(AdminType.caption1Bold)
                            .foregroundColor(AdminSurface.crimson)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AdminSurface.crimson.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
    }
}

// MARK: - iPad Disposition Cockpit

private struct IPadDamageDispositionCockpit: View {
    let item: PetAccessory
    let branchId: String
    let availableStock: Int
    let quantity: Int
    let unitCost: Double
    let totalCostLoss: Double
    let remainingStock: Int
    let shrinkagePercent: Double
    let selectedReason: DamageReasonModel

    var body: some View {
        VStack(spacing: AdminSpacing.md) {
            // Master Hero Card
            DamageHeroImpactCard(
                item: item,
                availableStock: availableStock,
                quantity: quantity,
                unitCost: unitCost,
                totalCostLoss: totalCostLoss,
                remainingStock: remainingStock,
                shrinkagePercent: shrinkagePercent
            )

            // Financial Write-Off Matrix Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("مصفوفة الهدر المالي والمحاسبي", systemImage: "chart.pie.fill")
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Spacer()
                    Text("عزل \(quantity) قطعة")
                        .font(AdminType.caption1Bold)
                        .foregroundColor(AdminSurface.crimson)
                }

                Divider().background(AdminSurface.hairline)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("إجمالي قيمة الخسارة")
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(String(format: "-%.2f ر.ق", totalCostLoss))
                            .font(AdminType.title3Bold)
                            .foregroundColor(AdminSurface.crimson)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("نسبة الهدر من المخزون")
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(String(format: "%.1f%%", shrinkagePercent))
                            .font(AdminType.title3Bold)
                            .foregroundColor(.orange)
                    }
                }

                if unitCost > 0 {
                    HStack {
                        Text("تكلفة الوحدة المعتمدة: \(String(format: "%.2f ر.ق", unitCost))")
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                        Spacer()
                    }
                }
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

            // Warehouse Routing Protocol
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("بروتوكول عزل وتوجيه التوالف", systemImage: "arrow.triangle.swap")
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Spacer()
                }

                HStack(spacing: 10) {
                    Image(systemName: selectedReason.icon)
                        .font(.system(size: 20))
                        .foregroundColor(selectedReason.badgeColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("السبب المحدد: \(selectedReason.titleAlter)")
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(selectedReason.subtitleAlter)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
                .padding(AdminSpacing.sm)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.small))

                Text("سيتم نقل الكمية المحددة (\(quantity) وحدة) إلى وعاء التوالف (Damaged Bucket). سيتم حجبها فوراً عن شاشات الكاشير والمبيعات مع تسجيل قيد تدقيق محاسبي لفرع (\(branchId)).")
                    .font(AdminType.footnote)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineSpacing(3)
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

            Spacer()
        }
    }
}


