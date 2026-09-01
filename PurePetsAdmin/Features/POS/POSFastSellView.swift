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

// MARK: - Live Pet Inventory Contract

/// Mirrors the Infra/Console `LIVE_PET_INVENTORY_MODE.individual` token.
private let kPOSIndividualInventoryMode = "INDIVIDUAL_TRACKED"

private enum POSFastSellSpace {
    static let root = "pos.fastsell.root"
}

extension PetAccessory {
    /// Console parity: `isIndividuallyTrackedLiveProduct`.
    var pos_isIndividuallyTrackedLivePet: Bool {
        isLivePet && (inventoryMode?.uppercased() == kPOSIndividualInventoryMode)
    }

    /// Console parity: `isPosCatalogSellable`.
    var pos_isSellable: Bool {
        active && !noStock && quantity > 0 && !isBlocked && !isDeleted && !isDisabled && !isArchived
    }

    /// The canonical catalog unit price the server validates against.
    ///
    /// `posIntegrity.canonicalCatalogUnitPrice` resolves
    /// `finalPrice ?? sellPrice ?? price`, so submitting the pre-discount
    /// `price` fails `assertPriceAssertion` for any discounted item with
    /// "Submitted unit price does not match the canonical catalog price".
    /// `finalPrice` is a computed getter that applies percent/amount discounts.
    var pos_canonicalUnitPrice: Double {
        let discounted = finalPrice.doubleValue
        if discounted > 0 { return discounted }
        return price.doubleValue
    }
}

// MARK: - Catalog Filter Rail

