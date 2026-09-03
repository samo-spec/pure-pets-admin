//
//  PPFulfillmentOrdersViewController.swift
//  PurePetsAdmin
//
//  SwiftUI Fulfillment Mission Control. UIKit retains dashboard/navigation ownership;
//  this feature owns fulfillment presentation and state. Firebase reads and
//  writes remain centralized in PPFulfillmentService.
//

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Design system

private enum PPFulfillmentTokens {
    static let spaceXS = CGFloat(PPSpaceXS)
    static let spaceSM = CGFloat(PPSpaceSM)
    static let spaceMD = CGFloat(PPSpaceMD)
    static let spaceBase = CGFloat(PPSpaceBase)
    static let spaceLG = CGFloat(PPSpaceLG)
    static let spaceXL = CGFloat(PPSpaceXL)
    static let screenMargin = CGFloat(PPScreenMargin)
    static let cornerSmall = CGFloat(PPCornerSmall)
    static let cornerMedium = CGFloat(PPCorner16)
    static let cornerCard = CGFloat(PPCornerCard)
    static let cornerHero = CGFloat(PPCornerCard)
    static let minimumTarget = CGFloat(PPTouchTargetMin)

    static let canvas = AdminSurface.background
    static let surface = AdminSurface.surface
    static let ink = AdminSurface.primaryText
    static let secondaryInk = AdminSurface.secondaryText
    static let tertiaryInk = Color(uiColor: .ppTextTertiary)
    static let gold = Color(uiColor: .ppPremiumAccent)
    static let success = Color(uiColor: .ppSuccess)
    static let warning = Color(uiColor: .ppWarning)
    static let danger = Color(uiColor: .ppError)
    static let info = Color(uiColor: .ppInfo)
    static let primary = AdminSurface.primary
    static let primarySoft = AdminSurface.primarySoft
    static let border = AdminSurface.hairline
    static let disabledFill = Color(uiColor: .ppSecondarySurface)

    /// Keeps existing call sites semantic while routing all typography through
    /// the app-wide AdminType scale instead of a Fulfillment-only font system.
    static func beiruti(_ weight: Font.Weight, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        let strong: Bool
        switch weight {
        case .medium, .semibold, .bold, .heavy, .black: strong = true
        default: strong = false
        }
        switch style {
        case .largeTitle: return strong ? AdminType.title : AdminType.title2
        case .title: return AdminType.title
        case .title2: return AdminType.title2
        case .title3: return AdminType.title3
        case .headline: return AdminType.headline
        case .subheadline: return strong ? AdminType.subheadlineBold : AdminType.subheadline
        case .body: return strong ? AdminType.headline : AdminType.body
        case .callout: return strong ? AdminType.calloutBold : AdminType.callout
        case .footnote: return strong ? AdminType.footnoteBold : AdminType.footnote
        case .caption: return strong ? AdminType.captionBold : AdminType.caption1
        case .caption2: return strong ? AdminType.caption2Bold : AdminType.caption2
        @unknown default: return strong ? AdminType.headline : AdminType.body
        }
    }
}

private struct PPFulfillmentCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(PPFulfillmentTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous)
                    .stroke(PPFulfillmentTokens.border, lineWidth: 1)
            )
    }
}

private extension View {
    func ppFulfillmentCard() -> some View {
        modifier(PPFulfillmentCardModifier())
    }
}

// MARK: - Localization and formatting

private enum PPFulfillmentL10n {
    static var locale: Locale { Locale(identifier: Language.currentLanguageCode()) }

    static func text(_ key: String) -> String {
        Language.get(key, alter: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
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

    static func eventAction(_ rawAction: String) -> String {
        switch rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "admin_override": return text("Fulfillment_Event_AdminOverride")
        case "provider_transition": return text("Fulfillment_Event_ProviderTransition")
        case "delivery_transition": return text("Fulfillment_Event_DeliveryTransition")
        case "created", "fulfillment_created": return text("Fulfillment_Event_Created")
        case "status_changed": return text("Fulfillment_Event_StatusChanged")
        case "payment_confirmed": return text("Fulfillment_Event_PaymentConfirmed")
        case "accept": return text("Fulfillment_Event_Accept")
        case "reject": return text("Fulfillment_Event_Reject")
        case "start_preparing": return text("Fulfillment_Event_StartPreparing")
        case "mark_ready": return text("Fulfillment_Event_MarkReady")
        case "request_delivery": return text("Fulfillment_Event_RequestDelivery")
        case "confirm_handover": return text("Fulfillment_Event_ConfirmHandover")
        case "cancel_request": return text("Fulfillment_Event_CancelRequest")
        case "order_accept_delivery": return text("Fulfillment_Event_AcceptDelivery")
        case "order_mark_shipped": return text("Fulfillment_Event_MarkShipped")
        case "order_mark_in_transit": return text("Fulfillment_Event_MarkInTransit")
        case "order_mark_delivered": return text("Fulfillment_Event_MarkDelivered")
        case "order_collect_payment": return text("Fulfillment_Event_CollectPayment")
        case "order_mark_completed": return text("Fulfillment_Event_MarkCompleted")
        case "order_cancel_delivery": return text("Fulfillment_Event_CancelDelivery")
        default:
            return rawAction.isEmpty ? text("Fulfillment_Event") : rawAction.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func actorType(_ rawType: String) -> String {
        switch rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "platform_admin": return text("Fulfillment_Actor_Admin")
        case "provider": return text("Fulfillment_Actor_Provider")
        case "delivery": return text("Fulfillment_Actor_Delivery")
        case "system": return text("Fulfillment_Actor_System")
        default: return rawType
        }
    }

    static func mode(for record: PPFulfillmentSnapshot) -> String {
        record.isPlatformOwned ? text("Fulfillment_Filter_Platform") : text("Fulfillment_Filter_Partner")
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(locale)
        )
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return text("Fulfillment_UpdatedJustNow") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return format("Fulfillment_UpdatedAgo_Format", formatter.localizedString(for: date, relativeTo: Date()))
    }

    static func money(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
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

private enum PPFulfillmentStage: String, CaseIterable, Identifiable, Sendable {
    case intake
    case preparation
    case handoff
    case settlement
    case outcome

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .intake: return "Fulfillment_Stage_Intake"
        case .preparation: return "Fulfillment_Stage_Preparation"
        case .handoff: return "Fulfillment_Stage_Handoff"
        case .settlement: return "Fulfillment_Stage_Settlement"
        case .outcome: return "Fulfillment_Stage_Outcome"
        }
    }

    var detailKey: String {
        switch self {
        case .intake: return "Fulfillment_Stage_Intake_Detail"
        case .preparation: return "Fulfillment_Stage_Preparation_Detail"
        case .handoff: return "Fulfillment_Stage_Handoff_Detail"
        case .settlement: return "Fulfillment_Stage_Settlement_Detail"
        case .outcome: return "Fulfillment_Stage_Outcome_Detail"
        }
    }

    var symbol: String {
        switch self {
        case .intake: return "tray.and.arrow.down.fill"
        case .preparation: return "shippingbox.fill"
        case .handoff: return "arrow.triangle.swap"
        case .settlement: return "banknote.fill"
        case .outcome: return "checkmark.seal.fill"
        }
    }

    func contains(_ status: String) -> Bool {
        let status = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch self {
        case .intake:
            return ["new_request", "accepted"].contains(status)
        case .preparation:
            return ["preparing", "ready_for_pickup"].contains(status)
        case .handoff:
            return ["delivery_requested", "delivery_assigned", "awaiting_handover", "handed_over", "picked_up", "in_transit", "delivered"].contains(status)
        case .settlement:
            return ["payment_pending", "payment_confirmed"].contains(status)
        case .outcome:
            return ["completed", "rejected", "cancelled", "failed", "returned"].contains(status)
        }
    }

    static func resolve(_ status: String) -> PPFulfillmentStage {
        allCases.first(where: { $0.contains(status) }) ?? .intake
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
        case .progress: return PPFulfillmentTokens.primary
        case .success: return PPFulfillmentTokens.success
        case .danger: return PPFulfillmentTokens.danger
        case .neutral: return PPFulfillmentTokens.tertiaryInk
        case .info: return PPFulfillmentTokens.info
        }
    }

    var softFill: Color {
        color.opacity(0.12)
    }

