//
//  POSFastSellView.swift
//  PurePetsAdmin
//
//  Quick sale screen: item search, cart builder, total display,
//  payment method picker (cash/card), submit button.
//
//  Live-pet selling follows the Console POS contract exactly: an
//  individually tracked live pet is never added by quantity. The operator
//  multi-selects the exact available ring/tag records through
//  `listLivePetInventoryUnits`, and the confirmed selection replaces the cart
//  line with its unitIds / unitPrices. The server re-verifies every unit.
//

import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox
import FirebaseFirestore
import Combine

// MARK: - Live Pet Inventory Contract

/// Mirrors the Infra/Console `LIVE_PET_INVENTORY_MODE.individual` token.
private let kPOSIndividualInventoryMode = "INDIVIDUAL_TRACKED"

// MARK: - POS Swift Diagnostic Logger Bridge

enum POSLogger {
    static func debug(_ event: String, category: String = "ui", message: String, metadata: [String: Any]? = nil) {
        PPPOSLogger.shared().logLevel(
            .debug,
            category: category,
            event: event,
            message: message,
            traceID: nil,
            durationMs: -1,
            metadata: metadata
        )
    }

    static func info(_ event: String, category: String = "ui", traceID: String? = nil, durationMs: Int = -1, message: String, metadata: [String: Any]? = nil) {
        PPPOSLogger.shared().logLevel(
            .info,
            category: category,
            event: event,
            message: message,
            traceID: traceID,
            durationMs: durationMs,
            metadata: metadata
        )
    }

    static func warn(_ event: String, category: String = "ui", traceID: String? = nil, message: String, metadata: [String: Any]? = nil) {
        PPPOSLogger.shared().logLevel(
            .warning,
            category: category,
            event: event,
            message: message,
            traceID: traceID,
            durationMs: -1,
            metadata: metadata
        )
    }

    static func error(_ event: String, category: String = "ui", traceID: String? = nil, durationMs: Int = -1, error: Error? = nil, message: String, metadata: [String: Any]? = nil) {
        var combined = metadata ?? [:]
        if let error {
            combined["errorDescription"] = error.localizedDescription
        }
        PPPOSLogger.shared().logLevel(
            .error,
            category: category,
            event: event,
            message: message,
            traceID: traceID,
            durationMs: durationMs,
            metadata: combined
        )
    }
}

private enum POSFastSellSpace {
    static let root = "pos.fastsell.root"
}

extension PetAccessory {
    /// Console parity: `isIndividuallyTrackedLiveProduct`.
    var pos_isIndividuallyTrackedLivePet: Bool {
        isLivePet && (inventoryMode?.uppercased() == kPOSIndividualInventoryMode)
    }

    /// Console parity: `isPosCatalogSellable` (per active branch).
    @MainActor
    var pos_isSellable: Bool {
        guard active && !isBlocked && !isDeleted && !isDisabled && !isArchived else { return false }
        if isLivePet {
            let activeBranch = BranchContextStore.shared.activeBranch?.branchID
            if let activeBranch, !activeBranch.isEmpty {
                let itemBranch = storeID ?? branchID ?? ""
                if !itemBranch.isEmpty && itemBranch != "main_store" && itemBranch != activeBranch {
                    return false
                }
            }
            return quantity > 0 && !noStock
        }
        let branchStock = PPBranchInventoryService.shared.availableStock(for: accessoryID, fallback: quantity)
        return branchStock > 0 && !noStock
    }

    /// The canonical catalog unit price the server validates against.
    ///
    /// `posIntegrity.canonicalCatalogUnitPrice` resolves
    /// `finalPrice ?? sellPrice ?? price`, so submitting the pre-discount
    /// `price` fails `assertPriceAssertion` for any discounted item with
    /// "Submitted unit price does not match the canonical catalog price".
    /// `finalPrice` is a computed getter that applies percent/amount discounts.
    @MainActor
    var pos_canonicalUnitPrice: Double {
        let discounted = finalPrice.doubleValue
        let base = (discounted > 0) ? discounted : price.doubleValue
        return PPBranchInventoryService.shared.effectiveSellingPrice(for: accessoryID, fallbackPrice: base)
    }
}

// MARK: - Catalog Filter Rail

/// Console parity: the POS fast-lane product type rail
/// Console parity: the POS fast-lane product type filter
/// (All / Accessories / Food / Pet Medicines / Live Pets).
enum POSCatalogFilter: String, CaseIterable, Identifiable {
    case all
    case accessories
    case food
    case medicine
    case livePets

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "POS_CatalogTypeAll"
        case .accessories: return "POS_CatalogTypeAccessories"
        case .food: return "POS_CatalogTypeFood"
        case .medicine: return "POS_CatalogTypeMedicine"
        case .livePets: return "POS_CatalogTypeLivePets"
        }
    }

    var fallbackTitle: String {
        switch self {
        case .all: return "الكل"
        case .accessories: return "إكسسوارات"
        case .food: return "طعام"
        case .medicine: return "أدوية"
        case .livePets: return "حيوانات حية"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .accessories: return "bag.fill"
        case .food: return "fork.knife"
        case .medicine: return "cross.case.fill"
        case .livePets: return "pawprint.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .all: return AdminSurface.primary
        case .accessories: return Color(uiColor: .ppQuickActionShopping)
        case .food: return Color(uiColor: .ppPremiumAccent)
        case .medicine: return Color(uiColor: .ppQuickActionServices)
        case .livePets: return Color(uiColor: .ppQuickActionAnimals)
        }
    }

    func matches(_ accessory: PetAccessory) -> Bool {
        switch self {
        case .all: return true
        case .accessories: return !accessory.isFood && !accessory.isLivePet && !accessory.isPetMedicine
        case .food: return accessory.isFood
        case .medicine: return accessory.isPetMedicine
        case .livePets: return accessory.isLivePet
        }
    }
}

// MARK: - POS Cart Item

struct POSCartItem: Identifiable, Equatable {
    let id = UUID()
    let accessory: PetAccessory
    var quantity: Int = 1

    /// Populated only for individually tracked live pets.
    var inventoryMode: String? = nil
    var unitIDs: [String] = []
    var unitRingTags: [String] = []
    var unitPrices: [[String: Any]] = []

    var isIndividuallyTracked: Bool { inventoryMode == kPOSIndividualInventoryMode }

    /// Exact-unit lines total the selected animals, never quantity × catalog price.
    @MainActor
    var lineTotal: Double {
        if isIndividuallyTracked {
            return unitPrices.reduce(0) { $0 + (($1["unitPrice"] as? Double) ?? 0) }
        }
        return accessory.pos_canonicalUnitPrice * Double(quantity)
    }

    @MainActor
    var unitPriceDisplay: Double {
        if isIndividuallyTracked {
            return quantity > 0 ? lineTotal / Double(quantity) : 0
        }
        return accessory.pos_canonicalUnitPrice
    }

    static func == (lhs: POSCartItem, rhs: POSCartItem) -> Bool {
        lhs.id == rhs.id
            && lhs.quantity == rhs.quantity
            && lhs.unitIDs == rhs.unitIDs
    }
}

// MARK: - POS Discount Models

enum POSDiscountType: String, CaseIterable, Identifiable {
    case percentage = "percentage"
    case fixedAmount = "fixed"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .percentage:
            return Language.get("POS_Discount_Percentage", alter: "نسبة مئوية (%)")
        case .fixedAmount:
            return Language.get("POS_Discount_FixedAmount", alter: "مبلغ ثابت (ر.ق)")
        }
    }
}

struct POSDiscount: Equatable {
    var type: POSDiscountType
    var value: Double // e.g. 10 for 10%, or 25 for 25 QAR

    func calculateAmount(subtotal: Double) -> Double {
        guard subtotal > 0 && value > 0 else { return 0 }
        switch type {
        case .percentage:
            let pct = min(max(value, 0), 100)
            return ((subtotal * pct / 100.0) * 100).rounded() / 100.0
        case .fixedAmount:
            return min(subtotal, (max(value, 0) * 100).rounded() / 100.0)
        }
    }

    func displayBadge(subtotal: Double) -> String {
        switch type {
        case .percentage:
            let amt = calculateAmount(subtotal: subtotal)
            let formattedAmt = String(format: "%.2f", amt)
            return "-\(formattedAmt) (\(Int(value))%)"
        case .fixedAmount:
            return "-\(String(format: "%.2f", value)) ر.ق"
        }
    }

    var isPercentage: Bool {
        type == .percentage
    }

    func displayLabel(subtotal: Double) -> String {
        displayBadge(subtotal: subtotal)
    }
}

// MARK: - Exact Animal Picker State

/// Sendable projection of `PPPOSInventoryUnit` so callable results can cross
/// into the main actor without sending a non-Sendable ObjC object.
struct POSAnimalUnit: Identifiable, Hashable, Sendable {
    let unitID: String
    let ringTag: String
    let sellingPrice: Double

    var id: String { unitID }
    var label: String { ringTag.isEmpty ? unitID : ringTag }
    var isSelectable: Bool { sellingPrice > 0 }
}

/// Sendable projection of an Objective-C/Firebase failure. The callable
/// callback can arrive off the main actor, so Foundation objects must not be
/// captured by the `@MainActor` task that updates SwiftUI state.
private struct POSSubmitFailure: Sendable {
    let productID: String
    let unitID: String
    let ringTag: String
    let domainCode: String
    let functionsCode: Int
    let serverMessage: String

    init(error: Error) {
        let nsError = error as NSError
        let details = PPPOSService.exactUnitConflictDetails(forError: error)
        productID = (details["productId"] as? String) ?? ""
        unitID = (details["unitId"] as? String) ?? ""
        ringTag = (details["ringTag"] as? String) ?? ""
        domainCode = ((details["domainCode"] as? String) ?? "").uppercased()
        functionsCode = nsError.code
        serverMessage = nsError.localizedDescription
    }
}

@MainActor
final class POSUnitPickerState: ObservableObject {
    @Published var product: PetAccessory?
    @Published var units: [POSAnimalUnit] = []
    @Published var selectedUnitIDs: [String] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var hasMore = false

    var nextCursor: String?
    private var requestID = 0

    var isPresented: Bool { product != nil }

    func selectableUnits() -> [POSAnimalUnit] {
        units.filter { $0.isSelectable }
    }

    func open(product: PetAccessory, preselected: [String]) {
        requestID += 1
        self.product = product
        units = []
        selectedUnitIDs = preselected
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        hasMore = false
        nextCursor = nil
        load(reset: true, preselected: preselected)
    }

    func close() {
        requestID += 1
        product = nil
        units = []
        selectedUnitIDs = []
        isLoading = false
        isLoadingMore = false
        errorMessage = nil
        hasMore = false
        nextCursor = nil
    }

    var selectedSubtotal: Double {
        let selectedSet = Set(selectedUnitIDs)
        return units.filter { selectedSet.contains($0.unitID) && $0.isSelectable }
            .reduce(0) { $0 + $1.sellingPrice }
    }

    var allSelectableSelected: Bool {
        let selectable = selectableUnits()
        guard !selectable.isEmpty else { return false }
        let selectedSet = Set(selectedUnitIDs)
        return selectable.allSatisfy { selectedSet.contains($0.unitID) }
    }

    func toggleSelectAll() {
        let selectable = selectableUnits()
        if allSelectableSelected {
            selectedUnitIDs.removeAll()
        } else {
            selectedUnitIDs = selectable.map { $0.unitID }
        }
        errorMessage = nil
    }

    func toggle(_ unitID: String) {
        if let index = selectedUnitIDs.firstIndex(of: unitID) {
            selectedUnitIDs.remove(at: index)
        } else {
            selectedUnitIDs.append(unitID)
        }
        errorMessage = nil
    }

    func loadMore() {
        guard hasMore, !isLoading, !isLoadingMore, nextCursor != nil else { return }
        isLoadingMore = true
        load(reset: false, preselected: selectedUnitIDs)
    }

    private func load(reset: Bool, preselected: [String]) {
        guard let productID = product?.accessoryID else { return }
        let token = requestID
        let cursor = reset ? nil : nextCursor

        PPPOSService.shared().listAvailableUnits(forProductID: productID, cursor: cursor) { [weak self] units, nextCursor, hasMore, error in
            // Project to Sendable values before crossing to the main actor.
            let projected: [POSAnimalUnit] = (units ?? []).map {
                POSAnimalUnit(unitID: $0.unitID, ringTag: $0.ringTag, sellingPrice: $0.sellingPrice)
            }
            let cursorValue = nextCursor
            let hasMoreValue = hasMore
            let failed = error != nil

            Task { @MainActor in
                guard let self, self.requestID == token else { return }
                self.isLoading = false
                self.isLoadingMore = false

                if failed {
                    self.errorMessage = Language.get("POS_ExactUnitLoadFailed", alter: "تعذر تحميل سجلات الحيوانات المتاحة.")
                    self.hasMore = false
                    return
                }

                var merged = reset ? [] : self.units
                var seen = Set(merged.map { $0.unitID })
                for unit in projected where !seen.contains(unit.unitID) {
                    merged.append(unit)
                    seen.insert(unit.unitID)
                }
                self.units = merged.sorted {
                    $0.label.localizedStandardCompare($1.label) == .orderedAscending
                }
                self.nextCursor = cursorValue
                self.hasMore = hasMoreValue && !(cursorValue ?? "").isEmpty

                // Console parity: preselections that are gone must be dropped.
                let available = Set(self.selectableUnits().map { $0.unitID })
                if !self.hasMore {
                    let kept = self.selectedUnitIDs.filter { available.contains($0) }
                    if kept.count != self.selectedUnitIDs.count {
                        self.errorMessage = Language.get("POS_ExactAnimalChanged", alter: "تغيرت سجلات الحيوانات المتاحة. راجع الاختيار المحدد قبل الدفع.")
                    }
                    self.selectedUnitIDs = kept
                } else if reset {
                    self.selectedUnitIDs = preselected.filter { available.contains($0) }
                }
            }
        }
    }
}

// MARK: - POS FastSell ViewModel

