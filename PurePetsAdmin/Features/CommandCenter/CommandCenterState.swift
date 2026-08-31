import Combine
import Foundation
import OSLog

@MainActor
final class CommandCenterState: ObservableObject {
    private static let diagnosticLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.purepets.admin",
        category: "CommandCenterState"
    )

    enum Phase: Equatable {
        case idle
        case loading
        case loaded(AdminCommandSnapshot)
        case empty(AdminCommandSnapshot)
        case failed(AdminCommandSnapshot)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isRefreshing = false

    private var session: AdminSession
    private var requestID = UUID()

    init(session: AdminSession) {
        self.session = session
    }

    var snapshot: AdminCommandSnapshot? {
        guard case let .loaded(snapshot) = phase else { return nil }
        return snapshot
    }

    /// Returns the latest usable snapshot while a refresh, empty result, or
    /// recoverable failure is being represented by the owning state machine.
    /// Child workflow surfaces use this value to keep the operational context
    /// visible without creating a second listener or aggregate.
    var currentSnapshot: AdminCommandSnapshot? {
        switch phase {
        case let .loaded(snapshot), let .empty(snapshot), let .failed(snapshot):
            return snapshot
        case .idle, .loading:
            return nil
        }
    }

    func loadIfNeeded() {
        guard case .idle = phase else { return }
        load(retainingContent: false)
    }

    func refresh() {
        guard !isRefreshing else {
            Self.diagnosticLog.info("event=refresh.skip reason=in_flight request=\(self.requestID.uuidString, privacy: .public)")
            return
        }
        load(retainingContent: snapshot != nil)
    }

    func cancel() {
        guard isRefreshing else { return }
        let cancelledRequestID = requestID
        requestID = UUID()
        isRefreshing = false
        if case .loading = phase {
            phase = .idle
        }
        Self.diagnosticLog.notice("event=refresh.cancel request=\(cancelledRequestID.uuidString, privacy: .public)")
    }

    func updateSession(_ session: AdminSession) {
        guard self.session != session else { return }
        self.session = session
        phase = .idle
        load(retainingContent: false)
    }

    private func load(retainingContent: Bool) {
        let currentRequestID = UUID()
        requestID = currentRequestID
        isRefreshing = true
        if !retainingContent { phase = .loading }
        Self.diagnosticLog.info(
            "event=refresh.start request=\(currentRequestID.uuidString, privacy: .public) retainingContent=\(retainingContent, privacy: .public) permissionCount=\(self.session.permissions.count, privacy: .public)"
        )

        PPAdminCommandCenterService.shared().loadSnapshot(for: session.source) { [weak self] rawSnapshot in
            Task { @MainActor in
                guard let self else {
                    Self.diagnosticLog.notice("event=refresh.discard request=\(currentRequestID.uuidString, privacy: .public) reason=state_released trace=\(rawSnapshot.diagnosticTraceID, privacy: .public)")
                    return
                }
                guard self.requestID == currentRequestID else {
                    Self.diagnosticLog.notice("event=refresh.discard request=\(currentRequestID.uuidString, privacy: .public) reason=stale_callback trace=\(rawSnapshot.diagnosticTraceID, privacy: .public)")
                    return
                }
                let mapped = self.map(rawSnapshot)
                let allRequestedAreasFailed = !rawSnapshot.requestedAreas.isEmpty &&
                    rawSnapshot.requestedAreas.allSatisfy { rawSnapshot.failedAreas.contains($0) }
                if allRequestedAreasFailed {
                    self.phase = .failed(mapped)
                } else if rawSnapshot.requestedAreas.isEmpty || (!mapped.hasAvailableData && rawSnapshot.failedAreas.isEmpty) {
                    self.phase = .empty(mapped)
                } else {
                    self.phase = .loaded(mapped)
                }
                self.isRefreshing = false
                let requested = rawSnapshot.requestedAreas.joined(separator: ",")
                let failed = rawSnapshot.failedAreas.joined(separator: ",")
                let partial = rawSnapshot.partialAreas.joined(separator: ",")
                Self.diagnosticLog.log(
                    level: rawSnapshot.failedAreas.isEmpty ? .info : .error,
                    "event=refresh.finish request=\(currentRequestID.uuidString, privacy: .public) trace=\(rawSnapshot.diagnosticTraceID, privacy: .public) phase=\(self.diagnosticPhaseName, privacy: .public) requested=\(requested, privacy: .public) failed=\(failed, privacy: .public) partial=\(partial, privacy: .public)"
                )
            }
        }
    }

    private var diagnosticPhaseName: String {
        switch phase {
        case .idle: return "idle"
        case .loading: return "loading"
        case .loaded: return "loaded"
        case .empty: return "empty"
        case .failed: return "failed"
        }
    }

    private func map(_ raw: PPAdminCommandSnapshot) -> AdminCommandSnapshot {
        let activeOrders = available(raw.activeOrdersCount)
        let awaitingFulfillment = available(raw.awaitingFulfillmentCount)
        let activeDeliveries = available(raw.activeDeliveryCount)
        let pendingProviders = available(raw.pendingProviderApplicationCount)
        let areaOrder = ["payments", "fulfillment", "delivery", "providers", "listings", "users", "stock"]
        let failedAreas = areaOrder.filter { raw.failedAreas.contains($0) }
        let partialAreas = areaOrder.filter { raw.partialAreas.contains($0) }
        let degradedAreas = failedAreas + partialAreas.filter { !failedAreas.contains($0) }

        var attention: [AttentionItem] = []
        if let pendingProviders, pendingProviders > 0 {
            attention.append(AttentionItem(
                id: "providerApplications",
                domain: "providers",
                severity: .actionRequired,
                titleKey: "CommandCenter_Attention_Providers_Title",
                detailKey: "CommandCenter_Attention_Providers_Detail",
                count: pendingProviders,
                symbol: "person.badge.clock",
                route: .providerApplications,
                occurredAt: raw.generatedAt,
                entityID: nil,
                requiredPermissions: AdminRoute.providerApplications.requiredPermissions
            ))
        }
        if let awaitingFulfillment, awaitingFulfillment > 0 {
            attention.append(AttentionItem(
                id: "fulfillment",
                domain: "fulfillment",
                severity: .critical,
                titleKey: "CommandCenter_Attention_Fulfillment_Title",
                detailKey: "CommandCenter_Attention_Fulfillment_Detail",
                count: awaitingFulfillment,
                symbol: "shippingbox.and.arrow.backward",
                route: .fulfillment,
                occurredAt: raw.generatedAt,
                entityID: nil,
                requiredPermissions: AdminRoute.fulfillment.requiredPermissions
            ))
        }
        if let activeDeliveries, activeDeliveries > 0 {
            attention.append(AttentionItem(
                id: "delivery",
                domain: "delivery",
                severity: .watch,
                titleKey: "CommandCenter_Attention_Delivery_Title",
                detailKey: "CommandCenter_Attention_Delivery_Detail",
                count: activeDeliveries,
                symbol: "truck.box",
                route: .delivery,
                occurredAt: raw.generatedAt,
                entityID: nil,
                requiredPermissions: AdminRoute.delivery.requiredPermissions
            ))
        }
        if let activeOrders, activeOrders > 0 {
            attention.append(AttentionItem(
                id: "payments",
                domain: "payments",
                severity: .actionRequired,
                titleKey: "CommandCenter_Attention_Orders_Title",
                detailKey: "CommandCenter_Attention_Orders_Detail",
                count: activeOrders,
                symbol: "creditcard.and.123",
                route: .payments,
                occurredAt: raw.generatedAt,
                entityID: nil,
                requiredPermissions: AdminRoute.payments.requiredPermissions
            ))
        }
        attention.sort {
            if $0.severity != $1.severity { return $0.severity < $1.severity }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.id < $1.id
        }

        let health: OperationalHealth
        if !degradedAreas.isEmpty {
            health = .partial(degradedAreas.count)
        } else if attention.isEmpty {
            health = .stable
        } else {
            health = .attention(attention.reduce(0) { $0 + $1.count })
        }

        return AdminCommandSnapshot(
            generatedAt: raw.generatedAt,
            health: health,
            attentionItems: attention,
            operations: OperationsSnapshot(
                activeOrders: activeOrders,
                awaitingFulfillment: awaitingFulfillment,
                activeDeliveries: activeDeliveries,
                pendingProviderApplications: pendingProviders
            ),
            business: BusinessSnapshot(
                listings: available(raw.adsCount),
                users: available(raw.usersCount),
                accessories: available(raw.accessoriesCount)
            ),
            requestedAreas: raw.requestedAreas,
            failedAreas: failedAreas,
            partialAreas: partialAreas
        )
    }

    private func available(_ value: Int) -> Int? {
        value == NSNotFound ? nil : value
    }
}
