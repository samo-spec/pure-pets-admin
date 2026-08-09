//
//  PPFulfillmentOrdersViewController.swift
//  PurePetsAdmin
//
//  SwiftUI Fulfillment Relay. UIKit retains dashboard/navigation ownership;
//  this feature owns fulfillment presentation and state. Firebase reads and
//  writes remain centralized in PPFulfillmentService.
//

import SwiftUI
import UIKit
import FirebaseFirestore

// MARK: - Design system

private enum PPFulfillmentTokens {
    static let spaceXS: CGFloat = 4
    static let spaceSM: CGFloat = 8
    static let spaceMD: CGFloat = 12
    static let spaceBase: CGFloat = 16
    static let spaceLG: CGFloat = 20
    static let spaceXL: CGFloat = 24
    static let screenMargin: CGFloat = 20
    static let cornerSmall: CGFloat = 12
    static let cornerMedium: CGFloat = 18
    static let cornerCard: CGFloat = 22
    static let cornerHero: CGFloat = 36
    static let minimumTarget: CGFloat = 44

    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.067, blue: 0.063, alpha: 1)
            : UIColor(red: 0.965, green: 0.953, blue: 0.933, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.125, green: 0.114, blue: 0.106, alpha: 1)
            : UIColor(red: 1, green: 0.992, blue: 0.984, alpha: 1)
    })
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.96, green: 0.94, blue: 0.92, alpha: 1)
            : UIColor(red: 0.09, green: 0.082, blue: 0.075, alpha: 1)
    })
    static let secondaryInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.74, green: 0.71, blue: 0.68, alpha: 1)
            : UIColor(red: 0.36, green: 0.337, blue: 0.302, alpha: 1)
    })
    static let tertiaryInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.61, green: 0.58, blue: 0.55, alpha: 1)
            : UIColor(red: 0.43, green: 0.40, blue: 0.36, alpha: 1)
    })
    static let gold = Color(red: 0.843, green: 0.643, blue: 0.361)
    static let goldInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.94, green: 0.75, blue: 0.43, alpha: 1)
            : UIColor(red: 0.45, green: 0.28, blue: 0.035, alpha: 1)
    })
    static let success = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.80, blue: 0.57, alpha: 1)
            : UIColor(red: 0.08, green: 0.45, blue: 0.27, alpha: 1)
    })
    static let danger = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.38, blue: 0.52, alpha: 1)
            : UIColor(red: 0.64, green: 0.09, blue: 0.21, alpha: 1)
    })
    static let info = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemCyan : .systemBlue
    })

    static func beiruti(_ weight: Font.Weight, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black:
            name = "Beiruti-Bold"
        case .semibold, .medium:
            name = "Beiruti-Medium"
        default:
            name = "Beiruti-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

private struct PPFulfillmentCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(PPFulfillmentTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous)
                    .stroke(PPFulfillmentTokens.ink.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 8)
    }
}

private extension View {
    func ppFulfillmentCard() -> some View {
        modifier(PPFulfillmentCardModifier())
    }
}

// MARK: - Localization and formatting

private enum PPFulfillmentL10n {
    static func text(_ key: String) -> String {
        Language.get(key, alter: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    static var isRTL: Bool { Language.isRTL() }
    static var layoutDirection: LayoutDirection { isRTL ? .rightToLeft : .leftToRight }

    static func status(_ rawStatus: String) -> String {
        text(statusKey(rawStatus))
    }

    static func statusKey(_ rawStatus: String) -> String {
        switch rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "new_request": return "Fulfillment_Status_NewRequest"
        case "accepted": return "Fulfillment_Status_Accepted"
        case "rejected": return "Fulfillment_Status_Rejected"
        case "preparing": return "Fulfillment_Status_Preparing"
        case "ready_for_pickup": return "Fulfillment_Status_ReadyForPickup"
        case "delivery_requested": return "Fulfillment_Status_DeliveryRequested"
        case "delivery_assigned": return "Fulfillment_Status_DeliveryAssigned"
        case "awaiting_handover": return "Fulfillment_Status_AwaitingHandover"
        case "handed_over": return "Fulfillment_Status_HandedOver"
        case "picked_up": return "Fulfillment_Status_PickedUp"
        case "in_transit": return "Fulfillment_Status_InTransit"
        case "delivered": return "Fulfillment_Status_Delivered"
        case "payment_pending": return "Fulfillment_Status_PaymentPending"
        case "payment_confirmed": return "Fulfillment_Status_PaymentConfirmed"
        case "completed": return "Fulfillment_Status_Completed"
        case "cancelled": return "Fulfillment_Status_Cancelled"
        case "failed": return "Fulfillment_Status_Failed"
        case "returned": return "Fulfillment_Status_Returned"
        case "pending": return "Fulfillment_Status_Pending"
        case "in_progress": return "Fulfillment_Status_InProgress"
        default: return "Fulfillment_Status_Unknown"
        }
    }

    static func mode(for record: PPFulfillmentSnapshot) -> String {
        record.isPlatformOwned ? text("Fulfillment_Filter_Platform") : text("Fulfillment_Filter_Partner")
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return text("Fulfillment_UpdatedJustNow") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return format("Fulfillment_UpdatedAgo_Format", formatter.localizedString(for: date, relativeTo: Date()))
    }

    static func money(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.isEmpty ? "QAR" : currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount))
            ?? String(format: "%.2f %@", amount, currency.isEmpty ? "QAR" : currency)
    }
}

// MARK: - Stable presentation models

private enum PPFulfillmentStatusGroup: String, CaseIterable, Identifiable {
    case all
    case active
    case awaiting
    case completed

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "Fulfillment_Filter_All"
        case .active: return "Fulfillment_Filter_Active"
        case .awaiting: return "Fulfillment_Filter_Awaiting"
        case .completed: return "Fulfillment_Filter_Completed"
        }
    }
}

private enum PPFulfillmentOwnerFilter: String, CaseIterable, Identifiable {
    case all
    case platform
    case partner

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "Fulfillment_Filter_All"
        case .platform: return "Fulfillment_Filter_Platform"
        case .partner: return "Fulfillment_Filter_Partner"
        }
    }
}

private enum PPFulfillmentTone: Sendable {
    case progress
    case success
    case danger
    case neutral
    case info

    var color: Color {
        switch self {
        case .progress: return PPFulfillmentTokens.goldInk
        case .success: return PPFulfillmentTokens.success
        case .danger: return PPFulfillmentTokens.danger
        case .neutral: return PPFulfillmentTokens.tertiaryInk
        case .info: return PPFulfillmentTokens.info
        }
    }

    var symbol: String {
        switch self {
        case .progress: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .danger: return "exclamationmark.octagon.fill"
        case .neutral: return "circle.dotted"
        case .info: return "truck.box.fill"
        }
    }
}

private struct PPFulfillmentItemSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let quantity: Int
    let unitPrice: Double

    init?(rawValue: Any, index: Int) {
        guard let dictionary = rawValue as? [AnyHashable: Any] else { return nil }
        let identifier = Self.firstString(in: dictionary, keys: ["itemId", "itemID", "productId", "productID", "id"])
        let resolvedName = Self.firstString(in: dictionary, keys: ["itemName", "name", "title", "itemId"])
        let resolvedQuantity = max(1, Int(PPFulfillmentSnapshot.double(dictionary["quantity"] ?? dictionary["qty"])))
        let resolvedPrice = PPFulfillmentSnapshot.double(dictionary["price"])
        id = identifier.isEmpty
            ? "\(index)|\(resolvedName)|\(resolvedQuantity)|\(resolvedPrice)"
            : identifier
        name = resolvedName
        quantity = resolvedQuantity
        unitPrice = resolvedPrice
    }

    private static func firstString(in dictionary: [AnyHashable: Any], keys: [String]) -> String {
        keys.lazy
            .map { PPFulfillmentSnapshot.string(dictionary[$0]) }
            .first(where: { !$0.isEmpty }) ?? ""
    }
}