@MainActor
final class POSFastSellViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var allAccessories: [PetAccessory] = []
    @Published private(set) var cartItems: [POSCartItem] = []
    private var branchInventoryCancellable: AnyCancellable?

    init() {
        branchInventoryCancellable = PPBranchInventoryService.shared.$inventoryMap
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }
    @Published private(set) var selectedPaymentMethod: String = "cash"
    @Published var attachedCheque: PPScannedCheque? = nil
    @Published private(set) var isSubmitting = false
    @Published private(set) var isPreparingReceipt = false
    @Published var submitError: String?
    @Published private(set) var completedReceipt: POSCompletedReceipt?
    @Published private(set) var receiptNotice: String?

    /// Filter, search, and live catalog presentation states.
    @Published var catalogFilter: POSCatalogFilter = .all
    @Published var catalogSearchText: String = ""
    @Published private(set) var isCatalogLoading = true
    @Published private(set) var catalogErrorMessage: String?

    @Published var selectedCustomer: POSCustomerRecord? = nil
    @Published var appliedDiscount: POSDiscount? = nil

    func count(for filter: POSCatalogFilter) -> Int {
        allAccessories.filter { $0.pos_isSellable && filter.matches($0) }.count
    }

    func clearSelectedCustomer() {
        if let prev = selectedCustomer {
            POSLogger.info("customer.cleared", category: "customer", message: "Cleared selected customer '\(prev.name)'")
        }
        selectedCustomer = nil
        invalidateSubmissionCommand()
    }

    func applyDiscount(_ discount: POSDiscount?) {
        appliedDiscount = discount
        if let d = discount {
            POSLogger.info("discount.applied", category: "pricing", message: "Applied discount: \(d.displayLabel(subtotal: cartSubtotal)) (Amount: \(discountAmount) QAR, Final Total: \(cartTotal) QAR)", metadata: [
                "isPercent": d.isPercentage,
                "value": d.value,
                "deduction": discountAmount,
                "cartTotal": cartTotal
            ])
        } else {
            POSLogger.info("discount.cleared", category: "pricing", message: "Discount cleared from cart")
        }
        invalidateSubmissionCommand()
    }

    func clearDiscount() {
        guard appliedDiscount != nil else { return }
        appliedDiscount = nil
        POSLogger.info("discount.cleared", category: "pricing", message: "Discount cleared from cart (Total: \(cartTotal) QAR)")
        invalidateSubmissionCommand()
    }

    private var listener: (any ListenerRegistration)?
    /// Retained across an uncertain callable response so retrying the same
    /// checkout cannot create a second transaction. Any cart/payment change
    /// invalidates it and starts a new command.
    private var submissionCommandID: String?
    private var submissionCashReceived: Double?
    private var receiptRequestID: UUID?

    var searchResults: [PetAccessory] {
        var list = allAccessories
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                $0.accessoryID.lowercased().contains(q) ||
                ($0.sku?.lowercased().contains(q) ?? false) ||
                ($0.barcode?.lowercased().contains(q) ?? false)
            }
        }
        list.sort { a, b in
            let dateA = a.createdAt
            let dateB = b.createdAt
            if dateA != dateB {
                return dateA > dateB
            }
            return a.accessoryID > b.accessoryID
        }
        return list
    }

    /// Sellable, type-filtered catalog for the footer quick-add grid (ordered newest first).
    var catalogResults: [PetAccessory] {
        var list = allAccessories.filter { $0.pos_isSellable && catalogFilter.matches($0) }
        let q = catalogSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                $0.accessoryID.lowercased().contains(q) ||
                ($0.sku?.lowercased().contains(q) ?? false) ||
                ($0.barcode?.lowercased().contains(q) ?? false)
            }
        }
        list.sort { a, b in
            let dateA = a.createdAt
            let dateB = b.createdAt
            if dateA != dateB {
                return dateA > dateB
            }
            return a.accessoryID > b.accessoryID
        }
        return list
    }

    var cartSubtotal: Double {
        let sum = cartItems.reduce(0) { $0 + $1.lineTotal }
        return (sum * 100).rounded() / 100.0
    }

    var discountAmount: Double {
        guard let discount = appliedDiscount else { return 0 }
        return discount.calculateAmount(subtotal: cartSubtotal)
    }

    var cartTotal: Double {
        max(0, ((cartSubtotal - discountAmount) * 100).rounded() / 100.0)
    }

    var cartItemCount: Int {
        cartItems.reduce(0) { $0 + $1.quantity }
    }

    var isCheckoutBusy: Bool { isSubmitting || isPreparingReceipt }

    let paymentMethods: [(key: String, title: String, icon: String)] = [
        ("cash", "POS_Cash", "banknote.fill"),
        ("card", "POS_Card", "creditcard.fill"),
        ("cheque", "POS_Cheque", "doc.text.fill"),
        ("fawry", "POS_Fawry", "wallet.pass.fill"),
        ("bank_transfer", "POS_BankTransfer", "arrow.up.forward.app.fill")
    ]

    func startListening() {
        listener?.remove()
        listener = nil
        isCatalogLoading = allAccessories.isEmpty
        catalogErrorMessage = nil
        POSLogger.info("catalog.listener.started", category: "catalog", message: "Starting PetAccessory catalog listener")

        listener = AccessoryManager.shared().observeAllAccessories { [weak self] items, error in
            let projectedItems = items ?? []
            let projectedError = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }
                self.isCatalogLoading = false
                if let projectedError {
                    self.catalogErrorMessage = projectedError
                    POSLogger.error("catalog.listener.error", category: "catalog", message: "Catalog listener failed: \(projectedError)")
                    return
                }
                self.catalogErrorMessage = nil
                self.allAccessories = projectedItems.sorted { a, b in
                    let dateA = a.createdAt
                    let dateB = b.createdAt
                    if dateA != dateB {
                        return dateA > dateB
                    }
                    return a.accessoryID > b.accessoryID
                }
                let sellableCount = self.allAccessories.filter { $0.pos_isSellable }.count
                POSLogger.info("catalog.snapshot.received", category: "catalog", message: "Catalog loaded: \(self.allAccessories.count) items (\(sellableCount) sellable in active branch)", metadata: [
                    "total": self.allAccessories.count,
                    "sellable": sellableCount,
                    "branchId": BranchContextStore.shared.activeBranch?.branchID ?? "none"
                ])
            }
        }
    }

    func retryCatalog() {
        POSLogger.info("catalog.retry", category: "catalog", message: "Retrying catalog listener")
        startListening()
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func quantityInCart(for accessoryID: String) -> Int {
        cartItems.filter { $0.accessory.accessoryID == accessoryID }
            .reduce(0) { $0 + $1.quantity }
    }

    func cartIndex(for accessoryID: String) -> Int? {
        cartItems.firstIndex { $0.accessory.accessoryID == accessoryID }
    }

    /// Quantity-tracked add. Individually tracked live pets never reach here —
    /// the view routes them to the exact-animal picker instead.
    /// - Returns: `true` when the cart actually changed.
    @discardableResult
    func addToCart(_ accessory: PetAccessory) -> Bool {
        guard accessory.pos_isSellable else {
            POSLogger.warn("cart.add_rejected", category: "cart", message: "Cannot add '\(accessory.name)': not sellable in active branch", metadata: [
                "productId": accessory.accessoryID,
                "name": accessory.name
            ])
            return false
        }
        let branchStock = PPBranchInventoryService.shared.availableStock(for: accessory.accessoryID, fallback: accessory.quantity)
        if let idx = cartIndex(for: accessory.accessoryID) {
            guard cartItems[idx].quantity < branchStock else {
                POSLogger.warn("cart.add_stock_capped", category: "cart", message: "Cannot add more '\(accessory.name)': branch stock limit (\(branchStock)) reached", metadata: [
                    "productId": accessory.accessoryID,
                    "quantity": cartItems[idx].quantity,
                    "stock": branchStock
                ])
                return false
            }
            cartItems[idx].quantity += 1
            POSLogger.info("cart.quantity_incremented", category: "cart", message: "Incremented '\(accessory.name)' to \(cartItems[idx].quantity) (Subtotal: \(cartSubtotal) QAR)", metadata: [
                "productId": accessory.accessoryID,
                "quantity": cartItems[idx].quantity,
                "cartTotal": cartTotal
            ])
        } else {
            guard branchStock > 0 else { return false }
            cartItems.append(POSCartItem(accessory: accessory, quantity: 1))
            POSLogger.info("cart.item_added", category: "cart", message: "Added '\(accessory.name)' to cart (Price: \(accessory.pos_canonicalUnitPrice) QAR, Subtotal: \(cartSubtotal) QAR)", metadata: [
                "productId": accessory.accessoryID,
                "name": accessory.name,
                "unitPrice": accessory.pos_canonicalUnitPrice,
                "cartTotal": cartTotal
            ])
        }
        invalidateSubmissionCommand()
        return true
    }

    /// Console parity: the confirmed exact-animal selection replaces the line.
    func applyUnitSelection(product: PetAccessory, units: [POSAnimalUnit]) {
        guard !units.isEmpty else { return }
        let unitIDs = units.map { $0.unitID }
        let ringTags = units.map { $0.label }
        let prices: [[String: Any]] = units.map { ["unitId": $0.unitID, "unitPrice": $0.sellingPrice] }
        let lineTotal = prices.reduce(0) { $0 + (($1["unitPrice"] as? Double) ?? 0) }

        if let idx = cartIndex(for: product.accessoryID) {
            cartItems[idx].inventoryMode = kPOSIndividualInventoryMode
            cartItems[idx].unitIDs = unitIDs
            cartItems[idx].unitRingTags = ringTags
            cartItems[idx].unitPrices = prices
            cartItems[idx].quantity = unitIDs.count
        } else {
            var item = POSCartItem(accessory: product, quantity: unitIDs.count)
            item.inventoryMode = kPOSIndividualInventoryMode
            item.unitIDs = unitIDs
            item.unitRingTags = ringTags
            item.unitPrices = prices
            cartItems.append(item)
        }
        POSLogger.info("cart.exact_units_bound", category: "cart", message: "Bound \(unitIDs.count) exact live units to '\(product.name)' (Line Total: \(lineTotal) QAR)", metadata: [
            "productId": product.accessoryID,
            "unitIds": unitIDs,
            "ringTags": ringTags,
            "lineTotal": lineTotal,
            "cartTotal": cartTotal
        ])
        invalidateSubmissionCommand()
    }

    func removeFromCart(_ item: POSCartItem) {
        let previousCount = cartItems.count
        cartItems.removeAll { $0.id == item.id }
        if cartItems.count != previousCount {
            POSLogger.info("cart.item_removed", category: "cart", message: "Removed '\(item.accessory.name)' from cart", metadata: [
                "productId": item.accessory.accessoryID,
                "remainingItems": cartItems.count,
                "cartTotal": cartTotal
            ])
            invalidateSubmissionCommand()
        }
    }

    func clearCart() {
        guard !cartItems.isEmpty else { return }
        let count = cartItems.count
        let total = cartTotal
        cartItems = []
        appliedDiscount = nil
        attachedCheque = nil
        POSLogger.info("cart.cleared", category: "cart", message: "Cleared cart (\(count) items, previously \(total) QAR)")
        invalidateSubmissionCommand()
    }

    func addReservedUnitToCart(
        accessory: PetAccessory,
        unitID: String,
        ringTag: String,
        agreedPrice: Double
    ) {
        invalidateSubmissionCommand()
        if let idx = cartItems.firstIndex(where: { $0.accessory.accessoryID == accessory.accessoryID && $0.isIndividuallyTracked }) {
            var existing = cartItems[idx]
            if !existing.unitIDs.contains(unitID) {
                existing.unitIDs.append(unitID)
                existing.unitRingTags.append(ringTag)
                existing.unitPrices.append(["unitId": unitID, "unitPrice": agreedPrice])
                existing.quantity = existing.unitIDs.count
                cartItems[idx] = existing
            }
        } else {
            let item = POSCartItem(
                accessory: accessory,
                quantity: 1,
                inventoryMode: kPOSIndividualInventoryMode,
                unitIDs: [unitID],
                unitRingTags: [ringTag],
                unitPrices: [["unitId": unitID, "unitPrice": agreedPrice]]
            )
            cartItems.append(item)
        }
        POSLogger.info("cart.reserved_unit_added", category: "cart", message: "Added reserved unit '\(ringTag.isEmpty ? unitID : ringTag)' for '\(accessory.name)' (Agreed: \(agreedPrice) QAR)", metadata: [
            "productId": accessory.accessoryID,
            "unitId": unitID,
            "ringTag": ringTag,
            "agreedPrice": agreedPrice
        ])
    }

    func increaseQuantity(_ item: POSCartItem) {
        guard let idx = cartItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard !cartItems[idx].isIndividuallyTracked else { return }
        let branchStock = PPBranchInventoryService.shared.availableStock(for: cartItems[idx].accessory.accessoryID, fallback: cartItems[idx].accessory.quantity)
        guard cartItems[idx].quantity < branchStock else { return }
        cartItems[idx].quantity += 1
        POSLogger.info("cart.quantity_increased", category: "cart", message: "Increased '\(item.accessory.name)' quantity to \(cartItems[idx].quantity)", metadata: [
            "productId": item.accessory.accessoryID,
            "quantity": cartItems[idx].quantity
        ])
        invalidateSubmissionCommand()
    }

    func decreaseQuantity(_ item: POSCartItem) {
        guard let idx = cartItems.firstIndex(where: { $0.id == item.id }) else { return }
        if cartItems[idx].isIndividuallyTracked {
            // Drop the last selected animal, or the whole line.
            if cartItems[idx].unitIDs.count <= 1 {
                cartItems.remove(at: idx)
            } else {
                cartItems[idx].unitIDs.removeLast()
                if !cartItems[idx].unitRingTags.isEmpty {
                    cartItems[idx].unitRingTags.removeLast()
                }
                if !cartItems[idx].unitPrices.isEmpty {
                    cartItems[idx].unitPrices.removeLast()
                }
                cartItems[idx].quantity = cartItems[idx].unitIDs.count
            }
            POSLogger.info("cart.exact_unit_dropped", category: "cart", message: "Dropped one exact unit from '\(item.accessory.name)'", metadata: [
                "productId": item.accessory.accessoryID
            ])
            invalidateSubmissionCommand()
            return
        }
        if cartItems[idx].quantity > 1 {
            cartItems[idx].quantity -= 1
            POSLogger.info("cart.quantity_decreased", category: "cart", message: "Decreased '\(item.accessory.name)' to \(cartItems[idx].quantity)", metadata: [
                "productId": item.accessory.accessoryID,
                "quantity": cartItems[idx].quantity
            ])
        } else {
            cartItems.remove(at: idx)
            POSLogger.info("cart.item_removed", category: "cart", message: "Removed '\(item.accessory.name)' from cart", metadata: [
                "productId": item.accessory.accessoryID
            ])
        }
        invalidateSubmissionCommand()
    }

    func selectPaymentMethod(_ paymentMethod: String) {
        guard paymentMethods.contains(where: { $0.key == paymentMethod }) else { return }
        guard selectedPaymentMethod != paymentMethod else { return }
        let previous = selectedPaymentMethod
        selectedPaymentMethod = paymentMethod
        POSLogger.info("payment.method_changed", category: "payment", message: "Switched payment method from \(previous) to \(paymentMethod)")
        invalidateSubmissionCommand()
    }

    private func localizedSubmitFailure(_ failure: POSSubmitFailure) -> String {
        switch failure.domainCode {
        case "POS_INSUFFICIENT_BRANCH_STOCK":
            return Language.get(
                "POS_BranchStockUnavailable",
                alter: "مخزون الفرع غير كافٍ أو لم تتم مزامنته بعد. حدّث المخزون أو اختر فرعًا آخر ثم أعد المحاولة."
            )
        case "POS_INSUFFICIENT_STOCK":
            return Language.get(
                "POS_StockChanged",
                alter: "تغيّرت الكمية المتاحة لهذا العنصر. حدّث المنتجات ثم أعد المحاولة."
            )
        case "POS_PRODUCT_NOT_FOUND":
            return Language.get(
                "POS_ProductUnavailable",
                alter: "لم يعد أحد عناصر السلة متاحًا. حدّث المنتجات وأعد اختيار العنصر."
            )
        default:
            break
        }

        let message = failure.serverMessage.lowercased()
        if message.contains("customer reservation fields require pending status") {
            return Language.get(
                "POS_BackendSyncRequired",
                alter: "تعذر مزامنة بيانات الفرع مع خدمة البيع. حدّث التطبيق أو تواصل مع المسؤول ثم أعد المحاولة."
            )
        }
        switch failure.functionsCode {
        case 7:
            return Language.get(
                "POS_CheckoutPermissionDenied",
                alter: "ليست لديك صلاحية إتمام البيع في هذا الفرع. اختر فرعًا مسموحًا أو اطلب الصلاحية."
            )
        case 14:
            return Language.get(
                "POS_CheckoutNetworkUnavailable",
                alter: "تعذر الوصول إلى خدمة البيع. تحقق من الاتصال ثم أعد المحاولة؛ لن يتكرر البيع عند إعادة المحاولة."
            )
        case 16:
            return Language.get(
                "POS_CheckoutSessionExpired",
                alter: "انتهت جلسة تسجيل الدخول. سجّل الدخول مجددًا ثم أعد المحاولة."
            )
        default:
            return Language.get("POS_SubmitFailed", alter: "تعذر إتمام عملية البيع. حاول مرة أخرى.")
        }
    }

    func submitOrder(cashReceived: Double? = nil) {
        guard !cartItems.isEmpty, !isCheckoutBusy, completedReceipt == nil else { return }
        isSubmitting = true
        submitError = nil
        receiptNotice = nil

        let acceptedCash = selectedPaymentMethod == "cash"
            ? max(cashReceived ?? cartTotal, cartTotal)
            : 0

        if submissionCommandID != nil, submissionCashReceived != acceptedCash {
            invalidateSubmissionCommand()
        }
        let commandID = submissionCommandID ?? generatePOSCommandID()
        submissionCommandID = commandID
        submissionCashReceived = acceptedCash

        let items: [[String: Any]] = cartItems.map { item in
            var payload: [String: Any] = [
                "itemID": item.accessory.accessoryID,
                "name": item.accessory.name,
                "price": item.unitPriceDisplay,
                "quantity": item.quantity
            ]
            if item.isIndividuallyTracked {
                payload["inventoryMode"] = kPOSIndividualInventoryMode
                payload["unitIds"] = item.unitIDs
                payload["unitPrices"] = item.unitPrices
            }
            return payload
        }

        let customerName = selectedCustomer?.name
        let customerPhone = selectedCustomer?.phone
        let posCustomerID = selectedCustomer?.id
        let activeBranchId = BranchContextStore.shared.activeBranch?.branchID

        var checkoutMetadata: [String: Any] = [
            "commandId": commandID,
            "itemsCount": items.count,
            "subtotal": cartSubtotal,
            "discount": discountAmount,
            "total": cartTotal,
            "paymentMethod": selectedPaymentMethod,
            "acceptedCash": acceptedCash,
            "branchId": activeBranchId ?? "none"
        ]
        if selectedPaymentMethod == "cheque", let cheque = attachedCheque {
            checkoutMetadata["chequeNumber"] = cheque.chequeNumber
            checkoutMetadata["chequeBank"] = cheque.bankName
            if let amount = cheque.amount {
                checkoutMetadata["chequeAmount"] = amount
            }
        }

        POSLogger.info("checkout.initiated", category: "checkout", traceID: commandID, message: "Initiating checkout: \(items.count) line items (Total: \(cartTotal) QAR via \(selectedPaymentMethod))", metadata: checkoutMetadata)

        PPPOSService.shared().submitPOSOrder(
            withItems: items,
            subtotal: cartSubtotal,
            discount: discountAmount,
            total: cartTotal,
            paymentMethod: selectedPaymentMethod,
            cashReceived: selectedPaymentMethod == "cash" ? NSNumber(value: acceptedCash) : nil,
            commandID: commandID,
            customerName: customerName,
            customerPhone: customerPhone,
            posCustomerID: posCustomerID,
            branchID: activeBranchId
        ) { [weak self] result, error in
            // Project ObjC/Foundation values before crossing into MainActor.
            let transactionID = result?.transactionID ?? ""
            let serverTotal = result?.total ?? 0
            let serverCurrency = result?.currency ?? ""
            let failure = error.map(POSSubmitFailure.init)

            Task { @MainActor in
                guard let self, self.submissionCommandID == commandID else { return }
                if let failure {
                    self.isSubmitting = false
                    POSLogger.error("checkout.failed", category: "checkout", traceID: commandID, message: "Checkout failed: \(failure.serverMessage)", metadata: [
                        "domainCode": failure.domainCode,
                        "productId": failure.productID,
                        "unitId": failure.unitID,
                        "ringTag": failure.ringTag,
                        "functionsCode": failure.functionsCode
                    ])
                    // The server names the offending animal; drop those lines so
                    // the operator reselects instead of retrying a dead unit.
                    if self.discardStaleExactUnits(
                        productID: failure.productID,
                        unitID: failure.unitID,
                        ringTag: failure.ringTag
                    ) {
                        self.invalidateSubmissionCommand()
                        self.submitError = Language.get("POS_ExactUnitRefreshNeeded", alter: "تغيّر حيوان واحد أو أكثر من الحيوانات المحددة أو لم يعد متاحًا. اختر سجلات الحيوانات مرة أخرى.")
                    } else {
                        self.submitError = self.localizedSubmitFailure(failure)
                    }
                    return
                }

                guard !transactionID.isEmpty else {
                    self.isSubmitting = false
                    POSLogger.error("checkout.missing_txnid", category: "checkout", traceID: commandID, message: "Server did not return a valid transaction ID")
                    // The server may already have committed the command. Keep
                    // its ID so Retry is idempotent instead of creating a sale.
                    self.submitError = Language.get("POS_SubmitFailed", alter: "تعذر إتمام عملية البيع. حاول مرة أخرى.")
                    return
                }

                POSLogger.info("checkout.success", category: "checkout", traceID: commandID, message: "Sale committed with txn: \(transactionID) (Total: \(serverTotal) \(serverCurrency))", metadata: [
                    "transactionId": transactionID,
                    "serverTotal": serverTotal,
                    "serverCurrency": serverCurrency,
                    "paymentMethod": self.selectedPaymentMethod
                ])

                let fallbackReceipt = POSCompletedReceipt(
                    transactionID: transactionID,
                    subtotal: self.cartSubtotal,
                    discount: self.discountAmount,
                    total: serverTotal > 0 ? serverTotal : self.cartTotal,
                    currency: serverCurrency,
                    paymentMethod: self.selectedPaymentMethod,
                    cashReceived: acceptedCash,
                    cartItems: self.cartItems,
                    customerName: customerName ?? "",
                    customerPhone: customerPhone ?? ""
                )
                NotificationCenter.default.post(name: Notification.Name("PPAccountingDataDidChangeNotification"), object: nil)
                self.invalidateSubmissionCommand()
                self.isSubmitting = false
                self.isPreparingReceipt = true
                let receiptRequestID = UUID()
                self.receiptRequestID = receiptRequestID

                // A receipt must never leave the operator trapped behind a
                // network-dependent loading state after the sale committed.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    guard let self, self.receiptRequestID == receiptRequestID else { return }
                    self.receiptRequestID = nil
                    self.isPreparingReceipt = false
                    self.receiptNotice = Language.get(
                        "POS_Receipt_PartialNotice",
                        alter: "تمت عملية البيع، لكن تعذر تحديث بعض تفاصيل الإيصال من الخادم. تم تجهيز إيصال مؤكد بالبيانات المتاحة ويمكن طباعته أو مشاركته."
                    )
                    self.completedReceipt = fallbackReceipt
                }

                PPPOSService.shared().fetchPOSReceipt(forTransactionID: transactionID) { [weak self] receipt, receiptError in
                    let authoritativeReceipt = receipt.map(POSCompletedReceipt.init(receipt:))
                    let needsFallback = receiptError != nil || authoritativeReceipt == nil

                    Task { @MainActor in
                        guard let self, self.receiptRequestID == receiptRequestID else { return }
                        self.receiptRequestID = nil
                        self.isPreparingReceipt = false
                        self.receiptNotice = needsFallback
                            ? Language.get(
                                "POS_Receipt_PartialNotice",
                                alter: "تمت عملية البيع، لكن تعذر تحديث بعض تفاصيل الإيصال من الخادم. تم تجهيز إيصال مؤكد بالبيانات المتاحة ويمكن طباعته أو مشاركته."
                            )
                            : nil
                        self.completedReceipt = authoritativeReceipt ?? fallbackReceipt
                    }
                }
            }
        }
    }

    /// Clear the completed cart only after the receipt workflow is dismissed.
    /// Keeping the accepted cart snapshot alive makes the PDF fallback safe if
    /// the authoritative transaction read is briefly unavailable.
    func acknowledgeCompletedReceipt() {
        receiptRequestID = nil
        completedReceipt = nil
        receiptNotice = nil
        cartItems = []
        searchText = ""
        attachedCheque = nil
    }

    /// Server rejected specific animals — drop those lines so the operator reselects.
    private func discardStaleExactUnits(productID: String, unitID: String, ringTag: String) -> Bool {
        guard !productID.isEmpty || !unitID.isEmpty || !ringTag.isEmpty else { return false }

        let before = cartItems.count
        cartItems.removeAll { item in
            guard item.isIndividuallyTracked else { return false }
            if !productID.isEmpty, item.accessory.accessoryID == productID { return true }
            if !unitID.isEmpty, item.unitIDs.contains(unitID) { return true }
            if !ringTag.isEmpty, item.unitRingTags.contains(ringTag) { return true }
            return false
        }
        return cartItems.count != before
    }

    private func invalidateSubmissionCommand() {
        submissionCommandID = nil
        submissionCashReceived = nil
    }

    private func generatePOSCommandID() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Qatar") ?? TimeZone.current
        let timestamp = formatter.string(from: Date())
        let entropy = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).uppercased()
        return "PPPOS-\(timestamp)\(entropy)"
    }
}