    var symbol: String {
        switch self {
        case .progress: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .danger: return "exclamationmark.octagon.fill"
        case .neutral: return "circle.dotted"
        case .info: return "shippingbox.fill"
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
    let adminOverrideCommandID: String

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
        adminOverrideCommandID = record.adminOverrideCommandID ?? ""
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
            && lhs.adminOverrideCommandID == rhs.adminOverrideCommandID
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

    var isException: Bool {
        ["rejected", "cancelled", "failed", "returned"].contains(status)
    }

    var stage: PPFulfillmentStage { PPFulfillmentStage.resolve(status) }

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
    static let awaitingStatuses: Set<String> = [
        "new_request", "accepted", "preparing", "ready_for_pickup",
        "delivery_requested", "delivery_assigned", "awaiting_handover", "payment_pending",
    ]

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
    let actorType: String
    let createdAt: Date?
    let reason: String
    let note: String

    init(dictionary: [AnyHashable: Any], index: Int) {
        let metadata = dictionary["metadata"] as? [AnyHashable: Any] ?? [:]
        action = Self.string(dictionary["action"]).isEmpty
            ? Self.string(dictionary["type"], fallback: PPFulfillmentL10n.text("Fulfillment_Event"))
            : Self.string(dictionary["action"])
        fromStatus = Self.string(dictionary["fromStatus"])
        toStatus = Self.string(dictionary["toStatus"])
        actor = Self.firstString(in: dictionary, keys: ["actorUserId", "actor", "performedBy", "by", "userId"])
        actorType = Self.firstString(in: dictionary, keys: ["actorType"])
        reason = Self.firstString(in: dictionary, keys: ["reason"])
            .isEmpty ? Self.firstString(in: metadata, keys: ["reason"]) : Self.firstString(in: dictionary, keys: ["reason"])
        note = Self.firstString(in: dictionary, keys: ["note"])
            .isEmpty ? Self.firstString(in: metadata, keys: ["note"]) : Self.firstString(in: dictionary, keys: ["note"])
        if let timestamp = dictionary["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else if let timestamp = dictionary["timestamp"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = (dictionary["createdAt"] ?? dictionary["timestamp"]) as? Date
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
    let exceptions: Int
    let providerNet: Double
    let currency: String
    let hasMixedCurrencies: Bool

    init(records: [PPFulfillmentSnapshot]) {
        active = records.filter { !$0.isTerminal }.count
        awaiting = records.filter(\.isAwaitingAction).count
        completed = records.filter(\.isCompleted).count
        exceptions = records.filter(\.isException).count
        let currencies = Set(records.map(\.currency).filter { !$0.isEmpty })
        hasMixedCurrencies = currencies.count > 1
        providerNet = hasMixedCurrencies ? 0 : records.reduce(0) { $0 + $1.providerNet }
        currency = currencies.first ?? "QAR"
    }
}

private struct PPFulfillmentAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum PPFulfillmentOverridePhase: String {
    case pending
    case acceptedWaitingSync
    case confirmed
    case alreadyCurrent
    case denied
    case conflict
    case invalid
    case error
    case stale
}

private struct PPFulfillmentPendingOverride {
    let targetStatus: String
    let commandID: String
    let commandDocumentID: String
    let notificationRequested: Bool
    let notificationAttempted: Bool
    let notificationSucceeded: Bool
    let notificationStatus: String?
    let notificationOutcomeKnown: Bool
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
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var isFromCache = false
    @Published private(set) var changedRecordIDs: Set<String> = []
    @Published var searchText = ""
    @Published var statusGroup: PPFulfillmentStatusGroup = .all
    @Published var ownerFilter: PPFulfillmentOwnerFilter = .all
    @Published var exactStatus = ""
    @Published var stageFilter: PPFulfillmentStage?

    private let service = PPFulfillmentService.shared()
    private var listener: PPFulfillmentListenerToken?
    private var previousStatuses: [String: String] = [:]
    private var hasLoadedOnce = false
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var listenerGeneration = 0

    deinit {
        listener?.remove()
        refreshWaiters.forEach { $0.resume() }
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
            || stageFilter != nil
    }

    var filteredRecords: [PPFulfillmentSnapshot] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        return records.filter { record in
            if !exactStatus.isEmpty, record.status != exactStatus { return false }
            if let stageFilter, record.stage != stageFilter { return false }
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
        isRefreshing = true
        errorMessage = nil
        listener?.remove()
        listenerGeneration += 1
        let generation = listenerGeneration
        let registration = service.observeFulfillments { [weak self] records, isFromCache, error in
            let snapshots = records.map(PPFulfillmentSnapshot.init(record:))
            let message = error?.localizedDescription
            let isPartialRead = PPFulfillmentService.isPartialReadError(error)
            DispatchQueue.main.async {
                guard let self, generation == self.listenerGeneration else { return }
                self.isLoading = false
                if let message, !isPartialRead {
                    self.errorMessage = message
                    self.finishRefresh()
                    return
                }
                self.lastSyncDate = Date()
                self.isFromCache = isFromCache
                self.markChangedRecords(in: snapshots)
                self.records = snapshots
                self.errorMessage = isPartialRead ? message : nil
                self.hasLoadedOnce = true
                self.resolveNames(for: snapshots)
                self.finishRefresh()
            }
        }
        listener = PPFulfillmentListenerToken(registration)
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        listenerGeneration += 1
        finishRefresh()
    }

    func refresh() async {
        startListening()
        guard isRefreshing else { return }
        await withCheckedContinuation { continuation in
            refreshWaiters.append(continuation)
        }
    }

    func retry() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        startListening()
    }

    func clearFilters() {
        statusGroup = .all
        ownerFilter = .all
        exactStatus = ""
        stageFilter = nil
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
            ?? (!record.ownerID.isEmpty ? record.ownerID : PPFulfillmentL10n.text("Fulfillment_UnknownOwner"))
    }

    func count(for stage: PPFulfillmentStage) -> Int {
        records.lazy.filter { $0.stage == stage }.count
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
        changedRecordIDs.formIntersection(Set(statuses.keys))
        changedRecordIDs.formUnion(changed)
    }

    private func finishRefresh() {
        isLoading = false
        isRefreshing = false
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        waiters.forEach { $0.resume() }
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
    var onDismiss: (() -> Void)? = nil
    let onOpenRecord: (PPFulfillmentSnapshot) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsFilters = false

    var body: some View {
        ZStack {
            PPFulfillmentTokens.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                dossierHeaderView

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceBase) {
                        operationalPulse
                        workflowBoard
                        queueControls
                        if let error = viewModel.errorMessage, !viewModel.records.isEmpty {
                            retainedConnectionNotice(error)
                        }
                        resultsHeader
                        content
                    }
                    .padding(.horizontal, PPFulfillmentTokens.screenMargin)
                    .padding(.top, PPFulfillmentTokens.spaceXS)
                    .padding(.bottom, PPFulfillmentTokens.spaceXL)
                }
                .refreshable { await viewModel.refresh() }
            }
        }
        .environment(\.layoutDirection, PPFulfillmentL10n.layoutDirection)
        .sheet(isPresented: $showsFilters) {
            PPFulfillmentFiltersSheet(viewModel: viewModel)
                .environment(\.layoutDirection, PPFulfillmentL10n.layoutDirection)
        }
        .onAppear(perform: viewModel.startListening)
        .onDisappear(perform: viewModel.stopListening)
    }

    // MARK: - Sovereign Navigation Bar

    private var dossierHeaderView: some View {
        AdminSovereignNavigationBar(
            title: PPFulfillmentL10n.text("Fulfillment_Title"),
            subtitle: Language.get("CommandCenter_Fulfillment_Workspace", alter: "مساحة التنفيذ"),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            if viewModel.isRefreshing {
                ProgressView()
                    .tint(PPFulfillmentTokens.primary)
            } else {
                Button(action: { viewModel.retry() }) {
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
                .accessibilityLabel(PPFulfillmentL10n.text("Fulfillment_Retry"))
            }
        }
    }

    private var operationalStatusBar: some View {
        liveStatus
            .font(AdminType.caption1)
            .foregroundStyle(PPFulfillmentTokens.secondaryInk)
            .accessibilityIdentifier("fulfillment.live.status")
    }

    private var refreshControl: some View {
        Button(action: viewModel.retry) {
            Image(systemName: viewModel.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PPFulfillmentTokens.primary)
                .frame(width: PPFulfillmentTokens.minimumTarget, height: PPFulfillmentTokens.minimumTarget)
                .background(PPFulfillmentTokens.primarySoft, in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRefreshing)
        .accessibilityLabel(PPFulfillmentL10n.text("Fulfillment_Retry"))
        .accessibilityIdentifier("fulfillment.refresh")
    }

    @ViewBuilder
    private var liveStatus: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) { liveStatusContent }
        } else {
            HStack(spacing: PPFulfillmentTokens.spaceSM) { liveStatusContent }
        }
    }

