//
//  FulfillmentListView.swift
//  PurePetsAdmin
//
//  Flagship Fulfillment Orders Command Center.
//  Reimagined from absolute first principles:
//  - Executive Holographic Telemetry Cockpit (SLA urgency, floor prep, fleet dispatch, settled GMV)
//  - Spatial Workflow Pipeline Rail with real-time micro-counters
//  - Category-Defining Hero Order Cards with visual product strips, SLA timers, & zero-latency quick actions
//  - Interactive Order Dossier & Inspection Suite with 5-stage visual stepper, live event stream, customer blueprint, & financial matrix
//  - Privileged Admin Override Modal with mandatory audit reasons, notes, & customer notification controls
//  - Multi-dimensional Omni-search and scope filters
//

import SwiftUI
import UIKit
import FirebaseFirestore

// MARK: - Sendable Conformance

extension PPFulfillmentRecord: @unchecked Sendable {}

// MARK: - Design Tokens & Aesthetics

private enum FulfillmentTokens {
    static let primary = AdminSurface.primary
    static let primarySoft = AdminSurface.primarySoft
    static let canvas = AdminSurface.background
    static let surface = AdminSurface.surface
    static let surfaceSecondary = Color(uiColor: .ppSecondarySurface)
    static let hairline = AdminSurface.hairline
    static let inkPrimary = AdminSurface.primaryText
    static let inkSecondary = AdminSurface.secondaryText
    static let inkTertiary = Color(uiColor: .ppTextTertiary)

    // Vibrant Semantic Tones
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.05) // #F59E0B
    static let amberSoft = Color(red: 0.96, green: 0.62, blue: 0.05).opacity(0.12)
    static let blue = Color(red: 0.15, green: 0.39, blue: 0.92)  // #2563EB
    static let blueSoft = Color(red: 0.15, green: 0.39, blue: 0.92).opacity(0.12)
    static let indigo = Color(red: 0.39, green: 0.40, blue: 0.95) // #6366F1
    static let indigoSoft = Color(red: 0.39, green: 0.40, blue: 0.95).opacity(0.12)
    static let emerald = Color(red: 0.06, green: 0.73, blue: 0.51) // #10B981
    static let emeraldSoft = Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.12)
    static let crimson = Color(red: 0.94, green: 0.27, blue: 0.27) // #EF4444
    static let crimsonSoft = Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.12)
    static let neutral = Color(red: 0.39, green: 0.45, blue: 0.55) // #64748B
    static let neutralSoft = Color(red: 0.39, green: 0.45, blue: 0.55).opacity(0.12)

    static let cornerSmall: CGFloat = 10
    static let cornerMedium: CGFloat = 16
    static let cornerCard: CGFloat = 22
    static let cornerHero: CGFloat = 26
    static let touchTarget: CGFloat = 44
}

// MARK: - Lifecycle Stages

enum FulfillmentStage: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case newRequests = "new_requests"
    case preparing = "preparing"
    case ready = "ready"
    case inTransit = "in_transit"
    case delivered = "delivered"
    case completed = "completed"
    case exceptions = "exceptions"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return Language.get("Fulfillment_Stage_All", alter: "الكل")
        case .newRequests:
            return Language.get("Fulfillment_Status_NewRequest", alter: "جديدة")
        case .preparing:
            return Language.get("Fulfillment_Status_Preparing", alter: "قيد التجهيز")
        case .ready:
            return Language.get("Fulfillment_Status_ReadyForPickup", alter: "جاهزة للشحن")
        case .inTransit:
            return Language.get("Fulfillment_Status_InTransit", alter: "في التوصيل")
        case .delivered:
            return Language.get("Fulfillment_Status_Delivered", alter: "تم التسليم")
        case .completed:
            return Language.get("Fulfillment_Status_Completed", alter: "مكتملة")
        case .exceptions:
            return Language.get("Fulfillment_Status_Cancelled", alter: "ملغاة ومسترجعة")
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .newRequests: return "bell.badge.fill"
        case .preparing: return "gearshape.2.fill"
        case .ready: return "shippingbox.fill"
        case .inTransit: return "box.truck.badge.clock.fill"
        case .delivered: return "house.fill"
        case .completed: return "checkmark.seal.fill"
        case .exceptions: return "exclamationmark.triangle.fill"
        }
    }

    var tone: Color {
        switch self {
        case .all: return FulfillmentTokens.primary
        case .newRequests: return FulfillmentTokens.amber
        case .preparing: return FulfillmentTokens.blue
        case .ready: return FulfillmentTokens.indigo
        case .inTransit: return Color.purple
        case .delivered: return FulfillmentTokens.emerald
        case .completed: return FulfillmentTokens.emerald
        case .exceptions: return FulfillmentTokens.crimson
        }
    }

    func matches(_ rawStatus: String?) -> Bool {
        if self == .all { return true }
        let norm = (rawStatus ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch self {
        case .all:
            return true
        case .newRequests:
            return norm == "new_request" || norm == "pending"
        case .preparing:
            return norm == "accepted" || norm == "preparing" || norm == "processing" || norm == "in_progress"
        case .ready:
            return norm == "ready_for_pickup" || norm == "delivery_requested"
        case .inTransit:
            return norm == "delivery_assigned" || norm == "awaiting_handover" || norm == "handed_over" || norm == "picked_up" || norm == "in_transit"
        case .delivered:
            return norm == "delivered" || norm == "payment_pending" || norm == "payment_confirmed"
        case .completed:
            return norm == "completed"
        case .exceptions:
            return norm == "cancelled" || norm == "rejected" || norm == "failed" || norm == "returned"
        }
    }
}

// MARK: - Sort Options

enum FulfillmentSortOption: String, CaseIterable, Identifiable {
    case newest = "newest"
    case urgentFirst = "urgent_first"
    case highestValue = "highest_value"
    case oldest = "oldest"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return Language.get("Fulfillment_Sort_Newest", alter: "الأحدث أولاً")
        case .urgentFirst: return Language.get("Fulfillment_Sort_Urgent", alter: "الأكثر إلحاحاً (SLA)")
        case .highestValue: return Language.get("Fulfillment_Sort_HighestValue", alter: "الأعلى قيمة")
        case .oldest: return Language.get("Fulfillment_Sort_Oldest", alter: "الأقدم أولاً")
        }
    }
}

// MARK: - Data Models

struct FulfillmentItemSnapshot: Identifiable, Sendable {
    let id: String
    let title: String
    let quantity: Int
    let unitPrice: Double
    let totalPrice: Double
    let imageURL: URL?
    let variantOptions: String?

    init(raw: [String: Any], index: Int) {
        let rawID = raw["itemId"] as? String ?? raw["productId"] as? String ?? raw["id"] as? String ?? "\(index)"
        self.id = rawID
        self.title = raw["name"] as? String ?? raw["title"] as? String ?? raw["productName"] as? String ?? "عنصر \(index + 1)"
        self.quantity = max(1, (raw["quantity"] as? NSNumber)?.intValue ?? (raw["count"] as? NSNumber)?.intValue ?? 1)
        self.unitPrice = (raw["unitPrice"] as? NSNumber)?.doubleValue ?? (raw["price"] as? NSNumber)?.doubleValue ?? 0.0
        self.totalPrice = (raw["totalPrice"] as? NSNumber)?.doubleValue ?? (Double(quantity) * unitPrice)

        if let imgStr = raw["image"] as? String ?? raw["imageUrl"] as? String ?? raw["photo"] as? String,
           let url = URL(string: imgStr), !imgStr.isEmpty {
            self.imageURL = url
        } else {
            self.imageURL = nil
        }

        var opts: [String] = []
        if let color = raw["color"] as? String, !color.isEmpty { opts.append(color) }
        if let size = raw["size"] as? String, !size.isEmpty { opts.append(size) }
        if let weight = raw["weight"] as? String, !weight.isEmpty { opts.append(weight) }
        self.variantOptions = opts.isEmpty ? nil : opts.joined(separator: " • ")
    }
}

struct FulfillmentRecordSnapshot: Identifiable, Sendable {
    let id: String
    let rawRecord: PPFulfillmentRecord
    let parentOrderID: String
    let parentOrderNumber: String
    let customerID: String
    let customerName: String
    let customerPhone: String?
    let deliveryAddress: String?
    let ownerID: String
    let ownerType: String
    let storeName: String
    let fulfillmentMode: String
    let status: String
    let deliveryMode: String
    let deliveryStatus: String?
    let driverName: String?
    let driverPhone: String?
    let items: [FulfillmentItemSnapshot]
    let subtotal: Double
    let deliveryFee: Double
    let platformCommission: Double
    let providerNet: Double
    let currency: String
    let createdAt: Date?
    let updatedAt: Date?
    let isPlatformOwned: Bool