private struct PPFulfillmentSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let parentOrderID: String
    let parentOrderNumber: String
    let customerID: String
    let customerName: String
    let ownerID: String
    let ownerType: String
    let fulfillmentMode: String
    let status: String
    let items: [PPFulfillmentItemSnapshot]
    let subtotal: Double
    let platformCommission: Double
    let providerNet: Double
    let currency: String
    let createdAt: Date?
    let updatedAt: Date?
    let adminOverrideAt: Date?
    let adminOverrideBy: String
    let adminOverrideReason: String

    init(record: PPFulfillmentRecord) {
        id = record.fulfillmentID
        parentOrderID = record.parentOrderID
        parentOrderNumber = record.parentOrderNumber
        customerID = record.customerID
        customerName = record.customerName
        ownerID = record.ownerID
        ownerType = record.ownerType
        fulfillmentMode = record.fulfillmentMode
        status = record.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        items = record.items.enumerated().compactMap { index, rawValue in
            PPFulfillmentItemSnapshot(rawValue: rawValue, index: index)
        }
        let money = record.money as? [String: Any] ?? [:]
        subtotal = Self.double(money["subtotal"])
        platformCommission = Self.double(money["platformCommission"])
        providerNet = Self.double(money["providerNet"])
        currency = Self.string(money["currency"], fallback: "QAR")
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        adminOverrideAt = record.adminOverrideAt
        adminOverrideBy = record.adminOverrideBy ?? ""
        adminOverrideReason = record.adminOverrideReason ?? ""
    }

    static func == (lhs: PPFulfillmentSnapshot, rhs: PPFulfillmentSnapshot) -> Bool {
        lhs.id == rhs.id
            && lhs.status == rhs.status
            && lhs.updatedAt == rhs.updatedAt
            && lhs.customerName == rhs.customerName
            && lhs.ownerID == rhs.ownerID
            && lhs.items.count == rhs.items.count
            && lhs.providerNet == rhs.providerNet
            && lhs.adminOverrideAt == rhs.adminOverrideAt
    }

    var isPlatformOwned: Bool {
        ownerType == "platform" || fulfillmentMode == "platform_managed" || ownerID.isEmpty
    }

    var isTerminal: Bool {
        Self.terminalStatuses.contains(status)
    }

    var isAwaitingAction: Bool {
        Self.awaitingStatuses.contains(status)
    }

    var isCompleted: Bool { status == "completed" }

    var tone: PPFulfillmentTone {
        Self.tone(for: status)
    }

    static func tone(for status: String) -> PPFulfillmentTone {
        switch status {
        case "completed", "accepted", "ready_for_pickup", "payment_confirmed": return .success
        case "rejected", "cancelled", "failed", "returned": return .danger
        case "delivery_assigned", "awaiting_handover", "handed_over", "picked_up", "in_transit", "delivered": return .info
        case "new_request", "preparing", "delivery_requested", "payment_pending", "in_progress": return .progress
        default: return .neutral
        }
    }

    var displayOrder: String {
        let value = parentOrderNumber.isEmpty ? parentOrderID : parentOrderNumber
        return value.isEmpty ? "—" : "#\(value)"
    }

    var searchText: String {
        [id, parentOrderID, parentOrderNumber, customerID, customerName, ownerID]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    static let terminalStatuses: Set<String> = ["completed", "cancelled", "rejected", "failed", "returned"]
    static let awaitingStatuses: Set<String> = ["new_request", "delivery_requested", "awaiting_handover", "payment_pending"]

    static func string(_ value: Any?, fallback: String = "") -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return fallback
    }

    static func double(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }

}

private struct PPFulfillmentEventSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let action: String
    let fromStatus: String
    let toStatus: String
    let actor: String
    let createdAt: Date?
    let reason: String

    init(dictionary: [AnyHashable: Any], index: Int) {
        action = Self.string(dictionary["action"]) .isEmpty
            ? Self.string(dictionary["type"], fallback: PPFulfillmentL10n.text("Fulfillment_Event"))
            : Self.string(dictionary["action"])
        fromStatus = Self.string(dictionary["fromStatus"])
        toStatus = Self.string(dictionary["toStatus"])
        actor = Self.firstString(in: dictionary, keys: ["actor", "performedBy", "by", "userId"])
        reason = Self.firstString(in: dictionary, keys: ["reason", "note"])
        if let timestamp = dictionary["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = dictionary["createdAt"] as? Date
        }
        let rawID = Self.firstString(in: dictionary, keys: ["eventId", "eventID", "id"])
        id = rawID.isEmpty
            ? "\(index)|\(action)|\(fromStatus)|\(toStatus)|\(createdAt?.timeIntervalSince1970 ?? 0)"
            : rawID
    }

    private static func string(_ value: Any?, fallback: String = "") -> String {
        PPFulfillmentSnapshot.string(value, fallback: fallback)
    }

    private static func firstString(in dictionary: [AnyHashable: Any], keys: [String]) -> String {
        keys.lazy.map { string(dictionary[$0]) }.first(where: { !$0.isEmpty }) ?? ""
    }
}

private struct PPFulfillmentMetrics: Equatable, Sendable {
    let active: Int
    let awaiting: Int
    let completed: Int
    let providerNet: Double
    let currency: String

    init(records: [PPFulfillmentSnapshot]) {
        active = records.filter { !$0.isTerminal }.count
        awaiting = records.filter(\.isAwaitingAction).count
        completed = records.filter(\.isCompleted).count
        providerNet = records.reduce(0) { $0 + $1.providerNet }
        currency = records.last(where: { !$0.currency.isEmpty })?.currency ?? "QAR"
    }
}

private struct PPFulfillmentAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Firestore documents ListenerRegistration.remove() as idempotent. The SDK's
/// Objective-C protocol has not adopted Sendable yet, so this wrapper is the
/// sole audited concurrency escape hatch and exposes cancellation only.
private final class PPFulfillmentListenerToken: @unchecked Sendable {
    private let registration: any ListenerRegistration

    init(_ registration: any ListenerRegistration) {
        self.registration = registration
    }

    func remove() {
        registration.remove()
    }

    deinit {
        registration.remove()
    }
}

// MARK: - List state owner

@MainActor
private final class PPFulfillmentOrdersViewModel: ObservableObject {
    @Published private(set) var records: [PPFulfillmentSnapshot] = []
    @Published private(set) var userNames: [String: String] = [:]
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var changedRecordIDs: Set<String> = []
    @Published var searchText = ""
    @Published var statusGroup: PPFulfillmentStatusGroup = .all
    @Published var ownerFilter: PPFulfillmentOwnerFilter = .all
    @Published var exactStatus = ""

    private let service = PPFulfillmentService.shared()
    private var listener: PPFulfillmentListenerToken?
    private var previousStatuses: [String: String] = [:]
    private var hasLoadedOnce = false

    deinit {
        listener?.remove()
    }

    var metrics: PPFulfillmentMetrics { PPFulfillmentMetrics(records: records) }

    var availableStatuses: [String] {
        Array(Set(records.map(\.status).filter { !$0.isEmpty }))
            .sorted { PPFulfillmentL10n.status($0).localizedStandardCompare(PPFulfillmentL10n.status($1)) == .orderedAscending }
    }