// MARK: - Fly To Cart

private struct POSFlyPayload: Identifiable {
    let id = UUID()
    let accessory: PetAccessory
    let start: CGRect
    let end: CGRect
}

/// Apple-grade toss: a ghost of the tapped tile arcs into the cart summary,
/// shrinking and fading on arrival. Driven by one animatable progress value so
/// the curve stays smooth and interruptible.
private struct POSFlyArc: ViewModifier, Animatable {
    var progress: CGFloat
    let start: CGPoint
    let end: CGPoint
    let control: CGPoint

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - (0.66 * progress))
            .opacity(progress > 0.8 ? Double((1 - progress) / 0.2) : 1)
            .rotationEffect(.degrees(Double(progress) * 12))
            .position(point(at: progress))
    }

    private func point(at t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        )
    }
}

// MARK: - POS FastSell View

struct AdminPOSFastSellView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool
    @StateObject private var viewModel = POSFastSellViewModel()
    @StateObject private var unitPicker = POSUnitPickerState()
    @ObservedObject private var branchStore = BranchContextStore.shared
    @State private var isBranchPickerVisible = false
    @State private var showsReservedLivePets = false
    @State private var showsDeepLogInspector = false
    @State private var showsCustomerPicker = false
    @State private var showsItemPicker = false
    @State private var isShowingScanner = false
    @State private var showsDiscountSheet = false
    @State private var showsCategoryLens = false
    @State private var lastScannedCode: String?
    @State private var animalSearchQuery = ""

    // Fly-to-cart choreography
    @State private var flyPayload: POSFlyPayload?
    @State private var flyProgress: CGFloat = 0
    @State private var cartAnchor: CGRect = .zero
    @State private var cartPulse: CGFloat = 1

    init(session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.session = session
        self.onDismiss = onDismiss
    }

    private func dismissKeyboard() {
        if isSearchFocused {
            isSearchFocused = false
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    var body: some View {
        NavigationView {
            posContent
                .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var posContent: some View {
        ZStack(alignment: .bottom) {
            AdminSurface.background
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }

            VStack(spacing: 0) {
                commandDeck
                catalogGrid
            }

            POSApexFlightDeck(
                viewModel: viewModel,
                currency: { formatCurrency($0) },
                cartPulse: cartPulse,
                onOpenUnitPicker: { openUnitPicker(for: $0) },
                onOpenDiscount: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showsDiscountSheet = true
                },
                onClearCart: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        viewModel.clearCart()
                    }
                }
            )

            if let payload = flyPayload {
                flyingGhost(payload)
                    .allowsHitTesting(false)
            }

            if viewModel.isCheckoutBusy {
                AdminLoadingOverlay(
                    message: viewModel.isPreparingReceipt
                        ? Language.get("POS_Receipt_Preparing", alter: "جارٍ تجهيز الإيصال...")
                        : Language.get("POS_Submitting", alter: "جارٍ إتمام البيع...")
                )
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .coordinateSpace(name: POSFastSellSpace.root)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showsCustomerPicker) {
            POSCustomerPickerSheet(
                currentSelected: viewModel.selectedCustomer,
                canCreateCustomer: session.hasPermission("pos.sell"),
                onSelect: { customer in
                    viewModel.selectedCustomer = customer
                    showsCustomerPicker = false
                }
            )
        }
        .sheet(isPresented: $showsCategoryLens) {
            POSCategoryLensSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showsDeepLogInspector) {
            POSDeepLogInspectorView()
        }
        .sheet(isPresented: $showsItemPicker) {
            itemPickerSheet
        }
        .sheet(isPresented: $showsDiscountSheet) {
            POSDiscountSheet(
                subtotal: viewModel.cartSubtotal,
                currentDiscount: viewModel.appliedDiscount,
                currency: { formatCurrency($0) },
                onApply: { discount in
                    viewModel.applyDiscount(discount)
                    showsDiscountSheet = false
                },
                onRemove: {
                    viewModel.clearDiscount()
                    showsDiscountSheet = false
                },
                onDismiss: {
                    showsDiscountSheet = false
                }
            )
        }
        .background(scannerPushLink)
        .sheet(isPresented: $showsReservedLivePets) {
            POSReservedLivePetsView(
                session: session,
                allAccessories: viewModel.allAccessories,
                onCompleteSale: { card in
                    showsReservedLivePets = false
                    if let acc = viewModel.allAccessories.first(where: { $0.accessoryID == card.productID }) {
                        viewModel.addReservedUnitToCart(
                            accessory: acc,
                            unitID: card.unitID,
                            ringTag: card.ringTag,
                            agreedPrice: card.sellingPrice
                        )
                    }
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { unitPicker.isPresented },
            set: { if !$0 { unitPicker.close() } }
        )) {
            exactAnimalPickerSheet
        }
        .sheet(item: Binding(
            get: { viewModel.completedReceipt },
            set: { if $0 == nil { viewModel.acknowledgeCompletedReceipt() } }
        )) { receipt in
            POSCompletedReceiptSheet(receipt: receipt, notice: viewModel.receiptNotice)
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
        .alert(
            Language.get("Error", alter: "خطأ"),
            isPresented: Binding(
                get: { viewModel.submitError != nil },
                set: { if !$0 { viewModel.submitError = nil } }
            )
        ) {
            Button(Language.get("OK", alter: "موافق")) {}
        } message: {
            Text(viewModel.submitError ?? "")
        }
    }

    private var scannerPushLink: some View {
        NavigationLink(
            destination: POSBarcodeScannerScreen(
                onResult: { code in
                    let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    isShowingScanner = false
                    guard !normalized.isEmpty else { return }
                    viewModel.catalogSearchText = normalized
                    lastScannedCode = normalized
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: String(
                            format: Language.get("POS_Scanner_Detected_Format", alter: "تم التقاط الرمز %@"),
                            normalized
                        )
                    )
                },
                onCancel: {
                    isShowingScanner = false
                }
            )
            .navigationBarHidden(true),
            isActive: $isShowingScanner
        ) {
            EmptyView()
        }
        .hidden()
        .accessibilityHidden(true)
    }

    // MARK: - Command Deck

    private var commandDeck: some View {
        VStack(spacing: AdminSpacing.sm) {
            commandHeaderView
            VStack(spacing: AdminSpacing.sm) {
                if isBranchPickerVisible {
                    PPAdminBranchSwitcherBar(style: .compact)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
                customerBarView
                omniSearchAndFilterBar
                commandStatusView
            }
            .padding(.horizontal, AdminSpacing.base)
        }
        .padding(.top, AdminSpacing.xs)
        .padding(.bottom, AdminSpacing.md)
        .background(AdminSurface.background)
        .overlay(
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: AdminStroke.hairline),
            alignment: .bottom
        )
    }

    private var commandHeaderView: some View {
        AdminSovereignNavigationBar(
            title: Language.get("POS_Title", alter: "بيع سريع"),
            subtitle: headerBranchSubtitle,
            statusDotColor: Color(uiColor: .ppSuccess),
            isModal: true,
            onBack: {
                dismissKeyboard()
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            HStack(spacing: 8) {
                // Show / hide branch picker pill toggle button (replaces deep pos diagnostics)
                Button {
                    dismissKeyboard()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        isBranchPickerVisible.toggle()
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isBranchPickerVisible ? Color(uiColor: .ppPrimary).opacity(0.12) : AdminSurface.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        isBranchPickerVisible
                                            ? Color(uiColor: .ppPrimary).opacity(0.4)
                                            : Color(uiColor: .ppSurfaceBorder).opacity(0.8),
                                        lineWidth: 0.8
                                    )
                            )
                        Image(systemName: isBranchPickerVisible ? "building.2.fill" : "building.2")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isBranchPickerVisible ? Color(uiColor: .ppPrimary) : AdminSurface.primaryText)
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("POS_Toggle_Branch_Picker", alter: "إظهار أو إخفاء فرع العمل"))
                .accessibilityHint(Language.get("POS_Toggle_Branch_Picker_Hint", alter: "انقر للتبديل بين إظهار وإخفاء محدد الفرع."))

                Button {
                    dismissKeyboard()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showsReservedLivePets = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(showsReservedLivePets ? Color(uiColor: .ppPrimary).opacity(0.12) : AdminSurface.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        showsReservedLivePets
                                            ? Color(uiColor: .ppPrimary).opacity(0.4)
                                            : Color(uiColor: .ppSurfaceBorder).opacity(0.8),
                                        lineWidth: 0.8
                                    )
                            )
                        Image("reservedFilled")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(Color(uiColor: .ppPrimary))
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("POS_ReservedLivePets_Button", alter: "الحيوانات المحجوزة"))
            }
        }
    }

    private var headerBranchSubtitle: String {
        let branchName = branchStore.currentBranchDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let branchCode = branchStore.activeBranch?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let codeBadge = branchCode.isEmpty ? "" : " (\(branchCode))"
        let workspace = Language.get("CommandCenter_Operations_Workspace", alter: "مساحة العمليات")

        if !branchName.isEmpty {
            return "\(branchName)\(codeBadge) • \(workspace)"
        } else {
            return "\(workspace) • \(Language.get("BranchContext_SelectBranch_Prompt", alter: "يرجى تحديد الفرع"))"
        }
    }

    // MARK: - Customer Context

    private var customerBarView: some View {
        HStack(spacing: AdminSpacing.sm) {
            Button {
                dismissKeyboard()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showsCustomerPicker = true
            } label: {
                HStack(spacing: AdminSpacing.sm) {
                    if let customer = viewModel.selectedCustomer {
                        ZStack {
                            Circle()
                                .fill(customer.avatarColor.opacity(0.16))
                                .frame(width: 38, height: 38)
                            Text(customer.initials)
                                .font(AdminType.captionBold)
                                .foregroundColor(customer.avatarColor)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text(Language.get("POS_Customer_BoundLabel", alter: "عميل السلة"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                            Text(customer.name)
                                .font(AdminType.subheadlineBold)
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)
                            Text(customer.phone)
                                .font(.system(.caption2, design: .monospaced).weight(.medium))
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                                .fill(AdminSurface.primarySoft)
                                .frame(width: 38, height: 38)
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(AdminSurface.primary)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(Language.get("POS_Customer_SelectOrAdd", alter: "تحديد أو إضافة عميل للسلة"))
                                .font(AdminType.subheadlineBold)
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(2)
                            Text(Language.get("POS_Customer_SelectHint", alter: "يفتح دليل العملاء لإرفاق عميل بهذه السلة"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: AdminSpacing.xs)

                    Image(systemName: "chevron.forward")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .padding(.horizontal, AdminSpacing.md)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                        .stroke(
                            viewModel.selectedCustomer == nil ? AdminSurface.hairline : AdminSurface.primary.opacity(0.34),
                            lineWidth: viewModel.selectedCustomer == nil ? AdminStroke.thin : AdminStroke.medium
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(customerAccessibilityLabel)
            .accessibilityHint(Language.get("POS_Customer_SelectHint", alter: "يفتح دليل العملاء لإرفاق عميل بهذه السلة"))

            if viewModel.selectedCustomer != nil {
                Button {
                    dismissKeyboard()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if reduceMotion {
                        viewModel.clearSelectedCustomer()
                    } else {
                        withAnimation(AdminAnimation.fast) {
                            viewModel.clearSelectedCustomer()
                        }
                    }
                } label: {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(width: AdminTouchTarget.minimum, height: 54)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin)
                        )
                }
                .accessibilityLabel(Language.get("POS_Customer_Remove", alter: "إزالة العميل"))
                .accessibilityHint(Language.get("POS_Customer_RemoveHint", alter: "يزيل العميل من السلة دون حذف ملفه"))
            }
        }
    }

    private var customerAccessibilityLabel: String {
        guard let customer = viewModel.selectedCustomer else {
            return Language.get("POS_Customer_SelectOrAdd", alter: "تحديد أو إضافة عميل للسلة")
        }
        return "\(Language.get("POS_Customer_Change", alter: "تغيير العميل")): \(customer.name), \(customer.phone)"
    }

    // MARK: - Catalog Command

    private var omniSearchAndFilterBar: some View {
        HStack(spacing: AdminSpacing.sm) {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSearchFocused ? AdminSurface.primary : AdminSurface.secondaryText)

                TextField(
                    searchPrompt,
                    text: $viewModel.catalogSearchText
                )
                .font(AdminType.body)
                .multilineTextAlignment(.leading)
                .foregroundColor(AdminSurface.primaryText)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit { dismissKeyboard() }
                .autocapitalization(.none)
                .disableAutocorrection(true)

                if !viewModel.catalogSearchText.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.catalogSearchText = ""
                        lastScannedCode = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundColor(AdminSurface.secondaryText)
                            .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    }
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    .accessibilityLabel(Language.get("POS_Search_Clear", alter: "مسح البحث"))
                }
            }
            .padding(.leading, AdminSpacing.md)
            .padding(.trailing, viewModel.catalogSearchText.isEmpty ? AdminSpacing.md : 0)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(
                        isSearchFocused ? AdminSurface.primary : AdminSurface.hairline,
                        lineWidth: isSearchFocused ? AdminStroke.medium : AdminStroke.thin
                    )
            )
            .shadow(
                color: isSearchFocused ? AdminSurface.primary.opacity(0.12) : .clear,
                radius: 10,
                y: 3
            )

            Button {
                dismissKeyboard()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isShowingScanner = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 52, height: 54)
                    .background(AdminSurface.primarySoft, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .stroke(AdminSurface.primary.opacity(0.24), lineWidth: AdminStroke.thin)
                    )
            }
            .accessibilityLabel(Language.get("POS_Scan_Barcode", alter: "مسح رمز المنتج"))
            .accessibilityHint(Language.get("POS_Scan_Barcode_Hint", alter: "يفتح الكاميرا للبحث برمز المنتج"))

            filterTriggerButton
        }
        .animation(reduceMotion ? nil : AdminAnimation.fast, value: viewModel.catalogSearchText.isEmpty)
        .onChange(of: viewModel.catalogSearchText) { value in
            if let lastScannedCode, value != lastScannedCode {
                self.lastScannedCode = nil
            }
        }
    }

    private var searchPrompt: String {
        if viewModel.catalogFilter == .all {
            return Language.get("POS_Search_All_Prompt", alter: "ابحث بالاسم أو المعرف في كل المنتجات...")
        }
        let category = Language.get(
            viewModel.catalogFilter.titleKey,
            alter: viewModel.catalogFilter.fallbackTitle
        )
        return String(
            format: Language.get("POS_Search_Category_Format", alter: "ابحث في %@..."),
            category
        )
    }

    private var filterTriggerButton: some View {
        Button {
            dismissKeyboard()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showsCategoryLens = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: viewModel.catalogFilter.symbol)
                    .font(.system(size: 15, weight: .bold))
                Text(Language.get(viewModel.catalogFilter.titleKey, alter: viewModel.catalogFilter.fallbackTitle))
                    .font(AdminType.caption2Bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(
                viewModel.catalogFilter == .all
                    ? AdminSurface.primaryText
                    : viewModel.catalogFilter.accentColor
            )
            .frame(minWidth: 66, minHeight: 54)
            .padding(.horizontal, AdminSpacing.xs)
            .background(
                viewModel.catalogFilter == .all
                    ? AdminSurface.control
                    : viewModel.catalogFilter.accentColor.opacity(0.13),
                in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(
                        viewModel.catalogFilter == .all
                            ? AdminSurface.hairline
                            : viewModel.catalogFilter.accentColor.opacity(0.34),
                        lineWidth: AdminStroke.thin
                    )
            )
        }
        .accessibilityLabel(Language.get("POS_FilterButton", alter: "تصفية المنتجات"))
        .accessibilityValue(Language.get(viewModel.catalogFilter.titleKey, alter: viewModel.catalogFilter.fallbackTitle))
        .accessibilityHint(Language.get("POS_CategoryLens_Hint", alter: "يفتح فئات الكتالوج المتاحة"))
    }

    @ViewBuilder
    private var commandStatusView: some View {
        if viewModel.isCatalogLoading && viewModel.allAccessories.isEmpty {
            HStack(spacing: AdminSpacing.sm) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(AdminSurface.primary)
                Text(Language.get("POS_Catalog_Loading", alter: "جارٍ مزامنة الكتالوج…"))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
            }
            .padding(.horizontal, AdminSpacing.sm)
            .frame(minHeight: 28)
            .accessibilityElement(children: .combine)
        } else if viewModel.catalogErrorMessage != nil && viewModel.allAccessories.isEmpty {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(uiColor: .ppError))
                Text(Language.get("POS_Catalog_LoadFailed", alter: "تعذر تأكيد الكتالوج المباشر"))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(2)
                Spacer(minLength: AdminSpacing.xs)
                Button {
                    viewModel.retryCatalog()
                } label: {
                    Text(Language.get("POS_Retry", alter: "إعادة المحاولة"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primary)
                        .frame(minHeight: AdminTouchTarget.minimum)
                        .padding(.horizontal, AdminSpacing.sm)
                }
            }
            .padding(.leading, AdminSpacing.sm)
            .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            .accessibilityElement(children: .contain)
        } else if let code = lastScannedCode,
                  viewModel.catalogSearchText == code,
                  viewModel.catalogResults.isEmpty {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(uiColor: .ppWarning))

                VStack(alignment: .leading, spacing: 0) {
                    Text(Language.get("POS_Scan_NoMatch_Title", alter: "لم يُعثر على منتج بهذا الرمز"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(
                        String(
                            format: Language.get(
                                "POS_Scan_NoMatch_Subtitle_Format",
                                alter: "الرمز %@ لا يطابق اسماً أو معرّفاً في الكتالوج الحالي."
                            ),
                            code
                        )
                    )
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)
                    .environment(\.layoutDirection, .leftToRight)
                }

                Spacer(minLength: AdminSpacing.xs)

                Button {
                    isShowingScanner = true
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                }
                .accessibilityLabel(Language.get("POS_Scanner_Retry", alter: "إعادة فحص الكاميرا"))
            }
            .padding(.leading, AdminSpacing.sm)
            .background(Color(uiColor: .ppWarning).opacity(0.09), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        } else if !viewModel.catalogSearchText.isEmpty || viewModel.catalogFilter != .all {
            let isScannedResult = lastScannedCode == viewModel.catalogSearchText
            HStack(spacing: AdminSpacing.xs) {
                Image(systemName: isScannedResult ? "checkmark.circle.fill" : viewModel.catalogFilter.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isScannedResult ? Color(uiColor: .ppSuccess) : viewModel.catalogFilter.accentColor)
                Text(
                    String(
                        format: Language.get("POS_Catalog_ResultCount_Format", alter: "%ld نتيجة"),
                        viewModel.catalogResults.count
                    )
                )
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)
                .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, AdminSpacing.sm)
            .frame(minHeight: 28)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var catalogGrid: some View {
        let items = viewModel.catalogResults
        if items.isEmpty {
            VStack(spacing: AdminSpacing.xs) {
                Image(systemName: "tray")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                Text(Language.get("POS_CatalogEmpty", alter: "لا توجد عناصر مطابقة"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: catalogGridColumns,
                    spacing: 8
                ) {
                    ForEach(items, id: \.accessoryID) { accessory in
                        POSCatalogTile(
                            accessory: accessory,
                            inCart: viewModel.quantityInCart(for: accessory.accessoryID),
                            currency: { formatCurrency($0) },
                            onTap: { rect in handleCatalogTap(accessory, from: rect) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, viewModel.cartItems.isEmpty ? 165 : 260)
            }
            .posScrollDismissesKeyboardCompat()
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        dismissKeyboard()
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var catalogGridColumns: [GridItem] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
        } else {
            return [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ]
        }
    }

    // MARK: - Interaction

    private func handleCatalogTap(_ accessory: PetAccessory, from rect: CGRect) {
        dismissKeyboard()
        guard !viewModel.isCheckoutBusy else { return }

        // Console parity: an individually tracked live pet must go through the
        // exact-animal picker; it is never incremented by quantity.
        if accessory.pos_isIndividuallyTrackedLivePet {
            openUnitPicker(for: accessory)
            return
        }

        let added = viewModel.addToCart(accessory)
        guard added else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        runFlyToCart(accessory: accessory, from: rect)
    }

    private func openUnitPicker(for accessory: PetAccessory) {
        let preselected = viewModel.cartIndex(for: accessory.accessoryID)
            .map { viewModel.cartItems[$0].unitIDs } ?? []
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        unitPicker.open(product: accessory, preselected: preselected)
    }

    private func confirmUnitSelection() {
        guard let product = unitPicker.product else { return }
        let selected = unitPicker.selectedUnitIDs
        guard !selected.isEmpty else {
            unitPicker.errorMessage = Language.get("POS_ExactAnimalRequired", alter: "اختر حيواناً متاحاً واحداً على الأقل قبل إضافة هذا النوع إلى السلة.")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        let byID = unitPicker.units.reduce(into: [String: POSAnimalUnit]()) { $0[$1.unitID] = $1 }
        let units = selected.compactMap { byID[$0] }.filter { $0.isSelectable }
        guard !units.isEmpty else {
            unitPicker.errorMessage = Language.get("POS_ExactAnimalChanged", alter: "تغيرت سجلات الحيوانات المتاحة. راجع الاختيار المحدد قبل الدفع.")
            return
        }
        viewModel.applyUnitSelection(product: product, units: units)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        unitPicker.close()
        pulseCart()
    }

    // MARK: - Motion

    private func runFlyToCart(accessory: PetAccessory, from rect: CGRect) {
        guard !reduceMotion, cartAnchor != .zero, rect != .zero else {
            pulseCart()
            return
        }

        flyProgress = 0
        flyPayload = POSFlyPayload(accessory: accessory, start: rect, end: cartAnchor)

        withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.58)) {
            flyProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            flyPayload = nil
            flyProgress = 0
            pulseCart()
        }
    }

    private func pulseCart() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.5)) {
            cartPulse = 1.08
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                cartPulse = 1
            }
        }
    }

    private func flyingGhost(_ payload: POSFlyPayload) -> some View {
        POSCatalogThumbnail(accessory: payload.accessory)
            .frame(width: max(payload.start.width * 0.52, 44), height: max(payload.start.width * 0.52, 44))
            .clipShape(RoundedRectangle(cornerRadius: AdminRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.medium)
                    .stroke(AdminSurface.primary.opacity(0.35), lineWidth: 1)
            )
            .modifier(
                POSFlyArc(
                    progress: flyProgress,
                    start: CGPoint(x: payload.start.midX, y: payload.start.midY),
                    end: CGPoint(x: payload.end.midX, y: payload.end.midY),
                    control: CGPoint(
                        x: (payload.start.midX + payload.end.midX) / 2,
                        y: min(payload.start.midY, payload.end.midY) - 110
                    )
                )
            )
    }