    init(record: PPFulfillmentRecord) {
        self.rawRecord = record
        self.id = record.fulfillmentID ?? ""
        self.parentOrderID = record.parentOrderID ?? ""
        let orderNum = record.parentOrderNumber ?? ""
        self.parentOrderNumber = orderNum.isEmpty ? (record.fulfillmentID ?? "-") : orderNum
        self.customerID = record.customerID ?? record.parentUserId ?? ""
        let cust = record.customerName ?? ""
        self.customerName = cust.isEmpty ? Language.get("Fulfillment_UnknownCustomer", alter: "عميل بطلب مباشر") : cust
        self.customerPhone = record.customerPhone
        self.deliveryAddress = record.deliveryAddress
        let rawOwnerID = record.ownerID ?? ""
        self.ownerID = rawOwnerID
        let rawOwnerType = (record.ownerType ?? "").lowercased()
        self.ownerType = rawOwnerType.isEmpty ? "platform" : rawOwnerType
        if record.ownerType == "platform" {
            self.storeName = Language.get("Fulfillment_Mode_Platform", alter: "مستودع المنصة")
        } else {
            let fallbackPartner = Language.get("Fulfillment_Mode_Partner", alter: "متجر شريك")
            self.storeName = rawOwnerID.count > 15 ? fallbackPartner : (rawOwnerID.isEmpty ? fallbackPartner : rawOwnerID)
        }
        self.fulfillmentMode = record.fulfillmentMode ?? "standard"
        self.status = (record.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.deliveryMode = "company"
        self.deliveryStatus = nil
        self.driverName = nil
        self.driverPhone = nil

        var parsedItems: [FulfillmentItemSnapshot] = []
        if let rawItems = record.items as? [[String: Any]] {
            for (idx, it) in rawItems.enumerated() {
                parsedItems.append(FulfillmentItemSnapshot(raw: it, index: idx))
            }
        }
        self.items = parsedItems

        let moneyDict = record.money ?? [:]
        self.subtotal = (moneyDict["subtotal"] as? NSNumber)?.doubleValue ?? 0.0
        self.deliveryFee = (moneyDict["deliveryFee"] as? NSNumber)?.doubleValue ?? 0.0
        self.platformCommission = (moneyDict["platformCommission"] as? NSNumber)?.doubleValue ?? 0.0
        let net = (moneyDict["providerNet"] as? NSNumber)?.doubleValue ?? 0.0
        self.providerNet = net > 0 ? net : subtotal
        self.currency = moneyDict["currency"] as? String ?? "QAR"
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.isPlatformOwned = (record.ownerType == "platform" || (record.ownerID ?? "").isEmpty)
    }

    var stage: FulfillmentStage {
        for s in FulfillmentStage.allCases where s != .all {
            if s.matches(status) { return s }
        }
        return .newRequests
    }

    var displayStatus: String {
        switch status {
        case "new_request": return Language.get("Fulfillment_Status_NewRequest", alter: "طلب جديد")
        case "pending": return Language.get("Fulfillment_Status_Pending", alter: "قيد الانتظار")
        case "accepted": return Language.get("Fulfillment_Status_Accepted", alter: "تم القبول")
        case "preparing", "processing", "in_progress": return Language.get("Fulfillment_Status_Preparing", alter: "قيد التجهيز")
        case "ready_for_pickup": return Language.get("Fulfillment_Status_ReadyForPickup", alter: "جاهز للاستلام")
        case "delivery_requested": return Language.get("Fulfillment_Status_DeliveryRequested", alter: "تم طلب التوصيل")
        case "delivery_assigned": return Language.get("Fulfillment_Status_DeliveryAssigned", alter: "تم تعيين مندوب")
        case "awaiting_handover": return Language.get("Fulfillment_Status_AwaitingHandover", alter: "بانتظار التسليم")
        case "handed_over": return Language.get("Fulfillment_Status_HandedOver", alter: "تم التسليم للمندوب")
        case "picked_up": return Language.get("Fulfillment_Status_PickedUp", alter: "تم الاستلام")
        case "in_transit": return Language.get("Fulfillment_Status_InTransit", alter: "في الطريق")
        case "delivered": return Language.get("Fulfillment_Status_Delivered", alter: "تم التوصيل")
        case "payment_pending": return Language.get("Fulfillment_Status_PaymentPending", alter: "بانتظار الدفع")
        case "payment_confirmed": return Language.get("Fulfillment_Status_PaymentConfirmed", alter: "تم تأكيد الدفع")
        case "completed": return Language.get("Fulfillment_Status_Completed", alter: "مكتمل")
        case "cancelled": return Language.get("Fulfillment_Status_Cancelled", alter: "ملغي")
        case "rejected": return Language.get("Fulfillment_Status_Rejected", alter: "مرفوض")
        case "failed": return Language.get("Fulfillment_Status_Failed", alter: "متعذر")
        case "returned": return Language.get("Fulfillment_Status_Returned", alter: "مرتجع")
        default: return status.capitalized
        }
    }

    var statusTone: Color {
        switch status {
        case "new_request", "pending": return FulfillmentTokens.amber
        case "accepted", "preparing", "processing", "in_progress": return FulfillmentTokens.blue
        case "ready_for_pickup", "delivery_requested": return FulfillmentTokens.indigo
        case "delivery_assigned", "awaiting_handover", "handed_over", "picked_up", "in_transit": return Color.purple
        case "delivered", "payment_confirmed", "completed": return FulfillmentTokens.emerald
        case "cancelled", "rejected", "failed", "returned": return FulfillmentTokens.crimson
        default: return FulfillmentTokens.neutral
        }
    }

    var statusSymbol: String {
        switch status {
        case "new_request", "pending": return "bell.fill"
        case "accepted": return "hand.thumbsup.fill"
        case "preparing", "processing", "in_progress": return "gearshape.2.fill"
        case "ready_for_pickup": return "shippingbox.fill"
        case "delivery_requested", "delivery_assigned": return "person.badge.shield.checkmark.fill"
        case "in_transit", "handed_over", "picked_up": return "box.truck.badge.clock.fill"
        case "delivered", "payment_confirmed": return "house.fill"
        case "completed": return "checkmark.seal.fill"
        case "cancelled", "rejected", "failed", "returned": return "xmark.circle.fill"
        default: return "circle.fill"
        }
    }

    var isSLAUrgent: Bool {
        guard (status == "new_request" || status == "pending"), let created = createdAt else { return false }
        return Date().timeIntervalSince(created) > (30 * 60) // > 30 minutes
    }

    var elapsedFormatted: String {
        guard let date = createdAt ?? updatedAt else { return "-" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return Language.get("Time_JustNow", alter: "الآن") }
        let mins = Int(diff / 60)
        if mins < 60 { return "\(mins) \(Language.get("Time_Minutes_Ago", alter: "د"))" }
        let hours = Int(mins / 60)
        if hours < 24 { return "\(hours) \(Language.get("Time_Hours_Ago", alter: "س"))" }
        let days = Int(hours / 24)
        return "\(days) \(Language.get("Time_Days_Ago", alter: "ي"))"
    }

    var nextQuickAction: (title: String, targetStatus: String, symbol: String)? {
        switch status {
        case "new_request", "pending":
            return (Language.get("Fulfillment_Quick_Accept", alter: "قبول الطلب"), "accepted", "checkmark.circle.fill")
        case "accepted":
            return (Language.get("Fulfillment_Quick_Prepare", alter: "بدء التجهيز"), "preparing", "gearshape.fill")
        case "preparing", "processing":
            return (Language.get("Fulfillment_Quick_Ready", alter: "جاهز للشحن"), "ready_for_pickup", "shippingbox.fill")
        case "ready_for_pickup":
            return (Language.get("Fulfillment_Quick_Request_Delivery", alter: "طلب مندوب"), "delivery_requested", "paperplane.fill")
        default:
            return nil
        }
    }
}

struct FulfillmentEventSnapshot: Identifiable, Sendable {
    let id: String
    let eventType: String
    let actorUID: String?
    let actorRole: String?
    let note: String?
    let fromStatus: String?
    let toStatus: String?
    let timestamp: Date?

    init(dict: [String: Any], docID: String) {
        self.id = docID
        self.eventType = dict["eventType"] as? String ?? dict["type"] as? String ?? "event"
        self.actorUID = dict["actorUid"] as? String ?? dict["actorId"] as? String ?? dict["uid"] as? String
        self.actorRole = dict["actorRole"] as? String ?? dict["role"] as? String
        self.note = dict["note"] as? String ?? dict["reason"] as? String
        self.fromStatus = dict["fromStatus"] as? String ?? dict["previousStatus"] as? String
        self.toStatus = dict["toStatus"] as? String ?? dict["targetStatus"] as? String ?? dict["status"] as? String
        if let ts = dict["timestamp"] as? Timestamp {
            self.timestamp = ts.dateValue()
        } else if let dt = dict["timestamp"] as? Date {
            self.timestamp = dt
        } else {
            self.timestamp = nil
        }
    }
}

struct FulfillmentCockpitMetrics: Sendable {
    let actionRequiredCount: Int
    let inPreparationCount: Int
    let inTransitCount: Int
    let completedCount: Int
    let totalGrossValue: Double
    let slaUrgentCount: Int
}

/// Keeps transport errors out of the presentation contract while preserving the
/// one recovery case that must rebind to an authoritative server snapshot.
enum FulfillmentOverrideCommitResult: Sendable {
    case succeeded
    case conflict(requiresLiveRecordReload: Bool)
    case denied
    case invalid
    case failed

    static func from(error: Error) -> Self {
        var currentError: NSError? = error as NSError
        var isConcurrencyConflict = false
        var isStatusChangedConflict = false

        for _ in 0..<4 {
            guard let candidate = currentError else { break }
            if candidate.domain == "com.firebase.functions" {
                switch candidate.code {
                case 7, 16: // permission-denied, unauthenticated
                    return .denied
                case 6, 9, 10: // already-exists, failed-precondition, aborted
                    isConcurrencyConflict = true
                    let message = candidate.localizedDescription.lowercased()
                    if message.contains("fulfillment status changed") {
                        isStatusChangedConflict = true
                    }
                case 3, 5: // invalid-argument, not-found
                    return .invalid
                default:
                    break
                }
            }
            currentError = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        if isConcurrencyConflict {
            return .conflict(requiresLiveRecordReload: isStatusChangedConflict)
        }
        return .failed
    }
}

// MARK: - Fulfillment List ViewModel

@MainActor
final class FulfillmentListViewModel: ObservableObject {
    @Published private(set) var records: [FulfillmentRecordSnapshot] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isFromCache: Bool = false
    @Published var errorMessage: String?
    @Published var selectedStage: FulfillmentStage = .all
    @Published var searchText: String = ""
    @Published var onlySLAUrgent: Bool = false
    @Published var selectedMode: String = "all" // "all", "platform", "partner"
    @Published var sortOption: FulfillmentSortOption = .newest
    @Published var isSubmittingAction: Bool = false
    @Published var actionSuccessToast: String?

    private var listener: AnyObject?

    var filteredRecords: [FulfillmentRecordSnapshot] {
        var result = records

        // Stage filter
        if selectedStage != .all {
            result = result.filter { selectedStage.matches($0.status) }
        }

        // SLA Urgent toggle
        if onlySLAUrgent {
            result = result.filter { $0.isSLAUrgent }
        }

        // Fulfillment Mode
        if selectedMode == "platform" {
            result = result.filter { $0.isPlatformOwned }
        } else if selectedMode == "partner" {
            result = result.filter { !$0.isPlatformOwned }
        }

        // Search query
        if !searchText.isEmpty {
            let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            result = result.filter { r in
                r.parentOrderNumber.lowercased().contains(q) ||
                r.id.lowercased().contains(q) ||
                r.customerName.lowercased().contains(q) ||
                r.storeName.lowercased().contains(q) ||
                r.items.contains(where: { $0.title.lowercased().contains(q) })
            }
        }

        // Sorting
        switch sortOption {
        case .newest:
            result.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .oldest:
            result.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        case .urgentFirst:
            result.sort { lhs, rhs in
                if lhs.isSLAUrgent != rhs.isSLAUrgent { return lhs.isSLAUrgent && !rhs.isSLAUrgent }
                return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
            }
        case .highestValue:
            result.sort { $0.providerNet > $1.providerNet }
        }

        return result
    }

    var metrics: FulfillmentCockpitMetrics {
        var actionReq = 0
        var inPrep = 0
        var inTransit = 0
        var comp = 0
        var totalVal = 0.0
        var urgent = 0

        for r in records {
            if FulfillmentStage.newRequests.matches(r.status) {
                actionReq += 1
            } else if FulfillmentStage.preparing.matches(r.status) || FulfillmentStage.ready.matches(r.status) {
                inPrep += 1
            } else if FulfillmentStage.inTransit.matches(r.status) || FulfillmentStage.delivered.matches(r.status) {
                inTransit += 1
            } else if FulfillmentStage.completed.matches(r.status) {
                comp += 1
            }

            if r.isSLAUrgent { urgent += 1 }
            totalVal += r.providerNet
        }

        return FulfillmentCockpitMetrics(
            actionRequiredCount: actionReq,
            inPreparationCount: inPrep,
            inTransitCount: inTransit,
            completedCount: comp,
            totalGrossValue: totalVal,
            slaUrgentCount: urgent
        )
    }

    func startListening() {
        guard listener == nil else { return }
        isLoading = true
        errorMessage = nil

        listener = PPFulfillmentService.shared().observeFulfillments { [weak self] rawRecords, fromCache, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isLoading = false
                self.isFromCache = fromCache

                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                self.records = (rawRecords ?? []).map { FulfillmentRecordSnapshot(record: $0) }
            }
        }
    }

    func stopListening() {
        if let reg = listener as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(reg)
        }
        listener = nil
    }

    func count(for stage: FulfillmentStage) -> Int {
        if stage == .all { return records.count }
        return records.filter { stage.matches($0.status) }.count
    }

    // MARK: - Actions