    @ViewBuilder
    private var liveStatusContent: some View {
        Label(connectionTitle, systemImage: connectionSymbol)
            .foregroundStyle(connectionColor)
        if !dynamicTypeSize.isAccessibilitySize { Text("•").accessibilityHidden(true) }
        if viewModel.lastSyncDate != nil {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(PPFulfillmentL10n.relativeDate(viewModel.lastSyncDate))
            }
        }
        if viewModel.records.count >= 100 {
            if !dynamicTypeSize.isAccessibilitySize { Text("•").accessibilityHidden(true) }
            Label(PPFulfillmentL10n.text("Fulfillment_Queue_Limit"), systemImage: "clock.arrow.circlepath")
                .foregroundStyle(PPFulfillmentTokens.warning)
        }
        if !viewModel.changedRecordIDs.isEmpty {
            if !dynamicTypeSize.isAccessibilitySize { Text("•").accessibilityHidden(true) }
            Label(
                PPFulfillmentL10n.format("Fulfillment_Changes_Format", "\(viewModel.changedRecordIDs.count)"),
                systemImage: "sparkles"
            )
            .foregroundStyle(PPFulfillmentTokens.primary)
        }
    }

    private var operationalPulse: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceMD) {
            operationalPulseHeader

            if hasOperationalSnapshot {
                Divider().overlay(healthColor.opacity(0.24))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 180 : 128), spacing: PPFulfillmentTokens.spaceMD)],
                    alignment: .leading,
                    spacing: PPFulfillmentTokens.spaceMD
                ) {
                    PPFulfillmentPulseMetric(
                        title: PPFulfillmentL10n.text("Fulfillment_Metric_Active"),
                        value: "\(viewModel.metrics.active)",
                        symbol: "bolt.fill",
                        color: PPFulfillmentTokens.primary
                    )
                    PPFulfillmentPulseMetric(
                        title: PPFulfillmentL10n.text("Fulfillment_Metric_Completed"),
                        value: "\(viewModel.metrics.completed)",
                        symbol: "checkmark.seal.fill",
                        color: PPFulfillmentTokens.success
                    )
                    PPFulfillmentPulseMetric(
                        title: PPFulfillmentL10n.text("Fulfillment_Metric_Exceptions"),
                        value: "\(viewModel.metrics.exceptions)",
                        symbol: "exclamationmark.triangle.fill",
                        color: viewModel.metrics.exceptions > 0 ? PPFulfillmentTokens.danger : PPFulfillmentTokens.tertiaryInk
                    )
                    PPFulfillmentPulseMetric(
                        title: PPFulfillmentL10n.text("Fulfillment_Metric_NetValue"),
                        value: viewModel.metrics.hasMixedCurrencies
                            ? PPFulfillmentL10n.text("Fulfillment_Metric_MixedCurrencies")
                            : PPFulfillmentL10n.money(viewModel.metrics.providerNet, currency: viewModel.metrics.currency),
                        symbol: "banknote.fill",
                        color: PPFulfillmentTokens.info
                    )
                }
            }
        }
        .padding(PPFulfillmentTokens.spaceBase)
        .background(PPFulfillmentTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous)
                .stroke(PPFulfillmentTokens.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fulfillment.operational.pulse")
    }

    @ViewBuilder
    private var operationalPulseHeader: some View {
        if !hasOperationalSnapshot {
            healthReadout
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceMD) {
                healthReadout
                waitingCount
            }
        } else {
            HStack(alignment: .top, spacing: PPFulfillmentTokens.spaceMD) {
                healthReadout
                Spacer(minLength: PPFulfillmentTokens.spaceSM)
                waitingCount
            }
        }
    }

    private var healthReadout: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceXS) {
            Label(healthTitle, systemImage: healthSymbol)
                .font(PPFulfillmentTokens.beiruti(.bold, size: 20, relativeTo: .title3))
                .foregroundStyle(healthColor)
            Text(healthDetail)
                .font(PPFulfillmentTokens.beiruti(.regular, size: 15, relativeTo: .subheadline))
                .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var waitingCount: some View {
        Text("\(viewModel.metrics.awaiting)")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(healthColor)
            .accessibilityLabel(
                PPFulfillmentL10n.format("Fulfillment_Metric_Waiting_Accessibility_Format", "\(viewModel.metrics.awaiting)")
            )
    }

    private var workflowBoard: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) {
            Text(PPFulfillmentL10n.text("Fulfillment_Workflow_Title"))
                .font(AdminType.captionBold)
                .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PPFulfillmentTokens.spaceSM) {
                    ForEach(PPFulfillmentStage.allCases) { stage in
                        PPFulfillmentStageNode(
                            stage: stage,
                            count: viewModel.count(for: stage),
                            isSelected: viewModel.stageFilter == stage
                        ) {
                            viewModel.stageFilter = viewModel.stageFilter == stage ? nil : stage
                            viewModel.exactStatus = ""
                            viewModel.statusGroup = .all
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var queueControls: some View {
        VStack(spacing: PPFulfillmentTokens.spaceMD) {
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
                            .frame(width: PPFulfillmentTokens.minimumTarget, height: PPFulfillmentTokens.minimumTarget)
                    }
                    .accessibilityLabel(PPFulfillmentL10n.text("Fulfillment_ClearSearch"))
                }
            }
            .padding(.horizontal, PPFulfillmentTokens.spaceBase)
            .frame(minHeight: 52)
            .background(PPFulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous).stroke(PPFulfillmentTokens.border))

            scopeControls
        }
    }

    @ViewBuilder
    private var scopeControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: PPFulfillmentTokens.spaceSM) { scopeControlContent }
        } else {
            HStack(spacing: PPFulfillmentTokens.spaceSM) { scopeControlContent }
        }
    }

    @ViewBuilder
    private var scopeControlContent: some View {
        // ── Scope chip (All / Active / Awaiting / Completed) ──────────
        Menu {
            ForEach(PPFulfillmentStatusGroup.allCases) { group in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        viewModel.statusGroup = group
                        viewModel.exactStatus = ""
                        viewModel.stageFilter = nil
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Label(PPFulfillmentL10n.text(group.titleKey), systemImage: symbol(for: group))
                }
            }
        } label: {
            HStack(spacing: PPFulfillmentTokens.spaceXS) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .semibold))
                    .imageScale(.small)
                Text(activeScopeTitle)
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, PPFulfillmentTokens.spaceMD)
            .frame(minHeight: 40)
            .foregroundStyle(PPFulfillmentTokens.primary)
            .background(PPFulfillmentTokens.primarySoft, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(PPFulfillmentTokens.primary.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityIdentifier("fulfillment.scope")
        .accessibilityLabel(activeScopeTitle)

        // ── Filter chip ──────────────────────────────────────────────
        Button(action: { showsFilters = true }) {
            HStack(spacing: PPFulfillmentTokens.spaceXS) {
                Image(systemName: viewModel.hasActiveFilters
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .imageScale(.small)
                    .symbolRenderingMode(viewModel.hasActiveFilters ? .hierarchical : .monochrome)
                Text(PPFulfillmentL10n.text("Fulfillment_Filters_Title"))
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
                    .lineLimit(1)
                if viewModel.hasActiveFilters {
                    Circle()
                        .fill(PPFulfillmentTokens.primary)
                        .frame(width: 6, height: 6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, PPFulfillmentTokens.spaceMD)
            .frame(minHeight: 40)
            .foregroundStyle(viewModel.hasActiveFilters ? PPFulfillmentTokens.primary : PPFulfillmentTokens.secondaryInk)
            .background(
                viewModel.hasActiveFilters
                    ? PPFulfillmentTokens.primarySoft
                    : PPFulfillmentTokens.surface,
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        viewModel.hasActiveFilters
                            ? PPFulfillmentTokens.primary.opacity(0.18)
                            : PPFulfillmentTokens.border,
                        lineWidth: 1
                    )
            )
            .contentShape(Capsule())
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: viewModel.hasActiveFilters)
        }
        .accessibilityIdentifier("fulfillment.filters")
    }

    private func retainedConnectionNotice(_ error: String) -> some View {
        HStack(alignment: .top, spacing: PPFulfillmentTokens.spaceMD) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(PPFulfillmentTokens.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(PPFulfillmentL10n.text("Fulfillment_Retained_Title"))
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 16, relativeTo: .headline))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                Text(error)
                    .font(PPFulfillmentTokens.beiruti(.regular, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
            }
            Spacer(minLength: 0)
            Button(PPFulfillmentL10n.text("Fulfillment_Retry"), action: viewModel.retry)
                .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
        }
        .padding(PPFulfillmentTokens.spaceBase)
        .background(PPFulfillmentTokens.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous).stroke(PPFulfillmentTokens.warning.opacity(0.32)))
        .accessibilityElement(children: .contain)
    }

    private var healthColor: Color {
        if !hasOperationalSnapshot { return viewModel.errorMessage == nil ? PPFulfillmentTokens.info : PPFulfillmentTokens.danger }
        if viewModel.errorMessage != nil || viewModel.isFromCache { return PPFulfillmentTokens.warning }
        if viewModel.metrics.exceptions > 0 { return PPFulfillmentTokens.danger }
        if viewModel.metrics.awaiting > 0 { return PPFulfillmentTokens.warning }
        return PPFulfillmentTokens.success
    }

    private var healthSymbol: String {
        if !hasOperationalSnapshot { return viewModel.errorMessage == nil ? "antenna.radiowaves.left.and.right" : "wifi.exclamationmark" }
        if viewModel.errorMessage != nil || viewModel.isFromCache { return "externaldrive.badge.exclamationmark" }
        if viewModel.metrics.exceptions > 0 { return "exclamationmark.triangle.fill" }
        if viewModel.metrics.awaiting > 0 { return "hourglass" }
        return "checkmark.circle.fill"
    }

    private var healthTitle: String {
        if !hasOperationalSnapshot {
            return PPFulfillmentL10n.text(viewModel.errorMessage == nil ? "Fulfillment_Health_Connecting_Title" : "Fulfillment_Health_Unavailable_Title")
        }
        if viewModel.errorMessage != nil || viewModel.isFromCache {
            return PPFulfillmentL10n.text("Fulfillment_Health_Retained_Title")
        }
        if viewModel.metrics.exceptions > 0 { return PPFulfillmentL10n.text("Fulfillment_Health_Exception_Title") }
        if viewModel.metrics.awaiting > 0 { return PPFulfillmentL10n.text("Fulfillment_Health_Attention_Title") }
        return PPFulfillmentL10n.text("Fulfillment_Health_Clear_Title")
    }

    private var healthDetail: String {
        if !hasOperationalSnapshot {
            return PPFulfillmentL10n.text(viewModel.errorMessage == nil ? "Fulfillment_Health_Connecting_Detail" : "Fulfillment_Health_Unavailable_Detail")
        }
        if viewModel.errorMessage != nil || viewModel.isFromCache {
            return PPFulfillmentL10n.text("Fulfillment_Health_Retained_Detail")
        }
        if viewModel.metrics.exceptions > 0 { return PPFulfillmentL10n.text("Fulfillment_Health_Exception_Detail") }
        if viewModel.metrics.awaiting > 0 { return PPFulfillmentL10n.text("Fulfillment_Health_Attention_Detail") }
        return PPFulfillmentL10n.text("Fulfillment_Health_Clear_Detail")
    }

    private var hasOperationalSnapshot: Bool { viewModel.lastSyncDate != nil }

    private var connectionTitle: String {
        if viewModel.isRefreshing { return PPFulfillmentL10n.text("Fulfillment_Connection_Syncing") }
        if viewModel.errorMessage != nil { return PPFulfillmentL10n.text("Fulfillment_Connection_Retained") }
        if viewModel.isFromCache { return PPFulfillmentL10n.text("Fulfillment_Connection_Cached") }
        return PPFulfillmentL10n.text("Fulfillment_Connection_Monitoring")
    }

    private var connectionSymbol: String {
        if viewModel.isRefreshing { return "arrow.triangle.2.circlepath" }
        if viewModel.errorMessage != nil { return "wifi.exclamationmark" }
        if viewModel.isFromCache { return "externaldrive.fill.badge.checkmark" }
        return "dot.radiowaves.left.and.right"
    }

    private var connectionColor: Color {
        if viewModel.errorMessage != nil || viewModel.isFromCache { return PPFulfillmentTokens.warning }
        return viewModel.isRefreshing ? PPFulfillmentTokens.info : PPFulfillmentTokens.success
    }

    private var activeScopeTitle: String {
        if !viewModel.exactStatus.isEmpty { return PPFulfillmentL10n.status(viewModel.exactStatus) }
        if let stage = viewModel.stageFilter { return PPFulfillmentL10n.text(stage.titleKey) }
        return PPFulfillmentL10n.text(viewModel.statusGroup.titleKey)
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) {
            resultsTitle
            Text(PPFulfillmentL10n.format("Fulfillment_Showing_Format", "\(viewModel.filteredRecords.count)", "\(viewModel.records.count)"))
                .font(PPFulfillmentTokens.beiruti(.regular, size: 14, relativeTo: .subheadline))
                .foregroundStyle(PPFulfillmentTokens.secondaryInk)
        }
    }

    @ViewBuilder
    private var resultsTitle: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) { resultsTitleContent }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: PPFulfillmentTokens.spaceMD) { resultsTitleContent }
        }
    }

    @ViewBuilder
    private var resultsTitleContent: some View {
        Text(PPFulfillmentL10n.text("Fulfillment_Queue_Title"))
            .font(PPFulfillmentTokens.beiruti(.bold, size: 23, relativeTo: .title2))
            .foregroundStyle(PPFulfillmentTokens.ink)
            .accessibilityAddTraits(.isHeader)
        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        if viewModel.hasActiveFilters {
            Button(PPFulfillmentL10n.text("Fulfillment_Filter_Clear"), action: viewModel.clearFilters)
                .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
                .foregroundStyle(PPFulfillmentTokens.primary)
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
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.filteredRecords.enumerated()), id: \.element.id) { index, record in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.acknowledgeChange(for: record.id)
                        onOpenRecord(record)
                    } label: {
                        PPFulfillmentCommandRow(
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

                    if index < viewModel.filteredRecords.count - 1 {
                        Divider()
                            .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 72)
                            .overlay(PPFulfillmentTokens.border.opacity(0.72))
                    }
                }
            }
            .background(PPFulfillmentTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous)
                    .stroke(PPFulfillmentTokens.border, lineWidth: 1)
            )
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

private struct PPFulfillmentSectionHeading: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: PPFulfillmentTokens.spaceMD) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PPFulfillmentTokens.primary)
                .frame(width: 36, height: 36)
                .background(PPFulfillmentTokens.primarySoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 21, relativeTo: .title3))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                Text(detail)
                    .font(PPFulfillmentTokens.beiruti(.regular, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct PPFulfillmentPulseMetric: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: PPFulfillmentTokens.spaceSM) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(PPFulfillmentTokens.beiruti(.medium, size: 12, relativeTo: .caption))
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                Text(value)
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 17, relativeTo: .headline))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}




private struct PPFulfillmentStageNode: View {
    let stage: PPFulfillmentStage
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PPFulfillmentTokens.spaceSM) {
                Image(systemName: stage.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(stageColor)
                    .accessibilityHidden(true)
                Text(PPFulfillmentL10n.text(stage.titleKey))
                    .font(AdminType.calloutBold)
                    .foregroundStyle(PPFulfillmentTokens.ink)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? stageColor : PPFulfillmentTokens.secondaryInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((isSelected ? stageColor : PPFulfillmentTokens.secondaryInk).opacity(0.09), in: Capsule())
            }
            .padding(.horizontal, PPFulfillmentTokens.spaceMD)
            .frame(minHeight: PPFulfillmentTokens.minimumTarget)
            .background(
                isSelected ? stageColor.opacity(0.09) : PPFulfillmentTokens.surface,
                in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous)
                    .stroke(isSelected ? stageColor.opacity(0.55) : PPFulfillmentTokens.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? PPFulfillmentL10n.text("Fulfillment_Filter_Selected") : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("fulfillment.stage.\(stage.rawValue)")
    }

    private var stageColor: Color {
        switch stage {
        case .intake: return PPFulfillmentTokens.primary
        case .preparation: return PPFulfillmentTokens.warning
        case .handoff: return PPFulfillmentTokens.info
        case .settlement: return PPFulfillmentTokens.gold
        case .outcome: return PPFulfillmentTokens.success
        }
    }
}