// MARK: - POS Apex Flight Deck (Reimagined Bottom Checkout Console)

private struct POSApexFlightDeck: View {
    @ObservedObject var viewModel: POSFastSellViewModel
    let currency: (Double) -> String
    let cartPulse: CGFloat
    let onOpenUnitPicker: (PetAccessory) -> Void
    let onOpenDiscount: () -> Void
    let onClearCart: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var tenderedAmount: Double? = nil
    @State private var isCustomTender: Bool = false
    @State private var showsCustomCashSheet: Bool = false
    @State private var isShowingScanner: Bool = false

    private var hasItems: Bool { !viewModel.cartItems.isEmpty }
    private var emeraldColor: Color { Color(red: 0.06, green: 0.72, blue: 0.51) }
    private var sapphireColor: Color { Color(red: 0.14, green: 0.54, blue: 0.98) }

    private func methodAccentColor(_ methodKey: String) -> Color {
        switch methodKey {
        case "cash":
            return emeraldColor
        case "card":
            return sapphireColor
        case "cheque":
            return Color(red: 0.85, green: 0.47, blue: 0.02)
        case "fawry":
            return Color(red: 0.96, green: 0.62, blue: 0.04)
        case "bank_transfer":
            return Color(red: 0.14, green: 0.54, blue: 0.92)
        default:
            return sapphireColor
        }
    }