    var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || statusGroup != .all
            || ownerFilter != .all
            || !exactStatus.isEmpty
    }

    var filteredRecords: [PPFulfillmentSnapshot] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        return records.filter { record in
            if !exactStatus.isEmpty, record.status != exactStatus { return false }
            switch statusGroup {
            case .all: break
            case .active where record.isTerminal: return false
            case .awaiting where !record.isAwaitingAction: return false
            case .completed where !record.isCompleted: return false
            default: break
            }
            switch ownerFilter {
            case .all: break
            case .platform where !record.isPlatformOwned: return false
            case .partner where record.isPlatformOwned: return false
            default: break
            }
            return query.isEmpty || searchableText(for: record).contains(query)
        }
    }

    func startListening() {
        isLoading = !hasLoadedOnce
        errorMessage = nil
        listener?.remove()
        let registration = service.observeFulfillments { [weak self] records, error in
            let snapshots = records.map(PPFulfillmentSnapshot.init(record:))
            let message = error?.localizedDescription
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                self.lastSyncDate = Date()
                if let message {
                    self.errorMessage = message
                    return
                }
                self.markChangedRecords(in: snapshots)
                self.records = snapshots
                self.errorMessage = nil
                self.hasLoadedOnce = true
                self.resolveNames(for: snapshots)
            }
        }
        listener = PPFulfillmentListenerToken(registration)
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func retry() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        startListening()
    }

    func clearFilters() {
        statusGroup = .all
        ownerFilter = .all
        exactStatus = ""
        searchText = ""
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func acknowledgeChange(for id: String) {
        changedRecordIDs.remove(id)
    }

    func displayCustomerName(for record: PPFulfillmentSnapshot) -> String {
        userNames[record.customerID]
            ?? (!record.customerName.isEmpty ? record.customerName : PPFulfillmentL10n.text("Fulfillment_UnknownCustomer"))
    }

    func displayOwnerName(for record: PPFulfillmentSnapshot) -> String {
        if record.isPlatformOwned { return PPFulfillmentL10n.text("Fulfillment_Filter_Platform") }
        return userNames[record.ownerID]
            ?? (!record.ownerID.isEmpty ? record.ownerID : PPFulfillmentL10n.text("Fulfillment_UnknownCustomer"))
    }

    private func searchableText(for record: PPFulfillmentSnapshot) -> String {
        [record.searchText, displayCustomerName(for: record), displayOwnerName(for: record)]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func markChangedRecords(in next: [PPFulfillmentSnapshot]) {
        var changed: Set<String> = []
        var statuses: [String: String] = [:]
        for record in next {
            statuses[record.id] = record.status
            if let oldStatus = previousStatuses[record.id], oldStatus != record.status {
                changed.insert(record.id)
            }
        }
        previousStatuses = statuses
        changedRecordIDs.formUnion(changed)
    }

    private func resolveNames(for records: [PPFulfillmentSnapshot]) {
        let identifiers = Set(records.flatMap { [$0.customerID, $0.ownerID] }.filter { !$0.isEmpty })
        guard !identifiers.isEmpty else { return }
        service.resolveUserProfiles(forIDs: Array(identifiers)) { [weak self] names in
            DispatchQueue.main.async {
                guard let self else { return }
                self.userNames.merge(names) { _, new in new }
            }
        }
    }
}

// MARK: - List screen

private struct PPFulfillmentOrdersScreen: View {
    @ObservedObject var viewModel: PPFulfillmentOrdersViewModel
    let onOpenRecord: (PPFulfillmentSnapshot) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var showsFilters = false

    var body: some View {
        ZStack {
            PPFulfillmentTokens.canvas.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: PPFulfillmentTokens.spaceBase) {
                    relayHero
                    searchField
                    quickFilters
                    resultsHeader
                    content
                }
                .padding(.horizontal, PPFulfillmentTokens.screenMargin)
                .padding(.top, PPFulfillmentTokens.spaceBase)
                .padding(.bottom, 36)
            }
            .refreshable { viewModel.startListening() }
        }
        .environment(\.layoutDirection, PPFulfillmentL10n.layoutDirection)
        .navigationTitle(PPFulfillmentL10n.text("Fulfillment_Title"))
        .sheet(isPresented: $showsFilters) {
            PPFulfillmentFiltersSheet(viewModel: viewModel)
                .environment(\.layoutDirection, PPFulfillmentL10n.layoutDirection)
        }
        .onAppear(perform: viewModel.startListening)
        .onDisappear(perform: viewModel.stopListening)
    }

    private var relayHero: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceLG) {
            HStack(alignment: .firstTextBaseline, spacing: PPFulfillmentTokens.spaceMD) {
                VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceXS) {
                    Text(PPFulfillmentL10n.text("Fulfillment_Eyebrow"))
                        .font(PPFulfillmentTokens.beiruti(.bold, size: 13, relativeTo: .caption))
                        .textCase(.uppercase)
                        .foregroundStyle(PPFulfillmentTokens.gold)
                    Text(PPFulfillmentL10n.text("Fulfillment_Relay_Title"))
                        .font(PPFulfillmentTokens.beiruti(.bold, size: 30, relativeTo: .largeTitle))
                        .foregroundStyle(Color(red: 1, green: 0.97, blue: 0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(PPFulfillmentL10n.text("Fulfillment_Subtitle"))
                        .font(PPFulfillmentTokens.beiruti(.regular, size: 16, relativeTo: .body))
                        .foregroundStyle(Color(red: 1, green: 0.93, blue: 0.84).opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                VStack(spacing: 5) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .bold))
                    Text(PPFulfillmentL10n.text("Fulfillment_Live"))
                        .font(PPFulfillmentTokens.beiruti(.bold, size: 12, relativeTo: .caption))
                }
                .foregroundStyle(Color(red: 0.47, green: 0.91, blue: 0.65))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.22), in: Capsule())
                .accessibilityElement(children: .combine)
            }

            PPFulfillmentRelayTrace(metrics: viewModel.metrics)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 136), spacing: PPFulfillmentTokens.spaceSM)],
                spacing: PPFulfillmentTokens.spaceSM
            ) {
                metricTiles
            }

            Label(PPFulfillmentL10n.relativeDate(viewModel.lastSyncDate), systemImage: "clock.arrow.circlepath")
                .font(PPFulfillmentTokens.beiruti(.medium, size: 13, relativeTo: .caption))
                .foregroundStyle(Color(red: 1, green: 0.93, blue: 0.84).opacity(0.72))
        }
        .padding(PPFulfillmentTokens.spaceLG)
        .background(
            LinearGradient(
                colors: [Color(red: 0.094, green: 0.055, blue: 0.075), Color(red: 0.23, green: 0.105, blue: 0.12)],
                startPoint: PPFulfillmentL10n.isRTL ? .topTrailing : .topLeading,
                endPoint: PPFulfillmentL10n.isRTL ? .bottomLeading : .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerHero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerHero, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 28, x: 0, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fulfillment.relay.hero")
    }

    @ViewBuilder
    private var metricTiles: some View {
        PPFulfillmentMetricTile(
            title: PPFulfillmentL10n.text("Fulfillment_Metric_Active"),
            value: "\(viewModel.metrics.active)",
            symbol: "bolt.fill",
            color: PPFulfillmentTokens.gold
        )
        PPFulfillmentMetricTile(
            title: PPFulfillmentL10n.text("Fulfillment_Metric_Waiting"),
            value: "\(viewModel.metrics.awaiting)",
            symbol: "hourglass",
            color: Color.orange
        )
        PPFulfillmentMetricTile(
            title: PPFulfillmentL10n.text("Fulfillment_Metric_Completed"),
            value: "\(viewModel.metrics.completed)",
            symbol: "checkmark.seal.fill",
            color: Color(red: 0.47, green: 0.91, blue: 0.65)
        )
        PPFulfillmentMetricTile(
            title: PPFulfillmentL10n.text("Fulfillment_Metric_NetValue"),
            value: PPFulfillmentL10n.money(viewModel.metrics.providerNet, currency: viewModel.metrics.currency),
            symbol: "banknote.fill",
            color: Color(red: 0.76, green: 0.74, blue: 0.98)
        )
    }

    private var searchField: some View {
        VStack(spacing: PPFulfillmentTokens.spaceSM) {
            HStack(spacing: PPFulfillmentTokens.spaceMD) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                    .accessibilityHidden(true)
                TextField(PPFulfillmentL10n.text("Fulfillment_SearchPlaceholder"), text: $viewModel.searchText)
                    .font(PPFulfillmentTokens.beiruti(.regular, size: 16, relativeTo: .body))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .accessibilityIdentifier("fulfillment.search")
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(PPFulfillmentTokens.tertiaryInk)
                    }
                    .accessibilityLabel(PPFulfillmentL10n.text("Fulfillment_ClearSearch"))
                }
            }
            .padding(.horizontal, PPFulfillmentTokens.spaceBase)
            .frame(minHeight: 52)
            .ppFulfillmentCard()

            HStack(spacing: PPFulfillmentTokens.spaceSM) {
                Button(action: { showsFilters = true }) {
                    Label(
                        PPFulfillmentL10n.text("Fulfillment_Filters_Title"),
                        systemImage: viewModel.hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                    .frame(maxWidth: .infinity, minHeight: PPFulfillmentTokens.minimumTarget)
                }
                .accessibilityIdentifier("fulfillment.filters")

                Button(action: viewModel.retry) {
                    Label(PPFulfillmentL10n.text("Fulfillment_Retry"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: PPFulfillmentTokens.minimumTarget)
                }
                .accessibilityIdentifier("fulfillment.refresh")
            }
            .font(PPFulfillmentTokens.beiruti(.bold, size: 15, relativeTo: .subheadline))
            .foregroundStyle(PPFulfillmentTokens.goldInk)
            .buttonStyle(.bordered)
            .tint(PPFulfillmentTokens.gold)
        }
    }

    private var quickFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PPFulfillmentTokens.spaceSM) {
                ForEach(PPFulfillmentStatusGroup.allCases) { group in
                    PPFulfillmentFilterChip(
                        title: PPFulfillmentL10n.text(group.titleKey),
                        symbol: symbol(for: group),
                        isSelected: viewModel.statusGroup == group && viewModel.exactStatus.isEmpty
                    ) {
                        viewModel.exactStatus = ""
                        viewModel.statusGroup = group
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    .accessibilityIdentifier("fulfillment.filter.status.\(group.rawValue)")
                }

                Divider().frame(height: 28)

                ForEach(PPFulfillmentOwnerFilter.allCases) { owner in
                    PPFulfillmentFilterChip(
                        title: PPFulfillmentL10n.text(owner.titleKey),
                        symbol: owner == .partner ? "person.2.fill" : (owner == .platform ? "pawprint.fill" : "square.grid.2x2"),
                        isSelected: viewModel.ownerFilter == owner
                    ) {
                        viewModel.ownerFilter = owner
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    .accessibilityIdentifier("fulfillment.filter.owner.\(owner.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(PPFulfillmentL10n.format("Fulfillment_Showing_Format", "\(viewModel.filteredRecords.count)", "\(viewModel.records.count)"))
                .font(PPFulfillmentTokens.beiruti(.semibold, size: 15, relativeTo: .subheadline))
                .foregroundStyle(PPFulfillmentTokens.secondaryInk)
            Spacer()
            if viewModel.hasActiveFilters {
                Button(PPFulfillmentL10n.text("Fulfillment_Filter_Clear"), action: viewModel.clearFilters)
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(PPFulfillmentTokens.goldInk)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.records.isEmpty {
            PPFulfillmentStateView(
                symbol: "shippingbox.and.arrow.backward.fill",
                title: PPFulfillmentL10n.text("Loading"),
                message: PPFulfillmentL10n.text("Fulfillment_Loading_Subtitle"),
                isLoading: true,
                actionTitle: nil,
                action: nil
            )
        } else if let error = viewModel.errorMessage, viewModel.records.isEmpty {
            PPFulfillmentStateView(
                symbol: "wifi.exclamationmark",
                title: PPFulfillmentL10n.text("Fulfillment_EmptyError_Title"),
                message: error,
                isLoading: false,
                actionTitle: PPFulfillmentL10n.text("Fulfillment_Retry"),
                action: viewModel.retry
            )
        } else if viewModel.filteredRecords.isEmpty {
            if viewModel.hasActiveFilters {
                PPFulfillmentStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: PPFulfillmentL10n.text("Fulfillment_EmptyFiltered_Title"),
                    message: PPFulfillmentL10n.text("Fulfillment_EmptyFiltered_Subtitle"),
                    isLoading: false,
                    actionTitle: PPFulfillmentL10n.text("Fulfillment_Filter_Clear"),
                    action: viewModel.clearFilters
                )
            } else {
                PPFulfillmentStateView(
                    symbol: "shippingbox",
                    title: PPFulfillmentL10n.text("Fulfillment_Empty_Title"),
                    message: PPFulfillmentL10n.text("Fulfillment_Empty_Subtitle"),
                    isLoading: false,
                    actionTitle: nil,
                    action: nil
                )
            }
        } else {
            ForEach(viewModel.filteredRecords) { record in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.acknowledgeChange(for: record.id)
                    onOpenRecord(record)
                } label: {
                    PPFulfillmentRelayCard(
                        record: record,
                        customerName: viewModel.displayCustomerName(for: record),
                        ownerName: viewModel.displayOwnerName(for: record),
                        hasChanged: viewModel.changedRecordIDs.contains(record.id),
                        differentiateWithoutColor: differentiateWithoutColor,
                        reduceMotion: reduceMotion
                    )
                }
                .buttonStyle(PPFulfillmentPressStyle(reduceMotion: reduceMotion))
                .accessibilityIdentifier("fulfillment.order.\(record.id)")
            }
        }
    }

    private func symbol(for group: PPFulfillmentStatusGroup) -> String {
        switch group {
        case .all: return "square.grid.2x2"
        case .active: return "bolt.fill"
        case .awaiting: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

private struct PPFulfillmentRelayTrace: View {
    let metrics: PPFulfillmentMetrics

    var body: some View {
        HStack(spacing: 6) {
            traceStep(symbol: "person.fill", titleKey: "Fulfillment_Relay_Customer", isActive: true)
            connector(isActive: metrics.active > 0)
            traceStep(symbol: "shippingbox.fill", titleKey: "Fulfillment_Relay_Preparation", isActive: metrics.active > 0)
            connector(isActive: metrics.awaiting > 0)
            traceStep(symbol: "truck.box.fill", titleKey: "Fulfillment_Relay_Handoff", isActive: metrics.awaiting > 0)
            connector(isActive: metrics.completed > 0)
            traceStep(symbol: "checkmark.seal.fill", titleKey: "Fulfillment_Relay_Complete", isActive: metrics.completed > 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(PPFulfillmentL10n.text("Fulfillment_Relay_Accessibility"))
    }

    private func traceStep(symbol: String, titleKey: String, isActive: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
                .background(isActive ? PPFulfillmentTokens.gold.opacity(0.22) : Color.white.opacity(0.06), in: Circle())
            Text(PPFulfillmentL10n.text(titleKey))
                .font(PPFulfillmentTokens.beiruti(.medium, size: 10, relativeTo: .caption2))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(isActive ? Color(red: 1, green: 0.88, blue: 0.67) : Color.white.opacity(0.42))
        .frame(maxWidth: .infinity)
    }

    private func connector(isActive: Bool) -> some View {
        Capsule()
            .fill(isActive ? PPFulfillmentTokens.gold : Color.white.opacity(0.15))
            .frame(maxWidth: 26, minHeight: 3, maxHeight: 3)
            .accessibilityHidden(true)
    }
}

private struct PPFulfillmentMetricTile: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(PPFulfillmentTokens.beiruti(.medium, size: 11, relativeTo: .caption2))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
                Text(value)
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct PPFulfillmentFilterChip: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "checkmark" : symbol)
                .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? PPFulfillmentTokens.goldInk : PPFulfillmentTokens.secondaryInk)
                .padding(.horizontal, 15)
                .frame(minHeight: PPFulfillmentTokens.minimumTarget)
                .background(isSelected ? PPFulfillmentTokens.gold.opacity(0.16) : PPFulfillmentTokens.surface, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? PPFulfillmentTokens.gold.opacity(0.65) : PPFulfillmentTokens.ink.opacity(0.10), lineWidth: 1))
        }
        .accessibilityValue(isSelected ? PPFulfillmentL10n.text("Fulfillment_Filter_Selected") : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PPFulfillmentRelayCard: View {
    let record: PPFulfillmentSnapshot
    let customerName: String
    let ownerName: String
    let hasChanged: Bool
    let differentiateWithoutColor: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(record.tone.color)
                .frame(width: differentiateWithoutColor ? 7 : 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceBase) {
                HStack(alignment: .top, spacing: PPFulfillmentTokens.spaceMD) {
                    PPFulfillmentAvatar(name: customerName)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(customerName)
                            .font(PPFulfillmentTokens.beiruti(.bold, size: 18, relativeTo: .headline))
                            .foregroundStyle(PPFulfillmentTokens.ink)
                            .lineLimit(2)
                        Text(record.displayOrder)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    Spacer(minLength: 4)
                }

                PPFulfillmentStatusBadge(status: record.status, tone: record.tone, compact: true)

                HStack(alignment: .center, spacing: 8) {
                    Text(customerName)
                        .lineLimit(1)
                    Image(systemName: PPFulfillmentL10n.isRTL ? "arrow.left" : "arrow.right")
                        .foregroundStyle(PPFulfillmentTokens.goldInk)
                        .accessibilityHidden(true)
                    Text(ownerName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(PPFulfillmentTokens.beiruti(.regular, size: 14, relativeTo: .subheadline))
                .foregroundStyle(PPFulfillmentTokens.secondaryInk)

                Divider().overlay(PPFulfillmentTokens.ink.opacity(0.08))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 118), alignment: .leading)],
                    alignment: .leading,
                    spacing: PPFulfillmentTokens.spaceSM
                ) {
                    metadata
                }
            }
            .padding(PPFulfillmentTokens.spaceBase)
        }
        .background(PPFulfillmentTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous)
                .stroke(hasChanged ? record.tone.color.opacity(0.7) : PPFulfillmentTokens.ink.opacity(0.07), lineWidth: hasChanged ? 2 : 1)
        )
        .shadow(color: Color.black.opacity(0.055), radius: 18, x: 0, y: 7)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.38, dampingFraction: 0.86), value: hasChanged)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(PPFulfillmentL10n.text("Fulfillment_OpenDetails_Hint"))
    }

    @ViewBuilder
    private var metadata: some View {
        Label(PPFulfillmentL10n.format("Fulfillment_ItemsCount_Format", "\(record.items.count)"), systemImage: "shippingbox")
        Label(PPFulfillmentL10n.money(record.subtotal, currency: record.currency), systemImage: "banknote")
        Label(PPFulfillmentL10n.relativeDate(record.updatedAt), systemImage: "clock")
    }

    private var accessibilityLabel: String {
        [customerName, ownerName, PPFulfillmentL10n.status(record.status), record.displayOrder,
         PPFulfillmentL10n.format("Fulfillment_ItemsCount_Format", "\(record.items.count)"),
         PPFulfillmentL10n.money(record.subtotal, currency: record.currency)]
            .joined(separator: ", ")
    }
}