private struct PPFulfillmentCommandRow: View {
    let record: PPFulfillmentSnapshot
    let customerName: String
    let ownerName: String
    let hasChanged: Bool
    let differentiateWithoutColor: Bool
    let reduceMotion: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) {
            commandHeader

            commandRoute
            .font(PPFulfillmentTokens.beiruti(.regular, size: 14, relativeTo: .subheadline))
            .foregroundStyle(PPFulfillmentTokens.secondaryInk)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) { metadata }
                } else {
                    HStack(spacing: PPFulfillmentTokens.spaceBase) { metadata }
                }
            }
            .font(PPFulfillmentTokens.beiruti(.regular, size: 13, relativeTo: .caption))
            .foregroundStyle(PPFulfillmentTokens.secondaryInk)

            if hasChanged {
                Label(PPFulfillmentL10n.text("Fulfillment_StatusChanged"), systemImage: "sparkles")
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 12, relativeTo: .caption))
                    .foregroundStyle(record.tone.color)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, PPFulfillmentTokens.spaceBase)
        .padding(.vertical, PPFulfillmentTokens.spaceMD)
        .background(hasChanged ? record.tone.color.opacity(0.045) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(record.tone.color)
                .frame(width: differentiateWithoutColor ? 5 : 3)
                .padding(.vertical, PPFulfillmentTokens.spaceMD)
                .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.38, dampingFraction: 0.86), value: hasChanged)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(PPFulfillmentL10n.text("Fulfillment_OpenDetails_Hint"))
    }

    @ViewBuilder
    private var commandHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceMD) {
                commandIdentity
                commandStatus
            }
        } else {
            HStack(alignment: .top, spacing: PPFulfillmentTokens.spaceMD) {
                commandIdentity
                Spacer(minLength: PPFulfillmentTokens.spaceSM)
                VStack(alignment: .trailing, spacing: 5) {
                    commandStatus
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PPFulfillmentTokens.tertiaryInk)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var commandIdentity: some View {
        HStack(alignment: .top, spacing: PPFulfillmentTokens.spaceMD) {
            Image(systemName: record.stage.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(record.tone.color)
                .frame(width: 44, height: 44)
                .background(record.tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(record.tone.color.opacity(differentiateWithoutColor ? 0.75 : 0.24), lineWidth: differentiateWithoutColor ? 2 : 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayOrder)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                    .environment(\.layoutDirection, .leftToRight)
                Text(customerName)
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 18, relativeTo: .headline))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var commandStatus: some View {
        Label(PPFulfillmentL10n.status(record.status), systemImage: record.tone.symbol)
            .font(PPFulfillmentTokens.beiruti(.bold, size: 13, relativeTo: .caption))
            .foregroundStyle(record.tone.color)
            .multilineTextAlignment(.trailing)
    }

    @ViewBuilder
    private var commandRoute: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) {
                Text(customerName)
                Image(systemName: "arrow.down")
                    .foregroundStyle(PPFulfillmentTokens.primary)
                    .accessibilityHidden(true)
                Text(ownerName)
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
            }
        } else {
            HStack(alignment: .center, spacing: PPFulfillmentTokens.spaceSM) {
                Text(customerName).lineLimit(1)
                Image(systemName: "arrow.forward")
                    .foregroundStyle(PPFulfillmentTokens.primary)
                    .accessibilityHidden(true)
                Text(ownerName)
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
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
                    .fill(PPFulfillmentTokens.primarySoft)
                    .frame(width: 72, height: 72)
                if isLoading {
                    ProgressView().tint(PPFulfillmentTokens.primary)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(PPFulfillmentTokens.primary)
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
                    .background(PPFulfillmentTokens.primary, in: Capsule())
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
            ZStack {
                PPFulfillmentTokens.canvas.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceXL) {
                        PPFulfillmentSectionHeading(
                            title: PPFulfillmentL10n.text("Fulfillment_Filters_Command_Title"),
                            detail: PPFulfillmentL10n.text("Fulfillment_Filters_Command_Subtitle"),
                            symbol: "line.3.horizontal.decrease"
                        )

                        filterSection(titleKey: "Fulfillment_Filter_Scope") {
                            ForEach(PPFulfillmentStatusGroup.allCases) { group in
                                optionRow(
                                    title: PPFulfillmentL10n.text(group.titleKey),
                                    symbol: scopeSymbol(group),
                                    selected: viewModel.statusGroup == group && viewModel.exactStatus.isEmpty && viewModel.stageFilter == nil
                                ) {
                                    viewModel.statusGroup = group
                                    viewModel.exactStatus = ""
                                    viewModel.stageFilter = nil
                                }
                            }
                        }

                        filterSection(titleKey: "Fulfillment_Filter_Stage") {
                            ForEach(PPFulfillmentStage.allCases) { stage in
                                optionRow(
                                    title: PPFulfillmentL10n.text(stage.titleKey),
                                    symbol: stage.symbol,
                                    selected: viewModel.stageFilter == stage
                                ) {
                                    viewModel.stageFilter = stage
                                    viewModel.statusGroup = .all
                                    viewModel.exactStatus = ""
                                }
                            }
                        }

                        filterSection(titleKey: "Fulfillment_Filter_AllOwnerTypes") {
                            ForEach(PPFulfillmentOwnerFilter.allCases) { owner in
                                optionRow(
                                    title: PPFulfillmentL10n.text(owner.titleKey),
                                    symbol: owner == .partner ? "person.2.fill" : (owner == .platform ? "pawprint.fill" : "square.grid.2x2"),
                                    selected: viewModel.ownerFilter == owner
                                ) {
                                    viewModel.ownerFilter = owner
                                }
                            }
                        }

                        if !viewModel.availableStatuses.isEmpty {
                            filterSection(titleKey: "Fulfillment_Filter_ExactStatus") {
                                optionRow(
                                    title: PPFulfillmentL10n.text("Fulfillment_Filter_AllStatuses"),
                                    symbol: "circle.grid.2x2",
                                    selected: viewModel.exactStatus.isEmpty
                                ) {
                                    viewModel.exactStatus = ""
                                }
                                ForEach(viewModel.availableStatuses, id: \.self) { status in
                                    optionRow(
                                        title: PPFulfillmentL10n.status(status),
                                        symbol: PPFulfillmentSnapshot.tone(for: status).symbol,
                                        selected: viewModel.exactStatus == status
                                    ) {
                                        viewModel.exactStatus = status
                                        viewModel.statusGroup = .all
                                        viewModel.stageFilter = nil
                                    }
                                }
                            }
                        }

                        Button(role: .destructive, action: viewModel.clearFilters) {
                            Label(PPFulfillmentL10n.text("Fulfillment_Filter_Clear"), systemImage: "line.3.horizontal.decrease.circle")
                                .font(PPFulfillmentTokens.beiruti(.bold, size: 16, relativeTo: .body))
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.bordered)
                        .tint(PPFulfillmentTokens.danger)
                    }
                    .padding(.horizontal, PPFulfillmentTokens.screenMargin)
                    .padding(.top, PPFulfillmentTokens.spaceBase)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle(PPFulfillmentL10n.text("Fulfillment_Filters_Title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(PPFulfillmentL10n.text("Done")) { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func filterSection<Content: View>(titleKey: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) {
            Text(PPFulfillmentL10n.text(titleKey))
                .font(PPFulfillmentTokens.beiruti(.bold, size: 15, relativeTo: .subheadline))
                .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }
                .background(PPFulfillmentTokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous).stroke(PPFulfillmentTokens.border))
        }
    }

    private func optionRow(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: PPFulfillmentTokens.spaceMD) {
                Image(systemName: symbol)
                    .foregroundStyle(selected ? PPFulfillmentTokens.primary : PPFulfillmentTokens.secondaryInk)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text(title)
                    .font(PPFulfillmentTokens.beiruti(selected ? .bold : .regular, size: 16, relativeTo: .body))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? PPFulfillmentTokens.primary : PPFulfillmentTokens.border)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PPFulfillmentTokens.spaceBase)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(PPFulfillmentTokens.border.opacity(0.72))
                .accessibilityHidden(true)
        }
        .accessibilityValue(selected ? PPFulfillmentL10n.text("Fulfillment_Filter_Selected") : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func scopeSymbol(_ group: PPFulfillmentStatusGroup) -> String {
        switch group {
        case .all: return "square.grid.2x2"
        case .active: return "bolt.fill"
        case .awaiting: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        }
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
    @Published var notifyCustomer = false
    @Published var showsOverride = false
    @Published var alert: PPFulfillmentAlert?
    @Published var overrideAlert: PPFulfillmentAlert?
    @Published private(set) var overridePhase: PPFulfillmentOverridePhase?

    private let service: PPFulfillmentService
    private var recordListener: PPFulfillmentListenerToken?
    private var eventsListener: PPFulfillmentListenerToken?
    private var commandListener: PPFulfillmentListenerToken?
    private var recordLoadError: String?
    private var eventsLoadError: String?
    private var pendingPostDismissAlert: PPFulfillmentAlert?
    private var pendingOverride: PPFulfillmentPendingOverride?
    private var notificationTracking: PPFulfillmentPendingOverride?
    private var overrideCommandID = ""
    private var overrideExpectedStatus = ""
    private var overrideConfirmationTask: Task<Void, Never>?
    private var listenerGeneration = 0

    init(seed: PPFulfillmentSnapshot, service: PPFulfillmentService) {
        record = seed
        self.service = service
    }

    deinit {
        overrideConfirmationTask?.cancel()
        recordListener?.remove()
        eventsListener?.remove()
        commandListener?.remove()
    }

    var customerName: String {
        userNames[record.customerID]
            ?? (!record.customerName.isEmpty ? record.customerName : PPFulfillmentL10n.text("Fulfillment_UnknownCustomer"))
    }

    var ownerName: String {
        if record.isPlatformOwned { return PPFulfillmentL10n.text("Fulfillment_Filter_Platform") }
        return userNames[record.ownerID]
            ?? (!record.ownerID.isEmpty ? record.ownerID : PPFulfillmentL10n.text("Fulfillment_UnknownOwner"))
    }

    var allowedOverrideTargets: [String] {
        PPFulfillmentService.allowedOverrideTargets(forStatus: record.status)
    }

    var canAdminOverride: Bool { service.canAdminOverride() }

    var canSubmitOverride: Bool {
        canAdminOverride
            && !isSubmitting
            && pendingOverride == nil
            && !overrideExpectedStatus.isEmpty
            && !overrideTarget.isEmpty
            && !overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isAwaitingOverrideConfirmation: Bool { pendingOverride != nil }

    func load() {
        isLoading = true
        recordLoadError = nil
        eventsLoadError = nil
        updateLoadError()
        recordListener?.remove()
        eventsListener?.remove()
        listenerGeneration += 1
        let generation = listenerGeneration

        let recordRegistration = service.observeFulfillment(record.id) { [weak self] record, isFromCache, hasPendingWrites, error in
            let snapshot = record.map(PPFulfillmentSnapshot.init(record:))
            DispatchQueue.main.async {
                guard let self, generation == self.listenerGeneration else { return }
                self.isLoading = false
                if let error {
                    self.recordLoadError = Self.localizedMessage(for: error)
                } else {
                    self.recordLoadError = nil
                    if let snapshot {
                        self.record = snapshot
                        self.resolveNames()
                        self.confirmPendingOverrideIfObserved(snapshot, isFromCache: isFromCache, hasPendingWrites: hasPendingWrites)
                    }
                }
                self.updateLoadError()
            }
        }
        recordListener = PPFulfillmentListenerToken(recordRegistration)

        let eventsRegistration = service.observeFulfillmentEvents(record.id) { [weak self] events, error in
            let decodedEvents = Self.decode(events: events)
            DispatchQueue.main.async {
                guard let self, generation == self.listenerGeneration else { return }
                if let error {
                    self.eventsLoadError = Self.localizedMessage(for: error)
                } else {
                    self.eventsLoadError = nil
                    self.events = decodedEvents
                }
                self.updateLoadError()
            }
        }
        eventsListener = PPFulfillmentListenerToken(eventsRegistration)
    }

    func stop() {
        listenerGeneration += 1
        clearPendingOverride()
        recordListener?.remove()
        recordListener = nil
        eventsListener?.remove()
        eventsListener = nil
        commandListener?.remove()
        commandListener = nil
    }

    func prepareOverride() {
        guard !isAwaitingOverrideConfirmation else { return }
        guard canAdminOverride else {
            alert = PPFulfillmentAlert(
                title: PPFulfillmentL10n.text("Fulfillment_AdminOverride"),
                message: PPFulfillmentL10n.text("Fulfillment_OverridePermissionDenied")
            )
            return
        }
        guard !allowedOverrideTargets.isEmpty else {
            alert = PPFulfillmentAlert(
                title: PPFulfillmentL10n.text("Fulfillment_AdminOverride"),
                message: PPFulfillmentL10n.text("Fulfillment_NoOverrideTargets")
            )
            return
        }
        overrideTarget = ""
        overrideReason = ""
        overrideNote = ""
        notifyCustomer = false
        overrideCommandID = UUID().uuidString
        overrideExpectedStatus = record.status
        overridePhase = nil
        showsOverride = true
    }

    func selectOverrideTarget(_ status: String) {
        guard canEditOverrideDraft, overrideTarget != status else { return }
        overrideTarget = status
        regenerateOverrideCommandID()
    }

    func updateOverrideReason(_ value: String) {
        guard canEditOverrideDraft, overrideReason != value else { return }
        overrideReason = value
        regenerateOverrideCommandID()
    }

    func updateOverrideNote(_ value: String) {
        guard canEditOverrideDraft, overrideNote != value else { return }
        overrideNote = value
        regenerateOverrideCommandID()
    }

    func updateNotifyCustomer(_ value: Bool) {
        guard canEditOverrideDraft, notifyCustomer != value else { return }
        notifyCustomer = value
        regenerateOverrideCommandID()
    }

    func submitOverride() {
        let target = overrideTarget
        let retryingCommand = overridePhase == .stale || overridePhase == .conflict
        let expectedStatus = retryingCommand ? record.status : overrideExpectedStatus
        let reason = overrideReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = overrideNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldNotify = notifyCustomer
        guard canSubmitOverride else {
            overrideAlert = PPFulfillmentAlert(
                title: PPFulfillmentL10n.text("Error_Title"),
                message: PPFulfillmentL10n.text("Fulfillment_Reason")
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let commandID = retryingCommand ? UUID().uuidString : (overrideCommandID.isEmpty ? UUID().uuidString : overrideCommandID)
        if retryingCommand {
            overrideExpectedStatus = expectedStatus
            overrideCommandID = commandID
        }
        overrideCommandID = commandID
        pendingOverride = PPFulfillmentPendingOverride(
            targetStatus: target,
            commandID: commandID,
            commandDocumentID: "",
            notificationRequested: shouldNotify,
            notificationAttempted: false,
            notificationSucceeded: false,
            notificationStatus: nil,
            notificationOutcomeKnown: false
        )
        isSubmitting = true
        overridePhase = .pending
        scheduleOverrideConfirmationTimeout(for: commandID)
        service.adminOverride(
            record.id,
            expectedStatus: expectedStatus,
            targetStatus: target,
            reason: reason,
            note: note,
            notify: shouldNotify,
            commandID: commandID
        ) { [weak self] result, error in
            let skipped = (result?["skipped"] as? NSNumber)?.boolValue == true
            let accepted = (result?["ok"] as? NSNumber)?.boolValue == true
            let returnedTarget = result?["toStatus"] as? String ?? ""
            let responseCommandID = result?["commandId"] as? String ?? ""
            let eventID = result?["eventId"] as? String ?? ""
            let commandDocumentID = result?["commandDocID"] as? String ?? ""
            let notificationAttempted = (result?["notificationAttempted"] as? NSNumber)?.boolValue == true
            let notificationSucceeded = (result?["notificationSucceeded"] as? NSNumber)?.boolValue == true
            let notificationStatus = result?["notificationStatus"] as? String
            let notificationOutcomeKnown = Self.notificationOutcomeIsKnown(notificationStatus)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false
                guard self.pendingOverride?.commandID == commandID else { return }
                if let error {
                    let phase = Self.phase(for: error)
                    if phase == .error {
                        // A transport failure may happen after Firestore commits.
                        // Keep the caller's stable command alive for listener
                        // reconciliation or an idempotent retry.
                        self.overridePhase = .pending
                        self.scheduleOverrideConfirmationTimeout(for: commandID)
                    } else {
                        self.clearPendingOverride()
                        self.overridePhase = phase
                        self.overrideAlert = PPFulfillmentAlert(title: PPFulfillmentL10n.text("Error_Title"), message: Self.localizedOverrideMessage(for: error))
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                    return
                }
                guard accepted, returnedTarget == target, responseCommandID == commandID else {
                    self.overridePhase = .pending
                    self.scheduleOverrideConfirmationTimeout(for: commandID)
                    return
                }
                if skipped {
                    self.clearPendingOverride()
                    self.overrideCommandID = ""
                    self.overridePhase = .alreadyCurrent
                    self.pendingPostDismissAlert = PPFulfillmentAlert(
                        title: PPFulfillmentL10n.text("Success"),
                        message: Self.successMessage(
                            skipped: true,
                            notificationRequested: shouldNotify,
                            notificationAttempted: notificationAttempted,
                            notificationSucceeded: notificationSucceeded,
                            notificationStatus: notificationStatus
                        )
                    )
                    self.showsOverride = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    return
                }
                guard !eventID.isEmpty else {
                    self.overridePhase = .pending
                    self.scheduleOverrideConfirmationTimeout(for: commandID)
                    return
                }
                self.pendingOverride = PPFulfillmentPendingOverride(
                    targetStatus: returnedTarget,
                    commandID: commandID,
                    commandDocumentID: commandDocumentID,
                    notificationRequested: shouldNotify,
                    notificationAttempted: notificationAttempted,
                    notificationSucceeded: notificationSucceeded,
                    notificationStatus: notificationStatus,
                    notificationOutcomeKnown: notificationOutcomeKnown
                )
                self.observeNotificationOutcome(commandDocumentID: commandDocumentID, commandID: commandID)
                self.overridePhase = .acceptedWaitingSync
                self.scheduleOverrideConfirmationTimeout(for: commandID)
            }
        }
    }

    func presentPendingPostDismissAlert() {
        guard let pendingPostDismissAlert else { return }
        self.pendingPostDismissAlert = nil
        alert = pendingPostDismissAlert
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

    private func updateLoadError() {
        loadError = recordLoadError ?? eventsLoadError
    }

    private func observeNotificationOutcome(commandDocumentID: String, commandID: String) {
        guard !commandDocumentID.isEmpty else { return }
        commandListener?.remove()
        commandListener = PPFulfillmentListenerToken(
            service.observeAdminOverrideCommand(record.id, commandDocumentID: commandDocumentID) { [weak self] command, isFromCache, hasPendingWrites, _ in
                guard let command, !isFromCache, !hasPendingWrites else { return }
                let notification = command["notification"] as? [AnyHashable: Any] ?? [:]
                let status = notification["status"] as? String
                let attempted = (notification["attempted"] as? NSNumber)?.boolValue ?? (notification["attempted"] as? Bool ?? false)
                let succeeded = (notification["succeeded"] as? NSNumber)?.boolValue ?? (notification["succeeded"] as? Bool ?? false)
                DispatchQueue.main.async {
                    guard let self, let current = self.pendingOverride ?? self.notificationTracking, current.commandID == commandID else { return }
                    let known = Self.notificationOutcomeIsKnown(status)
                    let updated = PPFulfillmentPendingOverride(
                        targetStatus: current.targetStatus,
                        commandID: current.commandID,
                        commandDocumentID: current.commandDocumentID,
                        notificationRequested: current.notificationRequested,
                        notificationAttempted: attempted,
                        notificationSucceeded: succeeded,
                        notificationStatus: status,
                        notificationOutcomeKnown: known
                    )
                    let isTracking = self.pendingOverride == nil
                    if isTracking {
                        self.notificationTracking = known ? nil : updated
                        if known {
                            self.pendingPostDismissAlert = PPFulfillmentAlert(
                                title: PPFulfillmentL10n.text("Success"),
                                message: Self.successMessage(
                                    skipped: false,
                                    notificationRequested: updated.notificationRequested,
                                    notificationAttempted: updated.notificationAttempted,
                                    notificationSucceeded: updated.notificationSucceeded,
                                    notificationStatus: updated.notificationStatus
                                )
                            )
                        }
                    } else {
                        self.pendingOverride = updated
                    }
                    if known {
                        self.commandListener?.remove()
                        self.commandListener = nil
                    }
                }
            }
        )
    }

    private func confirmPendingOverrideIfObserved(_ snapshot: PPFulfillmentSnapshot, isFromCache: Bool, hasPendingWrites: Bool) {
        guard let pendingOverride, !isFromCache, !hasPendingWrites else { return }
        guard snapshot.status == pendingOverride.targetStatus else { return }
        guard snapshot.adminOverrideCommandID == pendingOverride.commandID else { return }
        overrideConfirmationTask?.cancel()
        overrideConfirmationTask = nil
        isSubmitting = false
        let trackNotificationOutcome = !pendingOverride.notificationOutcomeKnown && !pendingOverride.commandDocumentID.isEmpty
        if trackNotificationOutcome {
            notificationTracking = pendingOverride
        } else {
            commandListener?.remove()
            commandListener = nil
        }
        self.pendingOverride = nil
        overrideCommandID = ""
        overridePhase = .confirmed
        pendingPostDismissAlert = PPFulfillmentAlert(
            title: PPFulfillmentL10n.text("Success"),
            message: Self.successMessage(
                skipped: false,
                notificationRequested: pendingOverride.notificationRequested,
                notificationAttempted: pendingOverride.notificationAttempted,
                notificationSucceeded: pendingOverride.notificationSucceeded,
                notificationStatus: pendingOverride.notificationOutcomeKnown
                    ? pendingOverride.notificationStatus
                    : "retry_pending"
            )
        )
        showsOverride = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private var canEditOverrideDraft: Bool {
        !isSubmitting && pendingOverride == nil
    }

    private func regenerateOverrideCommandID() {
        if overridePhase == .stale || overridePhase == .conflict {
            overrideExpectedStatus = record.status
        }
        overrideCommandID = UUID().uuidString
    }

    private func clearPendingOverride() {
        overrideConfirmationTask?.cancel()
        overrideConfirmationTask = nil
        commandListener?.remove()
        commandListener = nil
        isSubmitting = false
        pendingOverride = nil
        notificationTracking = nil
    }

    private func scheduleOverrideConfirmationTimeout(for commandID: String) {
        overrideConfirmationTask?.cancel()
        overrideConfirmationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, self.pendingOverride?.commandID == commandID else { return }
            self.isSubmitting = false
            self.clearPendingOverride()
            self.overridePhase = .stale
        }
    }

    private static func localizedMessage(for error: Error) -> String {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileNoSuchFileError {
            return PPFulfillmentL10n.text("Fulfillment_Detail_NotFound")
        }
        return error.localizedDescription
    }

    private static func phase(for error: Error) -> PPFulfillmentOverridePhase {
        let error = error as NSError
        if error.domain == "com.firebase.functions" {
            switch error.code {
            case FunctionsErrorCode.permissionDenied.rawValue, FunctionsErrorCode.unauthenticated.rawValue, 7, 16:
                return .denied
            case FunctionsErrorCode.failedPrecondition.rawValue, FunctionsErrorCode.aborted.rawValue, FunctionsErrorCode.alreadyExists.rawValue, 9, 10, 6:
                return .conflict
            case FunctionsErrorCode.invalidArgument.rawValue, FunctionsErrorCode.notFound.rawValue, 3, 5:
                return .invalid
            default:
                break
            }
        }
        return .error
    }

    private static func localizedOverrideMessage(for error: Error) -> String {
        switch phase(for: error) {
        case .denied:
            return PPFulfillmentL10n.text("Fulfillment_OverridePermissionDenied")
        case .conflict:
            return PPFulfillmentL10n.text("Fulfillment_OverrideConflict")
        case .invalid:
            return PPFulfillmentL10n.text("Fulfillment_OverrideInvalid")
        default:
            return PPFulfillmentL10n.text("Fulfillment_OverrideFailed")
        }
    }

    private static func notificationOutcomeIsKnown(_ status: String?) -> Bool {
        guard let status else { return false }
        return !["pending", "retry_pending", "dispatching", "failed", "error"].contains(status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func successMessage(
        skipped: Bool,
        notificationRequested: Bool,
        notificationAttempted: Bool,
        notificationSucceeded: Bool,
        notificationStatus: String?
    ) -> String {
        if skipped { return PPFulfillmentL10n.text("Fulfillment_OverrideSkipped") }
        let normalizedNotificationStatus = notificationStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if notificationRequested, ["pending", "retry_pending", "dispatching", "failed", "error"].contains(normalizedNotificationStatus) {
            return PPFulfillmentL10n.text("Fulfillment_OverrideSuccessNotificationPending")
        }
        if notificationRequested, notificationSucceeded {
            return PPFulfillmentL10n.text("Fulfillment_OverrideSuccessNotified")
        }
        if notificationRequested, notificationAttempted {
            return PPFulfillmentL10n.text("Fulfillment_OverrideSuccessNotificationFailed")
        }
        if notificationRequested {
            return PPFulfillmentL10n.text("Fulfillment_OverrideSuccessNotificationNotSent")
        }
        return PPFulfillmentL10n.text("Fulfillment_OverrideSuccess")
    }
}

// MARK: - Detail screen

private struct PPFulfillmentDetailScreen: View {
    @ObservedObject var viewModel: PPFulfillmentDetailViewModel
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            PPFulfillmentTokens.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                dossierHeaderView

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceXL) {
                        detailCommandHeader
                        if viewModel.isLoading {
                            HStack(spacing: PPFulfillmentTokens.spaceSM) {
                                ProgressView().tint(PPFulfillmentTokens.primary)
                                Text(PPFulfillmentL10n.text("Fulfillment_Detail_Syncing"))
                                    .font(PPFulfillmentTokens.beiruti(.medium, size: 14, relativeTo: .subheadline))
                                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if let error = viewModel.loadError {
                            detailLoadNotice(error)
                        }
                        lifecycleSection
                        overviewSection
                        compositionSection
                        settlementSection
                        if viewModel.record.adminOverrideAt != nil { auditSection }
                        timelineSection
                    }
                    .padding(.horizontal, PPFulfillmentTokens.screenMargin)
                    .padding(.top, PPFulfillmentTokens.spaceBase)
                    .padding(.bottom, viewModel.canAdminOverride && !viewModel.allowedOverrideTargets.isEmpty ? 12 : 40)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.canAdminOverride && !viewModel.allowedOverrideTargets.isEmpty {
                interventionDock
            }
        }
        .sheet(isPresented: $viewModel.showsOverride, onDismiss: viewModel.presentPendingPostDismissAlert) {
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

    // MARK: - Sovereign Navigation Bar

    private var dossierHeaderView: some View {
        AdminSovereignNavigationBar(
            title: viewModel.record.displayOrder,
            subtitle: Language.get("CommandCenter_Fulfillment_Workspace", alter: "مساحة التنفيذ"),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            if viewModel.isLoading {
                ProgressView().tint(PPFulfillmentTokens.primary)
            } else {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.load()
                }) {
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
                .accessibilityLabel(PPFulfillmentL10n.text("Fulfillment_Retry"))
            }
        }
    }

    private var detailCommandHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            detailStatusHeader

            routeReadout

            Divider()

            executionRefFooter
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                AdminSurface.control

                RadialGradient(
                    colors: [
                        effectiveTone.color.opacity(0.14),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 260
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            effectiveTone.color.opacity(0.40),
                            Color(uiColor: .ppSurfaceBorder).opacity(0.50)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        )
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.5, dampingFraction: 0.82), value: viewModel.overridePhase)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fulfillment.detail.command")
    }

    @ViewBuilder
    private var detailStatusHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                effectiveTone.color.opacity(0.24),
                                effectiveTone.color.opacity(0.10)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 25
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(effectiveTone.color.opacity(0.35), lineWidth: 0.75)
                    )

                Image(systemName: viewModel.record.stage.symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(effectiveTone.color)
            }
            .frame(width: 48, height: 48)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(PPFulfillmentL10n.text("Fulfillment_Detail_Command_Title"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .textCase(.uppercase)

                Text(viewModel.record.displayOrder)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            effectiveStatusBadge
        }
    }

    private var effectiveStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(effectiveTone.color)
                .frame(width: 7, height: 7)
                .shadow(color: effectiveTone.color.opacity(0.6), radius: 2, x: 0, y: 0)
            Text(effectiveStatus.isEmpty ? PPFulfillmentL10n.text("Fulfillment_Status_NewRequest") : PPFulfillmentL10n.status(effectiveStatus))
                .font(AdminType.captionBold)
                .foregroundStyle(effectiveTone.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(effectiveTone.softFill, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(effectiveTone.color.opacity(0.30), lineWidth: 0.75)
        )
        .id(effectiveStatus)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
    }

    private var routeReadout: some View {
        HStack(spacing: 10) {
            // Customer Plate
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.primary.opacity(0.12))
                    Image(systemName: "person.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("Fulfillment_DetailCustomer", alter: "العميل"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                    Text(viewModel.customerName)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Vector Connector
            ZStack {
                Circle()
                    .fill(Color(uiColor: .ppSurfaceBorder).opacity(0.30))
                    .frame(width: 24, height: 24)
                Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
            }

            // Merchant / Provider Plate
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .ppPremiumAccent).opacity(0.15))
                    Image(systemName: viewModel.record.isPlatformOwned ? "pawprint.fill" : "person.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(uiColor: .ppPremiumAccent))
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("Fulfillment_DetailOwner", alter: "الجهة المنفذة"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                    Text(viewModel.ownerName)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .ppSurfaceBorder).opacity(0.18))
        )
    }

    private var executionRefFooter: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PPFulfillmentL10n.text("Fulfillment_Ref"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                Text(viewModel.record.id)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                UIPasteboard.general.string = viewModel.record.id
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(Language.get("Copy", alter: "نسخ"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(AdminSurface.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AdminSurface.primary.opacity(0.12), in: Capsule(style: .continuous))
            }
            .buttonStyle(CommandPressStyle())
        }
    }

    private var lifecycleSection: some View {
        detailSection(
            titleKey: "Fulfillment_Workflow_Title",
            detailKey: "Fulfillment_Detail_Workflow_Subtitle",
            symbol: "point.3.connected.trianglepath.dotted"
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PPFulfillmentStage.allCases) { stage in
                        PPFulfillmentDetailStageNode(
                            stage: stage,
                            isReached: isReached(stage),
                            isCurrent: viewModel.record.stage == stage,
                            currentColor: effectiveTone.color
                        )
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
    }

    private func isReached(_ stage: PPFulfillmentStage) -> Bool {
        if viewModel.record.stage == stage { return true }
        return viewModel.events.contains { event in
            stage.contains(event.fromStatus) || stage.contains(event.toStatus)
        }
    }

    private func detailLoadNotice(_ error: String) -> some View {
        HStack(alignment: .top, spacing: PPFulfillmentTokens.spaceMD) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PPFulfillmentTokens.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(PPFulfillmentL10n.text("Fulfillment_Detail_Retained_Title"))
                    .font(AdminType.headline)
                    .foregroundStyle(PPFulfillmentTokens.ink)
                Text(error)
                    .font(AdminType.callout)
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
            }
            Spacer(minLength: 0)
            Button(PPFulfillmentL10n.text("Fulfillment_Retry"), action: viewModel.load)
                .font(AdminType.captionBold)
        }
        .padding(14)
        .background(PPFulfillmentTokens.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PPFulfillmentTokens.warning.opacity(0.32)))
        .accessibilityElement(children: .contain)
    }

    private var interventionDock: some View {
        VStack(spacing: 0) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.prepareOverride()
            }) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 32, height: 32)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text(PPFulfillmentL10n.text("Fulfillment_OverrideAction"))
                        .font(AdminType.headline)
                        .foregroundStyle(.white)

                    Spacer(minLength: 0)

                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.88, green: 0.22, blue: 0.25),
                                    Color(red: 0.74, green: 0.15, blue: 0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.88, green: 0.22, blue: 0.25).opacity(0.38), radius: 10, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
                )
            }
            .buttonStyle(CommandPressStyle())
            .disabled(viewModel.isAwaitingOverrideConfirmation)
            .accessibilityHint(PPFulfillmentL10n.text("Fulfillment_Override_AuditNotice"))
            .accessibilityIdentifier("fulfillment.override.dock")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            AdminSurface.control
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: -4)
        )
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var effectiveStatus: String {
        viewModel.record.status
    }

    private var effectiveTone: PPFulfillmentTone {
        PPFulfillmentSnapshot.tone(for: effectiveStatus)
    }

    private var overviewSection: some View {
        detailSection(
            titleKey: "Fulfillment_DetailOverview",
            detailKey: "Fulfillment_DetailOverview_Subtitle",
            symbol: "square.grid.2x2.fill"
        ) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                telemetryTile(
                    titleKey: "Fulfillment_DetailOrder",
                    value: viewModel.record.displayOrder,
                    symbol: "shippingbox.fill",
                    isMonospace: true
                )
                telemetryTile(
                    titleKey: "Fulfillment_Ref",
                    value: viewModel.record.id,
                    symbol: "barcode",
                    isMonospace: true
                )
                telemetryTile(
                    titleKey: "Fulfillment_DetailCreated",
                    value: PPFulfillmentL10n.date(viewModel.record.createdAt),
                    symbol: "calendar.badge.clock",
                    isMonospace: false
                )
                telemetryTile(
                    titleKey: "Fulfillment_DetailUpdated",
                    value: PPFulfillmentL10n.date(viewModel.record.updatedAt),
                    symbol: "clock.arrow.circlepath",
                    isMonospace: false
                )
            }
        }
    }

    private func telemetryTile(titleKey: String, value: String, symbol: String, isMonospace: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(PPFulfillmentL10n.text(titleKey))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(isMonospace ? .system(size: 13, weight: .bold, design: .monospaced) : AdminType.calloutBold)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .environment(\.layoutDirection, isMonospace ? .leftToRight : PPFulfillmentL10n.layoutDirection)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.50), lineWidth: 0.75)
        )
    }

    private var compositionSection: some View {
        detailSection(
            titleKey: "Fulfillment_DetailItems",
            detailKey: "Fulfillment_DetailItems_Subtitle",
            symbol: "shippingbox.fill"
        ) {
            if viewModel.record.items.isEmpty {
                Text(PPFulfillmentL10n.text("Fulfillment_NoItems"))
                    .font(AdminType.callout)
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(viewModel.record.items.enumerated()), id: \.element.id) { index, item in
                        PPFulfillmentItemRow(index: index + 1, item: item, currency: viewModel.record.currency)
                    }
                }
            }
        }
    }

    private var settlementSection: some View {
        detailSection(
            titleKey: "Fulfillment_DetailSettlement",
            detailKey: "Fulfillment_DetailSettlement_Subtitle",
            symbol: "banknote.fill"
        ) {
            VStack(spacing: 12) {
                settlementRow(titleKey: "Fulfillment_Subtotal", amount: viewModel.record.subtotal, emphasized: false)
                settlementRow(titleKey: "Fulfillment_PlatformCommission", amount: viewModel.record.platformCommission, emphasized: false)
                Divider()
                settlementRow(titleKey: "Fulfillment_ProviderNet", amount: viewModel.record.providerNet, emphasized: true)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AdminSurface.control)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.50), lineWidth: 0.75)
            )
        }
    }

    private var auditSection: some View {
        detailSection(
            titleKey: "Fulfillment_AdminOverride",
            detailKey: "Fulfillment_DetailAudit_Subtitle",
            symbol: "checkmark.shield.fill"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Label(PPFulfillmentL10n.date(viewModel.record.adminOverrideAt), systemImage: "calendar.badge.exclamationmark")
                    .font(AdminType.calloutBold)
                    .foregroundStyle(Color(uiColor: .ppWarning))

                if !viewModel.record.adminOverrideBy.isEmpty {
                    Label(viewModel.record.adminOverrideBy, systemImage: "person.fill")
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .environment(\.layoutDirection, .leftToRight)
                }

                if !viewModel.record.adminOverrideReason.isEmpty {
                    Text(viewModel.record.adminOverrideReason)
                        .font(AdminType.callout)
                        .foregroundStyle(AdminSurface.primaryText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .ppWarning).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppWarning).opacity(0.35), lineWidth: 0.75)
            )
        }
    }

    private var timelineSection: some View {
        detailSection(
            titleKey: "Fulfillment_DetailTimeline",
            detailKey: "Fulfillment_DetailTimeline_Subtitle",
            symbol: "point.3.connected.trianglepath.dotted"
        ) {
            if viewModel.events.isEmpty {
                Text(PPFulfillmentL10n.text("Fulfillment_NoEvents"))
                    .font(AdminType.callout)
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.events.enumerated()), id: \.element.id) { index, event in
                        PPFulfillmentTimelineRow(event: event, isLast: index == viewModel.events.count - 1)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AdminSurface.control)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.50), lineWidth: 0.75)
                )
            }
        }
    }

    private func detailSection<Content: View>(
        titleKey: String,
        detailKey: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: PPFulfillmentL10n.text(titleKey),
                detail: PPFulfillmentL10n.text(detailKey)
            )
            content()
        }
    }

    private func settlementRow(titleKey: String, amount: Double, emphasized: Bool) -> some View {
        HStack {
            Text(PPFulfillmentL10n.text(titleKey))
                .font(emphasized ? AdminType.headline : AdminType.callout)
                .foregroundStyle(emphasized ? AdminSurface.primaryText : AdminCommandInk.secondary)
            Spacer()
            Text(PPFulfillmentL10n.money(amount, currency: viewModel.record.currency))
                .font(emphasized ? .system(size: 18, weight: .bold, design: .rounded) : AdminType.calloutBold)
                .foregroundStyle(emphasized ? Color(red: 0.05, green: 0.65, blue: 0.45) : AdminSurface.primaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PPFulfillmentDetailStageNode: View {
    let stage: PPFulfillmentStage
    let isReached: Bool
    let isCurrent: Bool
    let currentColor: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.15))
                    Image(systemName: stage.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 32, height: 32)

                Spacer(minLength: 6)

                if isCurrent {
                    Circle()
                        .fill(currentColor)
                        .frame(width: 9, height: 9)
                        .shadow(color: currentColor.opacity(0.8), radius: 3, x: 0, y: 0)
                } else if isReached {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.05, green: 0.65, blue: 0.45))
                }
            }

            Text(PPFulfillmentL10n.text(stage.titleKey))
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)

            Text(stateText)
                .font(AdminType.caption2Bold)
                .foregroundStyle(accentColor)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 180 : 132, alignment: .leading)
        .frame(minHeight: 104, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isCurrent ? currentColor.opacity(0.08) : AdminSurface.control)
                .shadow(color: Color.black.opacity(isCurrent ? 0.06 : 0.02), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isCurrent ? currentColor.opacity(0.60) : Color(uiColor: .ppSurfaceBorder).opacity(0.50), lineWidth: isCurrent ? 1.5 : 0.75)
        )
        .opacity(isReached || isCurrent ? 1 : 0.60)
        .accessibilityElement(children: .combine)
        .accessibilityValue(stateText)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var accentColor: Color {
        if isCurrent { return currentColor }
        return isReached ? Color(red: 0.05, green: 0.65, blue: 0.45) : AdminCommandInk.tertiary
    }

    private var stateText: String {
        if isCurrent { return PPFulfillmentL10n.text("Fulfillment_Stage_Current") }
        if isReached { return PPFulfillmentL10n.text("Fulfillment_Stage_Observed") }
        return PPFulfillmentL10n.text("Fulfillment_Stage_NotObserved")
    }
}