    private var tenderSuggestions: [Double] {
        let total = viewModel.cartTotal
        guard total > 0 else { return [] }
        var list: [Double] = [total]
        let increments: [Double] = [50, 100, 200, 500, 1000]
        for inc in increments {
            if inc > total && !list.contains(inc) {
                list.append(inc)
                if list.count >= 4 { break }
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            // Cart Items Peek Bar & Drawer (when items in cart)
            if hasItems {
                cartPeekDrawer
                Divider().background(AdminSurface.hairline)
            }

            VStack(spacing: 9) {
                // 1. Fluid Segmented Payment Selector Rail
                paymentMethodSelector

                // 2. Dynamic Operational Status / Assistant Strip
                if viewModel.selectedPaymentMethod == "cash" && hasItems {
                    cashTenderAssistantStrip
                } else if viewModel.selectedPaymentMethod == "card" && hasItems {
                    cardTerminalStatusStrip
                } else if viewModel.selectedPaymentMethod == "cheque" && hasItems {
                    chequeAttachmentStrip
                } else if hasItems {
                    externalPaymentStatusStrip(for: viewModel.selectedPaymentMethod)
                }

                // 3. The Apex Charge Kinetic Button
                apexChargeButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(
            ZStack {
                AdminSurface.surface
                RadialGradient(
                    colors: [
                        methodAccentColor(viewModel.selectedPaymentMethod)
                            .opacity(colorScheme == .dark ? 0.10 : 0.04),
                        .clear
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: 220
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.10), radius: 20, x: 0, y: -6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.8 : 0.5), lineWidth: 0.75)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 16)
        .scaleEffect(cartPulse)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: POSCartAnchorKey.self,
                    value: geo.frame(in: .named(POSFastSellSpace.root))
                )
            }
        )
        .sheet(isPresented: $showsCustomCashSheet) {
            POSCustomCashSheet(
                cartTotal: viewModel.cartTotal,
                initialAmount: isCustomTender ? tenderedAmount : nil,
                currency: currency,
                onConfirm: { amount in
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        tenderedAmount = amount
                        isCustomTender = true
                    }
                    showsCustomCashSheet = false
                },
                onDismiss: {
                    showsCustomCashSheet = false
                }
            )
        }
        .fullScreenCover(isPresented: $isShowingScanner) {
            PPScannerView(
                cartTotal: viewModel.cartTotal,
                onAttach: { scannedCheque in
                    viewModel.attachedCheque = scannedCheque
                    isShowingScanner = false
                },
                onDismiss: {
                    isShowingScanner = false
                }
            )
        }
        .onChange(of: hasItems) { hasItems in
            if !hasItems {
                tenderedAmount = nil
                isCustomTender = false
            }
        }
        .onChange(of: viewModel.cartTotal) { newTotal in
            if let tendered = tenderedAmount, isCustomTender, tendered < newTotal {
                tenderedAmount = nil
                isCustomTender = false
            }
        }
    }

    // MARK: - Cart Peek Drawer

    private var cartPeekDrawer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AdminSurface.primary)

                    Text("\(viewModel.cartItemCount) \(Language.get("POS_Items", alter: "عناصر"))")
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AdminSurface.primary.opacity(0.12), in: Capsule(style: .continuous))

                // Discount Indicator & Trigger
                if viewModel.discountAmount > 0 {
                    HStack(spacing: 4) {
                        Button(action: onOpenDiscount) {
                            HStack(spacing: 4) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("-" + currency(viewModel.discountAmount))
                                    .font(AdminType.caption2Bold)
                                    .monospacedDigit()
                            }
                        }

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.clearDiscount()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(emeraldColor.opacity(0.85))
                        }
                        .accessibilityLabel(Language.get("POS_RemoveDiscount", alter: "إزالة الخصم"))
                    }
                    .foregroundColor(emeraldColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(emeraldColor.opacity(0.14), in: Capsule(style: .continuous))
                } else {
                    Button(action: onOpenDiscount) {
                        HStack(spacing: 4) {
                            Image(systemName: "tag")
                                .font(.system(size: 10, weight: .semibold))
                            Text(Language.get("POS_Discount", alter: "خصم"))
                                .font(AdminType.caption2Bold)
                        }
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AdminSurface.control, in: Capsule(style: .continuous))
                    }
                    .accessibilityLabel(Language.get("POS_AddDiscount", alter: "إضافة خصم"))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    if viewModel.discountAmount > 0 {
                        Text(currency(viewModel.cartSubtotal))
                            .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                            .strikethrough()
                            .foregroundColor(AdminSurface.secondaryText)
                            .monospacedDigit()
                    }

                    Text(currency(viewModel.cartTotal))
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .monospacedDigit()
                }

                Button(action: onClearCart) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(AdminSurface.control, in: Circle())
                }
                .accessibilityLabel(Language.get("POS_ClearCart", alter: "إفراغ السلة"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.cartItems) { item in
                        CompactCartItemChip(
                            item: item,
                            currency: currency,
                            onIncrease: {
                                if item.isIndividuallyTracked {
                                    onOpenUnitPicker(item.accessory)
                                } else {
                                    viewModel.increaseQuantity(item)
                                }
                            },
                            onDecrease: { viewModel.decreaseQuantity(item) },
                            onRemove: { viewModel.removeFromCart(item) }
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 7)
            }
        }
    }

    // MARK: - Payment Selector Horizontal Rail

    private var paymentMethodSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.paymentMethods, id: \.key) { method in
                        let isSelected = viewModel.selectedPaymentMethod == method.key
                        let accent = methodAccentColor(method.key)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.75)) {
                                viewModel.selectPaymentMethod(method.key)
                                tenderedAmount = nil
                                isCustomTender = false
                                proxy.scrollTo(method.key, anchor: .center)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: method.icon)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(
                                        isSelected
                                            ? accent
                                            : AdminSurface.secondaryText
                                    )

                                Text(Language.get(method.title, alter: method.key))
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)

                                if isSelected {
                                    Circle()
                                        .fill(accent)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .padding(.horizontal, 13)
                            .frame(minHeight: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        isSelected
                                            ? accent.opacity(colorScheme == .dark ? 0.22 : 0.12)
                                            : AdminSurface.control
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        isSelected
                                            ? accent.opacity(0.55)
                                            : Color(uiColor: .separator).opacity(0.12),
                                        lineWidth: 1.2
                                    )
                            )
                        }
                        .buttonStyle(POSTilePressStyle())
                        .id(method.key)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .onAppear {
                proxy.scrollTo(viewModel.selectedPaymentMethod, anchor: .center)
            }
        }
    }

    // MARK: - Cash Tender Strip

    private var cashTenderAssistantStrip: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(tenderSuggestions, id: \.self) { tender in
                    let isExact = tender == viewModel.cartTotal
                    let isSelected = !isCustomTender && (tenderedAmount == tender || (tenderedAmount == nil && isExact))
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            tenderedAmount = tender
                            isCustomTender = false
                        }
                    } label: {
                        Text(isExact ? Language.get("POS_Exact", alter: "مضبوط") : "\(Int(tender))")
                            .font(AdminType.caption2Bold)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                            .background(
                                isSelected ? emeraldColor : AdminSurface.control,
                                in: Capsule(style: .continuous)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(isSelected ? Color.clear : emeraldColor.opacity(0.30), lineWidth: 0.5)
                            )
                    }
                }

                // Custom Cash Received Pill
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showsCustomCashSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 9, weight: .bold))
                        Text(isCustomTender && tenderedAmount != nil
                            ? "\(Language.get("POS_Custom", alter: "مخصص")): \(formatCustomPillAmount(tenderedAmount!))"
                            : Language.get("POS_Custom", alter: "مخصص"))
                            .font(AdminType.caption2Bold)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .foregroundColor(isCustomTender ? .white : AdminSurface.primaryText)
                    .background(
                        isCustomTender ? emeraldColor : AdminSurface.control,
                        in: Capsule(style: .continuous)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(isCustomTender ? Color.clear : emeraldColor.opacity(0.30), lineWidth: 0.5)
                    )
                }

                Spacer(minLength: 2)

                if let tendered = tenderedAmount, tendered > viewModel.cartTotal {
                    let change = tendered - viewModel.cartTotal
                    HStack(spacing: 3) {
                        Text(Language.get("POS_ChangeDue", alter: "الباقي:"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(currency(change))
                            .font(AdminType.captionBold)
                            .foregroundColor(emeraldColor)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(emeraldColor.opacity(0.12), in: Capsule(style: .continuous))
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private func formatCustomPillAmount(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        } else {
            return String(format: "%.2f", value)
        }
    }

    // MARK: - Card Terminal Status Strip

    private var cardTerminalStatusStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "wave.3.forward")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(sapphireColor)
            Text(Language.get("POS_ReadyTerminal", alter: "جاهز للتمرير / الإدخال عبر جهاز نقاط البيع"))
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    // MARK: - External Payment Status Strip

    private func externalPaymentStatusStrip(for methodKey: String) -> some View {
        let accent = methodAccentColor(methodKey)
        let icon: String
        let hint: String
        switch methodKey {
        case "cheque":
            icon = "doc.text.fill"
            hint = Language.get("POS_ChequeHint", alter: "تأكد من استلام الشيك وصحة بيانات الساحب والتاريخ")
        case "fawry":
            icon = "wallet.pass.fill"
            hint = Language.get("POS_FawryHint", alter: "تأكد من تأكيد العملية عبر فوري ورقم المرجع")
        case "bank_transfer":
            icon = "arrow.up.forward.app.fill"
            hint = Language.get("POS_BankTransferHint", alter: "تأكد من وصول الحوالة البنكية لحساب المتجر")
        default:
            icon = "checkmark.shield.fill"
            hint = Language.get("POS_ExternalPaymentHint", alter: "أكد استلام المبلغ عبر المزود قبل إتمام البيع")
        }

        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accent)
            Text(hint)
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    // MARK: - Cheque Attachment Strip

    private var chequeAttachmentStrip: some View {
        let accent = methodAccentColor("cheque")
        return Group {
            if let cheque = viewModel.attachedCheque {
                // Attached Cheque Dossier Card
                HStack(spacing: 8) {
                    // Mini Cheque Snapshot
                    Image(uiImage: cheque.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 3, x: 0, y: 1)

                    // Cheque metadata
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(cheque.bankName.isEmpty ? Language.get("PPScanner_Title", alter: "شيك بنكي") : cheque.bankName)
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)

                            if let amount = cheque.amount, amount > 0 {
                                Text("• " + currency(amount))
                                    .font(AdminType.caption2Bold)
                                    .foregroundColor(accent)
                                    .monospacedDigit()
                            }
                        }

                        HStack(spacing: 4) {
                            Text(String(format: Language.get("PPScanner_AttachedChequeNumber", alter: "شيك رقم %@"), cheque.chequeNumber))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    // Green [✓ تم الإرفاق] verified badge
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(emeraldColor)
                        Text(Language.get("PPScanner_ChequeAttached", alter: "تم الإرفاق"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(emeraldColor)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(emeraldColor.opacity(colorScheme == .dark ? 0.20 : 0.12), in: Capsule(style: .continuous))

                    // Change / Re-scan action button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isShowingScanner = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                            Text(Language.get("PPScanner_ReplaceCheque", alter: "تغيير"))
                                .font(AdminType.caption2Bold)
                        }
                        .foregroundColor(AdminSurface.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AdminSurface.control, in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color(uiColor: .separator).opacity(0.20), lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(POSTilePressStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.control.opacity(colorScheme == .dark ? 0.6 : 0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 0.75)
                )
            } else {
                // Tactile Pill to Scan & Attach Cheque
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isShowingScanner = true
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(colorScheme == .dark ? 0.25 : 0.15))
                                .frame(width: 26, height: 26)

                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(accent)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(Language.get("PPScanner_ScanCheque", alter: "مسح وإرفاق الشيك"))
                                    .font(AdminType.captionBold)
                                    .foregroundColor(AdminSurface.primaryText)

                                Text("•")
                                    .font(AdminType.caption2)
                                    .foregroundColor(accent)

                                Text(Language.get("PPScanner_ChequeRequired", alter: "مطلوب لإتمام البيع"))
                                    .font(AdminType.caption2)
                                    .foregroundColor(accent)
                            }
                        }

                        Spacer(minLength: 4)

                        HStack(spacing: 4) {
                            Text(Language.get("PPScanner_ManualCapture", alter: "مسح ضوئي"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(accent)

                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(accent)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accent.opacity(colorScheme == .dark ? 0.22 : 0.12), in: Capsule(style: .continuous))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.opacity(colorScheme == .dark ? 0.14 : 0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(accent.opacity(0.40), lineWidth: 1.0)
                    )
                }
                .buttonStyle(POSTilePressStyle())
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Apex Charge Kinetic Button (Slide to Sale)

    private var apexChargeButton: some View {
        let isChequeMissing = viewModel.selectedPaymentMethod == "cheque" && viewModel.attachedCheque == nil
        return POSSlideToSaleButton(
            hasItems: hasItems,
            isCheckoutBusy: viewModel.isCheckoutBusy,
            totalAmountText: currency(viewModel.cartTotal),
            accentColor: methodAccentColor(viewModel.selectedPaymentMethod),
            onSlideComplete: {
                if isChequeMissing {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    isShowingScanner = true
                } else {
                    viewModel.submitOrder(cashReceived: tenderedAmount)
                }
            }
        )
    }
}

// MARK: - Slide to Sale Kinetic Slider

private struct POSSlideToSaleButton: View {
    let hasItems: Bool
    let isCheckoutBusy: Bool
    let totalAmountText: String
    let accentColor: Color
    let onSlideComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var isCompleted: Bool = false
    @State private var shimmerPhase: CGFloat = -0.5

    private let knobDiameter: CGFloat = 46.0
    private let trackHeight: CGFloat = 54.0
    private let horizontalPadding: CGFloat = 4.0

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let maxSlide = max(1, totalWidth - knobDiameter - (horizontalPadding * 2))
            let isRTL = Language.isRTL()
            let progress = min(1.0, max(0.0, dragOffset / maxSlide))

            ZStack(alignment: .leading) {
                // 1. Inactive / Base Track Surface
                Capsule(style: .continuous)
                    .fill(
                        hasItems
                            ? (colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                            : (colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.03))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                hasItems
                                    ? accentColor.opacity(0.28)
                                    : Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.6 : 0.3),
                                lineWidth: 1.0
                            )
                    )

                // 2. Active Illuminated Progress Fill (Follows Knob)
                if hasItems && (dragOffset > 0 || isCompleted || isCheckoutBusy) {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.30),
                                    accentColor.opacity(0.65)
                                ],
                                startPoint: isRTL ? .trailing : .leading,
                                endPoint: isRTL ? .leading : .trailing
                            )
                        )
                        .frame(width: isCheckoutBusy ? totalWidth : max(knobDiameter + (horizontalPadding * 2), dragOffset + knobDiameter + (horizontalPadding * 2)))
                }

                // 3. Center Guidance Text & Shimmering Animation
                HStack {
                    Spacer(minLength: knobDiameter + 8)

                    if isCheckoutBusy {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(accentColor)
                                .scaleEffect(0.9)
                            Text(Language.get("POS_Submitting", alter: "جارٍ إتمام العملية..."))
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)
                        }
                    } else if hasItems {
                        HStack(spacing: 6) {
                            if isRTL {
                                Image(systemName: "chevron.left.2")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(accentColor.opacity(0.8))
                                Text(Language.get("POS_SlideToSale", alter: "اسحب لإتمام عملية البيع"))
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(AdminSurface.primaryText)
                            } else {
                                Text(Language.get("POS_SlideToSale", alter: "Slide to complete sale"))
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                Image(systemName: "chevron.right.2")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(accentColor.opacity(0.8))
                            }
                        }
                        .opacity(max(0.0, 1.0 - (progress * 2.2)))
                        .mask(
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.35),
                                            Color.black,
                                            Color.black.opacity(0.35)
                                        ],
                                        startPoint: UnitPoint(x: shimmerPhase, y: 0.5),
                                        endPoint: UnitPoint(x: shimmerPhase + 0.5, y: 0.5)
                                    )
                                )
                        )
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "cart.badge.plus")
                                .font(.system(size: 13, weight: .medium))
                            Text(Language.get("POS_SelectItemsPrompt", alter: "اختر منتجات من الكتالوج للبدء"))
                                .font(AdminType.caption1Bold)
                        }
                        .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer(minLength: 8)

                    // Trailing Price Tag Pill
                    if hasItems && !isCheckoutBusy {
                        HStack(spacing: 4) {
                            Text(totalAmountText)
                                .font(AdminType.caption1Bold)
                                .monospacedDigit()
                            Image(systemName: isRTL ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(accentColor.opacity(0.9), in: Capsule(style: .continuous))
                        .opacity(max(0.0, 1.0 - (progress * 2.0)))
                        .padding(.trailing, horizontalPadding + 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 4. The Interactive Sliding Kinetic Knob
                ZStack {
                    // Knob Glow Ring when dragging
                    if isDragging {
                        Circle()
                            .fill(accentColor.opacity(0.25))
                            .frame(width: knobDiameter + 12, height: knobDiameter + 12)
                    }

                    // Knob Base Capsule
                    Circle()
                        .fill(
                            hasItems
                                ? LinearGradient(
                                    colors: [
                                        accentColor,
                                        accentColor.opacity(0.88)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [
                                        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                                        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    hasItems ? Color.white.opacity(0.4) : Color.clear,
                                    lineWidth: 1.0
                                )
                        )
                        .shadow(
                            color: hasItems ? accentColor.opacity(isDragging ? 0.5 : 0.28) : Color.clear,
                            radius: isDragging ? 10 : 5,
                            x: 0,
                            y: isDragging ? 3 : 1
                        )
                        .frame(width: knobDiameter, height: knobDiameter)

                    // Knob Icon / Status Indicator
                    if isCheckoutBusy {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: isRTL ? "arrow.left" : "arrow.right")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(hasItems ? .white : AdminSurface.secondaryText)
                    }
                }
                .padding(.leading, horizontalPadding)
                .offset(x: isRTL ? -dragOffset : dragOffset)
                .scaleEffect(isDragging ? 1.06 : 1.0)
                .animation(.spring(response: 0.24, dampingFraction: 0.75), value: isDragging)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard hasItems && !isCheckoutBusy && !isCompleted else { return }
                            if !isDragging {
                                isDragging = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            let rawDelta = isRTL ? -value.translation.width : value.translation.width
                            dragOffset = min(maxSlide, max(0, rawDelta))
                        }
                        .onEnded { value in
                            guard hasItems && !isCheckoutBusy && !isCompleted else { return }
                            isDragging = false

                            if dragOffset >= (maxSlide * 0.82) {
                                // Threshold reached -> Complete!
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                                    dragOffset = maxSlide
                                    isCompleted = true
                                }
                                onSlideComplete()
                            } else {
                                // Threshold not reached -> Spring back
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.68)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
            .frame(height: trackHeight)
            .clipShape(Capsule(style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.5
                }
            }
            .onChange(of: hasItems) { newValue in
                if !newValue {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
                        isCompleted = false
                    }
                }
            }
            .onChange(of: isCheckoutBusy) { busy in
                if !busy && isCompleted {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
                        isCompleted = false
                    }
                }
            }
        }
        .frame(height: trackHeight)
    }
}

// MARK: - POS Custom Cash Received Sheet

private struct POSCustomCashSheet: View {
    let cartTotal: Double
    let initialAmount: Double?
    let currency: (Double) -> String
    let onConfirm: (Double) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var inputText: String = ""
    @FocusState private var isFieldFocused: Bool

    private var emeraldColor: Color { Color(red: 0.06, green: 0.72, blue: 0.51) }

    private var parsedAmount: Double {
        let clean = inputText
            .replacingOccurrences(of: "٫", with: ".")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.number(from: clean)?.doubleValue ?? (Double(clean) ?? 0.0)
    }

    private var changeAmount: Double {
        max(0, parsedAmount - cartTotal)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Cart Total Summary Banner
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AdminSurface.primary.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(AdminSurface.primary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("POS_CartTotalRequired", alter: "إجمالي السلة المطلوب"))
                                .font(AdminType.caption1)
                                .foregroundColor(AdminSurface.secondaryText)
                            Text(currency(cartTotal))
                                .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title3))
                                .foregroundColor(AdminSurface.primaryText)
                                .monospacedDigit()
                        }

                        Spacer()
                    }
                    .padding(14)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline))

                    // Custom Amount Input Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Language.get("POS_CustomCashReceivedTitle", alter: "المبلغ المستلم من العميل"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)

                        HStack(spacing: 10) {
                            Image(systemName: "hand.raised.square.fill")
                                .font(.system(size: 20))
                                .foregroundColor(emeraldColor)

                            TextField(String(format: "%.2f", cartTotal), text: $inputText)
                                .font(Font.custom("Beiruti-Bold", size: 28, relativeTo: .title2))
                                .keyboardType(.decimalPad)
                                .foregroundColor(AdminSurface.primaryText)
                                .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                                .focused($isFieldFocused)

                            Text(Language.get("QAR", alter: "ر.ق"))
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.secondaryText)

                            if !inputText.isEmpty {
                                Button {
                                    inputText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(parsedAmount > 0 ? emeraldColor.opacity(0.60) : AdminSurface.hairline, lineWidth: parsedAmount > 0 ? 1.5 : 1.0)
                        )
                    }

                    // Quick Increment Buttons (+10, +20, +50, +100)
                    HStack(spacing: 8) {
                        ForEach([10, 20, 50, 100], id: \.self) { increment in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                let current = parsedAmount > 0 ? parsedAmount : cartTotal
                                let newAmount = current + Double(increment)
                                inputText = String(format: "%.0f", newAmount)
                            } label: {
                                Text("+\(increment)")
                                    .font(AdminType.captionBold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .foregroundColor(AdminSurface.primaryText)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(AdminSurface.hairline, lineWidth: 0.5)
                                    )
                            }
                        }
                    }

                    // Live Change Due or Shortfall Status
                    if parsedAmount > 0 {
                        if parsedAmount >= cartTotal {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(emeraldColor)

                                Text(Language.get("POS_CustomerChangeDue", alter: "الباقي للعميل:"))
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(AdminSurface.primaryText)

                                Spacer()

                                Text(currency(changeAmount))
                                    .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title3))
                                    .foregroundColor(emeraldColor)
                                    .monospacedDigit()
                            }
                            .padding(12)
                            .background(emeraldColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(emeraldColor.opacity(0.35), lineWidth: 0.8)
                            )
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color.orange)

                                Text(Language.get("POS_CashShortfall", alter: "المبلغ أقل من المطلوب:"))
                                    .font(AdminType.caption1)
                                    .foregroundColor(AdminSurface.secondaryText)

                                Spacer()

                                Text(currency(cartTotal - parsedAmount))
                                    .font(AdminType.captionBold)
                                    .foregroundColor(Color.orange)
                                    .monospacedDigit()
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    // Confirm Button
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let finalAmount = parsedAmount > 0 ? parsedAmount : cartTotal
                        onConfirm(finalAmount)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text(Language.get("Confirm", alter: "تأكيد"))
                                .font(AdminType.calloutBold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.white)
                        .background(
                            (parsedAmount >= cartTotal || parsedAmount == 0) ? emeraldColor : Color.gray.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                    .disabled(parsedAmount > 0 && parsedAmount < cartTotal)
                }
                .padding(AdminSpacing.screenMargin)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("POS_CustomCashTitle", alter: "مبلغ نقدي مخصص"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onDismiss()
                    } label: {
                        Text(Language.get("Close", alter: "إغلاق"))
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primary)
                    }
                }
            }
            .onAppear {
                if let initial = initialAmount, initial > 0 {
                    if initial.truncatingRemainder(dividingBy: 1) == 0 {
                        inputText = String(format: "%.0f", initial)
                    } else {
                        inputText = String(format: "%.2f", initial)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFieldFocused = true
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

    // MARK: - Add Product Sheet (preserved)

    private var itemPickerSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                AdminSearchField(
                    text: $viewModel.searchText,
                    placeholder: Language.get("POS_Search_Items", alter: "ابحث عن منتج...")
                )
                .padding()

                ScrollView {
                    LazyVStack(spacing: AdminSpacing.sm) {
                        ForEach(viewModel.searchResults, id: \.accessoryID) { accessory in
                            Button {
                                showsItemPicker = false
                                if accessory.pos_isIndividuallyTrackedLivePet {
                                    // Same live-pet contract as the catalog rail.
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        openUnitPicker(for: accessory)
                                    }
                                } else {
                                    viewModel.addToCart(accessory)
                                    pulseCart()
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(accessory.name)
                                            .font(AdminType.calloutBold)
                                            .foregroundColor(AdminSurface.primaryText)
                                        let branchStock = PPBranchInventoryService.shared.availableStock(for: accessory.accessoryID, fallback: accessory.quantity)
                                        Text(stockLabel(for: accessory))
                                            .font(AdminType.caption2)
                                            .foregroundColor(
                                                branchStock > 0 ? AdminSurface.secondaryText : .red
                                            )
                                    }
                                    Spacer()
                                    Text(formatCurrency(accessory.pos_canonicalUnitPrice))
                                        .font(AdminType.calloutBold)
                                        .foregroundColor(AdminSurface.primaryText)
                                }
                                .padding(.horizontal, AdminSpacing.base)
                                .frame(minHeight: AdminTouchTarget.minimum)
                            }
                            .disabled(!accessory.pos_isSellable)

                            if accessory.accessoryID != viewModel.searchResults.last?.accessoryID {
                                Divider().background(AdminSurface.hairline)
                                    .padding(.leading, AdminSpacing.base)
                            }
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                }
            }
            .background(AdminSurface.background)
            .navigationTitle(Language.get("POS_Add_Item", alter: "إضافة منتج"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        showsItemPicker = false
                    }
                }
            }
        }
    }

    // MARK: - POS Apex Animal Registry Sheet (Reimagined Exact Animal Selection)

    private var exactAnimalPickerSheet: some View {
        POSApexAnimalRegistrySheet(
            unitPicker: unitPicker,
            searchQuery: $animalSearchQuery,
            currency: { formatCurrency($0) },
            onConfirm: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                confirmUnitSelection()
            },
            onClose: {
                unitPicker.close()
            }
        )
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "QAR"
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f %@", value, Language.get("QAR", alter: "ر.ق"))
    }

    private func stockLabel(for accessory: PetAccessory) -> String {
        let stockTitle = Language.get("Stock", alter: "المخزون")
        let branchStock = PPBranchInventoryService.shared.availableStock(for: accessory.accessoryID, fallback: accessory.quantity)
        return "\(stockTitle): \(branchStock)"
    }
}