private struct PPFulfillmentAvatar: View {
    let name: String

    var body: some View {
        Text(initials)
            .font(PPFulfillmentTokens.beiruti(.bold, size: 15, relativeTo: .subheadline))
            .foregroundStyle(PPFulfillmentTokens.goldInk)
            .frame(width: 46, height: 46)
            .background(PPFulfillmentTokens.gold.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PPFulfillmentTokens.gold.opacity(0.35), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(whereSeparator: \Character.isWhitespace).prefix(2)
        let result = words.compactMap(\.first).map(String.init).joined()
        return result.isEmpty ? "•" : result.uppercased()
    }
}

private struct PPFulfillmentStatusBadge: View {
    let status: String
    let tone: PPFulfillmentTone
    var compact = false

    var body: some View {
        Label(PPFulfillmentL10n.status(status), systemImage: tone.symbol)
            .font(PPFulfillmentTokens.beiruti(.bold, size: compact ? 12 : 14, relativeTo: compact ? .caption : .subheadline))
            .foregroundStyle(tone.color)
            .padding(.horizontal, compact ? 10 : 13)
            .padding(.vertical, compact ? 7 : 9)
            .background(tone.color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(tone.color.opacity(0.30), lineWidth: 1))
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct PPFulfillmentStateView: View {
    let symbol: String
    let title: String
    let message: String
    let isLoading: Bool
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: PPFulfillmentTokens.spaceBase) {
            ZStack {
                RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous)
                    .fill(PPFulfillmentTokens.gold.opacity(0.12))
                    .frame(width: 72, height: 72)
                if isLoading {
                    ProgressView().tint(PPFulfillmentTokens.goldInk)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(PPFulfillmentTokens.goldInk)
                }
            }
            Text(title)
                .font(PPFulfillmentTokens.beiruti(.bold, size: 22, relativeTo: .title2))
                .foregroundStyle(PPFulfillmentTokens.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(PPFulfillmentTokens.beiruti(.regular, size: 16, relativeTo: .body))
                .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 16, relativeTo: .body))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, PPFulfillmentTokens.spaceXL)
                    .frame(minHeight: 48)
                    .background(PPFulfillmentTokens.goldInk, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(PPFulfillmentTokens.spaceXL)
        .ppFulfillmentCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fulfillment.state")
    }
}