    func quickAdvance(record: FulfillmentRecordSnapshot, targetStatus: String) {
        guard !isSubmittingAction else { return }
        isSubmittingAction = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let cmdID = "cmd_\(UUID().uuidString.prefix(8))"
        let note = "Staff quick advance to \(targetStatus) from Admin Console"

        if record.isPlatformOwned {
            // Official platform transition
            PPFulfillmentService.shared().transitionOfficialFulfillment(
                record.rawRecord,
                expectedStatus: record.status,
                action: targetStatus,
                note: note,
                commandID: cmdID
            ) { [weak self] _, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isSubmittingAction = false
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.actionSuccessToast = Language.get("Fulfillment_Transition_Success", alter: "تم تحديث حالة الطلب بنجاح")
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
        } else {
            // Authorized admin override for partner or non-official child
            PPFulfillmentService.shared().adminOverride(
                record.id,
                expectedStatus: record.status,
                targetStatus: targetStatus,
                reason: "Staff operational acceleration",
                note: note,
                notify: true,
                commandID: cmdID
            ) { [weak self] _, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isSubmittingAction = false
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.actionSuccessToast = Language.get("Fulfillment_Transition_Success", alter: "تم تحديث حالة الطلب بنجاح")
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
        }
    }

    func executeAdminOverride(
        record: FulfillmentRecordSnapshot,
        expectedStatus: String,
        targetStatus: String,
        reason: String,
        note: String?,
        notify: Bool,
        completion: @escaping @Sendable (FulfillmentOverrideCommitResult) -> Void
    ) {
        let cmdID = "override_\(UUID().uuidString.prefix(8))"
        PPFulfillmentService.shared().adminOverride(
            record.id,
            expectedStatus: expectedStatus,
            targetStatus: targetStatus,
            reason: reason,
            note: note,
            notify: notify,
            commandID: cmdID
        ) { _, error in
            Task { @MainActor in
                if let error = error {
                    completion(FulfillmentOverrideCommitResult.from(error: error))
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    completion(.succeeded)
                }
            }
        }
    }
}

// MARK: - Main Fulfillment Screen

struct AdminFulfillmentListView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FulfillmentListViewModel()

    // Presentation sheets
    @State private var selectedRecordForDossier: FulfillmentRecordSnapshot?
    @State private var recordForDossierPush: FulfillmentRecordSnapshot?
    @State private var recordForOverride: FulfillmentRecordSnapshot?
    @State private var recordForOverridePush: FulfillmentRecordSnapshot?
    @State private var showingFiltersSheet: Bool = false
    @State private var activeSearch: Bool = false
    @State private var parentPaymentOrderIDToOpen: String?

    init(session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.session = session
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            FulfillmentTokens.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                sovereignHeaderView

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        executiveHolographicCockpit
                        omniSearchBarAndQuickScope
                        spatialStagePipelineRail
                        recordsFeedSection
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 12)
                    .padding(.bottom, 48)
                }
                .refreshable {
                    viewModel.stopListening()
                    viewModel.startListening()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }

