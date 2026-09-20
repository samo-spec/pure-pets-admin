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
import FirebaseFunctions
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

/// Single money authority for the POS screen.
///
/// Every displayed and submitted amount must agree with the server, because
/// `processTransaction` recomputes all money itself and rejects a mismatched
/// client assertion with `failed-precondition` ("… does not match the
/// server-calculated amount") using a half-cent tolerance.
///
/// Infra reference (`Pure Pets Infra/functions/posIntegrity.js`,
/// `functions/transactions.js`):
/// - `roundMoney(v)` → `Math.round((v + Number.EPSILON) * 100) / 100`
/// - each line total is rounded, then `subtotal = roundMoney(subtotal + lineTotal)`
///   is accumulated **per line** (transactions.js:1671)
/// - `moneyMatches` compares with `abs(a - b) < 0.005`
///
/// Rounding only the final sum, as the cart previously did, drifts from the
/// server once several lines each carry a half-cent residue, which fails an
/// otherwise valid checkout. `sum(_:)` mirrors the server's accumulation
/// exactly so an honest cart can never be rejected for a rounding artifact.
enum POSMoney {
    /// Half-cent tolerance used by Infra `moneyMatches`.
    static let matchTolerance = 0.005

    /// Server-equivalent 2-decimal rounding.
    static func round(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return ((value + .ulpOfOne) * 100).rounded() / 100.0
    }

    /// Server-equivalent per-line accumulation: round each line, then round
    /// after every addition.
    static func sum(_ lineTotals: [Double]) -> Double {
        lineTotals.reduce(0) { running, line in
            POSMoney.round(running + POSMoney.round(line))
        }
    }

    /// True when two amounts agree within the server's tolerance.
    static func matches(_ lhs: Double, _ rhs: Double) -> Bool {
        let a = POSMoney.round(lhs)
        let b = POSMoney.round(rhs)
        guard a.isFinite, b.isFinite else { return false }
        return abs(a - b) < matchTolerance
    }

    /// Minor units for the wire contract (`assertedGroupPriceMinor`, `lineTotalMinor`).
    static func minorUnits(_ value: Double) -> Int {
        let rounded = POSMoney.round(value)
        guard rounded.isFinite else { return 0 }
        return Int((rounded * 100).rounded())
    }

    /// Single parser for every operator-entered money field (cash tender,
    /// fixed discount).
    ///
    /// Arabic is the primary language, so an operator can legitimately type
    /// Arabic-Indic digits (`١٢٣`) and the Arabic decimal separator (`٫`).
    /// Parsing those with a plain `Double(_:)` yields 0, which silently
    /// disables the confirm control with no explanation. Digits are normalised
    /// first via the shared `normalizedEnglishDigits`, then both Arabic and
    /// Latin decimal separators are accepted.
    static func parse(_ text: String) -> Double {
        let normalized = text
            .normalizedEnglishDigits
            .replacingOccurrences(of: "٫", with: ".")
            .replacingOccurrences(of: "٬", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return 0 }
        if let value = Double(normalized), value.isFinite { return value }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let value = formatter.number(from: normalized)?.doubleValue, value.isFinite else { return 0 }
        return value
    }
}

extension PetAccessory {
    /// Console parity: `isIndividuallyTrackedLiveProduct`.
    var pos_isIndividuallyTrackedLivePet: Bool {
        isLivePet && (inventoryMode?.uppercased() == kPOSIndividualInventoryMode)
    }