private struct PPFulfillmentKeyValue: View {
    let titleKey: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PPFulfillmentL10n.text(titleKey))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
            Text(value)
                .font(monospaced ? .system(size: 14, weight: .bold, design: .monospaced) : AdminType.calloutBold)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.80)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AdminSurface.primary.opacity(0.12))
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(PPFulfillmentL10n.format("Fulfillment_ItemQuantity_Format", "\(item.quantity)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))

                    Text("•")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AdminCommandInk.tertiary)

                    Text(PPFulfillmentL10n.money(item.unitPrice, currency: currency) + " / " + Language.get("Unit", alter: "حبة"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(PPFulfillmentL10n.money(item.unitPrice * Double(item.quantity), currency: currency))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AdminSurface.primaryText)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.45), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        item.name.isEmpty ? PPFulfillmentL10n.text("Fulfillment_Item") : item.name
    }
}

private struct PPFulfillmentTimelineRow: View {
    let event: PPFulfillmentEventSnapshot
    let isLast: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(tone.color)
                        .frame(width: 14, height: 14)
                        .shadow(color: tone.color.opacity(0.5), radius: 3, x: 0, y: 0)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                }

                if !isLast {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    tone.color.opacity(0.40),
                                    Color(uiColor: .ppSurfaceBorder).opacity(0.30)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2)
                        .frame(minHeight: 52, maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(PPFulfillmentL10n.eventAction(event.action))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)

                    Spacer(minLength: 4)

                    Text(PPFulfillmentL10n.date(event.createdAt))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                }

                if !event.fromStatus.isEmpty || !event.toStatus.isEmpty {
                    transitionReadout
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(tone.color)
                }

                actorReadout
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)

                if !event.reason.isEmpty {
                    eventContext(titleKey: "Fulfillment_Event_Reason", value: event.reason)
                }
                if !event.note.isEmpty {
                    eventContext(titleKey: "Fulfillment_Event_Note", value: event.note)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var transitionReadout: some View {
        HStack(spacing: 6) {
            if !event.fromStatus.isEmpty {
                Text(PPFulfillmentL10n.status(event.fromStatus))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tone.softFill, in: Capsule(style: .continuous))
            }
            Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
            if !event.toStatus.isEmpty {
                Text(PPFulfillmentL10n.status(event.toStatus))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tone.color.opacity(0.18), in: Capsule(style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var actorReadout: some View {
        HStack(spacing: 5) {
            if !event.actorType.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 10))
                    Text(PPFulfillmentL10n.actorType(event.actorType))
                }
            }
            if !event.actorType.isEmpty, !event.actor.isEmpty { Text("•") }
            if !event.actor.isEmpty {
                Text(event.actor)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
    }

    private func eventContext(titleKey: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(PPFulfillmentL10n.text(titleKey))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
            Text(value)
                .font(AdminType.callout)
                .foregroundStyle(AdminSurface.primaryText)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .ppSurfaceBorder).opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.top, 2)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case reason
        case note
    }

    var body: some View {
        NavigationView {
            ZStack {
                PPFulfillmentTokens.canvas.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        SectionHeader(
                            title: PPFulfillmentL10n.text("Fulfillment_Intervention_Title"),
                            detail: PPFulfillmentL10n.text("Fulfillment_Intervention_Subtitle")
                        )
                        transitionPanel
                        confirmationNotice
                        rationalePanel
                        communicationPanel
                        auditNotice
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .disabled(viewModel.isSubmitting || viewModel.isAwaitingOverrideConfirmation)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { submitDock }
            .navigationTitle(PPFulfillmentL10n.text("Fulfillment_AdminOverride"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PPFulfillmentL10n.text("Cancel")) { dismiss() }
                        .disabled(viewModel.isSubmitting || viewModel.isAwaitingOverrideConfirmation)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(PPFulfillmentL10n.text("Done")) { focusedField = nil }
                }
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(viewModel.isSubmitting || viewModel.isAwaitingOverrideConfirmation)
        .alert(item: $viewModel.overrideAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(PPFulfillmentL10n.text("OK")))
            )
        }
    }

    private var transitionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Fulfillment_Intervention_Transition")

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) { statusBridge }
                } else {
                    HStack(alignment: .center, spacing: 12) { statusBridge }
                }
            }

            Divider()

            VStack(spacing: 8) {
                ForEach(Array(viewModel.allowedOverrideTargets.enumerated()), id: \.element) { index, status in
                    targetRow(status)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.50), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private var confirmationNotice: some View {
        if let phase = viewModel.overridePhase,
           phase == .pending || phase == .acceptedWaitingSync || phase == .stale {
            let isStale = phase == .stale
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isStale ? "exclamationmark.triangle.fill" : "dot.radiowaves.left.and.right")
                    .foregroundStyle(isStale ? PPFulfillmentTokens.warning : PPFulfillmentTokens.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(PPFulfillmentL10n.text("Fulfillment_ConfirmationPending_Title"))
                        .font(PPFulfillmentTokens.beiruti(.bold, size: 15, relativeTo: .subheadline))
                        .foregroundStyle(PPFulfillmentTokens.ink)
                    Text(PPFulfillmentL10n.text(
                        phase == .acceptedWaitingSync
                            ? "Fulfillment_ConfirmationPending"
                            : "Fulfillment_OverrideReconciliationPending"
                    ))
                    .font(PPFulfillmentTokens.beiruti(.regular, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .padding(PPFulfillmentTokens.spaceBase)
            .background((isStale ? PPFulfillmentTokens.warning : PPFulfillmentTokens.primary).opacity(0.09), in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous).stroke((isStale ? PPFulfillmentTokens.warning : PPFulfillmentTokens.primary).opacity(0.30)))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("fulfillment.override.confirmation")
        }
    }

    @ViewBuilder
    private var statusBridge: some View {
        statusReadout(titleKey: "Fulfillment_CurrentStatus", status: viewModel.record.status)
        Image(systemName: dynamicTypeSize.isAccessibilitySize ? "arrow.down" : "arrow.forward")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(PPFulfillmentTokens.primary)
            .accessibilityHidden(true)
        statusReadout(titleKey: "Fulfillment_TargetStatus", status: viewModel.overrideTarget)
    }

    private func statusReadout(titleKey: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(PPFulfillmentL10n.text(titleKey))
                .font(PPFulfillmentTokens.beiruti(.medium, size: 12, relativeTo: .caption))
                .foregroundStyle(PPFulfillmentTokens.secondaryInk)
            if status.isEmpty {
                Text(PPFulfillmentL10n.text("Fulfillment_Intervention_SelectTarget"))
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(PPFulfillmentTokens.tertiaryInk)
            } else {
                PPFulfillmentStatusBadge(
                    status: status,
                    tone: PPFulfillmentSnapshot.tone(for: status),
                    compact: true
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func targetRow(_ status: String) -> some View {
        let selected = viewModel.overrideTarget == status
        let tone = PPFulfillmentSnapshot.tone(for: status)
        return Button {
            viewModel.selectOverrideTarget(status)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: PPFulfillmentTokens.spaceMD) {
                Image(systemName: tone.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tone.color)
                    .frame(width: 30, height: 30)
                    .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                Text(PPFulfillmentL10n.status(status))
                    .font(PPFulfillmentTokens.beiruti(selected ? .bold : .regular, size: 16, relativeTo: .body))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                Spacer(minLength: PPFulfillmentTokens.spaceSM)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? PPFulfillmentTokens.primary : PPFulfillmentTokens.border)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? PPFulfillmentL10n.text("Fulfillment_Filter_Selected") : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("fulfillment.override.target.\(status)")
    }

    private var rationalePanel: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceMD) {
            sectionLabel("Fulfillment_Intervention_Rationale")

            VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) {
                Text(PPFulfillmentL10n.text("Fulfillment_Reason"))
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: overrideReasonBinding)
                        .font(PPFulfillmentTokens.beiruti(.regular, size: 16, relativeTo: .body))
                        .focused($focusedField, equals: .reason)
                        .onChange(of: viewModel.overrideReason) { value in
                            let limited = limitUTF16(value, to: 256)
                            if limited != value { viewModel.updateOverrideReason(limited) }
                        }
                        .padding(7)
                        .frame(minHeight: 88)
                        .accessibilityLabel(PPFulfillmentL10n.text("Fulfillment_Reason"))
                        .accessibilityValue(characterCountAccessibility(viewModel.overrideReason.utf16.count, limit: 256))
                        .accessibilityIdentifier("fulfillment.override.reason")
                    if viewModel.overrideReason.isEmpty {
                        Text(PPFulfillmentL10n.text("Fulfillment_ReasonPlaceholder"))
                            .font(PPFulfillmentTokens.beiruti(.regular, size: 16, relativeTo: .body))
                            .foregroundStyle(PPFulfillmentTokens.tertiaryInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(PPFulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous).stroke(reasonBorderColor))
                characterCount(viewModel.overrideReason.utf16.count, limit: 256)
            }

            VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) {
                Text(PPFulfillmentL10n.text("Fulfillment_Note"))
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: overrideNoteBinding)
                        .font(PPFulfillmentTokens.beiruti(.regular, size: 16, relativeTo: .body))
                        .focused($focusedField, equals: .note)
                        .onChange(of: viewModel.overrideNote) { value in
                            let limited = limitUTF16(value, to: 512)
                            if limited != value { viewModel.updateOverrideNote(limited) }
                        }
                        .padding(7)
                        .frame(minHeight: 108)
                        .accessibilityLabel(PPFulfillmentL10n.text("Fulfillment_Note"))
                        .accessibilityValue(characterCountAccessibility(viewModel.overrideNote.utf16.count, limit: 512))
                        .accessibilityIdentifier("fulfillment.override.note")
                    if viewModel.overrideNote.isEmpty {
                        Text(PPFulfillmentL10n.text("Fulfillment_NotePlaceholder"))
                            .font(PPFulfillmentTokens.beiruti(.regular, size: 16, relativeTo: .body))
                            .foregroundStyle(PPFulfillmentTokens.tertiaryInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(PPFulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous).stroke(PPFulfillmentTokens.border))
                characterCount(viewModel.overrideNote.utf16.count, limit: 512)
            }
        }
    }

    private var communicationPanel: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) {
            sectionLabel("Fulfillment_Intervention_Communication")
            Toggle(isOn: notifyCustomerBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(PPFulfillmentL10n.text("Fulfillment_NotifyCustomer"), systemImage: "bell.badge.fill")
                        .font(PPFulfillmentTokens.beiruti(.bold, size: 16, relativeTo: .body))
                        .foregroundStyle(PPFulfillmentTokens.ink)
                    Text(PPFulfillmentL10n.text("Fulfillment_NotifyCustomer_Subtitle"))
                        .font(PPFulfillmentTokens.beiruti(.regular, size: 13, relativeTo: .caption))
                        .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                }
            }
            .tint(PPFulfillmentTokens.primary)
            .padding(PPFulfillmentTokens.spaceBase)
            .ppFulfillmentCard()
            .accessibilityIdentifier("fulfillment.override.notify")
        }
    }

    private var auditNotice: some View {
        HStack(alignment: .top, spacing: PPFulfillmentTokens.spaceMD) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(PPFulfillmentTokens.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(PPFulfillmentL10n.text("Fulfillment_Intervention_Audit_Title"))
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 15, relativeTo: .subheadline))
                    .foregroundStyle(PPFulfillmentTokens.ink)
                Text(PPFulfillmentL10n.text("Fulfillment_Override_AuditNotice"))
                    .font(PPFulfillmentTokens.beiruti(.regular, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(PPFulfillmentTokens.secondaryInk)
            }
        }
        .padding(PPFulfillmentTokens.spaceBase)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PPFulfillmentTokens.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous).stroke(PPFulfillmentTokens.warning.opacity(0.28)))
        .accessibilityElement(children: .combine)
    }

    private var submitDock: some View {
        Button {
            focusedField = nil
            viewModel.submitOverride()
        } label: {
            HStack(spacing: PPFulfillmentTokens.spaceSM) {
                if viewModel.isSubmitting {
                    ProgressView().tint(Color.white)
                } else {
                    Image(systemName: "checkmark.shield.fill")
                }
                Text(PPFulfillmentL10n.text(viewModel.isSubmitting ? "Fulfillment_Override_Submitting" : "Fulfillment_ConfirmOverride"))
                    .font(PPFulfillmentTokens.beiruti(.bold, size: 16, relativeTo: .body))
            }
            .foregroundStyle(submitForeground)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                submitBackground,
                in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerMedium, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSubmitOverride)
        .padding(.horizontal, PPFulfillmentTokens.screenMargin)
        .padding(.vertical, PPFulfillmentTokens.spaceSM)
        .background(PPFulfillmentTokens.surface)
        .overlay(alignment: .top) { Divider().overlay(PPFulfillmentTokens.border) }
        .accessibilityHint(PPFulfillmentL10n.text("Fulfillment_Override_AuditNotice"))
        .accessibilityIdentifier("fulfillment.override.confirm")
    }

    private var overrideReasonBinding: Binding<String> {
        Binding(get: { viewModel.overrideReason }, set: { viewModel.updateOverrideReason($0) })
    }

    private var overrideNoteBinding: Binding<String> {
        Binding(get: { viewModel.overrideNote }, set: { viewModel.updateOverrideNote($0) })
    }

    private var notifyCustomerBinding: Binding<Bool> {
        Binding(get: { viewModel.notifyCustomer }, set: { viewModel.updateNotifyCustomer($0) })
    }

    private func sectionLabel(_ key: String) -> some View {
        Text(PPFulfillmentL10n.text(key))
            .font(PPFulfillmentTokens.beiruti(.bold, size: 15, relativeTo: .subheadline))
            .foregroundStyle(PPFulfillmentTokens.secondaryInk)
            .accessibilityAddTraits(.isHeader)
    }

    private func characterCount(_ count: Int, limit: Int) -> some View {
        Text(PPFulfillmentL10n.format("Fulfillment_CharacterCount_Format", "\(count)", "\(limit)"))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(PPFulfillmentTokens.tertiaryInk)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel(characterCountAccessibility(count, limit: limit))
    }

    private var reasonBorderColor: Color {
        focusedField == .reason ? PPFulfillmentTokens.primary : PPFulfillmentTokens.border
    }

    private var submitBackground: Color {
        viewModel.canSubmitOverride || viewModel.isSubmitting
            ? PPFulfillmentTokens.danger
            : PPFulfillmentTokens.disabledFill
    }

    private var submitForeground: Color {
        viewModel.canSubmitOverride || viewModel.isSubmitting
            ? Color.white
            : PPFulfillmentTokens.tertiaryInk
    }

    private func limitUTF16(_ value: String, to limit: Int) -> String {
        guard value.utf16.count > limit else { return value }
        var result = value
        while result.utf16.count > limit, !result.isEmpty {
            result.removeLast()
        }
        return result
    }

    private func characterCountAccessibility(_ count: Int, limit: Int) -> String {
        PPFulfillmentL10n.format("Fulfillment_CharacterCount_Accessibility_Format", "\(count)", "\(limit)")
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
        view.backgroundColor = .ppBackground
        view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage()

        let host = UIHostingController(
            rootView: PPFulfillmentOrdersScreen(
                viewModel: viewModel,
                onDismiss: { [weak self] in
                    if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                        nav.popViewController(animated: true)
                    } else {
                        self?.dismiss(animated: true)
                    }
                },
                onOpenRecord: { [weak self] record in
                    let detail = PPFulfillmentDetailViewController(seed: record)
                    self?.navigationController?.pushViewController(detail, animated: true)
                }
            )
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
        view.backgroundColor = .ppBackground
        view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage()

        let host = UIHostingController(
            rootView: PPFulfillmentDetailScreen(
                viewModel: viewModel,
                onDismiss: { [weak self] in
                    if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                        nav.popViewController(animated: true)
                    } else {
                        self?.dismiss(animated: true)
                    }
                }
            )
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
            viewModel.stop()
        }
    }
}