            // Success feedback toast overlay
            if let toast = viewModel.actionSuccessToast {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(FulfillmentTokens.emerald)
                        Text(toast)
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
                    .padding(.bottom, 36)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation { viewModel.actionSuccessToast = nil }
                    }
                }
            }
        }
        .background(overridePushLink)
        .background(dossierPushLink)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(item: $selectedRecordForDossier) { record in
            FulfillmentDossierSheet(
                record: record,
                onOverride: { r in
                    selectedRecordForDossier = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        recordForOverridePush = r
                    }
                },
                onOpenParentOrder: { orderID in
                    selectedRecordForDossier = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        parentPaymentOrderIDToOpen = orderID
                    }
                },
                onQuickAdvance: { r, target in
                    viewModel.quickAdvance(record: r, targetStatus: target)
                }
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(item: $recordForOverride) { record in
            FulfillmentOverrideView(
                record: record,
                isPushMode: false,
                onDismiss: {
                    recordForOverride = nil
                },
                onCommit: { expectedStatus, target, reason, note, notify, completion in
                    viewModel.executeAdminOverride(
                        record: record,
                        expectedStatus: expectedStatus,
                        targetStatus: target,
                        reason: reason,
                        note: note,
                        notify: notify,
                        completion: completion
                    )
                }
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $showingFiltersSheet) {
            FulfillmentFilterSheet(
                selectedMode: $viewModel.selectedMode,
                onlyUrgent: $viewModel.onlySLAUrgent,
                sortOption: $viewModel.sortOption
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(item: Binding<IdentifiableString?>(
            get: { parentPaymentOrderIDToOpen.map { IdentifiableString(id: $0) } },
            set: { parentPaymentOrderIDToOpen = $0?.id }
        )) { orderID in
            AdminPaymentDetailView(orderID: orderID.id, session: session) {
                parentPaymentOrderIDToOpen = nil
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
    }

    private var overridePushLink: some View {
        NavigationLink(
            destination: overridePushDestination,
            isActive: Binding(
                get: { recordForOverridePush != nil },
                set: { if !$0 { recordForOverridePush = nil } }
            )
        ) {
            EmptyView()
        }
        .hidden()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var overridePushDestination: some View {
        if let record = recordForOverridePush {
            FulfillmentOverrideView(
                record: record,
                isPushMode: true,
                onDismiss: {
                    recordForOverridePush = nil
                },
                onCommit: { expectedStatus, target, reason, note, notify, completion in
                    viewModel.executeAdminOverride(
                        record: record,
                        expectedStatus: expectedStatus,
                        targetStatus: target,
                        reason: reason,
                        note: note,
                        notify: notify
                    ) { result in
                        if case .succeeded = result {
                            recordForOverridePush = nil
                        }
                        completion(result)
                    }
                }
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    private var dossierPushLink: some View {
        NavigationLink(
            destination: dossierPushDestination,
            isActive: Binding(
                get: { recordForDossierPush != nil },
                set: { if !$0 { recordForDossierPush = nil } }
            )
        ) {
            EmptyView()
        }
        .hidden()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var dossierPushDestination: some View {
        if let record = recordForDossierPush {
            FulfillmentDossierView(
                record: record,
                isPushMode: true,
                onDismiss: {
                    recordForDossierPush = nil
                },
                onOverride: { r in
                    recordForOverridePush = r
                },
                onOpenParentOrder: { orderID in
                    parentPaymentOrderIDToOpen = orderID
                },
                onQuickAdvance: { r, target in
                    viewModel.quickAdvance(record: r, targetStatus: target)
                }
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: - 1. Sovereign Navigation Header

    private var sovereignHeaderView: some View {
        VStack(spacing: 0) {
            AdminSovereignNavigationBar(
                title: Language.get("Fulfillment_Title", alter: "طلبات التنفيذ"),
                subtitle: viewModel.isFromCache
                    ? Language.get("Fulfillment_Cached_Pulse", alter: "مخزن مؤقتاً")
                    : Language.get("Fulfillment_Live_Pulse", alter: "مباشر"),
                statusDotColor: viewModel.isFromCache ? FulfillmentTokens.amber : FulfillmentTokens.emerald,
                onBack: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
            ) {
                HStack(spacing: 8) {
                    // Filter Sheet Trigger
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingFiltersSheet = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(FulfillmentTokens.inkPrimary)
                                .frame(width: 42, height: 42)
                                .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(FulfillmentTokens.hairline, lineWidth: 0.8)
                                )

                            if viewModel.onlySLAUrgent || viewModel.selectedMode != "all" {
                                Circle()
                                    .fill(FulfillmentTokens.amber)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Refresh Button
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.stopListening()
                        viewModel.startListening()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(FulfillmentTokens.primary)
                                .frame(width: 42, height: 42)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(FulfillmentTokens.inkPrimary)
                                .frame(width: 42, height: 42)
                                .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(FulfillmentTokens.hairline, lineWidth: 0.8)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error, retry: { viewModel.startListening() })
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - 2. Executive Holographic Cockpit (Telemetry HUD)

    private var executiveHolographicCockpit: some View {
        let m = viewModel.metrics
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            // 1. Action Required / Urgent
            CockpitMetricCard(
                title: Language.get("Fulfillment_Action_Required", alter: "حرجة وتنتظر إجراء"),
                value: "\(m.actionRequiredCount)",
                badge: m.slaUrgentCount > 0 ? "\(m.slaUrgentCount) SLA" : nil,
                symbol: "flame.fill",
                accentColor: FulfillmentTokens.amber,
                isSelected: viewModel.selectedStage == .newRequests
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.selectedStage = (viewModel.selectedStage == .newRequests) ? .all : .newRequests
                }
            }

            // 2. In Preparation
            CockpitMetricCard(
                title: Language.get("Fulfillment_In_Preparation", alter: "قيد التجهيز بالمتجر"),
                value: "\(m.inPreparationCount)",
                badge: nil,
                symbol: "gearshape.2.fill",
                accentColor: FulfillmentTokens.blue,
                isSelected: viewModel.selectedStage == .preparing
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.selectedStage = (viewModel.selectedStage == .preparing) ? .all : .preparing
                }
            }

            // 3. In Transit Fleet
            CockpitMetricCard(
                title: Language.get("Fulfillment_In_Transit_Fleet", alter: "في أسطول التوصيل"),
                value: "\(m.inTransitCount)",
                badge: nil,
                symbol: "box.truck.badge.clock.fill",
                accentColor: Color.purple,
                isSelected: viewModel.selectedStage == .inTransit
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.selectedStage = (viewModel.selectedStage == .inTransit) ? .all : .inTransit
                }
            }

            // 4. Completed & Settled GMV
            CockpitMetricCard(
                title: Language.get("Fulfillment_Gross_Settled", alter: "مكتملة ومسوّاة"),
                value: "\(m.completedCount)",
                badge: String(format: "%.0f %@", m.totalGrossValue, Language.get("Currency_QAR", alter: "ر.ق")),
                symbol: "checkmark.seal.fill",
                accentColor: FulfillmentTokens.emerald,
                isSelected: viewModel.selectedStage == .completed
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.selectedStage = (viewModel.selectedStage == .completed) ? .all : .completed
                }
            }
        }
    }

    // MARK: - 3. Omni-Search & Scope Bar

    private var omniSearchBarAndQuickScope: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FulfillmentTokens.inkSecondary)

                TextField(Language.get("Fulfillment_SearchPlaceholder", alter: "ابحث بالطلب، العميل، المتجر، أو المنتجات..."), text: $viewModel.searchText)
                    .font(AdminType.subheadline)
                    .foregroundStyle(FulfillmentTokens.inkPrimary)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(FulfillmentTokens.inkTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FulfillmentTokens.cornerMedium, style: .continuous)
                    .stroke(viewModel.searchText.isEmpty ? FulfillmentTokens.hairline : FulfillmentTokens.primary.opacity(0.6), lineWidth: 1)
            )

            // Quick Filters Bar
            if viewModel.metrics.slaUrgentCount > 0 || viewModel.selectedMode != "all" {
                HStack(spacing: 8) {
                    if viewModel.metrics.slaUrgentCount > 0 {
                        Button {
                            withAnimation { viewModel.onlySLAUrgent.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(Language.get("Fulfillment_SLA_Urgent", alter: "متأخر عن SLA"))
                                Text("\(viewModel.metrics.slaUrgentCount)")
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.2), in: Capsule())
                            }
                            .font(AdminType.caption2Bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(viewModel.onlySLAUrgent ? FulfillmentTokens.crimson : FulfillmentTokens.crimsonSoft, in: Capsule())
                            .foregroundStyle(viewModel.onlySLAUrgent ? .white : FulfillmentTokens.crimson)
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.selectedMode != "all" {
                        Button {
                            viewModel.selectedMode = "all"
                        } label: {
                            HStack(spacing: 4) {
                                Text(viewModel.selectedMode == "platform" ? Language.get("Fulfillment_Mode_Platform", alter: "المنصة") : Language.get("Fulfillment_Mode_Partner", alter: "شريك"))
                                Image(systemName: "xmark")
                            }
                            .font(AdminType.caption2Bold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(FulfillmentTokens.primarySoft, in: Capsule())
                            .foregroundStyle(FulfillmentTokens.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - 4. Spatial Stage Pipeline Rail

    private var spatialStagePipelineRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FulfillmentStage.allCases) { stage in
                    let isSelected = viewModel.selectedStage == stage
                    let count = viewModel.count(for: stage)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.selectedStage = stage
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: stage.symbol)
                                .font(.system(size: 13, weight: .bold))

                            Text(stage.title)
                                .font(AdminType.subheadlineBold)

                            Text("\(count)")
                                .font(AdminType.caption2Bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    isSelected ? Color.white.opacity(0.25) : FulfillmentTokens.inkSecondary.opacity(0.12),
                                    in: Capsule()
                                )
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            isSelected ? stage.tone : FulfillmentTokens.surface,
                            in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerMedium, style: .continuous)
                        )
                        .foregroundStyle(isSelected ? .white : FulfillmentTokens.inkSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: FulfillmentTokens.cornerMedium, style: .continuous)
                                .stroke(isSelected ? Color.clear : FulfillmentTokens.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 5. Records Feed Section

    @ViewBuilder
    private var recordsFeedSection: some View {
        if viewModel.isLoading && viewModel.records.isEmpty {
            VStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    ShimmerCardPlaceholder()
                }
            }
        } else if viewModel.filteredRecords.isEmpty {
            AdminEmptyStateView(
                symbol: "shippingbox.fill",
                title: Language.get("Fulfillment_No_Orders", alter: "لا توجد طلبات في هذا النطاق"),
                subtitle: Language.get("Fulfillment_No_Orders_Sub", alter: "يمكنك تغيير مرحلة المعالجة أو مسح خيارات البحث")
            )
            .padding(.top, 40)
        } else {
            VStack(spacing: 14) {
                // Header result indicator
                HStack {
                    Text(String(format: Language.get("Fulfillment_Showing_Format", alter: "عرض %@ من %@ طلب"), "\(viewModel.filteredRecords.count)", "\(viewModel.records.count)"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(FulfillmentTokens.inkSecondary)

                    Spacer()

                    Text(viewModel.sortOption.title)
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkTertiary)
                }
                .padding(.horizontal, 4)

                ForEach(viewModel.filteredRecords) { record in
                    FulfillmentHeroCard(
                        record: record,
                        onTapCard: {
                            recordForDossierPush = record
                        },
                        onOverride: {
                            recordForOverridePush = record
                        },
                        onQuickAdvance: { target in
                            viewModel.quickAdvance(record: record, targetStatus: target)
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Subviews: Cockpit Metric Card

private struct CockpitMetricCard: View {
    let title: String
    let value: String
    let badge: String?
    let symbol: String
    let accentColor: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accentColor)
                        .frame(width: 32, height: 32)
                        .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Spacer()

                    if let badge {
                        Text(badge)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accentColor.opacity(0.12), in: Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(FulfillmentTokens.inkPrimary)
                        .monospacedDigit()

                    Text(title)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(FulfillmentTokens.inkSecondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous)
                    .stroke(isSelected ? accentColor : FulfillmentTokens.hairline, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? accentColor.opacity(0.15) : Color.black.opacity(0.02), radius: isSelected ? 8 : 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Subviews: Flagship Hero Order Card

private struct FulfillmentHeroCard: View {
    let record: FulfillmentRecordSnapshot
    let onTapCard: () -> Void
    var onOverride: (() -> Void)? = nil
    let onQuickAdvance: (String) -> Void

    @State private var copied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Top Ribbon
            HStack(spacing: 10) {
                // Order Number with Copy Trigger
                Button {
                    UIPasteboard.general.string = record.parentOrderNumber
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(record.parentOrderNumber)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(FulfillmentTokens.inkPrimary)

                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(copied ? FulfillmentTokens.emerald : FulfillmentTokens.inkTertiary)
                    }
                }
                .buttonStyle(.plain)

                if record.isSLAUrgent {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(Language.get("Fulfillment_SLA_Urgent", alter: "SLA متأخر"))
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(FulfillmentTokens.crimson, in: Capsule())
                }

                Spacer()

                // Status Badge with Ambient Halo
                HStack(spacing: 5) {
                    Circle()
                        .fill(record.statusTone)
                        .frame(width: 6, height: 6)

                    Text(record.displayStatus)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(record.statusTone)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(record.statusTone.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(record.statusTone.opacity(0.25), lineWidth: 0.8))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().background(FulfillmentTokens.hairline)

            // Middle Section: Customer & Provider Intelligence
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Customer Profile Pill
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FulfillmentTokens.primary)
                            .frame(width: 26, height: 26)
                            .background(FulfillmentTokens.primarySoft, in: Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.customerName)
                                .font(AdminType.subheadlineBold)
                                .foregroundStyle(FulfillmentTokens.inkPrimary)
                                .lineLimit(1)

                            Text(record.elapsedFormatted)
                                .font(AdminType.caption2)
                                .foregroundStyle(FulfillmentTokens.inkTertiary)
                        }
                    }

                    Spacer()

                    // Store / Fulfillment Mode Pill
                    HStack(spacing: 6) {
                        Image(systemName: record.isPlatformOwned ? "building.2.crop.circle.fill" : "storefront.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(record.isPlatformOwned ? FulfillmentTokens.indigo : FulfillmentTokens.amber)

                        Text(record.storeName)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(FulfillmentTokens.inkSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(FulfillmentTokens.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                // Item Preview Visual Strip
                if !record.items.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(record.items.prefix(4)) { item in
                                HStack(spacing: 6) {
                                    if let url = item.imageURL {
                                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 28, height: 28)) {
                                            Image(systemName: "shippingbox")
                                                .font(.system(size: 11))
                                                .foregroundStyle(FulfillmentTokens.inkTertiary)
                                        }
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    } else {
                                        Image(systemName: "shippingbox.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(FulfillmentTokens.inkTertiary)
                                            .frame(width: 28, height: 28)
                                            .background(FulfillmentTokens.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title)
                                            .font(AdminType.caption2Bold)
                                            .foregroundStyle(FulfillmentTokens.inkPrimary)
                                            .lineLimit(1)

                                        Text("×\(item.quantity)")
                                            .font(AdminType.caption2)
                                            .foregroundStyle(FulfillmentTokens.inkTertiary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(FulfillmentTokens.surfaceSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                            }

                            if record.items.count > 4 {
                                Text("+\(record.items.count - 4)")
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(FulfillmentTokens.inkSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(FulfillmentTokens.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(FulfillmentTokens.hairline)

            // Bottom Action Bar & Financial Summary
            HStack(spacing: 12) {
                // Price & Items Count
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%.2f %@", record.providerNet, Language.get("Currency_QAR", alter: "ر.ق")))
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(FulfillmentTokens.inkPrimary)
                        .monospacedDigit()

                    Text("\(record.items.count) \(Language.get("Fulfillment_Items", alter: "عناصر"))")
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkTertiary)
                }

                Spacer()

                // Context Quick Action
                if let action = record.nextQuickAction {
                    Button {
                        onQuickAdvance(action.targetStatus)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: action.symbol)
                                .font(.system(size: 12, weight: .bold))
                            Text(action.title)
                                .font(AdminType.captionBold)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(record.statusTone, in: Capsule())
                        .foregroundStyle(.white)
                        .shadow(color: record.statusTone.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }

                // Privileged Admin Override Push Trigger
                if let onOverride {
                    Button(action: onOverride) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(FulfillmentTokens.crimson)
                            .frame(width: 32, height: 32)
                            .background(FulfillmentTokens.crimsonSoft, in: Circle())
                            .overlay(Circle().stroke(FulfillmentTokens.crimson.opacity(0.3), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Fulfillment_Admin_Override_Title", alter: "تعديل إداري"))
                }

                // Details Chevron Button
                Button(action: onTapCard) {
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FulfillmentTokens.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(FulfillmentTokens.surfaceSecondary, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous)
                .stroke(record.isSLAUrgent ? FulfillmentTokens.crimson.opacity(0.7) : FulfillmentTokens.hairline, lineWidth: record.isSLAUrgent ? 1.5 : 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, y: 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapCard)
    }
}

// MARK: - Subviews: Fulfillment Order Dossier & Command Suite

private typealias FulfillmentDossierSheet = FulfillmentDossierView

struct FulfillmentDossierView: View {
    let record: FulfillmentRecordSnapshot
    var isPushMode: Bool = true
    var onDismiss: (() -> Void)? = nil
    let onOverride: (FulfillmentRecordSnapshot) -> Void
    let onOpenParentOrder: (String) -> Void
    let onQuickAdvance: (FulfillmentRecordSnapshot, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var events: [FulfillmentEventSnapshot] = []
    @State private var isLoadingEvents: Bool = true
    @State private var eventsListener: AnyObject?
    @State private var recordForOverridePush: FulfillmentRecordSnapshot?

    private var statusBarHeight: CGFloat {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return max(window.safeAreaInsets.top, 44)
        }
        return 47
    }

    var body: some View {
        if isPushMode {
            dossierContent
                .navigationBarHidden(true)
                .ignoresSafeArea(.container, edges: .top)
        } else {
            NavigationView {
                dossierContent
                    .navigationBarHidden(true)
            }
        }
    }

    private var dossierContent: some View {
        ZStack {
            FulfillmentTokens.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                if isPushMode {
                    sovereignPushHeader
                } else {
                    sovereignSheetHeader
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        dossierJourneyStepper
                        financialSettlementMatrix
                        customerBlueprintCard
                        productManifestCard
                        deliveryCourierCard
                        auditTimelineCard
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 14)
                    .padding(.bottom, 120)
                }
            }

            // Sticky Action Dock at bottom
            VStack {
                Spacer()
                stickyCommandDock
            }
        }
        .background(overridePushLink)
        .onAppear(perform: startListeningEvents)
        .onDisappear(perform: stopListeningEvents)
    }

    private var sovereignPushHeader: some View {
        AdminSovereignNavigationBar(
            title: record.parentOrderNumber,
            subtitle: record.displayStatus,
            statusDotColor: record.statusTone,
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            Button {
                recordForOverridePush = record
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text(Language.get("Fulfillment_Admin_Override_Title", alter: "تعديل إداري"))
                }
                .font(AdminType.captionBold)
                .foregroundStyle(FulfillmentTokens.crimson)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(FulfillmentTokens.crimsonSoft, in: Capsule())
                .overlay(Capsule().stroke(FulfillmentTokens.crimson.opacity(0.3), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, isPushMode ? statusBarHeight : 0)
    }

    private var sovereignSheetHeader: some View {
        HStack(alignment: .center) {
            Button(Language.get("Close", alter: "إغلاق")) {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
            .font(AdminType.subheadlineBold)
            .foregroundStyle(FulfillmentTokens.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(FulfillmentTokens.primarySoft, in: Capsule())

            Spacer()

            VStack(spacing: 2) {
                Text(record.parentOrderNumber)
                    .font(AdminType.headline)
                    .foregroundStyle(FulfillmentTokens.inkPrimary)
                Text(record.displayStatus)
                    .font(AdminType.caption2)
                    .foregroundStyle(record.statusTone)
            }

            Spacer()

            Button {
                recordForOverridePush = record
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                    Text(Language.get("Fulfillment_Admin_Override_Title", alter: "تعديل إداري"))
                }
                .font(AdminType.captionBold)
                .foregroundStyle(FulfillmentTokens.crimson)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(FulfillmentTokens.crimsonSoft, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, 14)
        .background(AdminSurface.surface)
        .overlay(Divider().background(FulfillmentTokens.hairline), alignment: .bottom)
    }

    private var overridePushLink: some View {
        NavigationLink(
            destination: overridePushDestination,
            isActive: Binding(
                get: { recordForOverridePush != nil },
                set: { if !$0 { recordForOverridePush = nil } }
            )
        ) {
            EmptyView()
        }
        .hidden()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var overridePushDestination: some View {
        if let rec = recordForOverridePush {
            FulfillmentOverrideView(
                record: rec,
                isPushMode: true,
                onDismiss: {
                    recordForOverridePush = nil
                },
                onCommit: { expectedStatus, target, reason, note, notify, completion in
                    PPFulfillmentService.shared().adminOverride(
                        rec.id,
                        expectedStatus: expectedStatus,
                        targetStatus: target,
                        reason: reason,
                        note: note,
                        notify: notify,
                        commandID: "cmd_\(UUID().uuidString.prefix(8))"
                    ) { _, error in
                        Task { @MainActor in
                            if let error = error {
                                completion(FulfillmentOverrideCommitResult.from(error: error))
                            } else {
                                recordForOverridePush = nil
                                completion(.succeeded)
                            }
                        }
                    }
                }
            )
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // 1. Spatial Stage Journey Stepper
    private var dossierJourneyStepper: some View {
        let stages: [(title: String, symbol: String, isDone: Bool, isCurrent: Bool)] = [
            ("جديد", "bell.fill", record.stage != .newRequests, record.stage == .newRequests),
            ("مقبول", "hand.thumbsup.fill", record.stage != .newRequests && record.stage != .preparing, record.stage == .preparing),
            ("تجهيز", "gearshape.2.fill", record.stage == .ready || record.stage == .inTransit || record.stage == .delivered || record.stage == .completed, record.stage == .ready),
            ("توصيل", "box.truck.fill", record.stage == .delivered || record.stage == .completed, record.stage == .inTransit),
            ("مكتمل", "checkmark.seal.fill", record.stage == .completed, record.stage == .completed)
        ]

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Language.get("Fulfillment_Workflow_Title", alter: "مسار حركة الطلب"))
                    .font(AdminType.captionBold)
                    .foregroundStyle(FulfillmentTokens.inkSecondary)

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: record.statusSymbol)
                    Text(record.displayStatus)
                }
                .font(AdminType.caption2Bold)
                .foregroundStyle(record.statusTone)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(record.statusTone.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 0) {
                ForEach(0..<stages.count, id: \.self) { i in
                    let item = stages[i]
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(item.isCurrent ? record.statusTone : (item.isDone ? FulfillmentTokens.emerald : FulfillmentTokens.surfaceSecondary))
                                .frame(width: 32, height: 32)

                            Image(systemName: item.isDone ? "checkmark" : item.symbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(item.isCurrent || item.isDone ? .white : FulfillmentTokens.inkTertiary)
                        }
                        .overlay(
                            item.isCurrent ? Circle().stroke(record.statusTone.opacity(0.3), lineWidth: 5) : nil
                        )

                        Text(item.title)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(item.isCurrent ? FulfillmentTokens.inkPrimary : FulfillmentTokens.inkSecondary)
                    }

                    if i < stages.count - 1 {
                        Rectangle()
                            .fill(item.isDone ? FulfillmentTokens.emerald : FulfillmentTokens.hairline)
                            .frame(height: 2)
                            .padding(.bottom, 22)
                    }
                }
            }
        }
        .padding(18)
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous).stroke(FulfillmentTokens.hairline))
    }

    // 2. Financial Ledger Matrix
    private var financialSettlementMatrix: some View {
        VStack(spacing: 12) {
            HStack {
                Label(Language.get("Fulfillment_DetailSettlement", alter: "التسوية المالية"), systemImage: "banknote.fill")
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(FulfillmentTokens.inkPrimary)
                Spacer()
                Text(record.currency)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(FulfillmentTokens.inkTertiary)
            }

            Divider().background(FulfillmentTokens.hairline)

            HStack {
                DossierLedgerRow(title: "الإجمالي الفرعي", value: String(format: "%.2f", record.subtotal))
                Spacer()
                DossierLedgerRow(title: "عمولة المنصة", value: String(format: "%.2f", record.platformCommission))
            }

            HStack {
                DossierLedgerRow(title: "رسوم التوصيل", value: String(format: "%.2f", record.deliveryFee))
                Spacer()
                DossierLedgerRow(title: "صافي المتجر", value: String(format: "%.2f", record.providerNet), isBold: true)
            }
        }
        .padding(16)
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous).stroke(FulfillmentTokens.hairline))
    }

    // 3. Customer Blueprint Card
    private var customerBlueprintCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Language.get("Fulfillment_DetailCustomer", alter: "بيانات العميل"), systemImage: "person.fill")
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(FulfillmentTokens.inkPrimary)
                Spacer()
                Text(record.customerID.prefix(8).uppercased())
                    .font(AdminType.caption2)
                    .foregroundStyle(FulfillmentTokens.inkTertiary)
            }

            Divider().background(FulfillmentTokens.hairline)

            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(FulfillmentTokens.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.customerName)
                        .font(AdminType.headline)
                        .foregroundStyle(FulfillmentTokens.inkPrimary)

                    if let phone = record.customerPhone, !phone.isEmpty {
                        Text(phone)
                            .font(AdminType.caption1)
                            .foregroundStyle(FulfillmentTokens.inkSecondary)
                    }
                }

                Spacer()

                if let phone = record.customerPhone, let url = URL(string: "tel://\(phone)"), !phone.isEmpty {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Image(systemName: "phone.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(FulfillmentTokens.emerald)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous).stroke(FulfillmentTokens.hairline))
    }

    // 4. Product Manifest Card
    private var productManifestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Language.get("Fulfillment_DetailItems", alter: "محتويات وعناصر الطلب"), systemImage: "list.bullet.rectangle.portrait.fill")
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(FulfillmentTokens.inkPrimary)
                Spacer()
                Text("\(record.items.count) \(Language.get("Fulfillment_Items", alter: "عناصر"))")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(FulfillmentTokens.inkTertiary)
            }

            Divider().background(FulfillmentTokens.hairline)

            VStack(spacing: 10) {
                ForEach(record.items) { item in
                    HStack(spacing: 12) {
                        if let url = item.imageURL {
                            AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 44, height: 44)) {
                                Image(systemName: "shippingbox")
                                    .font(.system(size: 16))
                                    .foregroundStyle(FulfillmentTokens.inkTertiary)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(FulfillmentTokens.inkTertiary)
                                .frame(width: 44, height: 44)
                                .background(FulfillmentTokens.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(AdminType.subheadlineBold)
                                .foregroundStyle(FulfillmentTokens.inkPrimary)
                                .lineLimit(2)

                            if let opts = item.variantOptions {
                                Text(opts)
                                    .font(AdminType.caption2)
                                    .foregroundStyle(FulfillmentTokens.inkTertiary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.2f %@", item.totalPrice, Language.get("Currency_QAR", alter: "ر.ق")))
                                .font(AdminType.subheadlineBold)
                                .foregroundStyle(FulfillmentTokens.inkPrimary)
                                .monospacedDigit()

                            Text("×\(item.quantity)")
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(FulfillmentTokens.inkSecondary)
                        }
                    }
                    .padding(8)
                    .background(FulfillmentTokens.surfaceSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous).stroke(FulfillmentTokens.hairline))
    }

    // 5. Delivery & Logistics Card
    private var deliveryCourierCard: some View {
        let isDeliveryActive = record.status == "delivery_requested" ||
                              record.status == "delivery_assigned" ||
                              record.status == "awaiting_handover" ||
                              record.status == "handed_over" ||
                              record.status == "in_transit" ||
                              record.status == "delivered"

        let deliveryModeDisplay: String = {
            if record.deliveryMode == "pickup" {
                return Language.get("Fulfillment_Delivery_Mode_Pickup", alter: "استلام من المتجر")
            } else {
                return Language.get("Fulfillment_Delivery_Mode_Company", alter: "أسطول التوصيل")
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Language.get("Fulfillment_Section_Logistics", alter: "بيانات التنفيذ والشحن"), systemImage: "box.truck.fill")
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(FulfillmentTokens.inkPrimary)
                Spacer()

                if isDeliveryActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(record.statusTone)
                            .frame(width: 6, height: 6)
                        Text(record.displayStatus)
                    }
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(record.statusTone)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(record.statusTone.opacity(0.12), in: Capsule())
                } else {
                    Text(deliveryModeDisplay)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(FulfillmentTokens.indigo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FulfillmentTokens.indigoSoft, in: Capsule())
                }
            }

            Divider().background(FulfillmentTokens.hairline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Fulfillment_DetailOwner", alter: "التنفيذ بواسطة"))
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkTertiary)
                    Text(record.storeName)
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(FulfillmentTokens.inkPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(Language.get("Fulfillment_DetailMode", alter: "نوع التنفيذ"))
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkTertiary)
                    Text(record.isPlatformOwned ? Language.get("Fulfillment_Mode_Platform", alter: "تنفيذ المنصة") : Language.get("Fulfillment_Mode_Partner", alter: "متجر شريك"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(FulfillmentTokens.primary)
                }
            }

            if isDeliveryActive {
                Divider().background(FulfillmentTokens.hairline)

                HStack {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(record.statusTone)

                    Text(record.displayStatus)
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkSecondary)

                    Spacer()

                    Text(deliveryModeDisplay)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(FulfillmentTokens.inkTertiary)
                }
            }
        }
        .padding(16)
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous).stroke(FulfillmentTokens.hairline))
    }

    // 6. Real-time Audit Timeline Stream
    private var auditTimelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Language.get("Fulfillment_DetailTimeline", alter: "سجل حركات وتدقيق الطلب"), systemImage: "clock.arrow.circlepath")
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(FulfillmentTokens.inkPrimary)

                Spacer()

                if isLoadingEvents {
                    ProgressView().scaleEffect(0.8)
                }
            }

            Divider().background(FulfillmentTokens.hairline)

            if events.isEmpty && !isLoadingEvents {
                Text(Language.get("Fulfillment_NoEvents", alter: "لم تسجل أي حركات إضافية بعد"))
                    .font(AdminType.caption1)
                    .foregroundStyle(FulfillmentTokens.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(events) { ev in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(FulfillmentTokens.primary)
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(ev.eventType)
                                        .font(AdminType.captionBold)
                                        .foregroundStyle(FulfillmentTokens.inkPrimary)

                                    Spacer()

                                    if let date = ev.timestamp {
                                        Text(date.formatted(date: .omitted, time: .shortened))
                                            .font(AdminType.caption2)
                                            .foregroundStyle(FulfillmentTokens.inkTertiary)
                                    }
                                }

                                if let note = ev.note, !note.isEmpty {
                                    Text(note)
                                        .font(AdminType.caption2)
                                        .foregroundStyle(FulfillmentTokens.inkSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous).stroke(FulfillmentTokens.hairline))
    }

    // 7. Sticky Command Dock
    private var stickyCommandDock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Next Quick Action Button
                if let action = record.nextQuickAction {
                    Button {
                        onQuickAdvance(record, action.targetStatus)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: action.symbol)
                            Text(action.title)
                        }
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(record.statusTone, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: record.statusTone.opacity(0.35), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                }

                // Open Parent Order in Payments
                if !record.parentOrderID.isEmpty {
                    Button {
                        onOpenParentOrder(record.parentOrderID)
                    } label: {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(FulfillmentTokens.inkPrimary)
                            .frame(width: 50, height: 50)
                            .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FulfillmentTokens.hairline))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Fulfillment_View_Parent_Order", alter: "فتح الطلب في المدفوعات"))
                }
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(
            FulfillmentTokens.canvas
                .opacity(0.95)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // Event listener logic
    private func startListeningEvents() {
        isLoadingEvents = true
        eventsListener = PPFulfillmentService.shared().observeFulfillmentEvents(record.id) { rawEvents, _ in
            Task { @MainActor in
                self.isLoadingEvents = false
                var list: [FulfillmentEventSnapshot] = []
                for (idx, dict) in (rawEvents ?? []).enumerated() {
                    let stringDict = (dict as? [String: Any]) ?? [:]
                    let docID = stringDict["id"] as? String ?? "\(idx)"
                    list.append(FulfillmentEventSnapshot(dict: stringDict, docID: docID))
                }
                self.events = list
            }
        }
    }

    private func stopListeningEvents() {
        if let reg = eventsListener as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(reg)
        }
        eventsListener = nil
    }
}

private struct DossierLedgerRow: View {
    let title: String
    let value: String
    var isBold: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AdminType.caption2)
                .foregroundStyle(FulfillmentTokens.inkTertiary)
            Text(value)
                .font(isBold ? AdminType.headline : AdminType.subheadlineBold)
                .foregroundStyle(isBold ? FulfillmentTokens.primary : FulfillmentTokens.inkPrimary)
                .monospacedDigit()
        }
    }
}

// MARK: - Subviews: Sovereign Admin Fulfillment Override Terminal

struct FulfillmentOverrideView: View {
    let record: FulfillmentRecordSnapshot
    var isPushMode: Bool = true
    var onDismiss: () -> Void
    /// The first argument is the server-reconciled status that must be used as
    /// the callable's optimistic-concurrency precondition.
    var onCommit: (String, String, String, String?, Bool, @escaping @Sendable (FulfillmentOverrideCommitResult) -> Void) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var targetStatus: String = ""
    @State private var reason: String = ""
    @State private var internalNote: String = ""
    @State private var notifyCustomer: Bool = true
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @State private var hasCopiedRef: Bool = false
    @State private var showDestructiveConfirmation: Bool = false
    @State private var refreshedRecord: FulfillmentRecordSnapshot?
    @State private var isRefreshingLiveRecord: Bool = false
    @State private var requiresLiveRecordRefresh: Bool = false
    @FocusState private var isReasonFocused: Bool

    private var currentRecord: FulfillmentRecordSnapshot {
        refreshedRecord ?? record
    }

    private var allowedTargets: [String] {
        PPFulfillmentService.allowedOverrideTargets(forStatus: currentRecord.status)
    }

    private var selectedTargetMeta: (title: String, desc: String, symbol: String, tone: Color, isDestructive: Bool) {
        statusMeta(for: targetStatus)
    }

    private var currentStatusMeta: (title: String, desc: String, symbol: String, tone: Color, isDestructive: Bool) {
        statusMeta(for: currentRecord.status)
    }

    private var isCommitValid: Bool {
        !targetStatus.isEmpty &&
        !allowedTargets.isEmpty &&
        reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
        !isSubmitting &&
        !isRefreshingLiveRecord &&
        !requiresLiveRecordRefresh
    }

    private var statusBarHeight: CGFloat {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return max(window.safeAreaInsets.top, 44)
        }
        return 47
    }

    var body: some View {
        ZStack {
            FulfillmentTokens.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                // Adaptive Header
                if isPushMode {
                    sovereignPushHeader
                } else {
                    sovereignSheetHeader
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        // 1. Operator Authority & Sovereign Security Filament
                        operatorSecurityFilamentCard

                        // 2. State Machine Circuit (Dynamic Before -> Target Hologram)
                        stateTransitionCircuitCard

                        // 3. Standardized Operational Rationale Studio
                        operationalRationaleStudioCard

                        // 4. Customer Notification Broadcast & Live Blueprint
                        customerNotificationBlueprintCard

                        // 5. Operational Impact Breakdown
                        operationalImpactBreakdownCard

                        // 6. Diagnostic Error Recovery Box
                        if let err = errorMessage {
                            errorDiagnosticCard(err)
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 14)
                    .padding(.bottom, 150)
                }
            }

            // Floating Glass Safe-Action Pedestal
            safeActionPedestalDock
        }
        .navigationBarHidden(true)
        .ignoresSafeArea(.container, edges: isPushMode ? .top : [])
        .onAppear {
            if targetStatus.isEmpty {
                if let safeTarget = allowedTargets.first(where: { !statusMeta(for: $0).isDestructive }) {
                    targetStatus = safeTarget
                }
            }
        }
        .alert(
            Language.get("Fulfillment_Override_Destructive_Alert_Title", alter: "تأكيد الإجراء الحساس"),
            isPresented: $showDestructiveConfirmation
        ) {
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
            Button(Language.get("Confirm", alter: "تأكيد"), role: .destructive) {
                executeCommit()
            }
        } message: {
            Text(String(
                format: Language.get("Fulfillment_Override_Destructive_Alert_Msg", alter: "أنت على وشك تحويل الطلب إلى حالة حساسة (%@). هل تؤكد المتابعة؟"),
                selectedTargetMeta.title
            ))
        }
    }

    // MARK: - Headers

    private var sovereignPushHeader: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Fulfillment_Override_Terminal_Title", alter: "تعديل مسار التنفيذ الإداري"),
            subtitle: Language.get("Fulfillment_Override_Terminal_Subtitle", alter: "التدخل التشغيلي والتعافي السحابي • Pure Pets"),
            statusDotColor: FulfillmentTokens.crimson,
            onBack: {
                onDismiss()
                dismiss()
            }
        )
        .padding(.top, isPushMode ? statusBarHeight : 0)
    }

    private var sovereignSheetHeader: some View {
        HStack(alignment: .center) {
            Button {
                onDismiss()
                dismiss()
            } label: {
                Text(Language.get("Cancel", alter: "إلغاء"))
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(FulfillmentTokens.crimson)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(FulfillmentTokens.crimsonSoft, in: Capsule())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(Language.get("Fulfillment_Override_Terminal_Title", alter: "تعديل مسار التنفيذ الإداري"))
                    .font(AdminType.headline)
                    .foregroundStyle(FulfillmentTokens.inkPrimary)
                Text(currentRecord.parentOrderNumber)
                    .font(AdminType.caption2)
                    .foregroundStyle(FulfillmentTokens.inkTertiary)
                    .monospacedDigit()
            }

            Spacer()

            Color.clear
                .frame(width: 54, height: 32)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, 14)
        .background(AdminSurface.surface)
        .overlay(Divider().background(FulfillmentTokens.hairline), alignment: .bottom)
    }

    // MARK: - 1. Operator Authority & Sovereign Security Filament

    private var operatorSecurityFilamentCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FulfillmentTokens.crimson)
                    Text(Language.get("Fulfillment_Override_Operator_Role", alter: "المسؤول التشغيلي"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(FulfillmentTokens.crimson)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(FulfillmentTokens.crimsonSoft, in: Capsule())

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(FulfillmentTokens.emerald)
                        .frame(width: 6, height: 6)
                    Text(Language.get("Fulfillment_Override_Security_Banner", alter: "تدخل سيادي موثق • تدقيق أمني 256-bit"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(FulfillmentTokens.inkSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(FulfillmentTokens.surfaceSecondary, in: Capsule())
            }

            Divider().background(FulfillmentTokens.hairline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("Fulfillment_Ref", alter: "مرجع التنفيذ"))
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkTertiary)

                    Button {
                        UIPasteboard.general.string = currentRecord.parentOrderNumber
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation { hasCopiedRef = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { hasCopiedRef = false }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentRecord.parentOrderNumber)
                                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                                .foregroundStyle(FulfillmentTokens.inkPrimary)
                            Image(systemName: hasCopiedRef ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(hasCopiedRef ? FulfillmentTokens.emerald : FulfillmentTokens.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(currentRecord.customerName)
                            .font(AdminType.captionBold)
                            .foregroundStyle(FulfillmentTokens.inkPrimary)
                            .lineLimit(1)
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(FulfillmentTokens.primary)
                    }

                    HStack(spacing: 5) {
                        Text(currentRecord.storeName)
                            .font(AdminType.caption2)
                            .foregroundStyle(FulfillmentTokens.inkSecondary)
                            .lineLimit(1)
                        Image(systemName: currentRecord.isPlatformOwned ? "building.2.fill" : "storefront.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(currentRecord.isPlatformOwned ? FulfillmentTokens.indigo : FulfillmentTokens.amber)
                    }
                }
            }
        }
        .padding(16)
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous)
                .stroke(FulfillmentTokens.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    // MARK: - 2. State Machine Circuit (Dynamic Before -> Target Hologram)

    private var stateTransitionCircuitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FulfillmentTokens.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Fulfillment_Override_Circuit_Title", alter: "مخطط مسار الحالة التشغيلية"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(FulfillmentTokens.inkPrimary)
                    Text(Language.get("Fulfillment_Override_Circuit_Subtitle", alter: "الانتقال المباشر من الحالة الراهنة إلى المرحلة المستهدفة"))
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkSecondary)
                }
            }

            // Holographic Bridge Row
            HStack(spacing: 12) {
                // Current State
                VStack(spacing: 6) {
                    Text(Language.get("Fulfillment_Override_Current_State", alter: "الحالة الراهنة"))
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkTertiary)

                    HStack(spacing: 6) {
                        Image(systemName: currentStatusMeta.symbol)
                            .font(.system(size: 12, weight: .bold))
                        Text(currentStatusMeta.title)
                            .font(AdminType.captionBold)
                    }
                    .foregroundStyle(currentStatusMeta.tone)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(currentStatusMeta.tone.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(currentStatusMeta.tone.opacity(0.3), lineWidth: 0.8))
                }
                .frame(maxWidth: .infinity)

                // Pulse Transition Beam
                VStack(spacing: 3) {
                    Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(selectedTargetMeta.tone)

                    Text("OVERRIDE")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(FulfillmentTokens.inkTertiary)
                }
                .padding(.horizontal, 4)

                // Target State
                VStack(spacing: 6) {
                    Text(Language.get("Fulfillment_Override_Target_State", alter: "الحالة المستهدفة"))
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkTertiary)

                    if targetStatus.isEmpty {
                        Text(Language.get("Fulfillment_Override_Select_Target_Prompt", alter: "اختر الحالة"))
                            .font(AdminType.captionBold)
                            .foregroundStyle(FulfillmentTokens.inkTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(FulfillmentTokens.surfaceSecondary, in: Capsule())
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: selectedTargetMeta.symbol)
                                .font(.system(size: 12, weight: .bold))
                            Text(selectedTargetMeta.title)
                                .font(AdminType.captionBold)
                        }
                        .foregroundStyle(selectedTargetMeta.tone)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selectedTargetMeta.tone.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(selectedTargetMeta.tone.opacity(0.4), lineWidth: 1))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(FulfillmentTokens.surfaceSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Target Options Grid
            if allowedTargets.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(FulfillmentTokens.neutral)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Fulfillment_Override_No_Targets_Title", alter: "حالة نهائية مقفلة"))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(FulfillmentTokens.inkPrimary)
                        Text(Language.get("Fulfillment_Override_No_Targets_Desc", alter: "وصل هذا الطلب إلى حالة نهائية أو مسار تسليم نشط لا يقبل التعديل الإداري المباشر منعاً للتضارب المالي وحماية لسجلات الأسطول."))
                            .font(AdminType.caption)
                            .foregroundStyle(FulfillmentTokens.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .background(FulfillmentTokens.neutralSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FulfillmentTokens.neutral.opacity(0.3), lineWidth: 1))
            } else {
                VStack(spacing: 8) {
                    ForEach(allowedTargets, id: \.self) { statusKey in
                        let meta = statusMeta(for: statusKey)
                        let isSelected = targetStatus == statusKey

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                targetStatus = statusKey
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: meta.symbol)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(meta.tone)
                                    .frame(width: 38, height: 38)
                                    .background(meta.tone.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(meta.title)
                                            .font(AdminType.subheadlineBold)
                                            .foregroundStyle(FulfillmentTokens.inkPrimary)

                                        if meta.isDestructive {
                                            HStack(spacing: 3) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                Text(Language.get("HighRisk", alter: "حساس"))
                                            }
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(FulfillmentTokens.crimson)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(FulfillmentTokens.crimsonSoft, in: Capsule())
                                        }
                                    }

                                    Text(meta.desc)
                                        .font(AdminType.caption2)
                                        .foregroundStyle(FulfillmentTokens.inkSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                ZStack {
                                    Circle()
                                        .stroke(isSelected ? meta.tone : FulfillmentTokens.hairline, lineWidth: isSelected ? 2 : 1.5)
                                        .frame(width: 20, height: 20)

                                    if isSelected {
                                        Circle()
                                            .fill(meta.tone)
                                            .frame(width: 10, height: 10)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                isSelected ? meta.tone.opacity(0.06) : FulfillmentTokens.surface,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isSelected ? meta.tone.opacity(0.5) : FulfillmentTokens.hairline, lineWidth: isSelected ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous)
                .stroke(FulfillmentTokens.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    // MARK: - 3. Standardized Operational Rationale Studio

    private var operationalRationaleStudioCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "signature")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FulfillmentTokens.indigo)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(Language.get("Fulfillment_Override_Reason_Section", alter: "سبب التدخل والرقابة الإدارية"))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(FulfillmentTokens.inkPrimary)
                        Text("*")
                            .font(AdminType.headline)
                            .foregroundStyle(FulfillmentTokens.crimson)
                    }

                    Text(Language.get("Fulfillment_Override_Reason_Section_Sub", alter: "وثيقة إلزامية تسجل في سجل العمليات السيادية"))
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkSecondary)
                }
            }

            // Quick Preset Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let presets = [
                        Language.get("Fulfillment_Override_Preset_Driver", alter: "تعذر التواصل مع السائق"),
                        Language.get("Fulfillment_Override_Preset_Stock", alter: "نفاد المخزون لدى المزود"),
                        Language.get("Fulfillment_Override_Preset_Customer", alter: "طلب مباشر من العميل"),
                        Language.get("Fulfillment_Override_Preset_Delay", alter: "تأخر في التحضير التشغيلي"),
                        Language.get("Fulfillment_Override_Preset_Address", alter: "تصحيح العنوان والمنطقة"),
                        Language.get("Fulfillment_Override_Preset_Reschedule", alter: "إعادة جدولة الاستلام")
                    ]

                    ForEach(presets, id: \.self) { preset in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if reason.isEmpty {
                                reason = preset
                            } else if !reason.contains(preset) {
                                reason = "\(reason) - \(preset)"
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 10))
                                Text(preset)
                                    .font(AdminType.caption2Bold)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(FulfillmentTokens.primarySoft, in: Capsule())
                            .foregroundStyle(FulfillmentTokens.primary)
                            .overlay(Capsule().stroke(FulfillmentTokens.primary.opacity(0.3), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }

            // Multiline Editor Container
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if reason.isEmpty {
                        Text(Language.get("Fulfillment_Override_Reason_Placeholder", alter: "اكتب سبب التعديل بالتفصيل للتدقيق الأمني والعمليات..."))
                            .font(AdminType.subheadline)
                            .foregroundStyle(FulfillmentTokens.inkTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $reason)
                        .font(AdminType.subheadline)
                        .focused($isReasonFocused)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color.clear)
                        .onChange(of: reason) { val in
                            if val.count > 256 {
                                reason = String(val.prefix(256))
                            }
                        }
                }
                .background(FulfillmentTokens.surfaceSecondary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isReasonFocused ? FulfillmentTokens.primary : FulfillmentTokens.hairline, lineWidth: isReasonFocused ? 1.5 : 1)
                )

                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 ? FulfillmentTokens.emerald : FulfillmentTokens.amber)

                        Text(reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
                             ? Language.get("ValidReason", alter: "السبب مكتمل وموثق")
                             : Language.get("ReasonRequired", alter: "مطلوب لتجاوز فحص التدقيق"))
                            .font(AdminType.caption2)
                            .foregroundStyle(reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 ? FulfillmentTokens.emerald : FulfillmentTokens.inkTertiary)
                    }

                    Spacer()

                    Text("\(reason.count) / 256")
                        .font(AdminType.caption2)
                        .foregroundStyle(reason.count > 240 ? FulfillmentTokens.crimson : FulfillmentTokens.inkTertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 4)
            }

            Divider().background(FulfillmentTokens.hairline)

            // Optional Internal Ops Notes
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Fulfillment_Override_Notes_Section", alter: "ملاحظات تشغيلية داخلية للمناوبة (اختياري)"))
                    .font(AdminType.captionBold)
                    .foregroundStyle(FulfillmentTokens.inkSecondary)

                TextField(
                    Language.get("Fulfillment_Override_Notes_Placeholder", alter: "أي تفاصيل داخلية لفريق العمليات والمناوبة القادمة..."),
                    text: $internalNote
                )
                .font(AdminType.subheadline)
                .padding(10)
                .background(FulfillmentTokens.surfaceSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FulfillmentTokens.hairline, lineWidth: 1))
            }
        }
        .padding(16)
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous)
                .stroke(FulfillmentTokens.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    // MARK: - 4. Customer Notification Broadcast & Live Blueprint

    private var customerNotificationBlueprintCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FulfillmentTokens.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Fulfillment_Override_Notify_Title", alter: "إشعار العميل بالتعديل"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(FulfillmentTokens.inkPrimary)
                    Text(Language.get("Fulfillment_Override_Notify_Sub", alter: "إرسال إشعار فوري وتحديث مسار التتبع في تطبيق العميل"))
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkSecondary)
                }

                Spacer()

                Toggle("", isOn: $notifyCustomer)
                    .labelsHidden()
                    .tint(FulfillmentTokens.primary)
            }

            if notifyCustomer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 11))
                        Text(Language.get("Fulfillment_Override_Simulated_Notification_Title", alter: "معاينة الإشعار الفوري للعميل"))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundStyle(FulfillmentTokens.primary)

                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(colors: [FulfillmentTokens.primary, Color(red: 1.0, green: 0.3, blue: 0.43)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 32, height: 32)
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Pure Pets")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(FulfillmentTokens.inkPrimary)
                                Spacer()
                                Text(Language.get("Time_JustNow", alter: "الآن"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(FulfillmentTokens.inkTertiary)
                            }

                            Text(String(
                                format: Language.get("Fulfillment_Override_Simulated_Notification_Body", alter: "تحديث على طلبك: تم تعديل مسار طلبك [%@] إلى [%@] من قبل إدارة العمليات."),
                                currentRecord.parentOrderNumber,
                                selectedTargetMeta.title
                            ))
                            .font(.system(size: 12))
                            .foregroundStyle(FulfillmentTokens.inkSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
                }
                .padding(12)
                .background(FulfillmentTokens.primarySoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(FulfillmentTokens.amber)
                    Text(Language.get("Fulfillment_Override_Notify_Off_Notice", alter: "تنبيه: لن يتم إرسال أي إشعار للعميل، سيتغير المسار داخلياً فقط."))
                        .font(AdminType.caption2)
                        .foregroundStyle(FulfillmentTokens.inkSecondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FulfillmentTokens.amberSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous)
                .stroke(FulfillmentTokens.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    // MARK: - 5. Operational Impact Breakdown

    private var operationalImpactBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FulfillmentTokens.inkTertiary)
                Text(Language.get("Fulfillment_Override_Impact_Title", alter: "الآثار التشغيلية لهذا الإجراء"))
                    .font(AdminType.captionBold)
                    .foregroundStyle(FulfillmentTokens.inkSecondary)
            }

            VStack(spacing: 6) {
                impactRow(icon: "doc.badge.gearshape.fill", text: Language.get("Fulfillment_Override_Impact_1", alter: "تحديث وثيقة التنفيذ السحابية (FulfillmentOrders)"))
                impactRow(icon: "lock.doc.fill", text: Language.get("Fulfillment_Override_Impact_2", alter: "تسجيل حدث تدقيق أمني غير قابل للتعديل (AuditLogs)"))
                impactRow(icon: "arrow.triangle.2.circlepath.circle.fill", text: Language.get("Fulfillment_Override_Impact_3", alter: "إعادة احتساب وتزامن ملخص الطلب الأب (Orders)"))
            }
        }
        .padding(14)
        .background(FulfillmentTokens.surfaceSecondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func impactRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(FulfillmentTokens.primary)
            Text(text)
                .font(AdminType.caption2)
                .foregroundStyle(FulfillmentTokens.inkSecondary)
            Spacer()
        }
    }

    // MARK: - 6. Error Diagnostic Box

    private func errorDiagnosticCard(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 20))
                .foregroundStyle(FulfillmentTokens.crimson)

            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("Error", alter: "تعذر تنفيذ العملية"))
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(FulfillmentTokens.crimson)
                Text(error)
                    .font(AdminType.caption)
                    .foregroundStyle(FulfillmentTokens.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if requiresLiveRecordRefresh {
                    Divider()
                        .padding(.vertical, 4)

                    if isRefreshingLiveRecord {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(FulfillmentTokens.primary)
                            Text(Language.get("Fulfillment_Override_ConflictReloading", alter: "جارٍ تحديث حالة التنفيذ المباشرة…"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(FulfillmentTokens.inkSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Button(action: refreshLiveRecordAfterConflict) {
                            Label(
                                Language.get("Fulfillment_Override_ConflictRetry", alter: "تحديث الحالة المباشرة"),
                                systemImage: "arrow.clockwise.circle.fill"
                            )
                            .font(AdminType.captionBold)
                            .foregroundStyle(FulfillmentTokens.primary)
                            .frame(minHeight: FulfillmentTokens.touchTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Language.get("Fulfillment_Override_ConflictRetry_Hint", alter: "يجلب الحالة الحالية من الخادم قبل السماح بمحاولة جديدة"))
                    }
                }
            }
            Spacer()
        }
        .padding(14)
        .background(FulfillmentTokens.crimsonSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FulfillmentTokens.crimson.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Floating Safe-Action Pedestal Dock

    private var safeActionPedestalDock: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                if !isCommitValid {
                    HStack(spacing: 6) {
                        Image(systemName: targetStatus.isEmpty ? "arrow.triangle.branch" : "pencil.line")
                            .font(.system(size: 11, weight: .semibold))
                        Text(targetStatus.isEmpty
                             ? Language.get("Fulfillment_Override_Hint_Select_Target", alter: "يرجى تحديد المرحلة المستهدفة للمتابعة")
                             : (reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
                                ? Language.get("Fulfillment_Override_Hint_Enter_Reason", alter: "يرجى كتابة سبب التعديل (3 أحرف على الأقل) للاعتماد")
                                : ""))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundStyle(FulfillmentTokens.inkTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(FulfillmentTokens.surfaceSecondary, in: Capsule())
                    .transition(.opacity)
                }

                Button {
                    if selectedTargetMeta.isDestructive {
                        showDestructiveConfirmation = true
                    } else {
                        executeCommit()
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: targetStatus.isEmpty ? "arrow.triangle.branch" : selectedTargetMeta.symbol)
                                .font(.system(size: 16, weight: .bold))

                            VStack(spacing: 2) {
                                Text(Language.get("Fulfillment_Override_Submit_CTA", alter: "تأكيد وتطبيق التعديل الإداري"))
                                    .font(AdminType.subheadlineBold)

                                Text(Language.get("Fulfillment_Override_Submit_Sub", alter: "اعتماد فوري مع توثيق الرقابة"))
                                    .font(.system(size: 10, weight: .medium))
                                    .opacity(0.85)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        isCommitValid
                            ? (selectedTargetMeta.isDestructive
                               ? LinearGradient(colors: [FulfillmentTokens.crimson, Color(red: 0.8, green: 0.15, blue: 0.15)], startPoint: .leading, endPoint: .trailing)
                               : LinearGradient(colors: [FulfillmentTokens.primary, Color(red: 1.0, green: 0.3, blue: 0.43)], startPoint: .leading, endPoint: .trailing))
                            : LinearGradient(colors: [AdminSurface.control, AdminSurface.control], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .foregroundStyle(isCommitValid ? Color.white : AdminSurface.secondaryText)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isCommitValid ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                    )
                    .shadow(
                        color: isCommitValid
                            ? (selectedTargetMeta.isDestructive ? FulfillmentTokens.crimson.opacity(0.35) : FulfillmentTokens.primary.opacity(0.35))
                            : Color.clear,
                        radius: 8,
                        y: 3
                    )
                }
                .disabled(!isCommitValid)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(
                AdminSurface.surface
                    .shadow(color: Color.black.opacity(0.06), radius: 12, y: -4)
                    .ignoresSafeArea(edges: .bottom)
            )
            .overlay(
                Rectangle()
                    .fill(FulfillmentTokens.hairline)
                    .frame(height: 0.75),
                alignment: .top
            )
        }
    }

    private func executeCommit() {
        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanReason.isEmpty, !targetStatus.isEmpty, !requiresLiveRecordRefresh, !isRefreshingLiveRecord else { return }

        isSubmitting = true
        errorMessage = nil

        onCommit(currentRecord.status, targetStatus, cleanReason, internalNote.isEmpty ? nil : internalNote, notifyCustomer) { result in
            self.isSubmitting = false
            switch result {
            case .succeeded:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onDismiss()
                dismiss()
            case .conflict(let requiresLiveRecordReload):
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                if requiresLiveRecordReload {
                    beginLiveRecordConflictRecovery()
                } else {
                    errorMessage = Language.get("Fulfillment_OverrideConflict", alter: "تغيرت حالة التنفيذ قبل تطبيق هذا الأمر. راجع الحالة المباشرة قبل المحاولة مرة أخرى.")
                }
            case .denied:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = Language.get("Fulfillment_OverridePermissionDenied", alter: "ليس لديك صلاحية لتنفيذ هذا التعديل الإداري.")
            case .invalid:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = Language.get("Fulfillment_OverrideInvalid", alter: "لم يعد أمر التنفيذ صالحاً. راجع الحالة المختارة والمعلومات المطلوبة.")
            case .failed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = Language.get("Fulfillment_OverrideFailed", alter: "تعذر إكمال أمر التنفيذ. أبقِ هذا السجل مفتوحاً وتحقق من الحالة المباشرة قبل المحاولة مرة أخرى.")
            }
        }
    }

    private func beginLiveRecordConflictRecovery() {
        targetStatus = ""
        showDestructiveConfirmation = false
        requiresLiveRecordRefresh = true
        errorMessage = Language.get("Fulfillment_OverrideConflict", alter: "تغيرت حالة التنفيذ قبل تطبيق هذا الأمر. راجع الحالة المباشرة قبل المحاولة مرة أخرى.")
        refreshLiveRecordAfterConflict()
    }

    private func refreshLiveRecordAfterConflict() {
        guard requiresLiveRecordRefresh, !isRefreshingLiveRecord else { return }
        isRefreshingLiveRecord = true
        PPFulfillmentService.shared().refreshFulfillmentFromServer(record.id) { rawRecord, error in
            Task { @MainActor in
                self.isRefreshingLiveRecord = false
                guard error == nil, let rawRecord = rawRecord else {
                    self.errorMessage = Language.get("Fulfillment_Override_ConflictRefreshFailed", alter: "تعذر تحديث الحالة المباشرة. تحقق من الاتصال ثم حاول مرة أخرى.")
                    return
                }
                self.refreshedRecord = FulfillmentRecordSnapshot(record: rawRecord)
                self.requiresLiveRecordRefresh = false
                self.targetStatus = ""
                self.errorMessage = Language.get("Fulfillment_OverrideConflict", alter: "تغيرت حالة التنفيذ قبل تطبيق هذا الأمر. راجع الحالة المباشرة قبل المحاولة مرة أخرى.")
            }
        }
    }

    private func statusMeta(for statusKey: String) -> (title: String, desc: String, symbol: String, tone: Color, isDestructive: Bool) {
        switch statusKey {
        case "accepted":
            return (
                Language.get("Fulfillment_Status_Accepted", alter: "تم القبول"),
                Language.get("Fulfillment_Status_Accepted_Desc", alter: "قبول الطلب من المتجر والبدء في دورة التجهيز"),
                "hand.thumbsup.fill",
                FulfillmentTokens.blue,
                false
            )
        case "preparing", "processing", "in_progress":
            return (
                Language.get("Fulfillment_Status_Preparing", alter: "قيد التجهيز"),
                Language.get("Fulfillment_Status_Preparing_Desc", alter: "الطلب قيد التجهيز والتغليف في مستودع المتجر"),
                "gearshape.2.fill",
                FulfillmentTokens.blue,
                false
            )
        case "ready_for_pickup":
            return (
                Language.get("Fulfillment_Status_ReadyForPickup", alter: "جاهز للاستلام"),
                Language.get("Fulfillment_Status_ReadyForPickup_Desc", alter: "اكتمال التجهيز وبانتظار وصول مندوب التوصيل"),
                "shippingbox.fill",
                FulfillmentTokens.indigo,
                false
            )
        case "delivery_requested":
            return (
                Language.get("Fulfillment_Status_DeliveryRequested", alter: "تم طلب التوصيل"),
                Language.get("Fulfillment_Status_DeliveryRequested_Desc", alter: "تم إرسال طلب استدعاء لأسطول التوصيل المعتمد"),
                "person.badge.shield.checkmark.fill",
                FulfillmentTokens.indigo,
                false
            )
        case "delivery_assigned":
            return (
                Language.get("Fulfillment_Status_DeliveryAssigned", alter: "تم تعيين مندوب"),
                Language.get("Fulfillment_Status_DeliveryAssigned_Desc", alter: "تم تعيين مندوب توصيل لاستلام الشحنة"),
                "person.badge.shield.checkmark.fill",
                Color.purple,
                false
            )
        case "awaiting_handover":
            return (
                Language.get("Fulfillment_Status_AwaitingHandover", alter: "بانتظار التسليم"),
                Language.get("Fulfillment_Status_AwaitingHandover_Desc", alter: "المندوب وصل للمتجر وبانتظار تسليم البضاعة"),
                "clock.badge.checkmark.fill",
                Color.purple,
                false
            )
        case "handed_over":
            return (
                Language.get("Fulfillment_Status_HandedOver", alter: "تم التسليم للمندوب"),
                Language.get("Fulfillment_Status_HandedOver_Desc", alter: "تم تسليم الشحنة للمندوب بنجاح وبدء الرحلة"),
                "shippingbox.and.arrow.backward.fill",
                Color.purple,
                false
            )
        case "in_transit":
            return (
                Language.get("Fulfillment_Status_InTransit", alter: "في الطريق للعميل"),
                Language.get("Fulfillment_Status_InTransit_Desc", alter: "الشحنة في الطريق إلى عنوان العميل النهائي"),
                "box.truck.badge.clock.fill",
                Color.purple,
                false
            )
        case "cancelled":
            return (
                Language.get("Fulfillment_Status_Cancelled", alter: "إلغاء الطلب"),
                Language.get("Fulfillment_Status_Cancelled_Desc", alter: "إلغاء التنفيذ بالكامل وإعادة احتساب الطلب الأب"),
                "xmark.octagon.fill",
                FulfillmentTokens.crimson,
                true
            )
        case "rejected":
            return (
                Language.get("Fulfillment_Status_Rejected", alter: "رفض الطلب"),
                Language.get("Fulfillment_Status_Rejected_Desc", alter: "رفض التنفيذ من قبل الإدارة مع إشعار المتجر"),
                "xmark.circle.fill",
                FulfillmentTokens.crimson,
                true
            )
        default:
            return (
                statusKey.replacingOccurrences(of: "_", with: " ").capitalized,
                Language.get("Fulfillment_Status_Generic_Desc", alter: "تحديث الحالة إلى هذه المرحلة التشغيلية"),
                "arrow.triangle.branch",
                FulfillmentTokens.primary,
                false
            )
        }
    }
}

// Backward-compatibility wrapper so existing modal call sites remain functional
private struct FulfillmentOverrideModal: View {
    let record: FulfillmentRecordSnapshot
    let onCommit: (String, String, String, String?, Bool, @escaping @Sendable (FulfillmentOverrideCommitResult) -> Void) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FulfillmentOverrideView(
            record: record,
            isPushMode: false,
            onDismiss: { dismiss() },
            onCommit: onCommit
        )
    }
}

// MARK: - Subviews: Filter & Sort Sheet

private struct FulfillmentFilterSheet: View {
    @Binding var selectedMode: String
    @Binding var onlyUrgent: Bool
    @Binding var sortOption: FulfillmentSortOption

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(Language.get("Fulfillment_Filter_Scope", alter: "نطاق التنفيذ والمتاجر"))) {
                    Picker(Language.get("Fulfillment_DetailOwner", alter: "الجهة المنفذة"), selection: $selectedMode) {
                        Text(Language.get("All", alter: "الكل")).tag("all")
                        Text(Language.get("Fulfillment_Mode_Platform", alter: "مستودع المنصة الرسمي")).tag("platform")
                        Text(Language.get("Fulfillment_Mode_Partner", alter: "المتاجر والشركاء")).tag("partner")
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text(Language.get("Fulfillment_Filter_Urgency", alter: "مستوى الإلحاح"))) {
                    Toggle(Language.get("Fulfillment_SLA_Urgent", alter: "الطلبات المتأخرة عن SLA فقط (> 30 دقيقة)"), isOn: $onlyUrgent)
                        .tint(FulfillmentTokens.crimson)
                }

                Section(header: Text(Language.get("Fulfillment_Sort_Title", alter: "ترتيب القائمة"))) {
                    Picker(Language.get("Fulfillment_Sort_Option", alter: "الترتيب حسب"), selection: $sortOption) {
                        ForEach(FulfillmentSortOption.allCases) { opt in
                            Text(opt.title).tag(opt)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    Button(Language.get("Reset", alter: "إعادة ضبط الفلاتر")) {
                        selectedMode = "all"
                        onlyUrgent = false
                        sortOption = .newest
                    }
                    .foregroundStyle(FulfillmentTokens.crimson)
                }
            }
            .navigationTitle(Language.get("Filter", alter: "خيارات التصفية والفرز"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Language.get("Done", alter: "تم")) {
                        dismiss()
                    }
                    .font(AdminType.subheadlineBold)
                }
            }
        }
    }
}

// MARK: - Shimmer Placeholder

private struct ShimmerCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(FulfillmentTokens.surfaceSecondary)
                    .frame(width: 120, height: 16)
                Spacer()
                RoundedRectangle(cornerRadius: 12)
                    .fill(FulfillmentTokens.surfaceSecondary)
                    .frame(width: 70, height: 22)
            }
            RoundedRectangle(cornerRadius: 6)
                .fill(FulfillmentTokens.surfaceSecondary)
                .frame(width: 200, height: 14)
            RoundedRectangle(cornerRadius: 6)
                .fill(FulfillmentTokens.surfaceSecondary)
                .frame(height: 34)
        }
        .padding(16)
        .background(FulfillmentTokens.surface, in: RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FulfillmentTokens.cornerCard, style: .continuous).stroke(FulfillmentTokens.hairline))
    }
}

// MARK: - Identifiable String Helper

private struct IdentifiableString: Identifiable {
    let id: String
}