// MARK: - POS Apex Animal Registry Sheet Component

private struct POSApexAnimalRegistrySheet: View {
    @ObservedObject var unitPicker: POSUnitPickerState
    @Binding var searchQuery: String
    let currency: (Double) -> String
    let onConfirm: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isSearchFocused: Bool = false

    private var rosePrimary: Color { Color(red: 0.88, green: 0.12, blue: 0.32) }
    private var crimsonAccent: Color { Color(red: 0.98, green: 0.28, blue: 0.45) }
    private var emeraldReady: Color { Color(red: 0.06, green: 0.72, blue: 0.51) }

    private var filteredUnits: [POSAnimalUnit] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return unitPicker.units }
        return unitPicker.units.filter { unit in
            unit.label.lowercased().contains(query) || unit.unitID.lowercased().contains(query)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. Top Command Navigation Bar
                commandNavBar

                // 2. Specimen Hero Capsule & Fast Search
                specimenHeroCapsule

                // 3. Specimen Matrix Content
                if unitPicker.isLoading {
                    loadingMatrixView
                } else if unitPicker.units.isEmpty {
                    emptyMatrixView
                } else if filteredUnits.isEmpty {
                    emptySearchResultsView
                } else {
                    specimenCardsList
                }
            }

            // 4. Apex Specimen Dispatch Dock
            apexSpecimenDispatchDock
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .coordinateSpace(name: "AnimalRegistrySpace")
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Command Navigation Bar

    private var commandNavBar: some View {
        HStack(spacing: 12) {
            // Dismiss Button Pill
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onClose()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(Language.get("Cancel", alter: "إلغاء"))
                        .font(AdminType.captionBold)
                }
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.0), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Center Modal Title with Pulse Radar
            HStack(spacing: 7) {
                Circle()
                    .fill(rosePrimary)
                    .frame(width: 7, height: 7)
                    .shadow(color: rosePrimary.opacity(0.6), radius: 4, x: 0, y: 0)

                Text(Language.get("POS_ExactAnimalTitle", alter: "اختيار الحيوانات المحددة"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
            }

            Spacer()

            // Quick Batch Toggle Pill
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    unitPicker.toggleSelectAll()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: unitPicker.allSelectableSelected ? "checkmark.circle.fill" : "checklist")
                        .font(.system(size: 13, weight: .bold))
                    Text(unitPicker.allSelectableSelected
                         ? Language.get("POS_DeselectAll", alter: "إلغاء الكل")
                         : Language.get("POS_SelectAll", alter: "تحديد الكل"))
                        .font(AdminType.captionBold)
                }
                .foregroundColor(unitPicker.allSelectableSelected ? rosePrimary : AdminSurface.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(unitPicker.allSelectableSelected
                              ? rosePrimary.opacity(0.12)
                              : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(unitPicker.allSelectableSelected ? rosePrimary.opacity(0.4) : Color.clear, lineWidth: 0.75)
                )
            }
            .buttonStyle(.plain)
            .disabled(unitPicker.units.isEmpty || unitPicker.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Specimen Hero Capsule & Fast Filter

    private var specimenHeroCapsule: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                // Glowing Category Glyphic Avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [rosePrimary.opacity(0.20), crimsonAccent.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(rosePrimary.opacity(0.40), lineWidth: 1.0)
                        )

                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(rosePrimary)
                        .shadow(color: rosePrimary.opacity(0.5), radius: 6, x: 0, y: 2)
                }

                // Specimen Title & Telemetry Chips
                VStack(alignment: .leading, spacing: 4) {
                    Text(unitPicker.product?.name ?? Language.get("LiveAnimal", alter: "حيوان حي"))
                        .font(AdminType.title3)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        // Individual Tracking Pill
                        HStack(spacing: 4) {
                            Circle()
                                .fill(rosePrimary)
                                .frame(width: 5, height: 5)
                            Text(Language.get("POS_ExactAnimalIndividualTracking", alter: "تتبع فردي بالحلقة"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(rosePrimary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(rosePrimary.opacity(0.12), in: Capsule())

                        // Availability Pill
                        HStack(spacing: 4) {
                            Text("\(unitPicker.units.count)")
                                .font(AdminType.caption2Bold)
                            Text(Language.get("Available", alter: "متوفر"))
                                .font(AdminType.caption2)
                        }
                        .foregroundColor(emeraldReady)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(emeraldReady.opacity(0.12), in: Capsule())
                    }
                }

                Spacer()
            }

            // Inline Ring Tag Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AdminSurface.secondaryText)

                TextField(
                    Language.get("POS_SearchRingPlaceholder", alter: "ابحث برقم الحلقة أو المعرّف (مثال: 220)..."),
                    text: $searchQuery
                )
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.primaryText)
                .autocapitalization(.none)
                .disableAutocorrection(true)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.6 : 0.3), lineWidth: 0.75)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.05), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.7 : 0.4), lineWidth: 0.75)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Specimen Cards List

    private var specimenCardsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let message = unitPicker.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(message)
                            .font(AdminType.caption1)
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                ForEach(filteredUnits, id: \.unitID) { unit in
                    ApexAnimalSpecimenCard(
                        unit: unit,
                        isSelected: unitPicker.selectedUnitIDs.contains(unit.unitID),
                        currency: currency,
                        rosePrimary: rosePrimary,
                        emeraldReady: emeraldReady,
                        onToggle: {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                                unitPicker.toggle(unit.unitID)
                            }
                        }
                    )
                }

                if unitPicker.hasMore {
                    Button {
                        unitPicker.loadMore()
                    } label: {
                        HStack(spacing: 7) {
                            if unitPicker.isLoadingMore {
                                ProgressView()
                                    .tint(rosePrimary)
                            }
                            Text(Language.get("POS_ExactAnimalLoadMore", alter: "تحميل المزيد من الحيوانات"))
                                .font(AdminType.captionBold)
                                .foregroundColor(rosePrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(rosePrimary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(rosePrimary.opacity(0.25), lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(unitPicker.isLoadingMore)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 170) // room for floating apex dispatch dock
        }
    }

    // MARK: - Loading & Empty States

    private var loadingMatrixView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(rosePrimary)

            Text(Language.get("Loading", alter: "جارٍ التحقق من سجلات الحلقات والوسوم..."))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMatrixView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: "pawprint.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
            }

            Text(unitPicker.errorMessage ?? Language.get("POS_ExactUnitEmpty", alter: "لا توجد سجلات حيوانات متاحة حالياً"))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.center)

            Text(Language.get("POS_ExactUnitEmptyHint", alter: "تأكد من تسجيل حلقات الحيوانات في المخزون وتحديد أسعار البيع."))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var emptySearchResultsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.6))

            Text(Language.get("POS_NoMatchingRingTag", alter: "لا توجد حلقة تطابق بحثك"))
                .font(AdminType.subheadline)
                .foregroundColor(AdminSurface.primaryText)

            Button {
                searchQuery = ""
            } label: {
                Text(Language.get("ClearFilter", alter: "مسح البحث"))
                    .font(AdminType.captionBold)
                    .foregroundColor(rosePrimary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Apex Specimen Dispatch Dock

    private var apexSpecimenDispatchDock: some View {
        VStack(spacing: 0) {
            // Glass Capsule Command Strip
            VStack(spacing: 8) {
                // Live Telemetry Row
                HStack(alignment: .center) {
                    // Selected Count Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(unitPicker.selectedUnitIDs.isEmpty ? Color.gray : rosePrimary)
                            .frame(width: 6, height: 6)

                        Text("\(Language.get("POS_ExactAnimalSelectedCount", alter: "الحيوانات المختارة")): \(unitPicker.selectedUnitIDs.count)")
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )

                    Spacer()

                    // Dynamic Subtotal Live Calculation
                    if unitPicker.selectedSubtotal > 0 {
                        HStack(spacing: 4) {
                            Text(Language.get("Subtotal", alter: "المجموع:"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)

                            Text(currency(unitPicker.selectedSubtotal))
                                .font(AdminType.calloutBold)
                                .foregroundColor(rosePrimary)
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("\(Language.get("POS_ExactAnimalAvailableCount", alter: "المتاح")): \(unitPicker.units.count)")
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                // The Kinetic Injection Button
                Button {
                    onConfirm()
                } label: {
                    ZStack {
                        // Background Gradient
                        if !unitPicker.selectedUnitIDs.isEmpty {
                            LinearGradient(
                                colors: [rosePrimary, crimsonAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        } else {
                            LinearGradient(
                                colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.20)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }

                        // Content
                        HStack(spacing: 9) {
                            Image(systemName: unitPicker.selectedUnitIDs.isEmpty ? "circle.dashed" : "plus.circle.fill")
                                .font(.system(size: 16, weight: .bold))

                            if unitPicker.selectedUnitIDs.isEmpty {
                                Text(Language.get("POS_SelectAtLeastOneAnimal", alter: "اختر حيواناً واحداً على الأقل"))
                                    .font(AdminType.headline)
                            } else {
                                Text("\(Language.get("POS_ExactAnimalConfirm", alter: "إضافة إلى السلة")) • \(currency(unitPicker.selectedSubtotal))")
                                    .font(AdminType.headline)
                            }
                        }
                        .foregroundColor(unitPicker.selectedUnitIDs.isEmpty ? AdminSurface.secondaryText : .white)
                        .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(
                        color: unitPicker.selectedUnitIDs.isEmpty ? Color.clear : rosePrimary.opacity(0.40),
                        radius: 12,
                        x: 0,
                        y: 5
                    )
                }
                .buttonStyle(.plain)
                .disabled(unitPicker.selectedUnitIDs.isEmpty || unitPicker.isLoading)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(
            ZStack {
                AdminSurface.surface
                RadialGradient(
                    colors: [
                        rosePrimary.opacity(colorScheme == .dark ? 0.12 : 0.05),
                        .clear
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: 200
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.10), radius: 20, x: 0, y: -6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.8 : 0.5), lineWidth: 0.75)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 16)
    }
}

// MARK: - Apex Animal Specimen Card Component

private struct ApexAnimalSpecimenCard: View {
    let unit: POSAnimalUnit
    let isSelected: Bool
    let currency: (Double) -> String
    let rosePrimary: Color
    let emeraldReady: Color
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var formattedShortID: String {
        if unit.unitID.count > 8 {
            return "ID: ••• " + String(unit.unitID.suffix(7))
        }
        return "ID: " + unit.unitID
    }

    var body: some View {
        Button {
            guard unit.isSelectable else { return }
            onToggle()
        } label: {
            HStack(spacing: 12) {
                // 1. Tactile Multi-layer Ring Orb Selector
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? rosePrimary : Color.gray.opacity(colorScheme == .dark ? 0.4 : 0.3),
                            lineWidth: isSelected ? 2.0 : 1.5
                        )
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [rosePrimary, Color(red: 0.98, green: 0.35, blue: 0.50)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 16, height: 16)

                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white)
                    }
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isSelected)

                // 2. Specimen Holographic Tag & Serial Matrix
                VStack(alignment: .leading, spacing: 4) {
                    // Titanium Ring Tag Badge
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isSelected ? rosePrimary : AdminSurface.secondaryText)

                        Text(unit.label)
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .environment(\.layoutDirection, .leftToRight)
                    }

                    // Serial Registry Chip & Readiness
                    HStack(spacing: 6) {
                        Text(formattedShortID)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(AdminSurface.secondaryText)
                            .environment(\.layoutDirection, .leftToRight)

                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.5))

                        if unit.isSelectable {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(emeraldReady)
                                    .frame(width: 4, height: 4)
                                Text(Language.get("ReadyToSell", alter: "جاهز للبيع"))
                                    .font(AdminType.caption2)
                                    .foregroundColor(emeraldReady)
                            }
                        } else {
                            Text(Language.get("POS_ExactAnimalPriceRequired", alter: "يحتاج تسعير"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Spacer()

                // 3. Selling Price Monospaced Badge
                VStack(alignment: .trailing, spacing: 2) {
                    if unit.isSelectable {
                        Text(currency(unit.sellingPrice))
                            .font(AdminType.calloutBold)
                            .foregroundColor(isSelected ? rosePrimary : AdminSurface.primaryText)

                        Text(Language.get("POS_UnitDirectPrice", alter: "سعر السجل"))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(AdminSurface.secondaryText)
                    } else {
                        Text("—")
                            .font(AdminType.headline)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(rosePrimary.opacity(colorScheme == .dark ? 0.12 : 0.06))

                        LinearGradient(
                            colors: [rosePrimary.opacity(0.08), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AdminSurface.surface)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? rosePrimary.opacity(0.65)
                            : Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.7 : 0.35),
                        lineWidth: isSelected ? 1.5 : 0.75
                    )
            )
            .shadow(
                color: isSelected ? rosePrimary.opacity(0.18) : Color.black.opacity(colorScheme == .dark ? 0.20 : 0.03),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: isSelected ? 3 : 1
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!unit.isSelectable)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Cart Anchor Preference

private struct POSCartAnchorKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Catalog Thumbnail

private struct POSCatalogThumbnail: View {
    let accessory: PetAccessory

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)
            ZStack {
                AdminSurface.primary.opacity(0.12)
                if let urlString = accessory.imageURLsArray.first,
                   let url = URL(string: urlString) {
                    AdminRemoteImage(
                        url: url,
                        contentMode: .fill,
                        targetSize: UIDevice.current.userInterfaceIdiom == .pad ? CGSize(width: 180, height: 160) : CGSize(width: 140, height: 120)
                    ) {
                        glyph
                    }
                    .frame(width: w, height: h)
                    .clipped()
                } else {
                    glyph
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    private var glyph: some View {
        Image(systemName: accessory.isLivePet ? "pawprint.fill" : "bag.fill")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(AdminSurface.primary)
    }
}

// MARK: - Catalog Tile

/// Reports its own live frame so the fly-to-cart ghost can start exactly here.
private struct POSCatalogTile: View {
    let accessory: PetAccessory
    let inCart: Int
    let currency: (Double) -> String
    let onTap: (CGRect) -> Void

    private var tileHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 160 : 134
    }

    @MainActor
    private var totalStock: Int {
        if accessory.noStock || accessory.isBlocked || accessory.isDeleted || accessory.isDisabled || accessory.isArchived {
            return 0
        }
        if accessory.isLivePet {
            let activeBranch = BranchContextStore.shared.activeBranch?.branchID
            if let activeBranch, !activeBranch.isEmpty {
                let itemBranch = accessory.storeID ?? accessory.branchID ?? ""
                if !itemBranch.isEmpty && itemBranch != "main_store" && itemBranch != activeBranch {
                    return 0
                }
            }
            return accessory.quantity
        }
        return PPBranchInventoryService.shared.availableStock(for: accessory.accessoryID, fallback: accessory.quantity)
    }

    @MainActor
    private var remainingStock: Int {
        max(0, totalStock - inCart)
    }

    @MainActor
    private var stockText: String {
        if remainingStock <= 0 {
            return Language.get("POS_OutOfStock", alter: "نفد المخزون")
        }
        return String(
            format: Language.get("POS_RemainingStockFormat", alter: "المتبقي: %d"),
            remainingStock
        )
    }

    @MainActor
    private var stockDotColor: Color {
        if remainingStock <= 0 { return .red }
        if remainingStock <= 3 { return .orange }
        return Color(red: 0.1, green: 0.72, blue: 0.45)
    }

    @MainActor
    private var stockTextColor: Color {
        if remainingStock <= 0 { return .red }
        if remainingStock <= 3 { return .orange }
        return AdminSurface.secondaryText
    }

    var body: some View {
        GeometryReader { geo in
            Button {
                onTap(geo.frame(in: .named(POSFastSellSpace.root)))
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    // Top: Image thumbnail expands to fill all remaining vertical space safely
                    ZStack(alignment: .topTrailing) {
                        POSCatalogThumbnail(accessory: accessory)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        if inCart > 0 {
                            Text("\(inCart)")
                                .font(AdminType.caption2Bold)
                                .foregroundColor(.white)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(AdminSurface.primary, in: Circle())
                                .padding(3)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bottom: All labels anchored to bottom, laid out from bottom to top with guaranteed priority
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(accessory.name)
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 2) {
                            Text(currency(accessory.pos_canonicalUnitPrice))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            Spacer(minLength: 0)

                            if accessory.pos_isIndividuallyTrackedLivePet {
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                        }

                        HStack(spacing: 3) {
                            Circle()
                                .fill(stockDotColor)
                                .frame(width: 4, height: 4)

                            Text(stockText)
                                .font(AdminType.caption2)
                                .foregroundColor(stockTextColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            Spacer(minLength: 0)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                }
                .allowsHitTesting(false)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(inCart > 0 ? AdminSurface.primary.opacity(0.5) : AdminSurface.hairline, lineWidth: inCart > 0 ? 1.5 : 0.75)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(POSTilePressStyle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel("\(accessory.name), \(currency(accessory.pos_canonicalUnitPrice)), \(stockText)")
            .accessibilityHint(
                accessory.pos_isIndividuallyTrackedLivePet
                    ? Language.get("POS_ExactAnimalTitle", alter: "اختيار الحيوانات المحددة")
                    : Language.get("POS_AddToCartHint", alter: "إضافة هذا العنصر إلى السلة")
            )
        }
        .frame(height: tileHeight)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct POSTilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? AdminAnimation.pressScale : 1)
            .animation(AdminAnimation.fast, value: configuration.isPressed)
    }
}

// MARK: - Cart Item Row

private struct CartItemRow: View {
    let item: POSCartItem
    let onIncrease: () -> Void
    let onDecrease: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack(spacing: AdminSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.accessory.name)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(formatCurrency(item.unitPriceDisplay))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                HStack(spacing: 2) {
                    Button(action: onDecrease) {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .background(AdminSurface.control, in: Circle())

                    Text("\(item.quantity)")
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(minWidth: 28)

                    Button(action: onIncrease) {
                        Image(systemName: item.isIndividuallyTracked ? "pawprint" : "plus")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .foregroundColor(.white)
                    .background(AdminSurface.primary, in: Circle())
                }

                Text(formatCurrency(item.lineTotal))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(minWidth: 70, alignment: .trailing)

                Button(action: onRemove) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                }
            }

            // Exact animals sold on this line, so the operator can audit before checkout.
            if item.isIndividuallyTracked, !item.unitRingTags.isEmpty {
                Text(item.unitRingTags.joined(separator: " · "))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline))
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "QAR"
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f %@", value, Language.get("QAR", alter: "ر.ق"))
    }
}

// MARK: - Compact Cart Item Chip

private struct CompactCartItemChip: View {
    let item: POSCartItem
    let currency: (Double) -> String
    let onIncrease: () -> Void
    let onDecrease: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.accessory.name)
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)

                Text(currency(item.lineTotal))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.primary)
            }

            HStack(spacing: 3) {
                Button(action: onDecrease) {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .foregroundColor(AdminSurface.primary)
                .background(AdminSurface.control, in: Circle())

                Text("\(item.quantity)")
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(minWidth: 16)

                Button(action: onIncrease) {
                    Image(systemName: item.isIndividuallyTracked ? "pawprint" : "plus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .foregroundColor(.white)
                .background(AdminSurface.primary, in: Circle())

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.5)
        )
    }
}

// MARK: - POS Discount Sheet

struct POSDiscountSheet: View {
    let subtotal: Double
    let currentDiscount: POSDiscount?
    let currency: (Double) -> String
    let onApply: (POSDiscount) -> Void
    let onRemove: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var discountType: POSDiscountType = .percentage
    @State private var percentageValue: Double = 10.0
    @State private var fixedValueText: String = ""
    @State private var selectedPercentPreset: Double? = 10.0
    @State private var selectedFixedPreset: Double? = nil

    private var emeraldColor: Color { Color(red: 0.06, green: 0.72, blue: 0.51) }

    private var percentPresets: [Double] {
        [5, 10, 15, 20, 25, 50]
    }

    private var fixedPresets: [Double] {
        let candidates: [Double] = [5, 10, 15, 20, 25, 50, 100, 200]
        return candidates.filter { $0 < subtotal }
    }

    private var calculatedDiscountAmount: Double {
        switch discountType {
        case .percentage:
            let pct = min(max(percentageValue, 0), 100)
            return ((subtotal * pct / 100.0) * 100).rounded() / 100.0
        case .fixedAmount:
            let sanitized = fixedValueText.replacingOccurrences(of: ",", with: ".")
            let val = Double(sanitized) ?? 0
            return min(subtotal, (max(val, 0) * 100).rounded() / 100.0)
        }
    }

    private var calculatedNetTotal: Double {
        max(0, ((subtotal - calculatedDiscountAmount) * 100).rounded() / 100.0)
    }

    private var isValid: Bool {
        calculatedDiscountAmount > 0 && calculatedDiscountAmount <= subtotal
    }

    init(
        subtotal: Double,
        currentDiscount: POSDiscount?,
        currency: @escaping (Double) -> String,
        onApply: @escaping (POSDiscount) -> Void,
        onRemove: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.subtotal = subtotal
        self.currentDiscount = currentDiscount
        self.currency = currency
        self.onApply = onApply
        self.onRemove = onRemove
        self.onDismiss = onDismiss

        if let cur = currentDiscount {
            _discountType = State(initialValue: cur.type)
            if cur.type == .percentage {
                _percentageValue = State(initialValue: cur.value)
                _selectedPercentPreset = State(initialValue: cur.value)
            } else {
                _fixedValueText = State(initialValue: String(format: "%.2f", cur.value))
                _selectedFixedPreset = State(initialValue: cur.value)
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Original Order Subtotal Card
                        originalSubtotalCard

                        // 2. Discount Mode Segmented Selector
                        discountModeSelector

                        // 3. Presets Row
                        presetsSection

                        // 4. Custom Value Input & Steppers
                        customValueSection

                        // 5. Live Telemetry & Calculations Card
                        liveCalculationCard

                        // 6. Action Buttons
                        actionButtonsSection
                    }
                    .padding(AdminSpacing.screenMargin)
                }
            }
            .navigationTitle(Language.get("POS_Discount_Title", alter: "تطبيق الخصم"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onDismiss()
                    } label: {
                        Text(Language.get("Close", alter: "إغلاق"))
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primary)
                    }
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Subviews

    private var originalSubtotalCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AdminSurface.primary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "cart.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("POS_OriginalSubtotal", alter: "المجموع الأصلي للسلة"))
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                Text(currency(subtotal))
                    .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3))
                    .foregroundColor(AdminSurface.primaryText)
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline))
    }

    private var discountModeSelector: some View {
        HStack(spacing: 8) {
            ForEach(POSDiscountType.allCases) { type in
                let isSelected = discountType == type
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        discountType = type
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: type == .percentage ? "percent" : "banknote")
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        Text(type.title)
                            .font(AdminType.calloutBold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? AdminSurface.primary : AdminSurface.control)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.clear : AdminSurface.hairline)
                    )
                }
            }
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("POS_QuickDiscountPresets", alter: "خيارات سريعة"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if discountType == .percentage {
                        ForEach(percentPresets, id: \.self) { preset in
                            let isSelected = percentageValue == preset
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    percentageValue = preset
                                    selectedPercentPreset = preset
                                }
                            } label: {
                                Text("\(Int(preset))%")
                                    .font(AdminType.captionBold)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                    .background(
                                        isSelected ? emeraldColor : AdminSurface.control,
                                        in: Capsule(style: .continuous)
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(isSelected ? Color.clear : emeraldColor.opacity(0.3), lineWidth: 0.8)
                                    )
                            }
                        }
                    } else {
                        ForEach(fixedPresets, id: \.self) { preset in
                            let isSelected = (Double(fixedValueText) ?? 0) == preset
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    fixedValueText = String(format: "%.0f", preset)
                                    selectedFixedPreset = preset
                                }
                            } label: {
                                Text(currency(preset))
                                    .font(AdminType.captionBold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                    .background(
                                        isSelected ? emeraldColor : AdminSurface.control,
                                        in: Capsule(style: .continuous)
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(isSelected ? Color.clear : emeraldColor.opacity(0.3), lineWidth: 0.8)
                                    )
                            }
                        }
                    }
                }
            }
        }
    }

    private var customValueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("POS_CustomDiscountValue", alter: "القيمة المحددة"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            if discountType == .percentage {
                HStack(spacing: 12) {
                    Button {
                        if percentageValue > 1 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            percentageValue = max(1, percentageValue - (percentageValue > 10 ? 5 : 1))
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 44, height: 44)
                            .foregroundColor(AdminSurface.primaryText)
                            .background(AdminSurface.control, in: Circle())
                    }

                    Spacer()

                    HStack(spacing: 2) {
                        Text("\(Int(percentageValue))")
                            .font(Font.custom("Beiruti-Bold", size: 36, relativeTo: .title))
                            .foregroundColor(AdminSurface.primaryText)
                            .monospacedDigit()
                        Text("%")
                            .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title2))
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    Button {
                        if percentageValue < 100 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            percentageValue = min(100, percentageValue + (percentageValue >= 10 ? 5 : 1))
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 44, height: 44)
                            .foregroundColor(.white)
                            .background(AdminSurface.primary, in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "banknote")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AdminSurface.secondaryText)

                    TextField("0.00", text: $fixedValueText)
                        .font(Font.custom("Beiruti-Bold", size: 24, relativeTo: .title3))
                        .keyboardType(.decimalPad)
                        .foregroundColor(AdminSurface.primaryText)
                        .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)

                    Text(Language.get("QAR", alter: "ر.ق"))
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.secondaryText)

                    if !fixedValueText.isEmpty {
                        Button {
                            fixedValueText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline))
            }
        }
    }

    private var liveCalculationCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(Language.get("POS_OriginalSubtotal", alter: "المجموع الفرعي:"))
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Text(currency(subtotal))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .monospacedDigit()
            }

            HStack {
                HStack(spacing: 4) {
                    Text(Language.get("POS_Discount", alter: "الخصم:"))
                        .font(AdminType.caption1)
                    if discountType == .percentage {
                        Text("(\(Int(percentageValue))%)")
                            .font(AdminType.caption2Bold)
                    }
                }
                .foregroundColor(emeraldColor)

                Spacer()

                Text("-" + currency(calculatedDiscountAmount))
                    .font(AdminType.calloutBold)
                    .foregroundColor(emeraldColor)
                    .monospacedDigit()
            }

            Divider().background(AdminSurface.hairline)

            HStack {
                Text(Language.get("POS_NetTotal", alter: "الإجمالي الصافي للدفع:"))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Text(currency(calculatedNetTotal))
                    .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title3))
                    .foregroundColor(AdminSurface.primaryText)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AdminSurface.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(emeraldColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 10) {
            Button {
                guard isValid else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let discount = POSDiscount(
                    type: discountType,
                    value: discountType == .percentage ? percentageValue : (Double(fixedValueText.replacingOccurrences(of: ",", with: ".")) ?? 0)
                )
                onApply(discount)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text(Language.get("POS_ApplyDiscount", alter: "تطبيق الخصم") + " (\(currency(calculatedNetTotal)))")
                        .font(AdminType.calloutBold)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isValid ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.4))
                )
            }
            .disabled(!isValid)

            if currentDiscount != nil {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onRemove()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                        Text(Language.get("POS_RemoveDiscount", alter: "إزالة الخصم بالكامل"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 38)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Keyboard Dismissal Helper

extension View {
    @ViewBuilder
    func posScrollDismissesKeyboardCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}

// MARK: - Catalog Lens

struct POSCategoryLensSheet: View {
    @ObservedObject var viewModel: POSFastSellViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AdminSpacing.md) {
                        HStack(spacing: AdminSpacing.sm) {
                            ZStack {
                                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                                    .fill(AdminSurface.primarySoft)
                                    .frame(width: 48, height: 48)
                                Image(systemName: "scope")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundColor(AdminSurface.primary)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(Language.get("POS_CategoryLens_Title", alter: "عدسة الكتالوج"))
                                    .font(AdminType.title2)
                                    .foregroundColor(AdminSurface.primaryText)
                                Text(Language.get("POS_CategoryLens_Subtitle", alter: "اختر نطاقاً واحداً للبحث من دون تغيير محتوى السلة."))
                                    .font(AdminType.caption)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: AdminSpacing.xs)

                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(AdminSurface.primary)
                                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                                    .background(AdminSurface.control, in: Circle())
                            }
                            .accessibilityLabel(Language.get("POS_Close", alter: "إغلاق"))
                        }
                        .accessibilityElement(children: .contain)

                        VStack(spacing: AdminSpacing.sm) {
                            ForEach(POSCatalogFilter.allCases) { filter in
                                categoryRow(filter)
                            }
                        }
                    }
                    .padding(AdminSpacing.screenMargin)
                }
            }
            .navigationBarHidden(true)
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func categoryRow(_ filter: POSCatalogFilter) -> some View {
        let selected = viewModel.catalogFilter == filter
        let count = viewModel.count(for: filter)

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if reduceMotion {
                viewModel.catalogFilter = filter
            } else {
                withAnimation(AdminAnimation.standard) {
                    viewModel.catalogFilter = filter
                }
            }
            dismiss()
        } label: {
            HStack(spacing: AdminSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                        .fill(filter.accentColor.opacity(selected ? 0.18 : 0.10))
                        .frame(width: 46, height: 46)
                    Image(systemName: filter.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(filter.accentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get(filter.titleKey, alter: filter.fallbackTitle))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(String(format: Language.get("POS_CategoryLens_Count_Format", alter: "%ld منتج متاح"), count))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                        .monospacedDigit()
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(filter.accentColor)
                        .accessibilityLabel(Language.get("POS_CategoryLens_Selected", alter: "النطاق المحدد"))
                } else {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .padding(.horizontal, AdminSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                    .stroke(selected ? filter.accentColor.opacity(0.45) : AdminSurface.hairline, lineWidth: selected ? AdminStroke.medium : AdminStroke.thin)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityValue(selected ? Language.get("POS_CategoryLens_Selected", alter: "النطاق المحدد") : "")
    }
}

// MARK: - Permission-Aware Barcode Scanner

private enum POSBarcodeScannerPhase: Equatable {
    case permissionRequired
    case requesting
    case ready
    case denied
    case unavailable
}

struct POSBarcodeScannerScreen: View {
    let onResult: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: POSBarcodeScannerPhase

    init(onResult: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onResult = onResult
        self.onCancel = onCancel
        _phase = State(initialValue: Self.phaseForCurrentAuthorization())
    }

    var body: some View {
        ZStack {
            if phase == .ready {
                POSBarcodeCameraView(
                    onResult: onResult,
                    onFailure: { phase = .unavailable }
                )
                .ignoresSafeArea()
                Color.black.opacity(0.24).ignoresSafeArea().allowsHitTesting(false)
                scannerChrome
            } else {
                AdminSurface.background.ignoresSafeArea()
                scannerStateContent
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear { refreshAuthorization() }
        .onChange(of: scenePhase) { value in
            if value == .active { refreshAuthorization() }
        }
    }

    private var scannerChrome: some View {
        VStack(spacing: 0) {
            scannerHeader(dark: true)
            Spacer()

            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .stroke(Color.white.opacity(0.92), lineWidth: 3)
                .frame(maxWidth: 310, minHeight: 190, maxHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                        .stroke(AdminSurface.primary.opacity(0.9), lineWidth: 1)
                        .padding(8)
                )
                .accessibilityHidden(true)

            Text(Language.get("POS_Scanner_Guidance", alter: "ضع رمز QR أو الباركود بالكامل داخل الإطار"))
                .font(AdminType.calloutBold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AdminSpacing.base)
                .padding(.vertical, AdminSpacing.md)
                .background(Color.black.opacity(0.62), in: Capsule())
                .padding(.top, AdminSpacing.lg)
                .padding(.horizontal, AdminSpacing.screenMargin)

            Spacer()
        }
    }

    @ViewBuilder
    private var scannerStateContent: some View {
        VStack(spacing: AdminSpacing.lg) {
            scannerHeader(dark: false)
            Spacer()

            ZStack {
                Circle()
                    .fill(AdminSurface.primarySoft)
                    .frame(width: 104, height: 104)
                Image(systemName: scannerStateIcon)
                    .font(.system(size: 42, weight: .light))
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(spacing: AdminSpacing.sm) {
                Text(scannerStateTitle)
                    .font(AdminType.title2)
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                Text(scannerStateSubtitle)
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AdminSpacing.xl)

            scannerStateAction
                .padding(.horizontal, AdminSpacing.screenMargin)

            Spacer()
            Spacer()
        }
    }

    private func scannerHeader(dark: Bool) -> some View {
        HStack(spacing: AdminSpacing.sm) {
            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(dark ? .white : AdminSurface.primary)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    .background(dark ? Color.black.opacity(0.55) : AdminSurface.control, in: Circle())
            }
            .accessibilityLabel(Language.get("POS_Close", alter: "إغلاق"))

            Text(Language.get("POS_Scanner_Title", alter: "مسح رمز المنتج"))
                .font(AdminType.headline)
                .foregroundColor(dark ? .white : AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.sm)
    }

    @ViewBuilder
    private var scannerStateAction: some View {
        switch phase {
        case .permissionRequired:
            scannerActionButton(Language.get("POS_Scanner_Allow", alter: "السماح بالكاميرا"), icon: "camera.fill") {
                requestCameraAccess()
            }
        case .requesting:
            HStack(spacing: AdminSpacing.sm) {
                ProgressView().tint(AdminSurface.primary)
                Text(Language.get("POS_Scanner_Requesting", alter: "بانتظار إذن الكاميرا…"))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(minHeight: 52)
        case .denied:
            scannerActionButton(Language.get("POS_Scanner_OpenSettings", alter: "فتح الإعدادات"), icon: "gearshape.fill") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        case .unavailable:
            scannerActionButton(Language.get("POS_Scanner_Retry", alter: "إعادة فحص الكاميرا"), icon: "arrow.clockwise") {
                refreshAuthorization()
            }
        case .ready:
            EmptyView()
        }
    }

    private func scannerActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AdminType.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
        }
    }

    private var scannerStateIcon: String {
        switch phase {
        case .permissionRequired, .requesting: return "camera.viewfinder"
        case .denied: return "camera.fill.badge.xmark"
        case .unavailable: return "exclamationmark.triangle.fill"
        case .ready: return "barcode.viewfinder"
        }
    }

    private var scannerStateTitle: String {
        switch phase {
        case .permissionRequired, .requesting:
            return Language.get("POS_Scanner_PermissionTitle", alter: "استخدم الكاميرا لمسح الرمز")
        case .denied:
            return Language.get("POS_Scanner_DeniedTitle", alter: "الوصول إلى الكاميرا متوقف")
        case .unavailable:
            return Language.get("POS_Scanner_UnavailableTitle", alter: "الماسح غير متاح")
        case .ready:
            return Language.get("POS_Scanner_Title", alter: "مسح رمز المنتج")
        }
    }

    private var scannerStateSubtitle: String {
        switch phase {
        case .permissionRequired, .requesting:
            return Language.get("POS_Scanner_PermissionSubtitle", alter: "تُستخدم الكاميرا لقراءة رمز المنتج فقط، ثم يُبحث عنه في الكتالوج الحالي.")
        case .denied:
            return Language.get("POS_Scanner_DeniedSubtitle", alter: "فعّل الكاميرا للتطبيق من الإعدادات، ثم عُد للمسح.")
        case .unavailable:
            return Language.get("POS_Scanner_UnavailableSubtitle", alter: "تعذر تشغيل كاميرا أو قارئ رموز متوافق على هذا الجهاز.")
        case .ready:
            return ""
        }
    }

    private func requestCameraAccess() {
        phase = .requesting
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                phase = granted ? .ready : .denied
            }
        }
    }

    private func refreshAuthorization() {
        phase = Self.phaseForCurrentAuthorization()
    }

    private static func phaseForCurrentAuthorization() -> POSBarcodeScannerPhase {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .ready
        case .notDetermined: return .permissionRequired
        case .denied, .restricted: return .denied
        @unknown default: return .unavailable
        }
    }
}

private struct POSBarcodeCameraView: UIViewControllerRepresentable {
    let onResult: (String) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.metadataDelegate = context.coordinator
        controller.onFailure = onFailure
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        context.coordinator.onResult = onResult
        uiViewController.onFailure = onFailure
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onResult: (String) -> Void
        private var didEmitResult = false

        init(onResult: @escaping (String) -> Void) {
            self.onResult = onResult
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !didEmitResult,
                  let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = readable.stringValue,
                  !value.isEmpty else { return }
            didEmitResult = true
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onResult(value)
        }
    }
}