/// Console parity: the POS fast-lane product type rail
/// (Accessories / Food / Pet Medicines / Live Pets).
enum POSCatalogFilter: String, CaseIterable, Identifiable {
    case accessories
    case food
    case medicine
    case livePets

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .accessories: return "POS_CatalogTypeAccessories"
        case .food: return "POS_CatalogTypeFood"
        case .medicine: return "POS_CatalogTypeMedicine"
        case .livePets: return "POS_CatalogTypeLivePets"
        }
    }

    var fallbackTitle: String {
        switch self {
        case .accessories: return "إكسسوارات"
        case .food: return "طعام"
        case .medicine: return "أدوية"
        case .livePets: return "حيوانات حية"
        }
    }

    var symbol: String {
        switch self {
        case .accessories: return "bag"
        case .food: return "fork.knife"
        case .medicine: return "cross.case"
        case .livePets: return "pawprint"
        }
    }

    func matches(_ accessory: PetAccessory) -> Bool {
        switch self {
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
    var lineTotal: Double {
        if isIndividuallyTracked {
            return unitPrices.reduce(0) { $0 + (($1["unitPrice"] as? Double) ?? 0) }
        }
        return accessory.pos_canonicalUnitPrice * Double(quantity)
    }

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

    init(error: Error) {
        let details = PPPOSService.exactUnitConflictDetails(forError: error)
        productID = (details["productId"] as? String) ?? ""
        unitID = (details["unitId"] as? String) ?? ""
        ringTag = (details["ringTag"] as? String) ?? ""
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
    @Published private(set) var selectedPaymentMethod: String = "cash"
    @Published private(set) var isSubmitting = false
    @Published private(set) var isPreparingReceipt = false
    @Published var submitError: String?
    @Published private(set) var completedReceipt: POSCompletedReceipt?
    @Published private(set) var receiptNotice: String?

    /// Footer quick-add catalog rail.
    @Published var catalogFilter: POSCatalogFilter = .accessories
    @Published var catalogSearchText: String = ""

    private var listener: AnyObject?
    /// Retained across an uncertain callable response so retrying the same
    /// checkout cannot create a second transaction. Any cart/payment change
    /// invalidates it and starts a new command.
    private var submissionCommandID: String?
    private var submissionCashReceived: Double?
    private var receiptRequestID: UUID?

    var searchResults: [PetAccessory] {
        guard !searchText.isEmpty else { return allAccessories }
        let q = searchText.lowercased()
        return allAccessories.filter {
            $0.name.lowercased().contains(q)
        }
    }

    /// Sellable, type-filtered catalog for the footer quick-add grid.
    var catalogResults: [PetAccessory] {
        var list = allAccessories.filter { $0.pos_isSellable && catalogFilter.matches($0) }
        let q = catalogSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) || $0.accessoryID.lowercased().contains(q) }
        }
        return list
    }

    var cartTotal: Double {
        cartItems.reduce(0) { $0 + $1.lineTotal }
    }

    var cartItemCount: Int {
        cartItems.reduce(0) { $0 + $1.quantity }
    }

    var isCheckoutBusy: Bool { isSubmitting || isPreparingReceipt }

    let paymentMethods: [(key: String, title: String, icon: String)] = [
        ("cash", "POS_Cash", "banknote.fill"),
        ("card", "POS_Card", "creditcard.fill")
    ]

    func startListening() {
        listener = AccessoryManager.shared().observeAllAccessories { [weak self] items, error in
            Task { @MainActor in
                guard let self else { return }
                if error == nil {
                    self.allAccessories = items ?? []
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
        guard accessory.pos_isSellable else { return false }
        if let idx = cartIndex(for: accessory.accessoryID) {
            guard cartItems[idx].quantity < accessory.quantity else { return false }
            cartItems[idx].quantity += 1
        } else {
            cartItems.append(POSCartItem(accessory: accessory, quantity: 1))
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
        invalidateSubmissionCommand()
    }

    func removeFromCart(_ item: POSCartItem) {
        let previousCount = cartItems.count
        cartItems.removeAll { $0.id == item.id }
        if cartItems.count != previousCount {
            invalidateSubmissionCommand()
        }
    }

    func clearCart() {
        guard !cartItems.isEmpty else { return }
        cartItems = []
        invalidateSubmissionCommand()
    }

    func increaseQuantity(_ item: POSCartItem) {
        guard let idx = cartItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard !cartItems[idx].isIndividuallyTracked else { return }
        guard cartItems[idx].quantity < cartItems[idx].accessory.quantity else { return }
        cartItems[idx].quantity += 1
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
            invalidateSubmissionCommand()
            return
        }
        if cartItems[idx].quantity > 1 {
            cartItems[idx].quantity -= 1
        } else {
            cartItems.remove(at: idx)
        }
        invalidateSubmissionCommand()
    }

    func selectPaymentMethod(_ paymentMethod: String) {
        guard paymentMethods.contains(where: { $0.key == paymentMethod }) else { return }
        guard selectedPaymentMethod != paymentMethod else { return }
        selectedPaymentMethod = paymentMethod
        invalidateSubmissionCommand()
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

        PPPOSService.shared().submitPOSOrder(
            withItems: items,
            total: cartTotal,
            paymentMethod: selectedPaymentMethod,
            cashReceived: selectedPaymentMethod == "cash" ? NSNumber(value: acceptedCash) : nil,
            commandID: commandID
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
                        self.submitError = Language.get("POS_SubmitFailed", alter: "تعذر إتمام عملية البيع. حاول مرة أخرى.")
                    }
                    return
                }

                guard !transactionID.isEmpty else {
                    self.isSubmitting = false
                    // The server may already have committed the command. Keep
                    // its ID so Retry is idempotent instead of creating a sale.
                    self.submitError = Language.get("POS_SubmitFailed", alter: "تعذر إتمام عملية البيع. حاول مرة أخرى.")
                    return
                }

                let fallbackReceipt = POSCompletedReceipt(
                    transactionID: transactionID,
                    total: serverTotal > 0 ? serverTotal : self.cartTotal,
                    currency: serverCurrency,
                    paymentMethod: self.selectedPaymentMethod,
                    cashReceived: acceptedCash,
                    cartItems: self.cartItems
                )
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
    @StateObject private var viewModel = POSFastSellViewModel()
    @StateObject private var unitPicker = POSUnitPickerState()
    @State private var showsItemPicker = false
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

    var body: some View {
        ZStack(alignment: .bottom) {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView
                filterRail
                catalogGrid
            }

            POSApexFlightDeck(
                viewModel: viewModel,
                currency: { formatCurrency($0) },
                cartPulse: cartPulse,
                onOpenUnitPicker: { openUnitPicker(for: $0) },
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
        .sheet(isPresented: $showsItemPicker) {
            itemPickerSheet
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

    // MARK: - Header Pill

    /// One pill, 58pt ceiling: close, workspace/title stack, and the add action.
    private var dossierHeaderView: some View {
        HStack(spacing: AdminSpacing.sm) {
            Button {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 38, height: 38)
                    .background(AdminSurface.control, in: Circle())
            }
            .accessibilityLabel(Language.get("Close", alter: "إغلاق"))

            VStack(alignment: .leading, spacing: 0) {
                Text(Language.get("CommandCenter_Work_Workspace", alter: "مساحة العمليات"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
                Text(Language.get("POS_Title", alter: "بيع سريع"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showsItemPicker = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text(Language.get("Add", alter: "إضافة منتج"))
                        .font(AdminType.captionBold)
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(AdminSurface.primary, in: Capsule())
            }
            .accessibilityLabel(Language.get("Add", alter: "إضافة منتج"))
        }
        .padding(.horizontal, AdminSpacing.sm)
        .padding(.vertical, AdminSpacing.sm)
        .frame(maxHeight: 58)
        .background(AdminSurface.surface, in: Capsule())
        .overlay(Capsule().stroke(AdminSurface.hairline))
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
    }

    // MARK: - Category Filter Rail

    private var filterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(POSCatalogFilter.allCases) { filter in
                    let active = viewModel.catalogFilter == filter
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(AdminAnimation.fast) {
                            viewModel.catalogFilter = filter
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: filter.symbol)
                                .font(.system(size: 12, weight: .semibold))
                            Text(Language.get(filter.titleKey, alter: filter.fallbackTitle))
                                .font(AdminType.captionBold)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .foregroundColor(active ? .white : AdminSurface.primaryText)
                        .background(
                            active ? AdminSurface.primary : AdminSurface.control,
                            in: Capsule(style: .continuous)
                        )
                        .overlay(
                            Capsule(style: .continuous).stroke(active ? Color.clear : AdminSurface.hairline)
                        )
                    }
                    .accessibilityLabel(Language.get(filter.titleKey, alter: filter.fallbackTitle))
                    .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, 8)
        }
        .accessibilityLabel(Language.get("POS_CatalogFilterRail", alter: "فلاتر الكتالوج"))
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
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Interaction

    private func handleCatalogTap(_ accessory: PetAccessory, from rect: CGRect) {
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
    let onClearCart: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var tenderedAmount: Double? = nil

    private var hasItems: Bool { !viewModel.cartItems.isEmpty }
    private var emeraldColor: Color { Color(red: 0.06, green: 0.72, blue: 0.51) }
    private var sapphireColor: Color { Color(red: 0.14, green: 0.54, blue: 0.98) }

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
                // 1. Fluid Segmented Payment Selector
                paymentMethodSelector

                // 2. Dynamic Cash Tender Assist or Card Wave Status
                if viewModel.selectedPaymentMethod == "cash" && hasItems {
                    cashTenderAssistantStrip
                } else if viewModel.selectedPaymentMethod == "card" && hasItems {
                    cardTerminalStatusStrip
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
                        (viewModel.selectedPaymentMethod == "cash" ? emeraldColor : AdminSurface.primary)
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
        .onChange(of: hasItems) { hasItems in
            if !hasItems { tenderedAmount = nil }
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

                Spacer()

                Text(currency(viewModel.cartTotal))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .monospacedDigit()

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

    // MARK: - Payment Selector

    private var paymentMethodSelector: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.paymentMethods, id: \.key) { method in
                let isSelected = viewModel.selectedPaymentMethod == method.key
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.75)) {
                        viewModel.selectPaymentMethod(method.key)
                        tenderedAmount = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: method.icon)
                            .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                            .foregroundColor(
                                isSelected
                                    ? (method.key == "cash" ? emeraldColor : sapphireColor)
                                    : AdminSurface.secondaryText
                            )

                        Text(Language.get(method.title, alter: method.key))
                            .font(AdminType.calloutBold)
                            .foregroundColor(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                isSelected
                                    ? (method.key == "cash" ? emeraldColor : sapphireColor).opacity(colorScheme == .dark ? 0.22 : 0.12)
                                    : AdminSurface.control
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? (method.key == "cash" ? emeraldColor : sapphireColor).opacity(0.50)
                                    : Color.clear,
                                lineWidth: 1.2
                            )
                    )
                }
                .buttonStyle(POSTilePressStyle())
            }
        }
    }

    // MARK: - Cash Tender Strip

    private var cashTenderAssistantStrip: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(tenderSuggestions, id: \.self) { tender in
                    let isExact = tender == viewModel.cartTotal
                    let isSelected = tenderedAmount == tender || (tenderedAmount == nil && isExact)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            tenderedAmount = tender
                        }
                    } label: {
                        Text(isExact ? Language.get("POS_Exact", alter: "مضبوط") : "\(Int(tender))")
                            .font(AdminType.caption2Bold)
                            .padding(.horizontal, 10)
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

                Spacer(minLength: 0)

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

    // MARK: - Apex Charge Kinetic Button

    private var apexChargeButton: some View {
        Button {
            guard hasItems else { return }
            viewModel.submitOrder(cashReceived: tenderedAmount)
        } label: {
            HStack(spacing: 8) {
                if viewModel.isCheckoutBusy {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                    Text(Language.get("POS_Submitting", alter: "جارٍ إتمام العملية..."))
                        .font(AdminType.headline)
                        .foregroundColor(.white)
                } else if hasItems {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("POS_Submit", alter: "تقديم الطلب"))
                            .font(AdminType.headline)
                    }
                    .foregroundColor(.white)

                    Spacer()

                    HStack(spacing: 4) {
                        Text(currency(viewModel.cartTotal))
                            .font(AdminType.headline)
                            .monospacedDigit()
                        Image(systemName: "arrow.forward.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.18), in: Capsule(style: .continuous))
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "cart.badge.plus")
                            .font(.system(size: 14, weight: .medium))
                        Text(Language.get("POS_SelectItemsPrompt", alter: "اختر منتجات من الكتالوج للبدء"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        hasItems
                            ? LinearGradient(
                                colors: [
                                    AdminSurface.primary,
                                    AdminSurface.primary.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                                    colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        hasItems
                            ? Color.white.opacity(0.25)
                            : Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.7 : 0.4),
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(POSTilePressStyle())
        .disabled(!hasItems || viewModel.isCheckoutBusy)
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
                                        Text(stockLabel(for: accessory))
                                            .font(AdminType.caption2)
                                            .foregroundColor(
                                                accessory.quantity > 0 ? AdminSurface.secondaryText : .red
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
                            .disabled(accessory.quantity <= 0 || accessory.noStock)

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
        return "\(stockTitle): \(accessory.quantity)"
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
        ZStack {
            AdminSurface.primary.opacity(0.12)
            if let urlString = accessory.imageURLsArray.first,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        glyph
                    }
                }
            } else {
                glyph
            }
        }
        .clipped()
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

    private let tileHeight: CGFloat = 134

    var body: some View {
        GeometryReader { geo in
            Button {
                onTap(geo.frame(in: .named(POSFastSellSpace.root)))
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    ZStack(alignment: .topTrailing) {
                        POSCatalogThumbnail(accessory: accessory)
                            .frame(height: 75)
                            .frame(maxWidth: .infinity)
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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(accessory.name)
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

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
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(inCart > 0 ? AdminSurface.primary.opacity(0.5) : AdminSurface.hairline, lineWidth: inCart > 0 ? 1.5 : 0.75)
                )
            }
            .buttonStyle(POSTilePressStyle())
            .accessibilityLabel("\(accessory.name), \(currency(accessory.pos_canonicalUnitPrice))")
            .accessibilityHint(
                accessory.pos_isIndividuallyTrackedLivePet
                    ? Language.get("POS_ExactAnimalTitle", alter: "اختيار الحيوانات المحددة")
                    : Language.get("POS_AddToCartHint", alter: "إضافة هذا العنصر إلى السلة")
            )
        }
        .frame(height: tileHeight)
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