private struct PPFulfillmentPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

// MARK: - Filters sheet

private struct PPFulfillmentFiltersSheet: View {
    @ObservedObject var viewModel: PPFulfillmentOrdersViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(PPFulfillmentL10n.text("Fulfillment_Filter_AllStatuses")) {
                    filterRow(title: PPFulfillmentL10n.text("Fulfillment_Filter_AllStatuses"), value: "")
                    ForEach(viewModel.availableStatuses, id: \.self) { status in
                        filterRow(title: PPFulfillmentL10n.status(status), value: status)
                    }
                }
                Section(PPFulfillmentL10n.text("Fulfillment_Filter_AllOwnerTypes")) {
                    ForEach(PPFulfillmentOwnerFilter.allCases) { owner in
                        Button {
                            viewModel.ownerFilter = owner
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            checkRow(
                                title: PPFulfillmentL10n.text(owner.titleKey),
                                selected: viewModel.ownerFilter == owner
                            )
                        }
                    }
                }
                Section {
                    Button(role: .destructive, action: viewModel.clearFilters) {
                        Label(PPFulfillmentL10n.text("Fulfillment_Filter_Clear"), systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(PPFulfillmentL10n.text("Fulfillment_Filters_Title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(PPFulfillmentL10n.text("Done")) { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func filterRow(title: String, value: String) -> some View {
        Button {
            viewModel.exactStatus = value
            viewModel.statusGroup = .all
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            checkRow(title: title, selected: viewModel.exactStatus == value)
        }
    }

    private func checkRow(title: String, selected: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(PPFulfillmentTokens.ink)
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PPFulfillmentTokens.goldInk)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Detail state owner

@MainActor
private final class PPFulfillmentDetailViewModel: ObservableObject {
    @Published private(set) var record: PPFulfillmentSnapshot
    @Published private(set) var events: [PPFulfillmentEventSnapshot] = []
    @Published private(set) var userNames: [String: String] = [:]
    @Published private(set) var isLoading = true
    @Published private(set) var isSubmitting = false
    @Published private(set) var loadError: String?
    @Published var overrideTarget = ""
    @Published var overrideReason = ""
    @Published var overrideNote = ""
    @Published var notifyCustomer = true
    @Published var showsOverride = false
    @Published var alert: PPFulfillmentAlert?
    @Published var successfulStatus: String?

    private let service: PPFulfillmentService
    private var eventsListener: PPFulfillmentListenerToken?

    init(seed: PPFulfillmentSnapshot, service: PPFulfillmentService) {
        record = seed
        self.service = service
    }

    deinit {
        eventsListener?.remove()
    }

    var customerName: String {
        userNames[record.customerID]
            ?? (!record.customerName.isEmpty ? record.customerName : PPFulfillmentL10n.text("Fulfillment_UnknownCustomer"))
    }

    var ownerName: String {
        if record.isPlatformOwned { return PPFulfillmentL10n.text("Fulfillment_Filter_Platform") }
        return userNames[record.ownerID]
            ?? (!record.ownerID.isEmpty ? record.ownerID : PPFulfillmentL10n.text("Fulfillment_UnknownCustomer"))
    }

    var allowedOverrideTargets: [String] {
        PPFulfillmentService.allowedOverrideTargets(forStatus: record.status)
    }

    var canSubmitOverride: Bool {
        !isSubmitting
            && !overrideTarget.isEmpty
            && !overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() {
        isLoading = true
        loadError = nil
        service.fetchFulfillmentDetail(record.id) { [weak self] record, events, error in
            let snapshot = record.map(PPFulfillmentSnapshot.init(record:))
            let decodedEvents = Self.decode(events: events)
            let message = error?.localizedDescription
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if let message {
                    self.loadError = message
                } else {
                    if let snapshot {
                        self.record = snapshot
                        self.successfulStatus = nil
                    }
                    self.events = decodedEvents
                    self.resolveNames()
                }
            }
        }
        eventsListener?.remove()
        let registration = service.observeFulfillmentEvents(record.id) { [weak self] events, error in
            let decodedEvents = Self.decode(events: events)
            let succeeded = error == nil
            DispatchQueue.main.async {
                guard let self, succeeded else { return }
                self.events = decodedEvents
            }
        }
        eventsListener = PPFulfillmentListenerToken(registration)
    }

    func stop() {
        eventsListener?.remove()
        eventsListener = nil
    }

    func prepareOverride() {
        guard let first = allowedOverrideTargets.first else {
            alert = PPFulfillmentAlert(
                title: PPFulfillmentL10n.text("Fulfillment_AdminOverride"),
                message: PPFulfillmentL10n.text("Fulfillment_NoOverrideTargets")
            )
            return
        }
        overrideTarget = first
        overrideReason = ""
        overrideNote = ""
        notifyCustomer = true
        showsOverride = true
    }

    func submitOverride() {
        let reason = overrideReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmitOverride else {
            alert = PPFulfillmentAlert(
                title: PPFulfillmentL10n.text("Error_Title"),
                message: PPFulfillmentL10n.text("Fulfillment_Reason")
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        isSubmitting = true
        service.adminOverride(
            record.id,
            targetStatus: overrideTarget,
            reason: reason,
            note: overrideNote.trimmingCharacters(in: .whitespacesAndNewlines),
            notify: notifyCustomer
        ) { [weak self] result, error in
            let skipped = (result?["skipped"] as? NSNumber)?.boolValue == true
            let message = error?.localizedDescription
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false
                if let message {
                    self.alert = PPFulfillmentAlert(title: PPFulfillmentL10n.text("Error_Title"), message: message)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }
                self.successfulStatus = self.overrideTarget
                self.showsOverride = false
                self.alert = PPFulfillmentAlert(
                    title: PPFulfillmentL10n.text("Success"),
                    message: PPFulfillmentL10n.text(skipped ? "Fulfillment_OverrideSkipped" : "Fulfillment_OverrideSuccess")
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.load()
            }
        }
    }

    private func resolveNames() {
        let identifiers = [record.customerID, record.ownerID].filter { !$0.isEmpty }
        guard !identifiers.isEmpty else { return }
        service.resolveUserProfiles(forIDs: identifiers) { [weak self] names in
            DispatchQueue.main.async { self?.userNames.merge(names) { _, new in new } }
        }
    }

    nonisolated private static func decode(events: [Any]) -> [PPFulfillmentEventSnapshot] {
        events.enumerated().compactMap { index, raw in
            guard let dictionary = raw as? [AnyHashable: Any] else { return nil }
            return PPFulfillmentEventSnapshot(dictionary: dictionary, index: index)
        }
    }
}

// MARK: - Detail screen

private struct PPFulfillmentDetailScreen: View {
    @ObservedObject var viewModel: PPFulfillmentDetailViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PPFulfillmentTokens.canvas.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceXL) {
                    detailHero
                    if viewModel.isLoading {
                        ProgressView(PPFulfillmentL10n.text("Loading"))
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }
                    if let error = viewModel.loadError {
                        PPFulfillmentStateView(
                            symbol: "exclamationmark.triangle.fill",
                            title: PPFulfillmentL10n.text("Fulfillment_EmptyError_Title"),
                            message: error,
                            isLoading: false,
                            actionTitle: PPFulfillmentL10n.text("Fulfillment_Retry"),
                            action: viewModel.load
                        )
                    } else {
                        overviewSection
                        compositionSection
                        settlementSection
                        if viewModel.record.adminOverrideAt != nil { auditSection }
                        timelineSection
                    }
                }
                .padding(.horizontal, PPFulfillmentTokens.screenMargin)
                .padding(.top, PPFulfillmentTokens.spaceBase)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $viewModel.showsOverride) {
            PPFulfillmentOverrideSheet(viewModel: viewModel)
                .environment(\.layoutDirection, PPFulfillmentL10n.layoutDirection)
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text(PPFulfillmentL10n.text("OK"))))
        }
        .environment(\.layoutDirection, PPFulfillmentL10n.layoutDirection)
        .onAppear(perform: viewModel.load)
        .onDisappear(perform: viewModel.stop)
    }

    private var detailHero: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceLG) {
            HStack(alignment: .top, spacing: PPFulfillmentTokens.spaceMD) {
                PPFulfillmentAvatar(name: viewModel.customerName)
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.customerName)
                        .font(PPFulfillmentTokens.beiruti(.bold, size: 23, relativeTo: .title2))
                    Label(viewModel.ownerName, systemImage: viewModel.record.isPlatformOwned ? "pawprint.fill" : "person.2.fill")
                        .font(PPFulfillmentTokens.beiruti(.medium, size: 15, relativeTo: .subheadline))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                Spacer()
            }
            PPFulfillmentStatusBadge(status: effectiveStatus, tone: effectiveTone)
                .id(effectiveStatus)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity))
            Text(viewModel.record.id)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.6))
                .textSelection(.enabled)
                .environment(\.layoutDirection, .leftToRight)
        }
        .foregroundStyle(Color(red: 1, green: 0.97, blue: 0.92))
        .padding(PPFulfillmentTokens.spaceLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.094, green: 0.055, blue: 0.075), effectiveTone.color.opacity(0.56)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerHero, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerHero, style: .continuous).stroke(Color.white.opacity(0.11), lineWidth: 1))
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.5, dampingFraction: 0.82), value: viewModel.successfulStatus)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fulfillment.detail.hero")
    }

    private var effectiveStatus: String {
        viewModel.successfulStatus ?? viewModel.record.status
    }

    private var effectiveTone: PPFulfillmentTone {
        PPFulfillmentSnapshot.tone(for: effectiveStatus)
    }

    private var overviewSection: some View {
        detailSection(titleKey: "Fulfillment_DetailOverview", symbol: "square.grid.2x2.fill") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: PPFulfillmentTokens.spaceMD)], spacing: PPFulfillmentTokens.spaceMD) {
                PPFulfillmentKeyValue(titleKey: "Fulfillment_DetailOrder", value: viewModel.record.displayOrder)
                PPFulfillmentKeyValue(titleKey: "Fulfillment_Ref", value: viewModel.record.id, monospaced: true)
                PPFulfillmentKeyValue(titleKey: "Fulfillment_DetailCreated", value: PPFulfillmentL10n.date(viewModel.record.createdAt))
                PPFulfillmentKeyValue(titleKey: "Fulfillment_DetailUpdated", value: PPFulfillmentL10n.date(viewModel.record.updatedAt))
                PPFulfillmentKeyValue(titleKey: "Fulfillment_DetailMode", value: PPFulfillmentL10n.mode(for: viewModel.record))
                PPFulfillmentKeyValue(titleKey: "Fulfillment_DetailCustomer", value: viewModel.customerName)
            }
            .padding(PPFulfillmentTokens.spaceBase)
            .ppFulfillmentCard()
        }
    }

    private var compositionSection: some View {
        detailSection(titleKey: "Fulfillment_DetailItems", symbol: "shippingbox.fill") {
            if viewModel.record.items.isEmpty {
                Text(PPFulfillmentL10n.text("Fulfillment_NoItems"))
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 90)
                    .ppFulfillmentCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.record.items.enumerated()), id: \.element.id) { index, item in
                        PPFulfillmentItemRow(index: index + 1, item: item, currency: viewModel.record.currency)
                        if index < viewModel.record.items.count - 1 { Divider().padding(.leading, 58) }
                    }
                }
                .ppFulfillmentCard()
            }
        }
    }

    private var settlementSection: some View {
        detailSection(titleKey: "Fulfillment_DetailSettlement", symbol: "banknote.fill") {
            VStack(spacing: PPFulfillmentTokens.spaceMD) {
                settlementRow(titleKey: "Fulfillment_Subtotal", amount: viewModel.record.subtotal, emphasized: false)
                settlementRow(titleKey: "Fulfillment_PlatformCommission", amount: viewModel.record.platformCommission, emphasized: false)
                Divider()
                settlementRow(titleKey: "Fulfillment_ProviderNet", amount: viewModel.record.providerNet, emphasized: true)
            }
            .padding(PPFulfillmentTokens.spaceBase)
            .ppFulfillmentCard()
        }
    }

    private var auditSection: some View {
        detailSection(titleKey: "Fulfillment_AdminOverride", symbol: "shield.checkered") {
            VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceMD) {
                Label(PPFulfillmentL10n.date(viewModel.record.adminOverrideAt), systemImage: "calendar.badge.exclamationmark")
                if !viewModel.record.adminOverrideBy.isEmpty {
                    Label(viewModel.record.adminOverrideBy, systemImage: "person.badge.shield.checkmark.fill")
                        .environment(\.layoutDirection, .leftToRight)
                }
                if !viewModel.record.adminOverrideReason.isEmpty {
                    Text(viewModel.record.adminOverrideReason)
                        .font(PPFulfillmentTokens.beiruti(.medium, size: 16, relativeTo: .body))
                        .foregroundStyle(PPFulfillmentTokens.goldInk)
                }
            }
            .font(PPFulfillmentTokens.beiruti(.regular, size: 15, relativeTo: .subheadline))
            .foregroundStyle(PPFulfillmentTokens.secondaryInk)
            .padding(PPFulfillmentTokens.spaceBase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ppFulfillmentCard()
        }
    }

    private var timelineSection: some View {
        detailSection(titleKey: "Fulfillment_DetailTimeline", symbol: "point.3.connected.trianglepath.dotted") {
            if viewModel.events.isEmpty {
                Text(PPFulfillmentL10n.text("Fulfillment_NoEvents"))
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 90)
                    .ppFulfillmentCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.events.enumerated()), id: \.element.id) { index, event in
                        PPFulfillmentTimelineRow(event: event, isLast: index == viewModel.events.count - 1)
                    }
                }
                .padding(PPFulfillmentTokens.spaceBase)
                .ppFulfillmentCard()
            }
        }
    }

    private func detailSection<Content: View>(titleKey: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceMD) {
            Label(PPFulfillmentL10n.text(titleKey), systemImage: symbol)
                .font(PPFulfillmentTokens.beiruti(.bold, size: 21, relativeTo: .title3))
                .foregroundStyle(PPFulfillmentTokens.ink)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func settlementRow(titleKey: String, amount: Double, emphasized: Bool) -> some View {
        HStack {
            Text(PPFulfillmentL10n.text(titleKey))
            Spacer()
            Text(PPFulfillmentL10n.money(amount, currency: viewModel.record.currency))
                .fontWeight(.bold)
        }
        .font(PPFulfillmentTokens.beiruti(emphasized ? .bold : .regular, size: emphasized ? 18 : 16, relativeTo: emphasized ? .headline : .body))
        .foregroundStyle(emphasized ? PPFulfillmentTokens.success : PPFulfillmentTokens.ink)
    }
}