final class ScannerViewController: UIViewController {
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.purepets.admin.pos.scanner", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false

    weak var metadataDelegate: AVCaptureMetadataOutputObjectsDelegate?
    var onFailure: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCapture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSessionIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    private func configureCapture() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            failConfiguration()
            return
        }

        let output = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(output) else {
            failConfiguration()
            return
        }

        captureSession.beginConfiguration()
        captureSession.addInput(input)
        captureSession.addOutput(output)
        captureSession.commitConfiguration()

        output.setMetadataObjectsDelegate(metadataDelegate, queue: .main)
        let supported: [AVMetadataObject.ObjectType] = [.qr, .ean8, .ean13, .pdf417, .code128]
        let available = Set(output.availableMetadataObjectTypes)
        let enabled = supported.filter { available.contains($0) }
        guard !enabled.isEmpty else {
            failConfiguration()
            return
        }
        output.metadataObjectTypes = enabled

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
        isConfigured = true
        startSessionIfPossible()
    }

    private func startSessionIfPossible() {
        guard isConfigured else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    private func failConfiguration() {
        DispatchQueue.main.async { [weak self] in
            self?.onFailure?()
        }
    }
}

// MARK: - POS Deep Diagnostic Logging Inspector

extension PPPOSLogEntry: Identifiable {
    public var id: String { entryID }
}