    /// Authoritative stock for the active branch, honoring branchInventory documents
    /// for both live pets and standard items, falling back to catalog attributes only when unsegmented.
    @MainActor
    func pos_branchStock(activeBranch: String? = nil) -> Int {
        guard active && !isBlocked && !isDeleted && !isDisabled && !isArchived && !noStock else {
            return 0
        }
        let branchId = (activeBranch ?? BranchContextStore.shared.activeBranch?.branchID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let branchId, !branchId.isEmpty {
            if let branchRecord = PPBranchInventoryService.shared.inventory(for: accessoryID) {
                if isLivePet && quantity > 0 {
                    return max(branchRecord.availableQuantity, quantity)
                }
                return branchRecord.availableQuantity
            }
            let itemBranch = (storeID ?? branchID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if isLivePet {
                // Live pets are physical individual specimens strictly bound to their branch.
                // The server enforces POS_INVENTORY_UNIT_BRANCH_MISMATCH if the unit does not match the active POS branch.
                if !itemBranch.isEmpty && itemBranch != branchId {
                    return 0
                }
            } else {
                if !itemBranch.isEmpty && itemBranch != "main_store" && itemBranch != branchId {
                    return 0
                }
            }
        }
        return PPBranchInventoryService.shared.availableStock(for: accessoryID, fallback: quantity)
    }

    /// Console parity: `isPosCatalogSellable` (per active branch).
    @MainActor
    var pos_isSellable: Bool {
        pos_branchStock() > 0
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

enum POSSalesChannel: String, CaseIterable, Identifiable {
    case retail = "retail"
    case wholesale = "wholesale"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .retail:
            return Language.get("POS_Channel_Retail", alter: "قطاعي")
        case .wholesale:
            return Language.get("POS_Channel_Wholesale", alter: "جملة")
        }
    }

    var symbol: String {
        switch self {
        case .retail: return "circle.on.square.intersection.dotted"
        case .wholesale: return "shippingbox.fill"
        }
    }
}

extension PetAccessory {
    var pos_supportsWholesale: Bool {
        guard (!isLivePet || !pos_isIndividuallyTrackedLivePet) && !isPetMedicine else { return false }
        if let wp = wholesalePrice?.doubleValue, wp > 0 { return true }
        if let groups = quantityGroups {
            return groups.contains { ($0["wholesaleEnabled"] as? Bool) == true }
        }
        return false
    }

    func pos_wholesalePrice() -> Double {
        if let wp = wholesalePrice?.doubleValue, wp > 0 {
            return wp
        }
        if let groups = quantityGroups {
            for g in groups {
                if (g["wholesaleEnabled"] as? Bool) == true,
                   let minor = g["wholesalePriceMinor"] as? Int, minor > 0 {
                    return Double(minor) / 100.0
                }
            }
        }
        return 0
    }
}

struct POSCartItem: Identifiable, Equatable {
    let id = UUID()
    let accessory: PetAccessory
    var quantity: Int = 1 // groupQuantity

    // Commercial Channel & Quantity Groups V2
    var salesChannel: String = "retail"
    var quantityGroupID: String = "single"
    var quantityGroupNameAr: String = "حبة"
    var quantityGroupNameEn: String = "Single"
    var unitsPerGroup: Int = 1
    var unitGroupPrice: Double = 0
    var unitGroupPriceMinor: Int = 0

    var baseUnitQuantity: Int {
        quantity * max(1, unitsPerGroup)
    }

    /// Populated only for individually tracked live pets.
    var inventoryMode: String? = nil
    var unitIDs: [String] = []
    var unitRingTags: [String] = []
    var unitPrices: [[String: Any]] = []
    var unitSubSubKinds: [String] = []
    var unitSubSubKindItems: [String] = []

    var isIndividuallyTracked: Bool { inventoryMode == kPOSIndividualInventoryMode }

    var localizedGroupName: String {
        Language.isRTL()
            ? (quantityGroupNameAr.isEmpty ? quantityGroupNameEn : quantityGroupNameAr)
            : (quantityGroupNameEn.isEmpty ? quantityGroupNameAr : quantityGroupNameEn)
    }

    /// Exact-unit lines total the selected animals, never quantity × catalog price.
    ///
    /// Rounded to the server's money precision so the cart subtotal that
    /// `POSMoney.sum` builds matches Infra's per-line accumulation.
    @MainActor
    var lineTotal: Double {
        if isIndividuallyTracked {
            return POSMoney.round(unitPrices.reduce(0) { $0 + POSCartItem.unitPrice(from: $1) })
        }
        if unitGroupPrice > 0 {
            return POSMoney.round(unitGroupPrice * Double(quantity))
        }
        return POSMoney.round(accessory.pos_canonicalUnitPrice * Double(quantity))
    }

    /// `unitPrices` is an untyped `[[String: Any]]` because it crosses the
    /// Objective-C callable boundary, where a price can arrive as `NSNumber`,
    /// `Int`, or `Double`. `as? Double` alone silently reads those as 0, which
    /// would under-total a live-pet line, so every numeric representation is
    /// accepted explicitly.
    static func unitPrice(from entry: [String: Any]) -> Double {
        guard let raw = entry["unitPrice"] else { return 0 }
        if let value = raw as? Double { return value.isFinite ? value : 0 }
        if let value = raw as? NSNumber {
            let value = value.doubleValue
            return value.isFinite ? value : 0
        }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String, let parsed = Double(value), parsed.isFinite { return parsed }
        return 0
    }

    @MainActor
    var unitPriceDisplay: Double {
        if isIndividuallyTracked {
            return quantity > 0 ? POSMoney.round(lineTotal / Double(quantity)) : 0
        }
        if unitGroupPrice > 0 {
            return unitGroupPrice
        }
        return accessory.pos_canonicalUnitPrice
    }

    // Lot & Expiry Tracking V2
    var lotId: String? = nil
    var lotNumber: String? = nil
    var lotExpiryDate: Date? = nil

    var effectiveExpiryDate: Date? {
        lotExpiryDate ?? accessory.expiryDate
    }

    var isExpired: Bool {
        guard let exp = effectiveExpiryDate else { return false }
        return exp <= Date()
    }

    var isNearExpiry: Bool {
        guard let exp = effectiveExpiryDate, !isExpired else { return false }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
        return days <= 30
    }

    var expiryDisplayText: String? {
        guard let exp = effectiveExpiryDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: exp)
    }

    static func == (lhs: POSCartItem, rhs: POSCartItem) -> Bool {
        lhs.id == rhs.id
            && lhs.quantity == rhs.quantity
            && lhs.unitIDs == rhs.unitIDs
            && lhs.quantityGroupID == rhs.quantityGroupID
            && lhs.salesChannel == rhs.salesChannel
            && lhs.lotId == rhs.lotId
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
            return POSMoney.round(subtotal * pct / 100.0)
        case .fixedAmount:
            return min(POSMoney.round(subtotal), POSMoney.round(max(value, 0)))
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
    let currentBranchId: String
    var fallbackBranchId: String = ""
    var subSubKindID: Int = 0
    var subSubKindNameAr: String = ""
    var subSubKindNameEn: String = ""
    var subSubKindItemID: Int = 0
    var subSubKindItemNameAr: String = ""
    var subSubKindItemNameEn: String = ""

    var subSubKindName: String {
        if Language.isRTL() {
            return !subSubKindNameAr.isEmpty ? subSubKindNameAr : subSubKindNameEn
        } else {
            return !subSubKindNameEn.isEmpty ? subSubKindNameEn : subSubKindNameAr
        }
    }

    var subSubKindItemName: String {
        if Language.isRTL() {
            return !subSubKindItemNameAr.isEmpty ? subSubKindItemNameAr : subSubKindItemNameEn
        } else {
            return !subSubKindItemNameEn.isEmpty ? subSubKindItemNameEn : subSubKindItemNameAr
        }
    }

    var id: String { unitID }
    var label: String { ringTag.isEmpty ? unitID : ringTag }
    func isSelectable(in activeBranch: String?) -> Bool {
        guard sellingPrice > 0 else { return false }
        let branch = activeBranch?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let branch, !branch.isEmpty else { return true }
        let effectiveBranch = (!currentBranchId.isEmpty ? currentBranchId : fallbackBranchId).trimmingCharacters(in: .whitespacesAndNewlines)
        if !effectiveBranch.isEmpty {
            return effectiveBranch == branch
        }
        return true
    }

    @MainActor
    var isSelectable: Bool {
        isSelectable(in: BranchContextStore.shared.activeBranch?.branchID)
    }
}

/// Sendable projection of an Objective-C/Firebase failure. The callable
/// callback can arrive off the main actor, so Foundation objects must not be
/// captured by the `@MainActor` task that updates SwiftUI state.
private struct POSSubmitFailure: Sendable {
    let productID: String
    let productName: String
    let unitID: String
    let ringTag: String
    let domainCode: String
    let functionsCode: Int
    let serverMessage: String
    let submittedPrice: Double?
    let authoritativePrice: Double?

    init(error: Error) {
        let nsError = error as NSError
        let details = PPPOSService.exactUnitConflictDetails(forError: error)
        productID = (details["productId"] as? String) ?? ""
        productName = (details["productName"] as? String) ?? ""
        unitID = (details["unitId"] as? String) ?? ""
        ringTag = (details["ringTag"] as? String) ?? ""
        domainCode = ((details["domainCode"] as? String) ?? "").uppercased()
        functionsCode = nsError.code
        serverMessage = nsError.localizedDescription
        if let sub = details["submittedPrice"] as? NSNumber {
            submittedPrice = sub.doubleValue
        } else if let sub = details["submittedPrice"] as? Double {
            submittedPrice = sub
        } else {
            submittedPrice = nil
        }
        if let auth = details["authoritativePrice"] as? NSNumber {
            authoritativePrice = auth.doubleValue
        } else if let auth = details["authoritativePrice"] as? Double {
            authoritativePrice = auth
        } else {
            authoritativePrice = nil
        }
        isFunctionsError = nsError.domain == FunctionsErrorDomain || nsError.domain == "com.firebase.functions"
    }

    /// `functionsCode` is only meaningful for a Cloud Functions error. Without
    /// this the service's own codes (400/502) or a URL-loading code could be
    /// read as `permission-denied`/`unauthenticated` and show the operator a
    /// misleading recovery instruction.
    let isFunctionsError: Bool

    /// The server rejected the command outright, so no transaction exists and
    /// nothing needs reconciling. Anything else — transport failure, timeout,
    /// internal error — leaves the outcome genuinely unknown.
    var isDefinitiveRejection: Bool {
        if !domainCode.isEmpty { return true }
        guard isFunctionsError else { return false }
        switch functionsCode {
        // invalid-argument, not-found, permission-denied, failed-precondition,
        // already-exists, unauthenticated.
        case 3, 5, 6, 7, 9, 16:
            return true
        default:
            return false
        }
    }

    /// Only a unit-level conflict justifies dropping the operator's selected
    /// animals. A stock shortfall or permission error is retryable, and
    /// deleting cart lines for those loses work the operator must redo.
    var isExactUnitConflict: Bool {
        switch domainCode {
        case "POS_INVENTORY_UNIT_NOT_FOUND",
             "POS_INVENTORY_UNIT_UNAVAILABLE",
             "POS_INVENTORY_UNIT_BRANCH_MISMATCH",
             "INVENTORY_UNIT_BRANCH_MISMATCH":
            return true
        default:
            return false
        }
    }

    /// Infra `already-exists`: this command key is bound to a different sale
    /// payload, so it can never succeed again and must be released.
    var isCommandKeyConflict: Bool {
        isFunctionsError && functionsCode == 6
    }
}

/// Durable record of a dispatched POS command whose outcome was never observed.
///
/// The server keys idempotency on `(actorUid, commandId)` with no expiry, so a
/// command ID is only safe to reuse while the client still has it. It lived in
/// memory only, which meant a crash or force-quit mid-checkout lost the key —
/// the operator's natural retry then minted a new command and the customer was
/// charged, and stock deducted, twice. Persisting the key lets the next launch
/// warn instead of silently duplicating.
private enum POSPendingCommandStore {
    private static let commandKey = "PPAdmin.POS.PendingCommand.v1.commandId"
    private static let totalKey = "PPAdmin.POS.PendingCommand.v1.total"
    private static let itemCountKey = "PPAdmin.POS.PendingCommand.v1.itemCount"
    private static let dispatchedAtKey = "PPAdmin.POS.PendingCommand.v1.dispatchedAt"

    struct Record {
        let commandID: String
        let total: Double
        let itemCount: Int
        let dispatchedAt: Date
    }

    static func record(commandID: String, total: Double, itemCount: Int) {
        let defaults = UserDefaults.standard
        defaults.set(commandID, forKey: commandKey)
        defaults.set(total, forKey: totalKey)
        defaults.set(itemCount, forKey: itemCountKey)
        defaults.set(Date().timeIntervalSince1970, forKey: dispatchedAtKey)
    }

    static func clear() {
        let defaults = UserDefaults.standard
        [commandKey, totalKey, itemCountKey, dispatchedAtKey].forEach { defaults.removeObject(forKey: $0) }
    }

    static func pending() -> Record? {
        let defaults = UserDefaults.standard
        guard let commandID = defaults.string(forKey: commandKey), !commandID.isEmpty else { return nil }
        return Record(
            commandID: commandID,
            total: defaults.double(forKey: totalKey),
            itemCount: defaults.integer(forKey: itemCountKey),
            dispatchedAt: Date(timeIntervalSince1970: defaults.double(forKey: dispatchedAtKey))
        )
    }
}

public struct POSPriceDiscrepancyItem: Identifiable, Sendable {
    public var id: String { productID }
    public let productID: String
    public let productName: String
    public let submittedPrice: Double
    public let authoritativePrice: Double
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
        let fallbackBranch = (product?.storeID ?? product?.branchID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        PPPOSService.shared().listAvailableUnits(forProductID: productID, cursor: cursor) { [weak self] units, nextCursor, hasMore, error in
            // Project to Sendable values before crossing to the main actor.
            let unitsList = units ?? []
            let projected: [POSAnimalUnit] = unitsList.map { unit in
                POSAnimalUnit(
                    unitID: unit.unitID ?? "",
                    ringTag: unit.ringTag ?? "",
                    sellingPrice: unit.sellingPrice,
                    currentBranchId: unit.currentBranchId ?? "",
                    fallbackBranchId: fallbackBranch,
                    subSubKindID: unit.subSubKindID?.intValue ?? 0,
                    subSubKindNameAr: unit.subSubKindNameAr ?? "",
                    subSubKindNameEn: unit.subSubKindNameEn ?? "",
                    subSubKindItemID: unit.subSubKindItemID?.intValue ?? 0,
                    subSubKindItemNameAr: unit.subSubKindItemNameAr ?? "",
                    subSubKindItemNameEn: unit.subSubKindItemNameEn ?? ""
                )
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
            .dropFirst()
            .removeDuplicates()
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

    // Commercial Channel & Wholesale Reconciliation
    @Published var salesChannel: POSSalesChannel = .retail
    @Published var showWholesaleReconciliationAlert: Bool = false
    @Published var unsupportedWholesaleCartItems: [POSCartItem] = []

    // Apple-Grade Price Discrepancy Reconciliation
    @Published var priceDiscrepancy: POSPriceDiscrepancyItem? = nil

    /// Set when a sale was dispatched but its outcome was never observed —
    /// typically because the app was terminated mid-checkout. Warning the
    /// operator to reconcile against POS history is the only way to stop the
    /// sale being rung a second time on the next shift.
    @Published var unconfirmedSaleNotice: String? = nil

    func reconcilePrice(productID: String, newPrice: Double) {
        guard let idx = cartIndex(for: productID) else {
            priceDiscrepancy = nil
            return
        }
        var item = cartItems.remove(at: idx)
        item.unitGroupPrice = newPrice
        item.unitGroupPriceMinor = POSMoney.minorUnits(newPrice)
        cartItems.insert(item, at: idx)
        priceDiscrepancy = nil
        invalidateSubmissionCommand()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func dismissPriceDiscrepancy() {
        priceDiscrepancy = nil
    }

    var canSellWholesale: Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff else { return false }
        if staff.role == .superAdmin || staff.role == .owner || staff.isAdmin() { return true }
        return staff.hasPermission("pos.sell.wholesale")
    }

    /// `true` only when the canonical `staff_users` record is loaded and
    /// positively lacks `pos.sell`.
    ///
    /// The server authorizes every `processTransaction` call, so this is not a
    /// security boundary — it exists so a `pos.view`-only operator is told
    /// before ringing up a full cart instead of after. It is deliberately
    /// fail-open on a cold cache: refusing checkout because the staff snapshot
    /// has not loaded yet would lock out a permitted cashier, which is worse
    /// than deferring to the server's denial.
    var isSaleExplicitlyDenied: Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff else { return false }
        if staff.role == .superAdmin || staff.role == .owner || staff.isAdmin() { return false }
        return !staff.hasPermission("pos.sell")
    }

    func requestSalesChannelChange(_ newChannel: POSSalesChannel) {
        guard newChannel != salesChannel else { return }
        if newChannel == .wholesale {
            guard canSellWholesale else {
                submitError = Language.get("POS_Wholesale_Permission_Required", alter: "صلاحية البيع بالجملة غير متوفرة لهذا المستخدم.")
                return
            }
            let unsupported = cartItems.filter { !$0.accessory.pos_supportsWholesale }
            if !unsupported.isEmpty {
                unsupportedWholesaleCartItems = unsupported
                showWholesaleReconciliationAlert = true
                return
            }
            confirmSwitchToWholesale(removeUnavailable: false)
        } else {
            salesChannel = .retail
            repriceCartForRetail()
            invalidateSubmissionCommand()
        }
    }

    func confirmSwitchToWholesale(removeUnavailable: Bool) {
        if removeUnavailable {
            let unsupportedIDs = Set(unsupportedWholesaleCartItems.map { $0.id })
            cartItems.removeAll { unsupportedIDs.contains($0.id) }
        }
        unsupportedWholesaleCartItems = []
        showWholesaleReconciliationAlert = false
        salesChannel = .wholesale
        repriceCartForWholesale()
        invalidateSubmissionCommand()
    }

    private func repriceCartForWholesale() {
        for i in 0..<cartItems.count {
            guard !cartItems[i].isIndividuallyTracked else { continue }
            cartItems[i].salesChannel = "wholesale"
            let wholesalePrice = cartItems[i].accessory.pos_wholesalePrice()
            if wholesalePrice > 0 {
                cartItems[i].unitGroupPrice = wholesalePrice
                cartItems[i].unitGroupPriceMinor = POSMoney.minorUnits(wholesalePrice)
            }
        }
    }

    private func repriceCartForRetail() {
        for i in 0..<cartItems.count {
            guard !cartItems[i].isIndividuallyTracked else { continue }
            cartItems[i].salesChannel = "retail"
            let retailPrice = cartItems[i].accessory.pos_canonicalUnitPrice
            cartItems[i].unitGroupPrice = retailPrice
            cartItems[i].unitGroupPriceMinor = POSMoney.minorUnits(retailPrice)
        }
    }

    var wholesaleUnavailableAlertMessage: String {
        let count = unsupportedWholesaleCartItems.count
        let names = unsupportedWholesaleCartItems.map { $0.accessory.name }.prefix(3).joined(separator: "، ")
        return String(
            format: Language.get("POS_Wholesale_Unavailable_Message_Format", alter: "البيع بالجملة غير متاح لـ %d من أصناف السلة:\n%@"),
            count,
            names
        )
    }

    func setQuantityGroup(for itemID: UUID, groupID: String, nameAr: String, nameEn: String, unitsPerGroup: Int, price: Double, priceMinor: Int) {
        guard let idx = cartItems.firstIndex(where: { $0.id == itemID }) else { return }
        cartItems[idx].quantityGroupID = groupID
        cartItems[idx].quantityGroupNameAr = nameAr
        cartItems[idx].quantityGroupNameEn = nameEn
        cartItems[idx].unitsPerGroup = unitsPerGroup
        cartItems[idx].unitGroupPrice = price
        cartItems[idx].unitGroupPriceMinor = priceMinor
        invalidateSubmissionCommand()
    }

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

    /// Owns the catalog snapshot registration.
    ///
    /// `PPFirestoreListenerToken` removes the registration from its own
    /// `deinit`, so the listener is released even when the view is destroyed
    /// without `onDisappear` running. A `deinit` on this `@MainActor` model
    /// could not do that itself — Swift 6 forbids touching a non-`Sendable`
    /// `ListenerRegistration` from a nonisolated `deinit`.
    private var listener: PPFirestoreListenerToken?
    /// Staleness token for the catalog snapshot listener, mirroring
    /// `POSUnitPickerState.requestID`.
    private var catalogListenerGeneration = UUID()
    /// Retained across an uncertain callable response so retrying the same
    /// checkout cannot create a second transaction. Any cart/payment change
    /// invalidates it and starts a new command.
    private var submissionCommandID: String?
    private var submissionCashReceived: Double?
    private var receiptRequestID: UUID?

    /// Identifies the submission currently awaiting a response.
    ///
    /// This is deliberately **not** `submissionCommandID`. That ID is a retry
    /// key that every cart, discount, customer and payment mutation
    /// invalidates on purpose, so gating the completion handler on it meant a
    /// single edit during flight discarded the server's answer entirely:
    /// `isSubmitting` stayed `true` forever behind the blocking overlay while a
    /// sale that may already have been committed produced no receipt, no
    /// change due and no error. This token is owned only by `submitOrder` and
    /// its completion, so an outcome is always applied exactly once.
    private var inFlightSubmissionToken: UUID?

    /// The cart exactly as submitted, held on the main actor.
    ///
    /// `POSCartItem` is not `Sendable` — it carries the `PetAccessory` ObjC
    /// object and an untyped `[[String: Any]]` — so it must not be captured by
    /// the callable's `@Sendable` completion closure. Parking the snapshot here
    /// and reading it back inside the `@MainActor` hop keeps the receipt built
    /// from what was actually sold without crossing an isolation boundary.
    private var submittedCartSnapshot: [POSCartItem] = []

    var searchResults: [PetAccessory] {
        guard !searchText.isEmpty else { return allAccessories }
        let q = searchText.lowercased()
        // `allAccessories` is already stored in the canonical
        // createdAt-desc / accessoryID-desc order by `startListening`, and
        // `filter` preserves order, so re-sorting here was pure duplicate work
        // on every body evaluation — and the blanket `objectWillChange` from
        // the branch-inventory subscription makes that every inventory tick.
        return allAccessories.filter {
            $0.name.lowercased().contains(q) ||
            $0.accessoryID.lowercased().contains(q) ||
            ($0.sku?.lowercased().contains(q) ?? false) ||
            ($0.barcode?.lowercased().contains(q) ?? false)
        }
    }

    /// Sellable, type-filtered catalog for the footer quick-add grid (ordered newest first).
    var catalogResults: [PetAccessory] {
        let q = catalogSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allAccessories.filter { accessory in
            guard accessory.pos_isSellable, catalogFilter.matches(accessory) else { return false }
            guard !q.isEmpty else { return true }
            return accessory.name.lowercased().contains(q) ||
                accessory.accessoryID.lowercased().contains(q) ||
                (accessory.sku?.lowercased().contains(q) ?? false) ||
                (accessory.barcode?.lowercased().contains(q) ?? false)
        }
    }

    /// Mirrors Infra's `subtotal = roundMoney(subtotal + lineTotal)` accumulation
    /// so the asserted subtotal can never drift outside the server's tolerance.
    var cartSubtotal: Double {
        POSMoney.sum(cartItems.map { $0.lineTotal })
    }

    var discountAmount: Double {
        guard let discount = appliedDiscount else { return 0 }
        return discount.calculateAmount(subtotal: cartSubtotal)
    }

    var cartTotal: Double {
        max(0, POSMoney.round(cartSubtotal - discountAmount))
    }

    var cartItemCount: Int {
        cartItems.reduce(0) { $0 + $1.quantity }
    }

    var isCheckoutBusy: Bool { isSubmitting || isPreparingReceipt }
    var hasExpiredItems: Bool { cartItems.contains { $0.isExpired } }

    let paymentMethods: [(key: String, title: String, icon: String)] = [
        ("cash", "POS_Cash", "banknote.fill"),
        ("card", "POS_Card", "creditcard.fill"),
        ("cheque", "POS_Cheque", "doc.text.fill"),
        ("fawry", "POS_Fawry", "wallet.pass.fill"),
        ("bank_transfer", "POS_BankTransfer", "arrow.up.forward.app.fill")
    ]

    func startListening() {
        PPBranchInventoryService.shared.startListeningIfNeeded()
        surfacePendingCommandIfNeeded()
        listener?.remove()
        listener = nil
        // Invalidate any snapshot already in flight from the previous
        // registration: without this, a late callback from a removed listener
        // still replaced `allAccessories` and cleared the loading state, which
        // could reprice cart lines that fall back to the canonical catalog
        // price. The exact-animal picker already uses this pattern.
        let generation = UUID()
        catalogListenerGeneration = generation
        isCatalogLoading = allAccessories.isEmpty
        catalogErrorMessage = nil
        POSLogger.info("catalog.listener.started", category: "catalog", message: "Starting PetAccessory catalog listener")

        listener = PPFirestoreListenerToken(AccessoryManager.shared().observeAllAccessories { [weak self] items, error in
            let projectedItems = items ?? []
            let projectedError = error?.localizedDescription
            Task { @MainActor in
                guard let self, self.catalogListenerGeneration == generation else { return }
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
        })
    }

    func retryCatalog() {
        POSLogger.info("catalog.retry", category: "catalog", message: "Retrying catalog listener")
        startListening()
    }

    func stopListening() {
        // Bump the generation first so an in-flight snapshot callback cannot
        // land after teardown.
        catalogListenerGeneration = UUID()
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
        if salesChannel == .wholesale && !accessory.pos_supportsWholesale {
            submitError = String(format: Language.get("POS_Wholesale_Not_Supported_For_Product", alter: "هذا الصنف (%@) لا يدعم البيع بالجملة."), accessory.name)
            return false
        }
        let branchStock = accessory.pos_branchStock()
        let unitPrice = salesChannel == .wholesale ? accessory.pos_wholesalePrice() : accessory.pos_canonicalUnitPrice
        let unitPriceMinor = POSMoney.minorUnits(unitPrice)

        if let idx = cartIndex(for: accessory.accessoryID) {
            let nextUnits = (cartItems[idx].quantity + 1) * max(1, cartItems[idx].unitsPerGroup)
            guard nextUnits <= branchStock else {
                POSLogger.warn("cart.add_stock_capped", category: "cart", message: "Cannot add more '\(accessory.name)': branch stock limit (\(branchStock)) reached", metadata: [
                    "productId": accessory.accessoryID,
                    "quantity": cartItems[idx].quantity,
                    "stock": branchStock
                ])
                return false
            }
            cartItems[idx].quantity += 1
            let updated = cartItems.remove(at: idx)
            cartItems.append(updated)
            POSLogger.info("cart.quantity_incremented", category: "cart", message: "Incremented '\(accessory.name)' to \(updated.quantity) (Subtotal: \(cartSubtotal) QAR)", metadata: [
                "productId": accessory.accessoryID,
                "quantity": updated.quantity,
                "cartTotal": cartTotal
            ])
        } else {
            guard branchStock > 0 else { return false }
            var item = POSCartItem(accessory: accessory, quantity: 1)
            item.salesChannel = salesChannel.rawValue
            item.unitGroupPrice = unitPrice
            item.unitGroupPriceMinor = unitPriceMinor
            cartItems.append(item)
            POSLogger.info("cart.item_added", category: "cart", message: "Added '\(accessory.name)' to cart (Price: \(unitPrice) QAR, Subtotal: \(cartSubtotal) QAR)", metadata: [
                "productId": accessory.accessoryID,
                "name": accessory.name,
                "unitPrice": unitPrice,
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
        let subSubKinds = units.compactMap { $0.subSubKindName.isEmpty ? nil : $0.subSubKindName }
        let subSubKindItems = units.compactMap { $0.subSubKindItemName.isEmpty ? nil : $0.subSubKindItemName }
        let prices: [[String: Any]] = units.map { ["unitId": $0.unitID, "unitPrice": $0.sellingPrice] }
        let lineTotal = POSMoney.round(prices.reduce(0) { $0 + POSCartItem.unitPrice(from: $1) })

        if let idx = cartIndex(for: product.accessoryID) {
            var updated = cartItems.remove(at: idx)
            updated.inventoryMode = kPOSIndividualInventoryMode
            updated.unitIDs = unitIDs
            updated.unitRingTags = ringTags
            updated.unitPrices = prices
            updated.unitSubSubKinds = subSubKinds
            updated.unitSubSubKindItems = subSubKindItems
            updated.quantity = unitIDs.count
            cartItems.append(updated)
        } else {
            var item = POSCartItem(accessory: product, quantity: unitIDs.count)
            item.inventoryMode = kPOSIndividualInventoryMode
            item.unitIDs = unitIDs
            item.unitRingTags = ringTags
            item.unitPrices = prices
            item.unitSubSubKinds = subSubKinds
            item.unitSubSubKindItems = subSubKindItems
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
            var existing = cartItems.remove(at: idx)
            if !existing.unitIDs.contains(unitID) {
                existing.unitIDs.append(unitID)
                existing.unitRingTags.append(ringTag)
                existing.unitPrices.append(["unitId": unitID, "unitPrice": agreedPrice])
                existing.quantity = existing.unitIDs.count
            }
            cartItems.append(existing)
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
        let branchStock = cartItems[idx].accessory.pos_branchStock()
        let unitsPerGroup = max(1, cartItems[idx].unitsPerGroup)
        let nextUnits = (cartItems[idx].quantity + 1) * unitsPerGroup
        guard nextUnits <= branchStock else { return }
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

    func updateQuantity(_ item: POSCartItem, newQuantity: Int) {
        guard let idx = cartItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard !cartItems[idx].isIndividuallyTracked else { return }
        if newQuantity <= 0 {
            removeFromCart(item)
            return
        }
        let branchStock = cartItems[idx].accessory.pos_branchStock()
        let unitsPerGroup = max(1, cartItems[idx].unitsPerGroup)
        let maxGroups = branchStock / unitsPerGroup
        let targetQuantity = min(newQuantity, max(1, maxGroups))
        cartItems[idx].quantity = targetQuantity
        POSLogger.info("cart.quantity_updated", category: "cart", message: "Updated '\(item.accessory.name)' quantity to \(targetQuantity)", metadata: [
            "productId": item.accessory.accessoryID,
            "quantity": targetQuantity,
            "branchStock": branchStock,
            "cartTotal": cartTotal
        ])
        invalidateSubmissionCommand()
    }

    func bringItemToFront(_ item: POSCartItem) {
        guard let idx = cartItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard idx < cartItems.count - 1 else { return }
        let target = cartItems.remove(at: idx)
        cartItems.append(target)
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
        case "POS_INVENTORY_UNIT_BRANCH_MISMATCH", "INVENTORY_UNIT_BRANCH_MISMATCH":
            return Language.get(
                "POS_ExactUnitBranchMismatch",
                alter: "الحيوان المحدد مسجل في فرع آخر ولا يمكن بيعه من هذا الفرع. اختر حيواناً متوفراً في فرعك الحالي."
            )
        case "POS_INVENTORY_UNIT_NOT_FOUND":
            return Language.get(
                "POS_ExactUnitNotFound",
                alter: "لم يتم العثور على سجل الحيوان في المخزون. حدّث القائمة ثم أعد المحاولة."
            )
        case "POS_INVENTORY_UNIT_UNAVAILABLE":
            return Language.get(
                "POS_ExactUnitRefreshNeeded",
                alter: "تغيّر حيوان واحد أو أكثر من الحيوانات المحددة أو لم يعد متاحًا. اختر سجلات الحيوانات مرة أخرى."
            )
        case "POS_PRICE_DISCREPANCY":
            let name = failure.productName.isEmpty ? "" : " (\(failure.productName))"
            if let auth = failure.authoritativePrice, auth > 0 {
                return String(format: Language.get("POS_PriceDiscrepancy_Formatted", alter: "تغير السعر الرسمي للصنف%@ إلى %.2f ر.ق. يرجى تحديث السعر والمتابعة."), name, auth)
            }
            return Language.get("POS_PriceDiscrepancy_Generic", alter: "تغير سعر أحد الأصناف في النظام. حدّث السعر في السلة ثم أعد المحاولة.")
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
        // Only a Cloud Functions error carries these codes. Reading them off a
        // transport or service-layer error would show the wrong recovery step.
        guard failure.isFunctionsError else {
            return Language.get("POS_SubmitFailed", alter: "تعذر إتمام عملية البيع. حاول مرة أخرى.")
        }
        switch failure.functionsCode {
        case 6:
            // already-exists: a sale is already stored under this command key
            // with a different payload, so this attempt did not commit but an
            // earlier variant did. Reusing the key can only ever collide again.
            return Language.get(
                "POS_CheckoutCommandConflict",
                alter: "توجد عملية بيع مسجلة بنفس رقم الأمر ببيانات مختلفة. راجع سجل المبيعات للتأكد قبل إعادة البيع، ثم أنشئ عملية جديدة."
            )
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

    /// - Returns: `true` when the sale was dispatched to the server. `false`
    ///   means nothing is in flight and the caller's commit affordance must
    ///   settle back to its idle state.
    @discardableResult
    func submitOrder(cashReceived: Double? = nil) -> Bool {
        guard !cartItems.isEmpty, !isCheckoutBusy, completedReceipt == nil else { return false }
        guard !isSaleExplicitlyDenied else {
            submitError = Language.get(
                "POS_CheckoutPermissionDenied",
                alter: "ليست لديك صلاحية إتمام البيع في هذا الفرع. اختر فرعًا مسموحًا أو اطلب الصلاحية."
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        guard !hasExpiredItems else {
            submitError = Language.get(
                "pos_checkout_blocked_expired",
                alter: "لا يمكن إتمام البيع: السلة تحتوي على منتج منتهي الصلاحية"
            )
            return false
        }

        for item in cartItems where !item.isIndividuallyTracked {
            let availableStock = item.accessory.pos_branchStock()
            if item.baseUnitQuantity > availableStock {
                submitError = String(
                    format: Language.get(
                        "POS_ItemStockExceeded_Format",
                        alter: "كمية الصنف (%@) تتجاوز المخزون المتوفر في الفرع (%d متوفر)."
                    ),
                    item.accessory.name,
                    availableStock
                )
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return false
            }
        }

        // Snapshot the money before anything else so every downstream
        // consumer — assertion payload, receipt, tender validation — agrees.
        let submittedSubtotal = cartSubtotal
        let submittedDiscount = discountAmount
        let submittedTotal = cartTotal
        let isCashSale = selectedPaymentMethod == "cash"

        // A tender below the total is an operator error, not something to
        // paper over. Silently raising it to the total (the previous
        // behaviour) recorded cash that was never taken and broke drawer
        // reconciliation; the server rejects it anyway with
        // "Cash received must cover the sale total."
        if isCashSale, let tendered = cashReceived, !POSMoney.matches(tendered, submittedTotal), tendered < submittedTotal {
            submitError = String(
                format: Language.get(
                    "POS_CashReceivedBelowTotal_Format",
                    alter: "المبلغ المستلم (%.2f ر.ق) أقل من إجمالي البيع (%.2f ر.ق). صحّح المبلغ ثم أعد المحاولة."
                ),
                POSMoney.round(tendered),
                submittedTotal
            )
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return false
        }

        // No explicit tender means exact change.
        let acceptedCash = isCashSale ? max(POSMoney.round(cashReceived ?? submittedTotal), submittedTotal) : 0

        isSubmitting = true
        submitError = nil
        receiptNotice = nil

        if submissionCommandID != nil, submissionCashReceived != acceptedCash {
            invalidateSubmissionCommand()
        }
        let commandID = submissionCommandID ?? generatePOSCommandID()
        submissionCommandID = commandID
        submissionCashReceived = acceptedCash

        let submissionToken = UUID()
        inFlightSubmissionToken = submissionToken

        // The cart as actually submitted. The catalog listener can replace
        // `allAccessories` mid-flight and reprice lines that fall back to the
        // canonical catalog price, so the receipt must be built from this
        // snapshot rather than from live cart state.
        submittedCartSnapshot = cartItems

        let items: [[String: Any]] = submittedCartSnapshot.map { item in
            var payload: [String: Any] = [
                "itemID": item.accessory.accessoryID,
                "name": item.accessory.name,
                "price": item.unitPriceDisplay,
                "quantity": item.quantity,
                "salesChannel": salesChannel.rawValue,
                "quantityGroupId": item.quantityGroupID,
                "quantityGroupName": item.localizedGroupName,
                "unitsPerGroup": item.unitsPerGroup,
                "groupQuantity": item.quantity,
                "baseUnitQuantity": item.baseUnitQuantity,
                "assertedGroupPriceMinor": item.unitGroupPriceMinor > 0 ? item.unitGroupPriceMinor : POSMoney.minorUnits(item.unitPriceDisplay),
                "lineTotalMinor": POSMoney.minorUnits(item.lineTotal)
            ]
            if let lotId = item.lotId {
                payload["lotId"] = lotId
            }
            if let lotNumber = item.lotNumber {
                payload["lotNumber"] = lotNumber
            }
            if item.isIndividuallyTracked {
                payload["inventoryMode"] = kPOSIndividualInventoryMode
                payload["unitIds"] = item.unitIDs
                payload["unitPrices"] = item.unitPrices
                if !item.unitRingTags.isEmpty {
                    payload["unitRingTags"] = item.unitRingTags
                }
                if !item.unitSubSubKinds.isEmpty {
                    payload["unitSubSubKinds"] = item.unitSubSubKinds
                }
                if !item.unitSubSubKindItems.isEmpty {
                    payload["unitSubSubKindItems"] = item.unitSubSubKindItems
                }
            }
            return payload
        }

        let customerName = selectedCustomer?.name
        let customerPhone = selectedCustomer?.phone
        let posCustomerID = selectedCustomer?.id
        let activeBranchId = BranchContextStore.shared.activeBranch?.branchID
        let submittedPaymentMethod = selectedPaymentMethod

        var checkoutMetadata: [String: Any] = [
            "commandId": commandID,
            "itemsCount": items.count,
            "subtotal": submittedSubtotal,
            "discount": submittedDiscount,
            "total": submittedTotal,
            "paymentMethod": submittedPaymentMethod,
            "acceptedCash": acceptedCash,
            "branchId": activeBranchId ?? "none"
        ]
        if submittedPaymentMethod == "cheque", let cheque = attachedCheque {
            checkoutMetadata["chequeNumber"] = cheque.chequeNumber
            checkoutMetadata["chequeBank"] = cheque.bankName
            if let amount = cheque.amount {
                checkoutMetadata["chequeAmount"] = amount
            }
        }

        POSLogger.info("checkout.initiated", category: "checkout", traceID: commandID, message: "Initiating checkout: \(items.count) line items (Total: \(submittedTotal) QAR via \(submittedPaymentMethod))", metadata: checkoutMetadata)

        // Survive process death: if the app is killed between dispatch and
        // response the in-memory command ID is gone, and a fresh retry would
        // mint a new one and bill the customer twice.
        POSPendingCommandStore.record(commandID: commandID, total: submittedTotal, itemCount: items.count)

        PPPOSService.shared().submitPOSOrder(
            withItems: items,
            subtotal: submittedSubtotal,
            discount: submittedDiscount,
            total: submittedTotal,
            paymentMethod: submittedPaymentMethod,
            cashReceived: isCashSale ? NSNumber(value: acceptedCash) : nil,
            commandID: commandID,
            customerName: customerName,
            customerPhone: customerPhone,
            posCustomerID: posCustomerID,
            branchID: activeBranchId,
            salesChannel: salesChannel.rawValue
        ) { [weak self] result, error in
            // Project ObjC/Foundation values before crossing into MainActor.
            let transactionID = result?.transactionID ?? ""
            let serverTotal = result?.total ?? 0
            let serverCurrency = result?.currency ?? ""
            let wasIdempotentReplay = result?.isIdempotent ?? false
            let failure = error.map(POSSubmitFailure.init)

            Task { @MainActor in
                guard let self, self.inFlightSubmissionToken == submissionToken else { return }
                self.inFlightSubmissionToken = nil
                // Cleared exactly once, on every branch, so the blocking
                // overlay can never outlive the request.
                self.isSubmitting = false

                if let failure {
                    POSLogger.error("checkout.failed", category: "checkout", traceID: commandID, message: "Checkout failed: \(failure.serverMessage)", metadata: [
                        "domainCode": failure.domainCode,
                        "productId": failure.productID,
                        "unitId": failure.unitID,
                        "ringTag": failure.ringTag,
                        "functionsCode": failure.functionsCode
                    ])

                    // A definitively rejected command never reached a committed
                    // state, so there is nothing left to reconcile.
                    if failure.isDefinitiveRejection {
                        POSPendingCommandStore.clear()
                    }

                    // `already-exists` means this command key is permanently
                    // bound to a different payload. Retaining it would make
                    // every retry collide forever, dead-ending the sale, so the
                    // key is released and the next attempt mints a fresh one.
                    if failure.isCommandKeyConflict {
                        self.invalidateSubmissionCommand()
                    }

                    if failure.domainCode == "POS_PRICE_DISCREPANCY",
                       let authPrice = failure.authoritativePrice, authPrice > 0 {
                        let subPrice = failure.submittedPrice ?? 0
                        let name = !failure.productName.isEmpty
                            ? failure.productName
                            : (self.cartItems.first(where: { $0.accessory.accessoryID == failure.productID })?.accessory.name ?? failure.productID)
                        self.priceDiscrepancy = POSPriceDiscrepancyItem(
                            productID: failure.productID,
                            productName: name,
                            submittedPrice: subPrice,
                            authoritativePrice: authPrice
                        )
                        self.invalidateSubmissionCommand()
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        return
                    }

                    // The server names the offending animal; drop those lines so
                    // the operator reselects instead of retrying a dead unit.
                    // Only unit-level conflicts justify mutating the cart — a
                    // stock or permission error is retryable and must not
                    // silently delete the operator's selection.
                    if failure.isExactUnitConflict,
                       self.discardStaleExactUnits(
                        productID: failure.productID,
                        unitID: failure.unitID,
                        ringTag: failure.ringTag
                       ) {
                        self.invalidateSubmissionCommand()
                    }
                    self.submitError = self.localizedSubmitFailure(failure)
                    return
                }

                guard !transactionID.isEmpty else {
                    POSLogger.error("checkout.missing_txnid", category: "checkout", traceID: commandID, message: "Server did not return a valid transaction ID")
                    // The server may already have committed the command. Keep
                    // its ID so Retry is idempotent instead of creating a sale,
                    // keep the persisted record so a relaunch still warns, and
                    // say plainly that the outcome is unknown — telling the
                    // operator it simply "failed" invites a duplicate sale.
                    self.submitError = Language.get(
                        "POS_SubmitOutcomeUnknown",
                        alter: "لم يتأكد اكتمال البيع. قد تكون العملية سُجلت بالفعل — تحقق من سجل المبيعات قبل إعادة البيع. إعادة المحاولة آمنة ولن تُنشئ عملية مكررة."
                    )
                    return
                }

                POSLogger.info("checkout.success", category: "checkout", traceID: commandID, message: "Sale committed with txn: \(transactionID) (Total: \(serverTotal) \(serverCurrency))", metadata: [
                    "transactionId": transactionID,
                    "serverTotal": serverTotal,
                    "serverCurrency": serverCurrency,
                    "idempotentReplay": wasIdempotentReplay,
                    "paymentMethod": submittedPaymentMethod
                ])

                // The sale is committed and reconciled; nothing to recover.
                POSPendingCommandStore.clear()

                // The server is the money authority. If its total disagrees
                // with what was asserted, print the server's number and say so
                // rather than issuing a receipt whose lines do not add up.
                let authoritativeTotal = serverTotal > 0 ? serverTotal : submittedTotal
                let totalsDisagree = serverTotal > 0 && !POSMoney.matches(serverTotal, submittedTotal)
                if totalsDisagree {
                    POSLogger.warn("checkout.total_mismatch", category: "checkout", traceID: commandID, message: "Server total \(serverTotal) differs from submitted total \(submittedTotal)", metadata: [
                        "serverTotal": serverTotal,
                        "submittedTotal": submittedTotal
                    ])
                }

                let fallbackReceipt = POSCompletedReceipt(
                    transactionID: transactionID,
                    subtotal: submittedSubtotal,
                    discount: submittedDiscount,
                    total: authoritativeTotal,
                    currency: serverCurrency,
                    paymentMethod: submittedPaymentMethod,
                    cashReceived: acceptedCash,
                    cartItems: self.submittedCartSnapshot,
                    customerName: customerName ?? "",
                    customerPhone: customerPhone ?? ""
                )
                NotificationCenter.default.post(name: Notification.Name("PPAccountingDataDidChangeNotification"), object: nil)
                self.invalidateSubmissionCommand()
                self.isPreparingReceipt = true
                let receiptRequestID = UUID()
                self.receiptRequestID = receiptRequestID
                let mismatchNotice = totalsDisagree
                    ? Language.get(
                        "POS_Receipt_TotalMismatchNotice",
                        alter: "تم اعتماد البيع بالإجمالي المسجل في النظام، وهو يختلف عن الإجمالي المعروض في السلة. راجع أسعار الأصناف."
                    )
                    : nil

                // A receipt must never leave the operator trapped behind a
                // network-dependent loading state after the sale committed.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    guard let self, self.receiptRequestID == receiptRequestID else { return }
                    self.receiptRequestID = nil
                    self.isPreparingReceipt = false
                    self.receiptNotice = mismatchNotice ?? Language.get(
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
                        if needsFallback {
                            self.receiptNotice = mismatchNotice ?? Language.get(
                                "POS_Receipt_PartialNotice",
                                alter: "تمت عملية البيع، لكن تعذر تحديث بعض تفاصيل الإيصال من الخادم. تم تجهيز إيصال مؤكد بالبيانات المتاحة ويمكن طباعته أو مشاركته."
                            )
                        } else {
                            self.receiptNotice = mismatchNotice
                        }
                        self.completedReceipt = authoritativeReceipt ?? fallbackReceipt
                    }
                }
            }
        }

        return true
    }

    /// Clear the completed cart only after the receipt workflow is dismissed.
    /// Keeping the accepted cart snapshot alive makes the PDF fallback safe if
    /// the authoritative transaction read is briefly unavailable.
    ///
    /// This resets the **whole** commercial context. Previously it cleared only
    /// the cart, so the next customer silently inherited the last sale's
    /// discount and customer attribution — a money and audit defect, since the
    /// operator had no indication a discount was still armed.
    func acknowledgeCompletedReceipt() {
        receiptRequestID = nil
        completedReceipt = nil
        receiptNotice = nil
        cartItems = []
        searchText = ""
        attachedCheque = nil
        appliedDiscount = nil
        selectedCustomer = nil
        submitError = nil
        priceDiscrepancy = nil
        unsupportedWholesaleCartItems = []
        showWholesaleReconciliationAlert = false
        submittedCartSnapshot = []
        invalidateSubmissionCommand()
        POSLogger.info("cart.reset_after_sale", category: "cart", message: "Cart, discount and customer cleared after completing the sale")
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

    /// Warn once when a previous session dispatched a sale whose outcome was
    /// never observed, so the operator reconciles against POS history instead
    /// of ringing the same sale again.
    private func surfacePendingCommandIfNeeded() {
        guard inFlightSubmissionToken == nil, let pending = POSPendingCommandStore.pending() else { return }
        POSPendingCommandStore.clear()
        POSLogger.warn(
            "checkout.unconfirmed_recovered",
            category: "checkout",
            traceID: pending.commandID,
            message: "Found a dispatched POS command with no observed outcome",
            metadata: [
                "commandId": pending.commandID,
                "total": pending.total,
                "itemCount": pending.itemCount
            ]
        )
        unconfirmedSaleNotice = String(
            format: Language.get(
                "POS_UnconfirmedSaleNotice_Format",
                alter: "عملية بيع سابقة بقيمة %.2f ر.ق لم يتأكد اكتمالها (رقم الأمر %@). راجع سجل المبيعات قبل إعادة بيع نفس الأصناف."
            ),
            POSMoney.round(pending.total),
            pending.commandID
        )
    }

    func acknowledgeUnconfirmedSaleNotice() {
        unconfirmedSaleNotice = nil
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
    @State private var quantityEditingItem: POSCartItem? = nil

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
        posContent
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

                // `catalogGrid` owns its own empty presentation, and
                // `commandStatusView` owns the loading/error banners, so the
                // catalog has exactly one empty-state source of truth here.
                catalogGrid

                Spacer(minLength: 0)
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
                },
                onTapQuantity: { item in
                    handleQuantityTap(for: item)
                }
            )

            if let payload = flyPayload {
                flyingGhost(payload)
                    .allowsHitTesting(false)
            }

            if viewModel.isCheckoutBusy {
                // Two distinct phases: the callable is still in flight vs. the
                // sale is committed and the authoritative receipt is being
                // fetched. They are not interchangeable — the second is no
                // longer cancellable and must not read as "still selling".
                AdminLoadingOverlay(
                    message: viewModel.isPreparingReceipt
                        ? Language.get("POS_Receipt_Preparing", alter: "جارٍ تجهيز الإيصال...")
                        : Language.get("POS_Submitting", alter: "جارٍ إتمام البيع...")
                )
                .ignoresSafeArea()
            }

        }
        .ignoresSafeArea(.all, edges: .bottom)
        .coordinateSpace(name: POSFastSellSpace.root)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(item: $quantityEditingItem) { item in
            let branchStock = item.accessory.pos_branchStock()
            let unitsPerGroup = max(1, item.unitsPerGroup)
            let maxGroups = branchStock / unitsPerGroup
            let safeMaxGroups = max(0, maxGroups)
            let imageURL = PetAccessory.firstImageURL(for: item.accessory)

            let specimen = PPTactileSpecimenInfo(
                title: item.accessory.name ?? "",
                subtitle: String(format: Language.get("POS_AvailableStockFormat", alter: "المتوفر في الفرع: %d"), safeMaxGroups),
                imageURL: imageURL,
                sku: (item.accessory.sku?.isEmpty ?? true) ? nil : item.accessory.sku,
                barcode: (item.accessory.barcode?.isEmpty ?? true) ? nil : item.accessory.barcode,
                unitCost: item.unitPriceDisplay
            )

            let chips: [PPTactilePresetChip] = quantityPadChips(maxGroups: safeMaxGroups)

            let unitTitle = item.localizedGroupName.isEmpty ? Language.get("Units", alter: "وحدات") : item.localizedGroupName

            let config = PPTactileNumberPadConfig(
                title: Language.get("POS_EditCartQuantity", alter: "تعديل كمية السلة"),
                subtitle: item.accessory.name,
                mode: .quantity(unit: unitTitle, allowZero: true, maxLimit: max(1, safeMaxGroups)),
                initialValue: Double(item.quantity),
                referenceValue: Double(safeMaxGroups),
                referenceLabel: Language.get("POS_BranchAvailableStock", alter: "المتاح بالفرع"),
                showsVarianceTelemetry: false,
                specimen: specimen,
                customChips: chips,
                primaryActionTitle: Language.get("POS_ConfirmQuantity", alter: "تأكيد الكمية")
            )

            PPTactileNumberPadSheet(
                config: config,
                onCommit: { newQty in
                    let target = Int(newQty)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.updateQuantity(item, newQuantity: target)
                    quantityEditingItem = nil
                },
                onDismiss: {
                    quantityEditingItem = nil
                }
            )
        }
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
        .sheet(item: $viewModel.priceDiscrepancy) { discrepancy in
            POSPriceReconciliationSheet(
                discrepancy: discrepancy,
                onApplyAuthoritativePrice: {
                    viewModel.reconcilePrice(productID: discrepancy.productID, newPrice: discrepancy.authoritativePrice)
                },
                onRemoveItem: {
                    if let idx = viewModel.cartIndex(for: discrepancy.productID) {
                        viewModel.removeFromCart(viewModel.cartItems[idx])
                    }
                    viewModel.dismissPriceDiscrepancy()
                },
                onDismiss: {
                    viewModel.dismissPriceDiscrepancy()
                }
            )
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
        .onChange(of: viewModel.submitError) { error in
            guard let error = error, !error.isEmpty else { return }
            PPAlertHelper.showError(
                in: nil,
                title: Language.get("Error", alter: "خطأ"),
                subtitle: error
            ) {
                // PPAlertHelper's completion is not main-actor isolated.
                Task { @MainActor in viewModel.submitError = nil }
            }
        }
        .onChange(of: viewModel.unconfirmedSaleNotice) { notice in
            guard let notice = notice, !notice.isEmpty else { return }
            PPAlertHelper.showWarning(
                in: nil,
                title: Language.get("POS_UnconfirmedSaleTitle", alter: "بيع غير مؤكد"),
                subtitle: notice
            ) {
                Task { @MainActor in viewModel.acknowledgeUnconfirmedSaleNotice() }
            }
        }
        .onChange(of: viewModel.showWholesaleReconciliationAlert) { isPresented in
            guard isPresented else { return }
            PPAlertHelper.showConfirmation(
                in: nil,
                title: Language.get("POS_Wholesale_Unavailable_Title", alter: "البيع بالجملة غير متاح لبعض الأصناف"),
                subtitle: viewModel.wholesaleUnavailableAlertMessage,
                confirmButton: Language.get("POS_Remove_Unavailable_Items", alter: "إزالة الأصناف غير المتاحة ومتابعة الجملة"),
                cancelButton: Language.get("POS_Stay_In_Retail", alter: "البقاء في نمط التجزئة"),
                icon: UIImage(systemName: "exclamationmark.triangle.fill"),
                confirmBlock: { _, didConfirm in
                    if didConfirm {
                        viewModel.confirmSwitchToWholesale(removeUnavailable: true)
                    } else {
                        viewModel.showWholesaleReconciliationAlert = false
                    }
                },
                cancelBlock: {
                    viewModel.showWholesaleReconciliationAlert = false
                }
            )
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
        .padding(.top, 0)
        .padding(.bottom, AdminSpacing.md)
        .background(AdminSurface.background)
        .overlay(
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: AdminStroke.hairline),
            alignment: .bottom
        )
    }

    private var sellTypeMenuButton: some View {
        Menu {
            ForEach(POSSalesChannel.allCases) { channel in
                Button {
                    dismissKeyboard()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.requestSalesChannelChange(channel)
                } label: {
                    if viewModel.salesChannel == channel {
                        Label(channel.title, systemImage: "checkmark")
                    } else {
                        Label(channel.title, systemImage: channel.symbol)
                    }
                }
                .disabled(channel == .wholesale && !viewModel.canSellWholesale)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AdminSurface.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                    )

                HStack(spacing: 6) {
                    Image(systemName: viewModel.salesChannel.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .ppPrimary))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(Language.get("POS_SalesChannel_Title", alter: "نوع البيع"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)

                        Text(viewModel.salesChannel.title)
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)
                    }

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 44)
            .fixedSize(horizontal: true, vertical: false)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Language.get("POS_SalesChannel_Title", alter: "نوع البيع")): \(viewModel.salesChannel.title)")
        .accessibilityHint(Language.get("POS_SalesChannel_Hint", alter: "انقر لاختيار نوع البيع بين قطاعي وجملة."))
    }

    private var salesChannelSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(POSSalesChannel.allCases) { channel in
                let isSelected = viewModel.salesChannel == channel
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.requestSalesChannelChange(channel)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: channel.symbol)
                            .font(.system(size: 13, weight: .semibold))
                        Text(channel.title)
                            .font(AdminType.subheadlineBold)
                    }
                    .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminCommandInk.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        isSelected ? AdminSurface.surface : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .shadow(color: isSelected ? Color.black.opacity(0.06) : Color.clear, radius: 4, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(channel == .wholesale && !viewModel.canSellWholesale)
                .opacity((channel == .wholesale && !viewModel.canSellWholesale) ? 0.45 : 1.0)
            }
        }
        .padding(4)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var commandHeaderView: some View {
        AdminSovereignNavigationBar(
            title: Language.get("POS_Title", alter: "بيع سريع"),
            subtitle: headerBranchSubtitle,
            statusDotColor: Color(uiColor: .ppSuccess),
            isModal: true,
            customTopSpacing: PPStatusBarHelper.statusBarHeight,
            onBack: {
                dismissKeyboard()
                // Leaving mid-checkout tears down the view model, which loses
                // the receipt, the change due and the operator's only record of
                // a sale that may already have committed. Consistent with
                // `handleCatalogTap`, the screen stays put until the
                // transaction reaches a terminal state.
                guard !viewModel.isCheckoutBusy else {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    return
                }
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            },
            onSubtitleTap: {
                dismissKeyboard()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isBranchPickerVisible.toggle()
                }
            },
            isSubtitleActionActive: isBranchPickerVisible
        ) {
            HStack(spacing: 8) {
                // Reservation button
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

                // Sell Type Menu Button (replaces segmented control below navbar)
                sellTypeMenuButton
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
                            salesChannel: viewModel.salesChannel,
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

    // MARK: - Quantity Editing

    private func handleQuantityTap(for item: POSCartItem) {
        if item.isIndividuallyTracked {
            openUnitPicker(for: item.accessory)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            quantityEditingItem = item
        }
    }

    /// Preset chips for the cart-quantity number pad.
    ///
    /// Built outside the sheet's `@ViewBuilder` closure: a `ViewBuilder` only
    /// accepts declarations and view-producing statements, so conditional
    /// array construction has to live in a plain function.
    ///
    /// The "full stock" chip is omitted when the branch has nothing available,
    /// because a `.set(0)` shortcut labelled "كامل المخزون (0)" would read as a
    /// stock action while actually clearing the line.
    private func quantityPadChips(maxGroups: Int) -> [PPTactilePresetChip] {
        var chips: [PPTactilePresetChip] = [
            PPTactilePresetChip(title: "+1".normalizedEnglishDigits, action: .delta(1)),
            PPTactilePresetChip(title: "+5".normalizedEnglishDigits, action: .delta(5)),
            PPTactilePresetChip(title: "+10".normalizedEnglishDigits, action: .delta(10))
        ]

        if maxGroups > 0 {
            chips.append(
                PPTactilePresetChip(
                    title: String(format: Language.get("Max_Stock_Format", alter: "كامل المخزون (%d)"), maxGroups).normalizedEnglishDigits,
                    icon: "shippingbox.fill",
                    action: .set(Double(maxGroups)),
                    tint: AdminSurface.primary
                )
            )
        }

        chips.append(
            PPTactilePresetChip(
                title: Language.get("Remove_From_Cart", alter: "حذف من السلة"),
                icon: "trash.fill",
                action: .set(0),
                tint: AdminSurface.crimson
            )
        )

        return chips
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
    var onTapQuantity: ((POSCartItem) -> Void)? = nil

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
            let chips: [PPTactilePresetChip] = [
                PPTactilePresetChip(
                    title: Language.get("POS_ExactCash", alter: "المبلغ بالضبط"),
                    icon: "banknote.fill",
                    action: .matchReference,
                    tint: emeraldColor
                ),
                PPTactilePresetChip(title: "+10".normalizedEnglishDigits, action: .delta(10)),
                PPTactilePresetChip(title: "+20".normalizedEnglishDigits, action: .delta(20)),
                PPTactilePresetChip(title: "+50".normalizedEnglishDigits, action: .delta(50)),
                PPTactilePresetChip(title: "+100".normalizedEnglishDigits, action: .delta(100)),
                PPTactilePresetChip(
                    title: Language.get("Reset", alter: "إعادة ضبط"),
                    icon: "arrow.counterclockwise",
                    action: .zeroOut,
                    tint: AdminSurface.secondaryText
                )
            ]
            let config = PPTactileNumberPadConfig(
                title: Language.get("POS_CustomCashReceivedTitle", alter: "المبلغ المستلم من العميل"),
                subtitle: String(format: Language.get("POS_CartTotalRequiredFormat", alter: "إجمالي السلة المطلوب: %@"), currency(viewModel.cartTotal)),
                mode: .amount(currency: Language.get("QAR", alter: "ر.ق")),
                initialValue: (isCustomTender ? tenderedAmount : nil) ?? viewModel.cartTotal,
                referenceValue: viewModel.cartTotal,
                referenceLabel: Language.get("POS_CartTotalRequired", alter: "المطلوب"),
                customChips: chips,
                primaryActionTitle: Language.get("Confirm", alter: "تأكيد")
            )
            PPTactileNumberPadSheet(
                config: config,
                onCommit: { amount in
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

            POSStackedCartDeck(
                items: viewModel.cartItems,
                currency: currency,
                onIncrease: { item in
                    if item.isIndividuallyTracked {
                        onOpenUnitPicker(item.accessory)
                    } else {
                        viewModel.increaseQuantity(item)
                    }
                },
                onDecrease: { item in
                    viewModel.decreaseQuantity(item)
                },
                onRemove: { item in
                    viewModel.removeFromCart(item)
                },
                onOpenUnitPicker: { accessory in
                    onOpenUnitPicker(accessory)
                },
                onBringToFront: { item in
                    viewModel.bringItemToFront(item)
                },
                onTapQuantity: { item in
                    onTapQuantity?(item)
                }
            )
            .padding(.bottom, 6)
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
        let hasExpired = viewModel.hasExpiredItems
        return VStack(spacing: 8) {
            if hasExpired {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(Language.get("pos_checkout_blocked_expired", alter: "لا يمكن إتمام البيع: السلة تحتوي على منتج منتهي الصلاحية"))
                        .font(AdminType.captionBold)
                        .lineLimit(2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            POSSlideToSaleButton(
                hasItems: hasItems && !hasExpired,
                isCheckoutBusy: viewModel.isCheckoutBusy,
                totalAmountText: currency(viewModel.cartTotal),
                accentColor: hasExpired ? Color.gray : methodAccentColor(viewModel.selectedPaymentMethod),
                onSlideComplete: {
                    if hasExpired {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        return false
                    }
                    if isChequeMissing {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        isShowingScanner = true
                        return false
                    }
                    return viewModel.submitOrder(cashReceived: tenderedAmount)
                }
            )
        }
    }
}

// MARK: - Slide to Sale Kinetic Slider

private struct POSSlideToSaleButton: View {
    let hasItems: Bool
    let isCheckoutBusy: Bool
    let totalAmountText: String
    let accentColor: Color
    /// Returns `true` only when a submission actually started.
    ///
    /// The slider used to latch `isCompleted` and rely on an `isCheckoutBusy`
    /// transition to unlatch it. Every early return from the handler — expired
    /// item, missing cheque, a rejected tender — never sets `isCheckoutBusy`,
    /// so that transition never arrived and the control stayed latched with a
    /// checkmark, refusing all further drags. Reporting acceptance explicitly
    /// keeps the knob honest without a timer.
    let onSlideComplete: () -> Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var isCompleted: Bool = false
    @State private var shimmerPhase: CGFloat = -0.5

    private let knobDiameter: CGFloat = 46.0
    private let trackHeight: CGFloat = 54.0
    private let horizontalPadding: CGFloat = 4.0

    private var accessibilityLabelText: String {
        if isCheckoutBusy {
            return Language.get("POS_Submitting", alter: "جارٍ إتمام العملية...")
        }
        if !hasItems {
            return Language.get("POS_SelectItemsPrompt", alter: "اختر منتجات من الكتالوج للبدء")
        }
        return Language.get("POS_SlideToSale", alter: "اسحب لإتمام عملية البيع")
    }

    /// Commits the sale and settles the knob based on whether the submission
    /// was actually accepted. Shared by the drag gesture and the accessibility
    /// activation so both paths behave identically.
    private func commitSale(maxSlide: CGFloat) {
        guard hasItems && !isCheckoutBusy && !isCompleted else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
            dragOffset = maxSlide
            isCompleted = true
        }
        let accepted = onSlideComplete()
        if !accepted {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                dragOffset = 0
                isCompleted = false
            }
        }
    }

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
                                commitSale(maxSlide: maxSlide)
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
            // A drag is the only way a sighted operator commits the sale, and
            // VoiceOver / Switch Control / AssistiveTouch cannot perform one.
            // Exposing the track as a single activatable button makes checkout
            // reachable by assistive technology without altering the visuals.
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityValue(hasItems ? totalAmountText : "")
            .accessibilityHint(
                hasItems && !isCheckoutBusy
                    ? Language.get("POS_SlideToSale_A11yHint", alter: "انقر مرتين لإتمام عملية البيع")
                    : ""
            )
            .accessibilityAddTraits(hasItems && !isCheckoutBusy ? [] : .isStaticText)
            .accessibilityAction {
                commitSale(maxSlide: maxSlide)
            }
            .onAppear {
                // `repeatForever` is decorative; Reduce Motion must stop it
                // rather than leave an endless animation running.
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.5
                }
            }
            .onChange(of: reduceMotion) { isReduced in
                guard isReduced else { return }
                shimmerPhase = -0.5
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
        POSMoney.parse(inputText)
    }

    private var changeAmount: Double {
        max(0, POSMoney.round(parsedAmount - cartTotal))
    }

    /// Whether the entered tender covers the sale.
    ///
    /// Compared through `POSMoney` so this gate agrees exactly with the
    /// model-side check in `submitOrder`. Raw `>=` on unrounded doubles could
    /// disable Confirm for a tender the operator correctly typed as the
    /// displayed total, with nothing on screen explaining why.
    private var coversTotal: Bool {
        POSMoney.matches(parsedAmount, cartTotal) || POSMoney.round(parsedAmount) > cartTotal
    }

    /// An empty field means "exact change", which is always valid.
    private var isTenderValid: Bool {
        parsedAmount <= 0 || coversTotal
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
                        if coversTotal {
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

                                Text(currency(POSMoney.round(cartTotal - parsedAmount)))
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
                        let finalAmount = parsedAmount > 0 ? POSMoney.round(parsedAmount) : cartTotal
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
                            isTenderValid ? emeraldColor : Color.gray.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                    .disabled(!isTenderValid)
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
                                        let branchStock = accessory.pos_branchStock()
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
        let branchStock = accessory.pos_branchStock()
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

                    // SubSubKind & SubSubKindItem Badges
                    if !unit.subSubKindName.isEmpty || !unit.subSubKindItemName.isEmpty {
                        HStack(spacing: 4) {
                            if !unit.subSubKindName.isEmpty {
                                Text(unit.subSubKindName)
                                    .font(AdminType.caption2Bold)
                                    .foregroundColor(rosePrimary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(rosePrimary.opacity(0.08), in: Capsule())
                            }
                            if !unit.subSubKindItemName.isEmpty {
                                Text(unit.subSubKindItemName)
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(AdminSurface.primaryText.opacity(0.05), in: Capsule())
                            }
                        }
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
                        } else if unit.sellingPrice <= 0 {
                            Text(Language.get("POS_ExactAnimalPriceRequired", alter: "يحتاج تسعير"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(.orange)
                        } else {
                            Text(Language.get("AtAnotherBranch", alter: "في فرع آخر"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(.secondary)
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
                    } else if unit.sellingPrice > 0 {
                        Text(currency(unit.sellingPrice))
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.secondaryText)

                        Text(Language.get("POS_UnitDirectPrice", alter: "سعر السجل"))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
                    } else {
                        Text("—")
                            .font(AdminType.headline)
                            .foregroundColor(.orange)
                    }
                }
            }
            .opacity(unit.isSelectable ? 1.0 : 0.55)
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
                if let url = resolvedImageURL {
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

    private var resolvedImageURL: URL? {
        if let url = PetAccessory.firstImageURL(for: accessory) {
            return url
        }
        for candidate in accessory.imageURLsArray {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) {
                return url
            }
        }
        return nil
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
    var salesChannel: POSSalesChannel = .retail
    let currency: (Double) -> String
    let onTap: (CGRect) -> Void

    private var isWholesaleMode: Bool { salesChannel == .wholesale }
    private var isSellableInChannel: Bool {
        if isWholesaleMode {
            return accessory.pos_supportsWholesale
        }
        return true
    }
    private var activePrice: Double {
        if isWholesaleMode {
            return accessory.pos_wholesalePrice()
        }
        return accessory.pos_canonicalUnitPrice
    }

    private var tileHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 160 : 134
    }

    @MainActor
    private var totalStock: Int {
        if accessory.noStock || accessory.isBlocked || accessory.isDeleted || accessory.isDisabled || accessory.isArchived {
            return 0
        }
        return accessory.pos_branchStock()
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
                            if isWholesaleMode && !accessory.pos_supportsWholesale {
                                Text(Language.get("POS_Wholesale_Unavailable_Badge", alter: "غير متاح للجملة"))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Color.gray)
                                    .lineLimit(1)
                            } else {
                                Text(currency(activePrice))
                                    .font(AdminType.caption2Bold)
                                    .foregroundColor(isWholesaleMode ? Color(uiColor: .systemTeal) : AdminSurface.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }

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
                .opacity(isWholesaleMode && !accessory.pos_supportsWholesale ? 0.45 : 1.0)
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
                    HStack(spacing: 4) {
                        if item.unitsPerGroup > 1 || item.salesChannel == "wholesale" {
                            Text(item.localizedGroupName)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(item.salesChannel == "wholesale" ? Color(uiColor: .systemTeal) : AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background((item.salesChannel == "wholesale" ? Color(uiColor: .systemTeal) : AdminSurface.primary).opacity(0.12), in: Capsule())
                        }
                        if let lotNum = item.lotNumber, !lotNum.isEmpty {
                            Text("LOT: \(lotNum)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                        }
                        if item.isExpired {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text(Language.get("pos_cart_item_expired", alter: "منتهي الصلاحية"))
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.14), in: Capsule())
                        } else if item.isNearExpiry {
                            HStack(spacing: 2) {
                                Image(systemName: "clock.badge.exclamationmark.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text(Language.get("pos_cart_item_near_expiry", alter: "قريب الانتهاء"))
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                        }
                        if item.unitsPerGroup > 1 {
                            Text(String(format: Language.get("POS_BaseUnitsDeductionFormat", alter: "(%d قطعة)"), item.baseUnitQuantity))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        Text(formatCurrency(item.unitPriceDisplay))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
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

            if !item.unitSubSubKinds.isEmpty || !item.unitSubSubKindItems.isEmpty {
                HStack(spacing: 6) {
                    if !item.unitSubSubKinds.isEmpty {
                        Text(item.unitSubSubKinds.joined(separator: " · "))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.primary)
                    }
                    if !item.unitSubSubKindItems.isEmpty {
                        Text("(\(item.unitSubSubKindItems.joined(separator: " · ")))")
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.medium)
                .stroke(item.isExpired ? Color.red.opacity(0.6) : AdminSurface.hairline, lineWidth: item.isExpired ? 1.5 : 1.0)
        )
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "QAR"
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f %@", value, Language.get("QAR", alter: "ر.ق"))
    }
}

// MARK: - POS Stacked Cart Row

private struct POSCartCardRow: View {
    let item: POSCartItem
    let currency: (Double) -> String
    var isFrontCard: Bool = true
    let onIncrease: () -> Void
    let onDecrease: () -> Void
    let onRemove: () -> Void
    let onOpenUnitPicker: (() -> Void)?
    var onTapQuantity: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: item.isIndividuallyTracked ? 7 : 0) {
            // MARK: - Primary Row: Icon, Identity, Line Total, Stepper
            HStack(spacing: 8) {
                // Leading category / pet icon squircle
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(item.isIndividuallyTracked ? Color.orange.opacity(0.14) : AdminSurface.primary.opacity(0.10))
                        .frame(width: 36, height: 36)

                    Image(systemName: item.isIndividuallyTracked ? "pawprint.fill" : "shippingbox.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(item.isIndividuallyTracked ? Color.orange : AdminSurface.primary)
                }

                // Name & Subtitle Details
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(item.accessory.name)
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if item.isIndividuallyTracked {
                            HStack(spacing: 2) {
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 7, weight: .bold))
                                Text(Language.get("POS_LiveSpecimen_Tag", alter: "حيوان حي"))
                                    .font(Font.custom("Beiruti-Bold", size: 10))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12), in: Capsule(style: .continuous))
                            .foregroundColor(Color.orange)
                        }
                    }

                    HStack(spacing: 5) {
                        if !item.isIndividuallyTracked {
                            if item.unitsPerGroup > 1 {
                                Text("\(item.localizedGroupName) (\(item.unitsPerGroup))")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(AdminSurface.primary.opacity(0.12), in: Capsule(style: .continuous))
                                    .foregroundColor(AdminSurface.primary)
                            }

                            if let lotNum = item.lotNumber, !lotNum.isEmpty {
                                Text("LOT: \(lotNum)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.12), in: Capsule(style: .continuous))
                                    .foregroundColor(Color.blue)
                            }
                            if item.isExpired {
                                HStack(spacing: 2) {
                                    Image(systemName: "exclamationmark.octagon.fill")
                                        .font(.system(size: 8, weight: .bold))
                                    Text(Language.get("pos_cart_item_expired", alter: "منتهي الصلاحية"))
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(0.15), in: Capsule(style: .continuous))
                                .foregroundColor(Color.red)
                            } else if item.isNearExpiry {
                                HStack(spacing: 2) {
                                    Image(systemName: "clock.badge.exclamationmark.fill")
                                        .font(.system(size: 8, weight: .bold))
                                    Text(Language.get("pos_cart_item_near_expiry", alter: "قريب الانتهاء"))
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.15), in: Capsule(style: .continuous))
                                .foregroundColor(Color.orange)
                            }
                        }

                        Text(currency(item.unitPriceDisplay) + " " + Language.get("POS_Each", alter: "للقطعة"))
                            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
                .layoutPriority(0)

                Spacer(minLength: 4)

                // Price & Controls
                HStack(spacing: 6) {
                    Text(currency(item.lineTotal))
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)

                    if isFrontCard {
                        // Tactile Stepper Capsule (widened for easy tap & breathing room)
                        HStack(spacing: 3) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onDecrease()
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AdminSurface.primary)
                                    .frame(width: 28, height: 28)
                                    .background(AdminSurface.control, in: Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel(Language.get("POS_DecreaseQty", alter: "إنقاص الكمية"))

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onTapQuantity?()
                            } label: {
                                Text("\(item.quantity)")
                                    .font(AdminType.subheadlineBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                    .monospacedDigit()
                                    .frame(minWidth: 28, minHeight: 28, alignment: .center)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel(String(format: Language.get("POS_QuantityValueFormat", alter: "الكمية %d، اضغط للتعديل"), item.quantity))
                            .accessibilityHint(Language.get("POS_TapToEditQuantity_Hint", alter: "اضغط لتعديل الكمية بواسطة لوحة المفاتيح"))

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onIncrease()
                            } label: {
                                Image(systemName: item.isIndividuallyTracked ? "pawprint.fill" : "plus")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(item.isIndividuallyTracked ? Color.orange : AdminSurface.primary, in: Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel(item.isIndividuallyTracked
                                ? Language.get("POS_SelectUnits", alter: "اختيار الحيوانات")
                                : Language.get("POS_IncreaseQty", alter: "زيادة الكمية"))
                        }
                        .padding(3)
                        .background(AdminSurface.surface.opacity(0.9), in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 0.5)
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(3)
                    } else {
                        // Subtle count badge for background cards
                        Text("x\(item.quantity)")
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AdminSurface.control, in: Capsule(style: .continuous))
                    }
                }
            }

            // MARK: - Dedicated Rings Shelf for Live Pets
            if item.isIndividuallyTracked {
                livePetRingsShelf
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, item.isIndividuallyTracked ? 10 : 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    item.isExpired
                        ? Color.red.opacity(0.7)
                        : (item.isIndividuallyTracked
                            ? Color.orange.opacity(colorScheme == .dark ? 0.50 : 0.35)
                            : Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.7 : 0.4)),
                    lineWidth: item.isExpired ? 1.5 : (item.isIndividuallyTracked ? 1.0 : 0.75)
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.30 : (item.isIndividuallyTracked ? 0.08 : 0.06)),
            radius: 6,
            x: 0,
            y: 2
        )
        .overlay(alignment: .topLeading) {
            if isFrontCard {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onRemove()
                } label: {
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ? Color(uiColor: .tertiarySystemGroupedBackground) : Color(uiColor: .systemGray6))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(AdminSurface.hairline, lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 2, x: 0, y: 1)

                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.9))
                    }
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .offset(x: Language.isRTL() ? 4 : -4, y: -4)
                .accessibilityLabel(Language.get("POS_RemoveItem", alter: "حذف من السلة"))
            }
        }
        .accessibilityElement(children: isFrontCard ? .contain : .combine)
        .accessibilityLabel(isFrontCard
            ? "\(item.accessory.name), \(item.quantity), \(currency(item.lineTotal))"
            : "\(item.accessory.name), \(item.quantity) \(Language.get("POS_Items", alter: "عناصر")), \(currency(item.lineTotal))")
        .accessibilityHint(isFrontCard ? "" : Language.get("POS_BringCardToFront_Hint", alter: "اضغط مرتين لتقديم هذه البطاقة إلى واجهة السلة"))
    }

    // MARK: - Live Pet Rings Shelf
    @ViewBuilder
    private var livePetRingsShelf: some View {
        let visibleTags = item.unitRingTags.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let effectiveTags = !visibleTags.isEmpty ? visibleTags : item.unitIDs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpenUnitPicker?()
        } label: {
            HStack(spacing: 6) {
                // Leading Ring Indicator & Title
                HStack(spacing: 3) {
                    Image(systemName: "circle.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.orange)

                    Text(Language.get("POS_LivePet_Rings_Label", alter: "الحجول:"))
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundColor(Color.orange)
                }
                .fixedSize(horizontal: true, vertical: false)

                if !effectiveTags.isEmpty {
                    // Horizontal scroll of full ring tags
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(Array(effectiveTags.enumerated()), id: \.offset) { _, tag in
                                HStack(spacing: 3) {
                                    Image(systemName: "tag.fill")
                                        .font(.system(size: 8, weight: .bold))
                                    Text(verbatim: "#\(tag)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.orange.opacity(0.16))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.orange.opacity(0.35), lineWidth: 0.8)
                                )
                                .foregroundColor(Color.orange)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(Language.get("POS_SelectRingTagsPrompt", alter: "اضغط لاختيار أرقام الحجول"))
                            .font(Font.custom("Beiruti-Bold", size: 11))
                    }
                    .foregroundColor(Color.orange)
                }

                Spacer(minLength: 2)

                // Sub-sub-kind variants (if present)
                if !item.unitSubSubKinds.isEmpty {
                    Text(item.unitSubSubKinds.joined(separator: " · "))
                        .font(Font.custom("Beiruti-Regular", size: 10))
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }

                // Edit / Picker Tap Hint
                if isFrontCard {
                    HStack(spacing: 2) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .bold))
                        Text(Language.get("POS_EditRings", alter: "تعديل"))
                            .font(Font.custom("Beiruti-Bold", size: 11))
                    }
                    .foregroundColor(Color.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 0.6)
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.orange.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.orange.opacity(0.22), lineWidth: 0.8)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Language.get("POS_SelectedRingsA11y", alter: "الحجول المختارة: ") + effectiveTags.joined(separator: ", "))
        .accessibilityHint(Language.get("POS_TapToChangeRings_Hint", alter: "اضغط لتعديل اختيار الحجول"))
    }
}

// MARK: - POS Stacked Cart Deck

private struct POSStackedCartDeck: View {
    let items: [POSCartItem]
    let currency: (Double) -> String
    let onIncrease: (POSCartItem) -> Void
    let onDecrease: (POSCartItem) -> Void
    let onRemove: (POSCartItem) -> Void
    let onOpenUnitPicker: (PetAccessory) -> Void
    let onBringToFront: (POSCartItem) -> Void
    var onTapQuantity: ((POSCartItem) -> Void)? = nil

    @State private var isExpanded: Bool = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    private func localizedHiddenText(_ count: Int) -> String {
        if Language.isRTL() {
            if count == 1 {
                return Language.get("POS_Cart_OneMoreItem", alter: "+1 عنصر آخر")
            } else if count == 2 {
                return Language.get("POS_Cart_TwoMoreItems", alter: "+2 عنصران آخران")
            } else if count <= 10 {
                return String(format: Language.get("POS_Cart_FewMoreItems_Format", alter: "+%d عناصر أخرى"), count)
            } else {
                return String(format: Language.get("POS_Cart_ManyMoreItems_Format", alter: "+%d عنصرًا آخر"), count)
            }
        } else {
            return count == 1
                ? Language.get("POS_Cart_OneMoreItem_EN", alter: "+1 more item")
                : String(format: Language.get("POS_Cart_MoreItems_Format_EN", alter: "+%d more items"), count)
        }
    }

    var body: some View {
        let display = Array(items.reversed())
        VStack(spacing: 4) {
            if isExpanded {
                expandedDeckView(displayItems: display)
            } else {
                collapsedDeckView(displayItems: display)
            }
        }
        .onChange(of: items.count) { newCount in
            if newCount <= 1 && isExpanded {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isExpanded = false
                }
            }
        }
    }

    // MARK: - Collapsed Stack View

    private func collapsedDeckView(displayItems: [POSCartItem]) -> some View {
        let hiddenCount = max(0, displayItems.count - 1)
        return VStack(spacing: 5) {
            ZStack(alignment: .top) {
                // Background Card 2 (if 3 or more items)
                if displayItems.count >= 3 {
                    let item2 = displayItems[2]
                    POSCartCardRow(
                        item: item2,
                        currency: currency,
                        isFrontCard: false,
                        onIncrease: {},
                        onDecrease: {},
                        onRemove: {},
                        onOpenUnitPicker: nil
                    )
                    .offset(y: -14)
                    .scaleEffect(0.92, anchor: .top)
                    .opacity(0.55)
                    .zIndex(1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            onBringToFront(item2)
                        }
                    }
                }

                // Background Card 1 (if 2 or more items)
                if displayItems.count >= 2 {
                    let item1 = displayItems[1]
                    POSCartCardRow(
                        item: item1,
                        currency: currency,
                        isFrontCard: false,
                        onIncrease: {},
                        onDecrease: {},
                        onRemove: {},
                        onOpenUnitPicker: nil
                    )
                    .offset(y: -7)
                    .scaleEffect(0.96, anchor: .top)
                    .opacity(0.80)
                    .zIndex(2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            onBringToFront(item1)
                        }
                    }
                }

                // Front / Top Card
                if let frontItem = displayItems.first {
                    POSCartCardRow(
                        item: frontItem,
                        currency: currency,
                        isFrontCard: true,
                        onIncrease: {
                            if frontItem.isIndividuallyTracked {
                                onOpenUnitPicker(frontItem.accessory)
                            } else {
                                onIncrease(frontItem)
                            }
                        },
                        onDecrease: { onDecrease(frontItem) },
                        onRemove: { onRemove(frontItem) },
                        onOpenUnitPicker: { onOpenUnitPicker(frontItem.accessory) },
                        onTapQuantity: { onTapQuantity?(frontItem) }
                    )
                    .offset(y: max(0, dragOffset * 0.15))
                    .zIndex(3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, displayItems.count >= 3 ? 15 : (displayItems.count == 2 ? 8 : 2))

            // Expandable Trailer Handle (when more than 1 item)
            if hiddenCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AdminSurface.primary)

                    Text(localizedHiddenText(hiddenCount))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.primaryText)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4.5)
                .background(AdminSurface.control, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.05), radius: 3, x: 0, y: 1)
                .contentShape(Capsule(style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(localizedHiddenText(hiddenCount))
                .accessibilityHint(Language.get("POS_Cart_Expand_Hint", alter: "اضغط مرتين لإظهار قائمة عناصر السلة بالكامل"))
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        isExpanded = true
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            if value.translation.height > 0 {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 18 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                    isExpanded = true
                                }
                            }
                            dragOffset = 0
                        }
                )
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Expanded List View

    private func expandedDeckView(displayItems: [POSCartItem]) -> some View {
        let dynamicDeckHeight: CGFloat = displayItems.reduce(CGFloat(0)) { total, item in
            total + (item.isIndividuallyTracked ? 96 : 64)
        } + 12
        let maxDeckHeight = min(dynamicDeckHeight, UIScreen.main.bounds.height * 0.40)

        return VStack(spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 7) {
                    ForEach(displayItems) { item in
                        POSCartCardRow(
                            item: item,
                            currency: currency,
                            isFrontCard: true,
                            onIncrease: {
                                if item.isIndividuallyTracked {
                                    onOpenUnitPicker(item.accessory)
                                } else {
                                    onIncrease(item)
                                }
                            },
                            onDecrease: { onDecrease(item) },
                            onRemove: {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                    onRemove(item)
                                }
                            },
                            onOpenUnitPicker: { onOpenUnitPicker(item.accessory) },
                            onTapQuantity: { onTapQuantity?(item) }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .scale(scale: 0.90))
                        ))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
            }
            .frame(maxHeight: maxDeckHeight)

            // Collapse Handle
            HStack(spacing: 5) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AdminSurface.primary)

                Text(Language.get("POS_Cart_Collapse", alter: "طي عناصر السلة"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.secondaryText)

                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(AdminSurface.control, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.5)
            )
            .contentShape(Capsule(style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Language.get("POS_Cart_Collapse", alter: "طي عناصر السلة"))
            .accessibilityHint(Language.get("POS_Cart_Collapse_Hint", alter: "اضغط مرتين للعودة لعرض السلة المكدس"))
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                    isExpanded = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        if value.translation.height < -18 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                isExpanded = false
                            }
                        }
                    }
            )
            .padding(.bottom, 2)
        }
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
    @State private var showTactilePad: Bool = false

    private var emeraldColor: Color { Color(red: 0.06, green: 0.72, blue: 0.51) }

    private var percentPresets: [Double] {
        [5, 10, 15, 20, 25, 50]
    }

    private var fixedPresets: [Double] {
        let candidates: [Double] = [5, 10, 15, 20, 25, 50, 100, 200]
        return candidates.filter { $0 < subtotal }
    }

    /// The discount the sheet would apply. Built once here so the previewed
    /// amount and the applied amount can never diverge: both go through
    /// `POSDiscount.calculateAmount`, which is the only discount authority.
    private var draftDiscount: POSDiscount {
        POSDiscount(
            type: discountType,
            value: discountType == .percentage ? percentageValue : POSMoney.parse(fixedValueText)
        )
    }

    private var calculatedDiscountAmount: Double {
        draftDiscount.calculateAmount(subtotal: subtotal)
    }

    private var calculatedNetTotal: Double {
        max(0, POSMoney.round(subtotal - calculatedDiscountAmount))
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
            .sheet(isPresented: $showTactilePad) {
                if discountType == .percentage {
                    let config = PPTactileNumberPadConfig(
                        title: Language.get("POS_Discount_Percentage", alter: "نسبة الخصم"),
                        subtitle: String(format: Language.get("POS_OriginalSubtotalFormat", alter: "المجموع الأصلي للسلة: %@"), currency(subtotal)),
                        mode: .percentage(maxLimit: 100),
                        initialValue: percentageValue,
                        referenceValue: 100,
                        referenceLabel: Language.get("Max", alter: "الحد الأقصى"),
                        primaryActionTitle: Language.get("Apply", alter: "تطبيق")
                    )
                    PPTactileNumberPadSheet(
                        config: config,
                        onCommit: { val in
                            percentageValue = min(100, max(0, val))
                            selectedPercentPreset = percentageValue
                            showTactilePad = false
                        },
                        onDismiss: {
                            showTactilePad = false
                        }
                    )
                } else {
                    let sanitized = fixedValueText.replacingOccurrences(of: ",", with: ".")
                    let currentVal = Double(sanitized) ?? 0.0
                    let config = PPTactileNumberPadConfig(
                        title: Language.get("POS_Discount_Amount", alter: "قيمة الخصم"),
                        subtitle: String(format: Language.get("POS_OriginalSubtotalFormat", alter: "المجموع الأصلي للسلة: %@"), currency(subtotal)),
                        mode: .discount(currency: Language.get("QAR", alter: "ر.ق"), isPercentage: false, maxLimit: subtotal),
                        initialValue: currentVal,
                        referenceValue: subtotal,
                        referenceLabel: Language.get("POS_OriginalSubtotal", alter: "إجمالي السلة"),
                        primaryActionTitle: Language.get("Apply", alter: "تطبيق")
                    )
                    PPTactileNumberPadSheet(
                        config: config,
                        onCommit: { val in
                            let clamped = min(subtotal, max(0, val))
                            fixedValueText = String(format: "%.2f", clamped)
                            selectedFixedPreset = clamped
                            showTactilePad = false
                        },
                        onDismiss: {
                            showTactilePad = false
                        }
                    )
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
                        showTactilePad = true
                    } label: {
                        Image(systemName: "circle.grid.3x3.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(emeraldColor)
                            .frame(width: 40, height: 40)
                            .background(emeraldColor.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(PlainButtonStyle())

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

                    Button {
                        showTactilePad = true
                    } label: {
                        Image(systemName: "circle.grid.3x3.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(emeraldColor)
                            .padding(7)
                            .background(emeraldColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
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
                onApply(draftDiscount)
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

// MARK: - Barcode Scanner Centralized
// POSBarcodeScannerScreen, POSBarcodeCameraView, and ScannerViewController are centralized in AdminSharedComponents.swift for app-wide reuse across all barcode fields.



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

@MainActor
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
        // Key names must match `-[PPPOSLogger diagnosticSummary]` exactly.
        // `totalCount`, `activeBranch` and `lastLatencyMs` are not in that
        // contract, so the branch and latency tiles silently rendered "all"
        // and "--" forever regardless of real activity.
        self.totalCount = summary["totalLogs"] as? Int ?? all.count
        self.infoCount = summary["infoCount"] as? Int ?? 0
        self.warningCount = summary["warningCount"] as? Int ?? 0
        self.errorCount = summary["errorCount"] as? Int ?? 0
        self.lastLatencyMs = summary["lastCheckoutDurationMs"] as? Int ?? 0
        // The logger has no branch concept; the branch context is the honest
        // source for the branch tile.
        let branch = BranchContextStore.shared.activeBranch
        self.activeBranch = (branch?.code.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? branch?.branchID
            ?? ""
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
                promptClearLogsConfirmation()
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

    // MARK: - Clear Logs Confirmation (PPAlertHelper)

    private func promptClearLogsConfirmation() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("POS_DeepLog_Clear", alter: "مسح السجل"),
            subtitle: Language.get("POS_DeepLog_Clear_Confirm", alter: "هل أنت متأكد من رغبتك في مسح جميع سجلات تشخيص نقاط البيع اللحظية؟"),
            confirmButton: Language.get("Delete", alter: "مسح"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "trash.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                viewModel.clearLogs()
            },
            cancelBlock: nil
        )
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

// MARK: - POS Price Reconciliation Sheet

struct POSPriceReconciliationSheet: View {
    let discrepancy: POSPriceDiscrepancyItem
    let onApplyAuthoritativePrice: () -> Void
    let onRemoveItem: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var rosePrimary: Color { Color(red: 0.88, green: 0.28, blue: 0.42) }
    private var emeraldColor: Color { Color(red: 0.06, green: 0.72, blue: 0.51) }
    private var amberColor: Color { Color(red: 0.96, green: 0.62, blue: 0.09) }

    private var priceDiff: Double {
        discrepancy.authoritativePrice - discrepancy.submittedPrice
    }

    var body: some View {
        VStack(spacing: 20) {
            // Drag indicator capsule
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            // Header Icon & Title
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(amberColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "tag.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(amberColor)
                }

                Text(Language.get("POS_PriceDiscrepancyTitle", alter: "تحديث السعر المعتمد"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("POS_PriceDiscrepancySubtitle", alter: "تغير السعر الرسمي للصنف في النظام عن السعر المسجل في السلة."))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Product & Price Comparison Card
            VStack(spacing: 14) {
                HStack {
                    Text(discrepancy.productName.isEmpty ? discrepancy.productID : discrepancy.productName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(2)
                    Spacer()
                }

                Divider()

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("POS_PreviousPrice", alter: "السعر في السلة"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(String(format: "%.2f ر.ق.", discrepancy.submittedPrice))
                            .font(.system(size: 16, weight: .semibold))
                            .strikethrough(color: .secondary)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: "arrow.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(amberColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("POS_AuthoritativePrice", alter: "السعر المعتمد بالسيرفر"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(emeraldColor)
                        Text(String(format: "%.2f ر.ق.", discrepancy.authoritativePrice))
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(emeraldColor)
                    }

                    Spacer()

                    // Diff badge
                    Text(priceDiff > 0 ? String(format: "+%.2f ر.ق.", priceDiff) : String(format: "%.2f ر.ق.", priceDiff))
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(priceDiff > 0 ? amberColor.opacity(0.15) : emeraldColor.opacity(0.15))
                        .foregroundColor(priceDiff > 0 ? amberColor : emeraldColor)
                        .cornerRadius(8)
                }
            }
            .padding(16)
            .background(AdminSurface.card)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(amberColor.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 20)

            Spacer()

            // Actions
            VStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onApplyAuthoritativePrice()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(Language.get("POS_UpdatePriceAndProceed", alter: "تحديث السعر في السلة والمتابعة"))
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundColor(.white)
                    .background(emeraldColor)
                    .cornerRadius(14)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRemoveItem()
                } label: {
                    Text(Language.get("POS_RemoveItemFromCart", alter: "إزالة الصنف من السلة"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(rosePrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(AdminSurface.background.ignoresSafeArea())
    }
}