private struct PPFulfillmentKeyValue: View {
    let titleKey: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PPFulfillmentL10n.text(titleKey))
                .font(PPFulfillmentTokens.beiruti(.medium, size: 13, relativeTo: .caption))
                .foregroundStyle(PPFulfillmentTokens.secondaryInk)
            Text(value)
                .font(monospaced ? .system(size: 15, weight: .semibold, design: .monospaced) : PPFulfillmentTokens.beiruti(.bold, size: 16, relativeTo: .body))
                .foregroundStyle(PPFulfillmentTokens.ink)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, monospaced ? .leftToRight : PPFulfillmentL10n.layoutDirection)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PPFulfillmentItemRow: View {
    let index: Int
    let item: PPFulfillmentItemSnapshot
    let currency: String

    var body: some View {
        HStack(alignment: .top, spacing: PPFulfillmentTokens.spaceMD) {
            Text("\(index)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PPFulfillmentTokens.goldInk)
                .frame(width: 34, height: 34)
                .background(PPFulfillmentTokens.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 17, relativeTo: .headline))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                Text(PPFulfillmentL10n.format("Fulfillment_ItemQuantity_Format", item.quantity))
                    .font(PPFulfillmentTokens.beiruti(.regular, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
            }
            Spacer()
            Text(PPFulfillmentL10n.money(item.unitPrice * Double(item.quantity), currency: currency))
                .font(PPFulfillmentTokens.beiruti(.bold, size: 15, relativeTo: .subheadline))
                .foregroundStyle(PPFulfillmentTokens.ink)
        }
        .padding(PPFulfillmentTokens.spaceBase)
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        item.name.isEmpty ? PPFulfillmentL10n.text("Fulfillment_Item") : item.name
    }
}

private struct PPFulfillmentTimelineRow: View {
    let event: PPFulfillmentEventSnapshot
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: PPFulfillmentTokens.spaceMD) {
            VStack(spacing: 0) {
                Circle()
                    .fill(tone.color)
                    .overlay(Circle().stroke(PPFulfillmentTokens.surface, lineWidth: 3))
                    .frame(width: 18, height: 18)
                    .shadow(color: tone.color.opacity(0.35), radius: 4)
                if !isLast {
                    Rectangle()
                        .fill(tone.color.opacity(0.25))
                        .frame(width: 2, height: 64)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(event.action.isEmpty ? PPFulfillmentL10n.text("Fulfillment_Event") : event.action.replacingOccurrences(of: "_", with: " ").localizedCapitalized)
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 16, relativeTo: .headline))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                if !event.fromStatus.isEmpty || !event.toStatus.isEmpty {
                    HStack(spacing: 6) {
                        if !event.fromStatus.isEmpty { Text(PPFulfillmentL10n.status(event.fromStatus)) }
                        Image(systemName: PPFulfillmentL10n.isRTL ? "arrow.left" : "arrow.right")
                            .accessibilityHidden(true)
                        if !event.toStatus.isEmpty { Text(PPFulfillmentL10n.status(event.toStatus)) }
                    }
                    .font(PPFulfillmentTokens.beiruti(.medium, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(tone.color)
                }
                HStack(spacing: 5) {
                    if !event.actor.isEmpty { Text(event.actor) }
                    if !event.actor.isEmpty, event.createdAt != nil { Text("•") }
                    Text(PPFulfillmentL10n.date(event.createdAt))
                }
                .font(PPFulfillmentTokens.beiruti(.regular, size: 13, relativeTo: .caption))
                .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                if !event.reason.isEmpty {
                    Text(event.reason)
                        .font(PPFulfillmentTokens.beiruti(.regular, size: 14, relativeTo: .subheadline))
                        .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                }
            }
            .padding(.bottom, isLast ? 0 : PPFulfillmentTokens.spaceBase)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var tone: PPFulfillmentTone {
        let temporary = event.toStatus
        switch temporary {
        case "completed", "accepted", "ready_for_pickup", "payment_confirmed": return .success
        case "rejected", "cancelled", "failed", "returned": return .danger
        case "delivery_assigned", "awaiting_handover", "handed_over", "picked_up", "in_transit", "delivered": return .info
        default: return .progress
        }
    }
}

// MARK: - Override sheet

private struct PPFulfillmentOverrideSheet: View {
    @ObservedObject var viewModel: PPFulfillmentDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case reason
        case note
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Label(PPFulfillmentL10n.status(viewModel.record.status), systemImage: viewModel.record.tone.symbol)
                        .foregroundStyle(viewModel.record.tone.color)
                } header: {
                    Text(PPFulfillmentL10n.text("Fulfillment_CurrentStatus"))
                }

                Section(PPFulfillmentL10n.text("Fulfillment_TargetStatus")) {
                    Picker(PPFulfillmentL10n.text("Fulfillment_TargetStatus"), selection: $viewModel.overrideTarget) {
                        ForEach(viewModel.allowedOverrideTargets, id: \.self) { status in
                            Text(PPFulfillmentL10n.status(status)).tag(status)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section(PPFulfillmentL10n.text("Fulfillment_Reason")) {
                    TextField(PPFulfillmentL10n.text("Fulfillment_ReasonPlaceholder"), text: $viewModel.overrideReason)
                        .focused($focusedField, equals: .reason)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .note }
                        .accessibilityIdentifier("fulfillment.override.reason")
                }

                Section(PPFulfillmentL10n.text("Fulfillment_Note")) {
                    TextField(PPFulfillmentL10n.text("Fulfillment_NotePlaceholder"), text: $viewModel.overrideNote)
                        .focused($focusedField, equals: .note)
                        .submitLabel(.done)
                        .accessibilityIdentifier("fulfillment.override.note")
                }

                Section {
                    Toggle(PPFulfillmentL10n.text("Fulfillment_NotifyCustomer"), isOn: $viewModel.notifyCustomer)
                    Button(role: .destructive, action: viewModel.submitOverride) {
                        HStack {
                            if viewModel.isSubmitting { ProgressView() }
                            Text(PPFulfillmentL10n.text("Fulfillment_ConfirmOverride"))
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(!viewModel.canSubmitOverride)
                    .accessibilityIdentifier("fulfillment.override.confirm")
                } footer: {
                    Text(PPFulfillmentL10n.text("Fulfillment_Override_AuditNotice"))
                }
            }
            .navigationTitle(PPFulfillmentL10n.text("Fulfillment_AdminOverride"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PPFulfillmentL10n.text("Cancel")) { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Objective-C UIKit entry point

@MainActor
@objcMembers
final class PPFulfillmentOrdersViewController: UIViewController {
    private let viewModel = PPFulfillmentOrdersViewModel()
    private var hostingController: UIHostingController<PPFulfillmentOrdersScreen>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = PPFulfillmentL10n.text("Fulfillment_Title")
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.075, green: 0.067, blue: 0.063, alpha: 1)
                : UIColor(red: 0.965, green: 0.953, blue: 0.933, alpha: 1)
        }
        view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage()

        let host = UIHostingController(
            rootView: PPFulfillmentOrdersScreen(viewModel: viewModel) { [weak self] record in
                let detail = PPFulfillmentDetailViewController(seed: record)
                self?.navigationController?.pushViewController(detail, animated: true)
            }
        )
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            viewModel.stopListening()
        }
    }
}

@MainActor
private final class PPFulfillmentDetailViewController: UIViewController {
    private let viewModel: PPFulfillmentDetailViewModel
    private var hostingController: UIHostingController<PPFulfillmentDetailScreen>?

    init(seed: PPFulfillmentSnapshot) {
        viewModel = PPFulfillmentDetailViewModel(seed: seed, service: PPFulfillmentService.shared())
        super.init(nibName: nil, bundle: nil)
        title = seed.displayOrder
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.075, green: 0.067, blue: 0.063, alpha: 1)
                : UIColor(red: 0.965, green: 0.953, blue: 0.933, alpha: 1)
        }
        view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage()

        let overrideItem = UIBarButtonItem(
            image: UIImage(systemName: "shield.lefthalf.filled.badge.checkmark"),
            style: .plain,
            target: self,
            action: #selector(presentOverride)
        )
        overrideItem.tintColor = .systemRed
        overrideItem.accessibilityLabel = PPFulfillmentL10n.text("Fulfillment_AdminOverride")
        overrideItem.accessibilityIdentifier = "fulfillment.override"
        navigationItem.rightBarButtonItem = overrideItem

        let host = UIHostingController(rootView: PPFulfillmentDetailScreen(viewModel: viewModel))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    @objc private func presentOverride() {
        viewModel.prepareOverride()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            viewModel.stop()
        }
    }
}