extension PPPOSLogLevel {
    var localizedTitle: String {
        switch self {
        case .debug: return "Debug"
        case .info: return Language.get("POS_DeepLog_Infos", alter: "معلومات")
        case .warning: return Language.get("POS_DeepLog_Warnings", alter: "تحذيرات")
        case .error: return Language.get("POS_DeepLog_Errors", alter: "أخطاء")
        @unknown default: return "Log"
        }
    }

    var themeColor: Color {
        switch self {
        case .debug: return Color.gray
        case .info: return Color.blue
        case .warning: return Color.orange
        case .error: return Color.red
        @unknown default: return Color.gray
        }
    }

    var badgeIcon: String {
        switch self {
        case .debug: return "ant.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        @unknown default: return "circle.fill"
        }
    }
}

final class POSDeepLogViewModel: ObservableObject {
    @Published var entries: [PPPOSLogEntry] = []
    @Published var searchText: String = ""
    @Published var selectedLevel: PPPOSLogLevel? = nil
    @Published var selectedCategory: String? = nil
    @Published var totalCount: Int = 0
    @Published var infoCount: Int = 0
    @Published var warningCount: Int = 0
    @Published var errorCount: Int = 0
    @Published var activeBranch: String = ""
    @Published var lastLatencyMs: Int = 0
    @Published var showCopiedToast: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        let all = PPPOSLogger.shared().allEntries()
        self.entries = all
        let summary = PPPOSLogger.shared().diagnosticSummary()
        self.totalCount = summary["totalCount"] as? Int ?? all.count
        self.infoCount = summary["infoCount"] as? Int ?? 0
        self.warningCount = summary["warningCount"] as? Int ?? 0
        self.errorCount = summary["errorCount"] as? Int ?? 0
        self.activeBranch = summary["activeBranch"] as? String ?? ""
        self.lastLatencyMs = summary["lastLatencyMs"] as? Int ?? 0
    }

    var availableCategories: [String] {
        let set = Set(entries.map { $0.category }).filter { !$0.isEmpty }
        return set.sorted()
    }

    var filteredEntries: [PPPOSLogEntry] {
        entries.filter { entry in
            if let lvl = selectedLevel, entry.level != lvl {
                return false
            }
            if let cat = selectedCategory, entry.category != cat {
                return false
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !query.isEmpty {
                let eventMatch = entry.event.lowercased().contains(query)
                let msgMatch = entry.message.lowercased().contains(query)
                let catMatch = entry.category.lowercased().contains(query)
                let traceMatch = entry.traceID?.lowercased().contains(query) ?? false
                return eventMatch || msgMatch || catMatch || traceMatch
            }
            return true
        }
    }

    func clearLogs() {
        PPPOSLogger.shared().clearLogs()
        refresh()
    }

    @MainActor
    func copyAllLogs() {
        let text = PPPOSLogger.shared().exportLogsAsPlainText()
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopiedToast = true
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self?.showCopiedToast = false
            }
        }
    }

    func exportText() -> String {
        return PPPOSLogger.shared().exportLogsAsPlainText()
    }
}

struct POSDeepLogInspectorView: View {
    @StateObject private var viewModel = POSDeepLogViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSharing = false
    @State private var showsClearAlert = false

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView
                    kpiSummaryView
                    searchAndFilterBar
                    Divider().background(AdminSurface.hairline)

                    if viewModel.filteredEntries.isEmpty {
                        emptyStateView
                    } else {
                        logListView
                    }
                }

                if viewModel.showCopiedToast {
                    copiedToastBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, AdminSpacing.lg)
                }
            }
            .navigationBarHidden(true)
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .onReceive(
                NotificationCenter.default
                    .publisher(for: NSNotification.Name.PPPOSLogDidAppend)
            ) { _ in
                viewModel.refresh()
            }
            .alert(isPresented: $showsClearAlert) {
                Alert(
                    title: Text(Language.get("POS_DeepLog_Clear", alter: "مسح السجل")),
                    message: Text(Language.get("POS_DeepLog_Clear_Confirm", alter: "هل أنت متأكد من رغبتك في مسح جميع سجلات تشخيص نقاط البيع اللحظية؟")),
                    primaryButton: .destructive(Text(Language.get("Delete", alter: "مسح"))) {
                        viewModel.clearLogs()
                    },
                    secondaryButton: .cancel(Text(Language.get("Cancel", alter: "إلغاء")))
                )
            }
            .sheet(isPresented: $isSharing) {
                POSDeepLogActivityShareSheet(text: viewModel.exportText())
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var headerView: some View {
        HStack(spacing: AdminSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .fill(AdminSurface.primarySoft)
                    .frame(width: 44, height: 44)
                Image(systemName: "terminal.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("POS_DeepLog_Title", alter: "سجل التشخيص المباشر"))
                    .font(AdminType.title3)
                    .foregroundColor(AdminSurface.primaryText)
                Text(Language.get("POS_DeepLog_Subtitle", alter: "مراقبة فورية لأحداث البيع، المخزون، والاتصال بالخادم"))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: AdminSpacing.xs)

            // Copy button
            Button {
                viewModel.copyAllLogs()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    .background(AdminSurface.control, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin))
            }
            .accessibilityLabel(Language.get("POS_DeepLog_CopyAll", alter: "نسخ السجل بالكامل"))

            // Share button
            Button {
                isSharing = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    .background(AdminSurface.control, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin))
            }
            .accessibilityLabel(Language.get("POS_DeepLog_Share", alter: "مشاركة"))

            // Clear button
            Button {
                showsClearAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.red)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    .background(Color.red.opacity(0.10), in: Circle())
                    .overlay(Circle().stroke(Color.red.opacity(0.25), lineWidth: AdminStroke.thin))
            }
            .accessibilityLabel(Language.get("POS_DeepLog_Clear", alter: "مسح السجل"))

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    .background(AdminSurface.control, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin))
            }
            .accessibilityLabel(Language.get("POS_Close", alter: "إغلاق"))
        }
        .padding(.horizontal, AdminSpacing.base)
        .padding(.vertical, AdminSpacing.sm)
        .background(AdminSurface.surface)
        .overlay(
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: AdminStroke.hairline),
            alignment: .bottom
        )
    }

    private var kpiSummaryView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AdminSpacing.sm) {
                kpiCard(
                    title: Language.get("POS_DeepLog_Total", alter: "إجمالي السجلات"),
                    value: "\(viewModel.totalCount)",
                    icon: "list.bullet.rectangle",
                    color: AdminSurface.primary
                )
                kpiCard(
                    title: Language.get("POS_DeepLog_Infos", alter: "معلومات"),
                    value: "\(viewModel.infoCount)",
                    icon: "info.circle.fill",
                    color: Color.blue
                )
                kpiCard(
                    title: Language.get("POS_DeepLog_Warnings", alter: "تحذيرات"),
                    value: "\(viewModel.warningCount)",
                    icon: "exclamationmark.triangle.fill",
                    color: Color.orange
                )
                kpiCard(
                    title: Language.get("POS_DeepLog_Errors", alter: "أخطاء"),
                    value: "\(viewModel.errorCount)",
                    icon: "xmark.octagon.fill",
                    color: Color.red
                )
                kpiCard(
                    title: Language.get("POS_DeepLog_ActiveBranch", alter: "الفرع النشط"),
                    value: viewModel.activeBranch.isEmpty ? "all" : viewModel.activeBranch,
                    icon: "building.2.fill",
                    color: AdminSurface.primary
                )
                kpiCard(
                    title: Language.get("POS_DeepLog_LastLatency", alter: "زمن المعاملة الأخير"),
                    value: viewModel.lastLatencyMs > 0 ? "\(viewModel.lastLatencyMs) ms" : "--",
                    icon: "stopwatch.fill",
                    color: viewModel.lastLatencyMs > 1000 ? Color.orange : Color.green
                )
            }
            .padding(.horizontal, AdminSpacing.base)
            .padding(.vertical, AdminSpacing.xs)
        }
        .background(AdminSurface.surface)
    }

    private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: AdminSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(AdminSurface.primaryText)
                Text(title)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AdminSpacing.sm)
        .padding(.vertical, AdminSpacing.xs)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin)
        )
    }

    private var searchAndFilterBar: some View {
        VStack(spacing: AdminSpacing.xs) {
            // Search field
            HStack(spacing: AdminSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText)

                TextField(
                    Language.get("POS_DeepLog_SearchPlaceholder", alter: "بحث في الأحداث، الرموز، أو التفاصيل..."),
                    text: $viewModel.searchText
                )
                .font(AdminType.caption)
                .foregroundColor(AdminSurface.primaryText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.sm)
            .frame(height: 34)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin)
            )

            // Severity & Category Filter Rows
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AdminSpacing.xs) {
                    // All Levels
                    filterPill(
                        title: Language.get("All", alter: "الكل"),
                        isSelected: viewModel.selectedLevel == nil,
                        color: AdminSurface.primary
                    ) {
                        viewModel.selectedLevel = nil
                    }

                    // Level pills
                    filterPill(
                        title: PPPOSLogLevel.info.localizedTitle,
                        isSelected: viewModel.selectedLevel == .info,
                        color: PPPOSLogLevel.info.themeColor
                    ) {
                        viewModel.selectedLevel = (viewModel.selectedLevel == .info ? nil : .info)
                    }

                    filterPill(
                        title: PPPOSLogLevel.warning.localizedTitle,
                        isSelected: viewModel.selectedLevel == .warning,
                        color: PPPOSLogLevel.warning.themeColor
                    ) {
                        viewModel.selectedLevel = (viewModel.selectedLevel == .warning ? nil : .warning)
                    }

                    filterPill(
                        title: PPPOSLogLevel.error.localizedTitle,
                        isSelected: viewModel.selectedLevel == .error,
                        color: PPPOSLogLevel.error.themeColor
                    ) {
                        viewModel.selectedLevel = (viewModel.selectedLevel == .error ? nil : .error)
                    }

                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, AdminSpacing.xxs)

                    // Category pills
                    if !viewModel.availableCategories.isEmpty {
                        ForEach(viewModel.availableCategories, id: \.self) { cat in
                            filterPill(
                                title: "#\(cat)",
                                isSelected: viewModel.selectedCategory == cat,
                                color: AdminSurface.primary
                            ) {
                                viewModel.selectedCategory = (viewModel.selectedCategory == cat ? nil : cat)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AdminSpacing.base)
        .padding(.vertical, AdminSpacing.xs)
        .background(AdminSurface.surface)
    }

    private func filterPill(title: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                .padding(.horizontal, AdminSpacing.sm)
                .padding(.vertical, 5)
                .background(
                    isSelected ? color : AdminSurface.control,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? color : AdminSurface.hairline, lineWidth: AdminStroke.thin)
                )
        }
    }

    private var logListView: some View {
        ScrollView {
            LazyVStack(spacing: AdminSpacing.sm) {
                ForEach(viewModel.filteredEntries) { entry in
                    POSDeepLogEntryCard(entry: entry, timeFormatter: Self.timeFormatter)
                }
            }
            .padding(.horizontal, AdminSpacing.base)
            .padding(.vertical, AdminSpacing.sm)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: AdminSpacing.md) {
            Spacer()
            ZStack {
                Circle()
                    .fill(AdminSurface.primarySoft)
                    .frame(width: 72, height: 72)
                Image(systemName: "terminal")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(spacing: AdminSpacing.xxs) {
                Text(Language.get("POS_DeepLog_EmptyTitle", alter: "لا توجد سجلات بعد"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                Text(Language.get("POS_DeepLog_EmptySubtitle", alter: "ستظهر أحداث وعمليات نقطة البيع هنا فور حدوثها."))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AdminSpacing.xl)
            }
            Spacer()
        }
    }

    private var copiedToastBanner: some View {
        HStack(spacing: AdminSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(Language.get("POS_DeepLog_CopiedToast", alter: "تم نسخ السجل إلى الحافظة"))
                .font(AdminType.captionBold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, AdminSpacing.base)
        .padding(.vertical, AdminSpacing.sm)
        .background(Color.black.opacity(0.85), in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}

struct POSDeepLogEntryCard: View {
    let entry: PPPOSLogEntry
    let timeFormatter: DateFormatter

    @State private var isMetadataExpanded = false
    @State private var copiedTrace = false
    @State private var copiedJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            // Header Row: Level + Category + Timestamp + Duration
            HStack(spacing: AdminSpacing.xs) {
                // Level Pill
                HStack(spacing: 3) {
                    Image(systemName: entry.level.badgeIcon)
                        .font(.system(size: 9, weight: .bold))
                    Text(entry.levelString.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                }
                .foregroundColor(entry.level.themeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(entry.level.themeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(entry.level.themeColor.opacity(0.25), lineWidth: AdminStroke.thin)
                )

                // Category Tag
                Text("#\(entry.category)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                Spacer()

                // Latency / Duration badge if applicable
                if entry.durationMs > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                        Text("\(entry.durationMs)ms")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(entry.durationMs > 1000 ? .orange : AdminSurface.secondaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AdminSurface.control, in: Capsule())
                }

                // Timestamp
                Text(timeFormatter.string(from: entry.timestamp))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(AdminSurface.secondaryText)
            }

            // Event Name
            Text(entry.event)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(AdminSurface.primaryText)

            // Message
            Text(entry.message)
                .font(AdminType.caption)
                .foregroundColor(AdminSurface.primaryText.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            // Trace ID row (if available)
            if let trace = entry.traceID, !trace.isEmpty {
                HStack(spacing: AdminSpacing.xxs) {
                    Text("trace:")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(trace)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(AdminSurface.primary)
                        .lineLimit(1)

                    Button {
                        UIPasteboard.general.string = trace
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        copiedTrace = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedTrace = false
                        }
                    } label: {
                        Image(systemName: copiedTrace ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(copiedTrace ? .green : AdminSurface.secondaryText)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            // Metadata Drawer
            if !entry.metadata.isEmpty {
                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isMetadataExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: AdminSpacing.xxs) {
                            Image(systemName: isMetadataExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                            Text("Metadata (\(entry.metadata.count))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            Spacer()
                        }
                        .foregroundColor(AdminSurface.primary)
                    }

                    if isMetadataExpanded {
                        VStack(alignment: .trailing, spacing: AdminSpacing.xxs) {
                            Button {
                                UIPasteboard.general.string = entry.jsonString()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                copiedJSON = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copiedJSON = false
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: copiedJSON ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 9))
                                    Text(copiedJSON ? Language.get("Copied", alter: "تم النسخ") : Language.get("Copy", alter: "نسخ"))
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundColor(copiedJSON ? .green : AdminSurface.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }

                            Text(entry.jsonString())
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(Color(white: 0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(AdminSpacing.sm)
                        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: AdminStroke.thin)
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(AdminSpacing.sm)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .stroke(
                    entry.level == .error ? Color.red.opacity(0.35) : (entry.level == .warning ? Color.orange.opacity(0.35) : AdminSurface.hairline),
                    lineWidth: entry.level == .error || entry.level == .warning ? AdminStroke.medium : AdminStroke.thin
                )
        )
    }
}

struct POSDeepLogActivityShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.permittedArrowDirections = []
            if let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
