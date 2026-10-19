import SwiftUI
import UIKit

/// Presentation for the medicine lane of PPInventoryListView. The parent owns
/// its listener, staff session, branch projection, commands and destinations.
@MainActor
struct PPPharmacyInventorySurface<Rows: View>: View {
    @Binding var searchText: String
    @Binding var filter: InventoryFilter
    let totalCount: Int
    let resultCount: Int
    let availableCount: Int
    let lowCount: Int
    let unavailableCount: Int
    let valuation: String?
    let isLoading: Bool
    let stockConfirmed: Bool
    let hasBranch: Bool
    let branchName: String
    let errorMessage: String?
    let projectionMessage: String?
    let showsCatalogSwitcher: Bool
    let onBack: () -> Void
    let onAdd: (() -> Void)?
    let onBranch: () -> Void
    let onCycleCount: (() -> Void)?
    let onSelectCatalog: (CatalogHorizonTab) -> Void
    let onRefresh: () async -> Void
    @ViewBuilder let rows: () -> Rows

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool

    private var isStockFilter: Bool {
        [.inStock, .lowStock, .outOfStock].contains(filter)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900 && !typeSize.isAccessibilitySize
            VStack(spacing: 0) {
                navigation
                if wide {
                    HStack(alignment: .top, spacing: 32) {
                        ScrollView {
                            overview
                                .padding(.vertical, 24)
                        }
                        .frame(width: 264)
                        ScrollView {
                            catalog(showOverview: false)
                        }
                        .refreshable { await onRefresh() }
                        .scrollDismissesKeyboard(.interactively)
                    }
                    .padding(.horizontal, 32)
                } else {
                    ScrollView {
                        catalog(showOverview: true)
                            .padding(.horizontal, 20)
                    }
                    .refreshable { await onRefresh() }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .frame(maxWidth: 1320)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .tint(AdminSurface.primary)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .environment(\.locale, PPPharmacyText.locale)
        .accessibilityIdentifier("admin.pharmacy")
    }

    // MARK: Navigation keeps UIKit/Host as the sole route owner

    private var navigation: some View {
        HStack(spacing: 8) {
            backButton
            navigationIdentity
            Spacer(minLength: 4)
            toolsMenu
            if let onAdd { topAddButton(onAdd) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.backward")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(AdminSurface.control, in: Circle())
        }
        .buttonStyle(PPPharmacyPressStyle())
        .accessibilityLabel(PPPharmacyText.string("Back"))
    }

    private var navigationIdentity: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(PPPharmacyText.string("PharmacyAdmin_Title"))
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
            Text(PPPharmacyText.string("PharmacyAdmin_Workspace"))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func topAddButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.white)
                .background(AdminSurface.primary, in: Circle())
        }
        .buttonStyle(PPPharmacyPressStyle())
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel(PPPharmacyText.string("PharmacyAdmin_Add"))
        .accessibilityIdentifier("admin.pharmacy.add")
    }

    private func addButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(PPPharmacyText.string("PharmacyAdmin_Add"), systemImage: "plus")
                .font(AdminType.headline)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .foregroundStyle(Color.white)
                .background(AdminSurface.primary, in: Capsule())
        }
        .buttonStyle(PPPharmacyPressStyle())
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityIdentifier("admin.pharmacy.add.empty")
    }

    private var toolsMenu: some View {
        Menu {
            Button(PPPharmacyText.string("PharmacyAdmin_SearchAction"), systemImage: "magnifyingglass") {
                searchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            Button(PPPharmacyText.string("Refresh"), systemImage: "arrow.clockwise") {
                Task { await onRefresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(isLoading)
            Button(PPPharmacyText.string("PharmacyAdmin_ChangeBranch"), systemImage: "building.2", action: onBranch)
            if let onCycleCount {
                Button(PPPharmacyText.string("Inventory_Action_Cycle_Count"), systemImage: "checklist", action: onCycleCount)
            }
            if showsCatalogSwitcher {
                Section(PPPharmacyText.string("PharmacyAdmin_OtherCatalogs")) {
                    ForEach(CatalogHorizonTab.allCases.filter { $0 != .medicines }) { tab in
                        Button(tab.title, systemImage: tab.icon) { onSelectCatalog(tab) }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(AdminSurface.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(PPPharmacyText.string("PharmacyAdmin_WorkspaceActions"))
    }

    // MARK: Branch context and a purposeful replenishment cue

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Label(PPPharmacyText.string("PharmacyAdmin_MedicineCare"), systemImage: "pills")
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primary)
                Text(PPPharmacyText.string("PharmacyAdmin_Shelf"))
                    .font(AdminType.largeTitle)
                    .foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(PPPharmacyText.string("PharmacyAdmin_Introduction"))
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onBranch) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "building.2")
                        .font(.title3)
                        .foregroundStyle(AdminSurface.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PPPharmacyText.string("PharmacyAdmin_SelectedBranch"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(hasBranch ? branchName : PPPharmacyText.string("PharmacyAdmin_ChooseBranch"))
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(AdminSurface.hairline, lineWidth: 1) }
            }
            .buttonStyle(PPPharmacyPressStyle())
            .accessibilityHint(PPPharmacyText.string("PharmacyAdmin_BranchHint"))
            .accessibilityIdentifier("admin.pharmacy.branch")

            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        summaryNumber(totalCount, key: "PharmacyAdmin_LoadedMedicines", confirmed: catalogCountKnown)
                        summaryNumber(availableCount, key: "PharmacyAdmin_WithStock", confirmed: stockConfirmed)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        summaryNumber(totalCount, key: "PharmacyAdmin_LoadedMedicines", confirmed: catalogCountKnown)
                        summaryNumber(availableCount, key: "PharmacyAdmin_WithStock", confirmed: stockConfirmed)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(PPPharmacyText.string("PharmacyAdmin_ShelfValue"))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                    if let valuation, stockConfirmed {
                        Text(valuation)
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primaryText)
                            .environment(\.layoutDirection, .leftToRight)
                    } else {
                        Text(PPPharmacyText.string("PharmacyAdmin_ValuePending"))
                            .font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }

            if stockConfirmed && lowCount + unavailableCount > 0 {
                attentionNote
            } else if stockConfirmed && totalCount > 0 {
                Label(PPPharmacyText.string("PharmacyAdmin_NoShortages"), systemImage: "checkmark.circle")
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
    }

    private func summaryNumber(_ count: Int, key: String, confirmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(confirmed ? PPPharmacyText.number(count) : "—")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AdminSurface.primaryText)
            Text(PPPharmacyText.string(key))
                .font(AdminType.footnote)
                .foregroundStyle(AdminSurface.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var catalogCountKnown: Bool { totalCount > 0 || (!isLoading && errorMessage == nil) }

    private var attentionNote: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(PPPharmacyText.string("PharmacyAdmin_Replenishment"), systemImage: "tray.and.arrow.down")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
            if unavailableCount > 0 {
                attentionButton(.outOfStock, count: unavailableCount, key: "PharmacyAdmin_Unavailable")
            }
            if lowCount > 0 {
                attentionButton(.lowStock, count: lowCount, key: "PharmacyAdmin_RunningLow")
            }
            Text(PPPharmacyText.string("PharmacyAdmin_LowThreshold"))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
        }
        .padding(16)
        .background(AdminSurface.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(AdminSurface.primary).frame(width: 3).padding(.vertical, 20)
                .accessibilityHidden(true)
        }
    }

    private func attentionButton(_ selected: InventoryFilter, count: Int, key: String) -> some View {
        Button { selectFilter(selected) } label: {
            HStack(spacing: 12) {
                Text(PPPharmacyText.number(count))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(PPPharmacyText.string(key)).font(AdminType.body)
                Spacer(minLength: 0)
                Image(systemName: "arrow.forward").font(.body)
            }
            .foregroundStyle(AdminSurface.primaryText)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PPPharmacyPressStyle())
    }

    // MARK: Catalog, search and recoverable states

    private func catalog(showOverview: Bool) -> some View {
        LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
            if showOverview { overview.padding(.top, 24) }
            if let errorMessage {
                notice(title: PPPharmacyText.string("PharmacyAdmin_UpdateInterrupted"), message: errorMessage, retry: true)
            }
            if let projectionMessage {
                notice(title: PPPharmacyText.string("PharmacyAdmin_BalanceNotConfirmed"), message: projectionMessage, retry: hasBranch)
            }
            Section {
                if isLoading && totalCount == 0 {
                    loadingState
                } else if totalCount == 0 && errorMessage != nil {
                    statePanel(symbol: "wifi.exclamationmark", title: "PharmacyAdmin_LoadFailed", message: "PharmacyAdmin_LoadFailedHint") {
                        retryButton
                    }
                } else if totalCount == 0 {
                    statePanel(symbol: "pills", title: "PharmacyAdmin_EmptyTitle", message: "PharmacyAdmin_EmptyHint") {
                        if let onAdd { addButton(onAdd) }
                        else { Text(PPPharmacyText.string("PharmacyAdmin_ReadOnly")).font(AdminType.footnote) }
                    }
                } else if isStockFilter && !stockConfirmed {
                    statePanel(symbol: "building.2", title: "PharmacyAdmin_BalanceNotConfirmed", message: "PharmacyAdmin_FilterNeedsBranch") {
                        if hasBranch { retryButton }
                        else {
                            Button(PPPharmacyText.string("PharmacyAdmin_ChooseBranch"), action: onBranch)
                                .font(AdminType.headline).frame(minHeight: 44)
                        }
                    }
                } else if resultCount == 0 {
                    statePanel(symbol: "magnifyingglass", title: "PharmacyAdmin_NoResults", message: "PharmacyAdmin_NoResultsHint") {
                        Button(PPPharmacyText.string("PharmacyAdmin_ClearFilters")) {
                            searchText = ""
                            selectFilter(.all)
                        }
                        .font(AdminType.headline).frame(minHeight: 44)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(PPPharmacyText.string("PharmacyAdmin_Medicines"))
                            .font(AdminType.headline)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text(PPPharmacyText.number(resultCount))
                            .font(AdminType.footnote)
                            .monospacedDigit()
                    }
                    .foregroundStyle(AdminSurface.secondaryText)
                    rows()
                }
            } header: {
                searchAndFilters
                    .padding(.vertical, 12)
                    .background(AdminSurface.background)
            }
        }
        .padding(.top, showOverview ? 0 : 12)
        .padding(.bottom, 28)
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(AdminSurface.secondaryText)
                    .accessibilityHidden(true)
                TextField(PPPharmacyText.string("PharmacyAdmin_Search"), text: $searchText)
                    .font(AdminType.body)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .multilineTextAlignment(.leading)
                    .onSubmit { searchFocused = false }
                    .accessibilityIdentifier("admin.pharmacy.search")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(PPPharmacyText.string("PharmacyAdmin_ClearSearch"))
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, searchText.isEmpty ? 16 : 0)
            .frame(minHeight: 52)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(AdminSurface.hairline, lineWidth: 1) }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterButton(.all, key: "PharmacyAdmin_All", count: catalogCountKnown ? totalCount : nil)
                    filterButton(.lowStock, key: "PharmacyAdmin_RunningLow", count: stockConfirmed ? lowCount : nil)
                    filterButton(.outOfStock, key: "PharmacyAdmin_Unavailable", count: stockConfirmed ? unavailableCount : nil)
                    filterButton(.inStock, key: "PharmacyAdmin_WithStock", count: stockConfirmed ? availableCount : nil)
                    Menu {
                        ForEach(InventoryFilter.allCases.filter { ![.all, .lowStock, .outOfStock, .inStock].contains($0) }) { option in
                            Button { selectFilter(option) } label: {
                                Label(option.defaultTitle, systemImage: filter == option ? "checkmark" : option.iconName)
                            }
                        }
                    } label: {
                        Label(extraFilterSelected ? filter.defaultTitle : PPPharmacyText.string("PharmacyAdmin_MoreFilters"), systemImage: "line.3.horizontal.decrease")
                            .font(AdminType.footnoteBold)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(extraFilterSelected ? AdminSurface.primary.opacity(0.10) : AdminSurface.surface, in: Capsule())
                    }
                    .accessibilityLabel(PPPharmacyText.string("PharmacyAdmin_MoreFilters"))
                }
            }
        }
    }

    private var extraFilterSelected: Bool { ![.all, .lowStock, .outOfStock, .inStock].contains(filter) }

    private func filterButton(_ option: InventoryFilter, key: String, count: Int?) -> some View {
        let selected = filter == option
        return Button { selectFilter(option) } label: {
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                Text(PPPharmacyText.string(key))
                if let count { Text(PPPharmacyText.number(count)).monospacedDigit() }
            }
            .font(AdminType.footnoteBold)
            .foregroundStyle(selected ? Color.white : AdminSurface.primaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(selected ? AdminSurface.primary : AdminSurface.surface, in: Capsule())
            .overlay { Capsule().stroke(selected ? Color.clear : AdminSurface.hairline, lineWidth: 1) }
        }
        .buttonStyle(PPPharmacyPressStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("admin.pharmacy.filter.\(option.rawValue)")
    }

    private func selectFilter(_ selected: InventoryFilter) {
        guard filter != selected else { return }
        searchFocused = false
        UISelectionFeedbackGenerator().selectionChanged()
        // Do not animate a dense list reordering under the operator's finger.
        filter = selected
    }

    private func notice(title: String, message: String, retry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.circle")
                .font(AdminType.headline)
            Text(message).font(AdminType.footnote)
                .textSelection(.enabled)
            if retry { retryButton }
        }
        .foregroundStyle(AdminSurface.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private var retryButton: some View {
        Button { Task { await onRefresh() } } label: {
            Label(PPPharmacyText.string("PharmacyAdmin_Retry"), systemImage: "arrow.clockwise")
                .font(AdminType.headline).frame(minHeight: 44)
        }
        .disabled(isLoading)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if reduceMotion { Image(systemName: "hourglass") }
                else { ProgressView().tint(AdminSurface.primary) }
                Text(PPPharmacyText.string("PharmacyAdmin_Loading")).font(AdminType.body)
            }
            ForEach(0..<3) { _ in
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 16).frame(width: 64, height: 80)
                    VStack(alignment: .leading, spacing: 12) {
                        Capsule().frame(width: 130, height: 14)
                        Capsule().frame(maxWidth: 220).frame(height: 10)
                        Capsule().frame(width: 84, height: 10)
                    }
                }
                .foregroundStyle(AdminSurface.hairline.opacity(0.65))
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statePanel<Action: View>(symbol: String, title: String, message: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(AdminSurface.primary)
                .accessibilityHidden(true)
            Text(PPPharmacyText.string(title)).font(AdminType.title2)
                .accessibilityAddTraits(.isHeader)
            Text(PPPharmacyText.string(message)).font(AdminType.body)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
        .multilineTextAlignment(.leading)
        .foregroundStyle(AdminSurface.primaryText)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A medicine is an exact catalog record, including every sellable variant.
/// Stock and price are injected from the existing branch projection, never
/// inferred from a catalog total, expiry date, thumbnail or visibility flag.
@MainActor
struct PPPharmacyMedicineRow: View {
    let item: PetAccessory
    let quantity: Int
    let reservedQuantity: Int
    let price: NSNumber?
    let stockState: PPInventoryCellStockState
    let canManage: Bool
    /// The shared family shell already owns the medicine's name and image.
    /// Its child displays only the selected option and exact-record actions.
    var isFamilyMember: Bool = false
    let onOpen: () -> Void
    let onLots: () -> Void
    let onMore: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var title: String {
        let primary = Language.isRTL() ? item.name : (item.nameEn ?? "")
        let fallback = Language.isRTL() ? (item.nameEn ?? "") : item.name
        return !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? primary :
            (!fallback.isEmpty ? fallback : PPPharmacyText.string("PharmacyAdmin_Untitled"))
    }

    private var stockTitle: String {
        if let caption = stockState.caption { return caption }
        if item.noStock { return PPPharmacyText.string("PharmacyAdmin_SalesPaused") }
        if quantity <= 0 { return PPPharmacyText.string("PharmacyAdmin_Out") }
        if quantity <= 3 { return PPPharmacyText.string("PharmacyAdmin_RunningLow") }
        return PPPharmacyText.string("PharmacyAdmin_AvailableUnits")
    }

    private var stockSymbol: String {
        if stockState != .ready { return stockState.isBusy ? "hourglass" : "info.circle" }
        return item.noStock || quantity <= 3 ? "exclamationmark.circle" : "checkmark.circle"
    }

    private var listed: Bool { item.showInAppMarket && !item.isDisabled && !item.isBlocked && !item.isArchived }

    private var optionTitle: String {
        if let resolved = item.resolvedOptionDisplayTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !resolved.isEmpty, resolved != item.accessoryID { return resolved }
        let option = item.pos_variantDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !option.isEmpty, option != item.accessoryID { return option }
        if let colour = item.pos_variantColor, !colour.localizedName.isEmpty { return colour.localizedName }
        if let sku = item.sku?.trimmingCharacters(in: .whitespacesAndNewlines), !sku.isEmpty { return sku }
        return title
    }

    private var actionTitle: String {
        isFamilyMember && optionTitle != title
            ? [title, optionTitle].joined(separator: Language.isRTL() ? "، " : ", ") : title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                layout {
                    if !isFamilyMember { medicineImage }
                    VStack(alignment: .leading, spacing: 6) {
                        if isFamilyMember {
                            Text(PPPharmacyText.string("Inventory_Family_SelectedOption"))
                                .font(AdminType.caption)
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        Text(isFamilyMember ? optionTitle : title)
                            .font(AdminType.title3)
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let category = item.accessoryCategoryName ?? item.category, !category.isEmpty {
                            Text(category).font(AdminType.footnote)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !isFamilyMember, let variant = item.pos_smartVariantDescription, !variant.isEmpty {
                            Text(variant).font(AdminType.footnote)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(price.map { PetAccessory.formatCurrency($0) } ?? PPPharmacyText.string("Inventory_Price_Unavailable"))
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primaryText)
                            .environment(\.layoutDirection, price == nil ? (Language.isRTL() ? .rightToLeft : .leftToRight) : .leftToRight)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .padding(.top, 8)
                            .accessibilityHidden(true)
                    }
                }
                .multilineTextAlignment(.leading)
                .padding(20)
                .contentShape(Rectangle())
            }
            .buttonStyle(PPPharmacyPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(PPPharmacyText.string("PharmacyAdmin_OpenHint"))

            Divider().padding(.horizontal, 20)

            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if stockState == .ready {
                            Text(PPPharmacyText.number(max(0, quantity)))
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                        Label(stockTitle, systemImage: stockSymbol)
                            .font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if stockState == .ready && reservedQuantity > 0 {
                        Text(PPPharmacyText.format("PharmacyAdmin_Reserved", PPPharmacyText.number(reservedQuantity)))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                Label(PPPharmacyText.string(listed ? "PharmacyAdmin_Listed" : "PharmacyAdmin_NotListed"), systemImage: listed ? "eye" : "eye.slash")
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { lotsButton; Spacer(minLength: 0); moreButton }
                VStack(alignment: .leading, spacing: 8) { lotsButton; moreButton }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AdminSurface.control.opacity(0.6))
        }
        .background(isFamilyMember ? Color.clear : AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            if !isFamilyMember {
                RoundedRectangle(cornerRadius: 24).stroke(AdminSurface.hairline, lineWidth: 1).allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("admin.pharmacy.medicine.\(item.accessoryID)")
    }

    private var medicineImage: some View {
        AdminRemoteImage(url: PetAccessory.firstImageURL(for: item), contentMode: .fit, targetSize: CGSize(width: 80, height: 96)) {
            Image(systemName: "pills")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AdminSurface.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .frame(width: 80, height: 96)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    private var lotsButton: some View {
        Button(action: onLots) {
            Label(PPPharmacyText.string("PharmacyAdmin_LotsExpiry"), systemImage: "shippingbox")
                .font(AdminType.footnoteBold)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
        }
        .disabled(stockState != .ready || !canManage)
        .accessibilityHint(PPPharmacyText.string(canManage ? "PharmacyAdmin_LotsHint" : "PharmacyAdmin_LotsRequiresManage"))
    }

    private var moreButton: some View {
        Button(action: onMore) {
            Label(PPPharmacyText.string(canManage ? "PharmacyAdmin_Manage" : "PharmacyAdmin_Actions"), systemImage: "ellipsis.circle")
                .font(AdminType.footnoteBold)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
        }
        .accessibilityLabel(PPPharmacyText.format("PharmacyAdmin_ActionsFor", actionTitle))
    }
}

@MainActor
enum PPPharmacyText {
    static var locale: Locale { Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA") }
    static func string(_ key: String) -> String { Language.get(key, alter: nil) }
    static func number(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
    static func format(_ key: String, _ value: String) -> String {
        String(format: string(key), locale: locale, value)
    }
}

private struct PPPharmacyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
