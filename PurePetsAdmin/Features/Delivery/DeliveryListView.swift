import SwiftUI
import FirebaseFirestore
import UIKit

extension PPDeliveryRequestRecord: @unchecked Sendable {}
extension PPDeliveryDriverRecord: @unchecked Sendable {}
extension PPDeliveryCompanyMemberRecord: @unchecked Sendable {}
extension PPDeliveryExceptionRecord: @unchecked Sendable {}
extension PPDeliveryAllowedAction: @unchecked Sendable {}
extension PPDeliveryCommandCenterSnapshot: @unchecked Sendable {}
extension PPDeliveryDossierSnapshot: @unchecked Sendable {}
extension PPDeliveryCommandResult: @unchecked Sendable {}

private func deliveryText(_ key: String) -> String {
    Language.get(key, alter: nil)
}

private func deliveryFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: deliveryText(key),
           locale: Locale(identifier: Language.currentLanguageCode() ?? "ar"),
           arguments: arguments)
}

private func deliveryDictionary(_ value: Any?) -> [String: Any] {
    if let value = value as? [String: Any] { return value }
    if let value = value as? [AnyHashable: Any] {
        return value.reduce(into: [:]) { result, element in
            if let key = element.key as? String { result[key] = element.value }
        }
    }
    if let value = value as? NSDictionary {
        return value.reduce(into: [:]) { result, element in
            if let key = element.key as? String { result[key] = element.value }
        }
    }
    return [:]
}

private func deliveryInteger(_ dictionary: [String: Any], _ key: String) -> Int {
    (dictionary[key] as? NSNumber)?.intValue ?? 0
}

private func deliveryDate(_ value: Any?) -> Date? {
    if let date = value as? Date { return date }
    if let timestamp = value as? Timestamp { return timestamp.dateValue() }
    guard let raw = value as? String else { return nil }
    return ISO8601DateFormatter().date(from: raw)
}

private func deliveryDateText(_ value: Any?) -> String {
    guard let date = deliveryDate(value) else { return deliveryText("Delivery_Not_Available") }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: Language.currentLanguageCode() ?? "ar")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func deliveryEnumText(_ value: String) -> String {
    guard !value.isEmpty else { return deliveryText("Delivery_Not_Available") }
    let key = "Delivery_Value_\(value.uppercased())"
    let localized = deliveryText(key)
    return localized == key ? value.replacingOccurrences(of: "_", with: " ") : localized
}

private func deliveryStatusBadge(_ status: String) -> AdminStatusBadge.Status {
    switch status.lowercased() {
    case "completed", "delivered": return .success
    case "cancelled", "rejected", "failed", "expired": return .error
    case "assigned_to_driver", "assigned", "accepted_by_company", "accepted": return .info
    case "picked_up", "in_transit", "offered", "pending": return .warning
    default: return .neutral
    }
}

private func deliveryStatusColor(_ status: String) -> Color {
    switch status.lowercased() {
    case "completed", "delivered": return .green
    case "accepted_by_company", "accepted", "assigned_to_driver", "assigned": return .blue
    case "picked_up", "in_transit", "offered", "pending": return .orange
    case "cancelled", "rejected", "failed", "expired": return .red
    default: return AdminSurface.primary
    }
}

private func deliveryStatusText(_ status: String) -> String {
    switch status.lowercased() {
    case "offered": return deliveryText("Delivery_Status_Offered")
    case "accepted_by_company", "accepted": return deliveryText("Delivery_Status_Accepted")
    case "assigned_to_driver", "assigned": return deliveryText("Delivery_Status_Assigned")
    case "picked_up": return deliveryText("Delivery_Status_PickedUp")
    case "in_transit": return deliveryText("Delivery_Status_InTransit")
    case "delivered": return deliveryText("Delivery_Status_Delivered")
    case "completed": return deliveryText("Delivery_Status_Completed")
    case "cancelled": return deliveryText("Delivery_Status_Cancelled")
    case "rejected": return deliveryText("Delivery_Status_Rejected")
    case "failed": return deliveryText("Delivery_Status_Failed")
    case "expired": return deliveryText("Delivery_Status_Expired")
    default: return deliveryText("Delivery_Status_Unknown")
    }
}

private func deliveryAddressText(_ raw: Any?) -> String {
    let address = deliveryDictionary(raw)
    let candidateKeys = ["formattedAddress", "fullAddress", "address", "line1", "street", "area", "city"]
    var values: [String] = []
    for key in candidateKeys {
        guard let value = address[key] as? String else { continue }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !values.contains(trimmed) { values.append(trimmed) }
    }
    return values.isEmpty ? deliveryText("Delivery_Not_Available") : values.joined(separator: " · ")
}

private func deliveryCurrencyText(_ amount: NSNumber?, currency: String = "QAR") -> String {
    guard let amount else { return deliveryText("Delivery_Not_Available") }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.locale = Locale(identifier: Language.currentLanguageCode() ?? "ar")
    let value = formatter.string(from: amount) ?? amount.stringValue
    let currencyText = currency.uppercased() == "QAR" ? Language.get("QAR", alter: "ر.ق") : currency
    return "\(value) \(currencyText)"
}

private struct DeliveryIncident: Identifiable {
    let id = UUID()
    let domainCode: String
    let stateKey: String
    let causeKey: String
    let impactKey: String
    let recoveryKey: String

    static func classify(_ error: NSError) -> DeliveryIncident {
        let code = PPDeliveryService.domainCode(for: error)
        switch code {
        case "DELIVERY_COMPANY_NOT_CONFIGURED":
            return DeliveryIncident(domainCode: code,
                                    stateKey: "Delivery_Error_State_Configuration",
                                    causeKey: "Delivery_Error_Cause_Company_Not_Configured",
                                    impactKey: "Delivery_Error_Impact_Dispatch_Blocked",
                                    recoveryKey: "Delivery_Error_Recovery_Configure_Carrier")
        case "DELIVERY_COMPANY_NOT_FOUND":
            return DeliveryIncident(domainCode: code,
                                    stateKey: "Delivery_Error_State_Carrier_Missing",
                                    causeKey: "Delivery_Error_Cause_Company_Not_Found",
                                    impactKey: "Delivery_Error_Impact_Carrier_Unavailable",
                                    recoveryKey: "Delivery_Error_Recovery_Refresh_Carrier")
        case "DELIVERY_REQUEST_NOT_FOUND":
            return DeliveryIncident(domainCode: code,
                                    stateKey: "Delivery_Error_State_Request_Missing",
                                    causeKey: "Delivery_Error_Cause_Request_Not_Found",
                                    impactKey: "Delivery_Error_Impact_Command_Not_Applied",
                                    recoveryKey: "Delivery_Error_Recovery_Return_Queue")
        case "DELIVERY_DRIVER_NOT_FOUND", "DELIVERY_DRIVER_NOT_ELIGIBLE", "DELIVERY_CAPACITY_EXCEEDED", "DELIVERY_LOCATION_STALE":
            return DeliveryIncident(domainCode: code,
                                    stateKey: "Delivery_Error_State_Assignment_Blocked",
                                    causeKey: "Delivery_Error_Cause_Driver_Eligibility",
                                    impactKey: "Delivery_Error_Impact_Assignment_Blocked",
                                    recoveryKey: "Delivery_Error_Recovery_Review_Driver")
        case "DELIVERY_PERMISSION_DENIED":
            return DeliveryIncident(domainCode: code,
                                    stateKey: "Delivery_Error_State_Access_Denied",
                                    causeKey: "Delivery_Error_Cause_Permission",
                                    impactKey: "Delivery_Error_Impact_Action_Unavailable",
                                    recoveryKey: "Delivery_Error_Recovery_Request_Access")
        case "DELIVERY_STATE_CONFLICT":
            return DeliveryIncident(domainCode: code,
                                    stateKey: "Delivery_Error_State_Changed",
                                    causeKey: "Delivery_Error_Cause_Stale_Action",
                                    impactKey: "Delivery_Error_Impact_Command_Not_Applied",
                                    recoveryKey: "Delivery_Error_Recovery_Refresh_Dossier")
        case "DELIVERY_AUTHORITY_MISMATCH":
            return DeliveryIncident(domainCode: code,
                                    stateKey: "Delivery_Error_State_Authority_Mismatch",
                                    causeKey: "Delivery_Error_Cause_Fulfillment_Authority",
                                    impactKey: "Delivery_Error_Impact_Command_Not_Applied",
                                    recoveryKey: "Delivery_Error_Recovery_Open_Fulfillment")
        case "DELIVERY_COD_MISMATCH":
            return DeliveryIncident(domainCode: code,
                                    stateKey: "Delivery_Error_State_COD_Attention",
                                    causeKey: "Delivery_Error_Cause_COD_Mismatch",
                                    impactKey: "Delivery_Error_Impact_Reconciliation_Blocked",
                                    recoveryKey: "Delivery_Error_Recovery_Verify_Custody")
        case "DELIVERY_POD_REQUIRED":
            return DeliveryIncident(domainCode: code,
                                    stateKey: "Delivery_Error_State_POD_Incomplete",
                                    causeKey: "Delivery_Error_Cause_POD_Required",
                                    impactKey: "Delivery_Error_Impact_Completion_Blocked",
                                    recoveryKey: "Delivery_Error_Recovery_Collect_POD")
        default:
            // A generic Firebase/HTTP not-found intentionally lands here. It is
            // infrastructure state, not evidence that the carrier is missing.
            return DeliveryIncident(domainCode: "DELIVERY_SERVICE_UNAVAILABLE",
                                    stateKey: "Delivery_Error_State_Service_Unavailable",
                                    causeKey: "Delivery_Error_Cause_Service",
                                    impactKey: "Delivery_Error_Impact_Data_Unavailable",
                                    recoveryKey: "Delivery_Error_Recovery_Retry")
        }
    }
}

private enum DeliveryAdminTab: String, CaseIterable, Identifiable {
    case newRequests
    case accepted
    case assigned
    case inProgress
    case delivered
    case completed
    case closed
    case drivers
    case overview
    case exceptions
    case cod
    case pod

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .newRequests: return "DeliveryCompany_Tab_New"
        case .accepted: return "DeliveryCompany_Tab_Accepted"
        case .assigned: return "DeliveryCompany_Tab_Assigned"
        case .inProgress: return "DeliveryCompany_Tab_InProgress"
        case .delivered: return "DeliveryCompany_Tab_Delivered"
        case .completed: return "DeliveryCompany_Tab_Completed"
        case .closed: return "DeliveryCompany_Tab_Closed"
        case .drivers: return "DeliveryCompany_Tab_Members"
        case .overview: return "Delivery_Tab_Overview"
        case .exceptions: return "Delivery_Tab_Exceptions"
        case .cod: return "Delivery_Tab_COD"
        case .pod: return "Delivery_Tab_POD"
        }
    }

    var isDeliveryFilter: Bool {
        switch self {
        case .newRequests, .accepted, .assigned, .inProgress, .delivered, .completed, .closed:
            return true
        default:
            return false
        }
    }
}

private struct PendingDriverCommand: Identifiable {
    let id = UUID()
    let action: String
    let driver: PPDeliveryDriverRecord
}

@MainActor
private final class DeliveryCommandCenterViewModel: ObservableObject {
    @Published private(set) var snapshot: PPDeliveryCommandCenterSnapshot?
    @Published private(set) var dossier: PPDeliveryDossierSnapshot?
    @Published private(set) var companyMembers: [PPDeliveryCompanyMemberRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingDossier = false
    @Published private(set) var isLoadingMembers = false
    @Published private(set) var isExecuting = false
    @Published private(set) var incident: DeliveryIncident?
    @Published private(set) var dossierIncident: DeliveryIncident?
    @Published private(set) var commandIncident: DeliveryIncident?
    @Published private(set) var memberIncident: DeliveryIncident?
    @Published private(set) var memberErrorKey: String?
    @Published private(set) var memberConfirmationKey: String?
    @Published var searchText = ""
    @Published var selectedTab: DeliveryAdminTab = .newRequests
    @Published var selectedRequestID: String?

    var records: [PPDeliveryRequestRecord] { snapshot?.records ?? [] }
    var drivers: [PPDeliveryDriverRecord] { snapshot?.drivers ?? [] }
    var exceptions: [PPDeliveryExceptionRecord] { snapshot?.exceptions ?? [] }
    var officialCompanyID: String { deliveryDictionary(snapshot?.carrier)["id"] as? String ?? "" }
    var driverMembers: [PPDeliveryCompanyMemberRecord] {
        companyMembers.filter { $0.role.lowercased() == "driver" }
    }
    var canManageDrivers: Bool {
        snapshot?.permissionSource == "legacy_official_delivery_bridge" ||
            snapshot?.permissions.contains("delivery.driver.manage") == true
    }

    func member(for driverUID: String) -> PPDeliveryCompanyMemberRecord? {
        companyMembers.first { $0.uid == driverUID }
    }

    func prepareDriverManagementAction() {
        memberIncident = nil
        memberErrorKey = nil
        commandIncident = nil
    }

    var filteredRecords: [PPDeliveryRequestRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return records }
        return records.filter {
            $0.orderNumber.lowercased().contains(query) ||
            $0.orderID.lowercased().contains(query) ||
            $0.requestID.lowercased().contains(query) ||
            $0.customerName.lowercased().contains(query) ||
            $0.assignedDriverName.lowercased().contains(query)
        }
    }

    func records(for tab: DeliveryAdminTab) -> [PPDeliveryRequestRecord] {
        let queryIsEmpty = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let source = queryIsEmpty ? records : filteredRecords
        return source.filter { record in
            let status = record.status.lowercased()
            switch tab {
            case .newRequests: return status == "offered" || status == "pending"
            case .accepted: return status == "accepted_by_company" || status == "accepted"
            case .assigned: return status == "assigned_to_driver" || status == "assigned"
            case .inProgress: return status == "picked_up" || status == "in_transit"
            case .delivered: return status == "delivered"
            case .completed: return status == "completed"
            case .closed: return ["cancelled", "rejected", "failed", "expired"].contains(status)
            default: return true
            }
        }
    }

    var availableTabs: [DeliveryAdminTab] {
        let deliveryTabs: [DeliveryAdminTab] = [.newRequests, .accepted, .assigned, .inProgress, .delivered, .completed, .closed]
        guard let snapshot else { return deliveryTabs }
        let permissions = Set(snapshot.permissions)
        let legacy = snapshot.permissionSource == "legacy_official_delivery_bridge"
        var result = deliveryTabs
        if legacy || permissions.contains("delivery.driver.view") { result.append(.drivers) }
        result.append(.overview)
        result.append(.exceptions)
        if legacy || permissions.contains("delivery.cod.view") { result.append(.cod) }
        if legacy || permissions.contains("delivery.pod.review") { result.append(.pod) }
        return result
    }

    var projectionCounts: [String: Any] {
        let projection = deliveryDictionary(snapshot?.projection)
        return deliveryDictionary(projection["counts"])
    }

    var projectionDriverCounts: [String: Any] {
        let projection = deliveryDictionary(snapshot?.projection)
        return deliveryDictionary(projection["drivers"])
    }

    var availabilityFunnel: [String: Any] {
        let projection = deliveryDictionary(snapshot?.projection)
        return deliveryDictionary(projection["eligibilityFunnel"])
    }

    func count(_ key: String) -> Int { deliveryInteger(projectionCounts, key) }
    func driverCount(_ key: String) -> Int { deliveryInteger(projectionDriverCounts, key) }

    func load(refresh: Bool = false) {
        guard !isLoading && !isRefreshing else { return }
        if snapshot == nil { isLoading = true } else { isRefreshing = refresh }
        incident = nil
        // The Admin service intentionally omits companyId. Infra resolves that
        // request to the canonical or protected legacy Pure Pets official fleet;
        // this screen must never become a mutable third-party carrier selector.
        PPDeliveryService.shared().fetchCommandCenter { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                self.isRefreshing = false
                if let error {
                    self.incident = DeliveryIncident.classify(error as NSError)
                    return
                }
                guard let snapshot else {
                    let error = NSError(domain: PPDeliveryServiceErrorDomain, code: 1)
                    self.incident = DeliveryIncident.classify(error)
                    return
                }
                self.snapshot = snapshot
                if !self.availableTabs.contains(self.selectedTab) { self.selectedTab = .overview }
                if self.availableTabs.contains(.drivers) {
                    self.loadMembers(companyID: deliveryDictionary(snapshot.carrier)["id"] as? String ?? "")
                } else {
                    self.companyMembers = []
                }
            }
        }
    }

    func loadMembers(companyID: String? = nil) {
        let resolvedCompanyID = (companyID ?? officialCompanyID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedCompanyID.isEmpty, !isLoadingMembers else { return }
        isLoadingMembers = true
        memberIncident = nil
        memberErrorKey = nil
        PPDeliveryService.shared().fetchCompanyMembers(companyID: resolvedCompanyID) { [weak self] members, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoadingMembers = false
                if let error {
                    self.memberIncident = DeliveryIncident.classify(error as NSError)
                    return
                }
                self.companyMembers = members ?? []
            }
        }
    }

    func inviteDriver(identifier: String, completion: @escaping @Sendable (Bool) -> Void) {
        let safeIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeIdentifier.isEmpty, !officialCompanyID.isEmpty, canManageDrivers, !isExecuting else {
            completion(false)
            return
        }
        isExecuting = true
        memberIncident = nil
        memberErrorKey = nil
        memberConfirmationKey = nil
        PPDeliveryService.shared().inviteDriver(identifier: safeIdentifier,
                                                companyID: officialCompanyID) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isExecuting = false
                if let error {
                    self.recordMemberMutationError(error as NSError)
                    completion(false)
                    return
                }
                self.memberConfirmationKey = "Delivery_Driver_Invite_Success"
                self.loadMembers()
                self.load(refresh: true)
                completion(true)
            }
        }
    }

    func disableDriver(_ driverUID: String, completion: @escaping @Sendable (Bool) -> Void) {
        guard !driverUID.isEmpty, !officialCompanyID.isEmpty, canManageDrivers, !isExecuting else {
            completion(false)
            return
        }
        isExecuting = true
        memberIncident = nil
        memberErrorKey = nil
        memberConfirmationKey = nil
        PPDeliveryService.shared().disableDriver(driverUID: driverUID,
                                                 companyID: officialCompanyID) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isExecuting = false
                if let error {
                    self.recordMemberMutationError(error as NSError)
                    completion(false)
                    return
                }
                self.memberConfirmationKey = "Delivery_Driver_Disable_Success"
                self.loadMembers()
                self.load(refresh: true)
                completion(true)
            }
        }
    }

    private func recordMemberMutationError(_ error: NSError) {
        if PPDeliveryService.isPermissionError(error) {
            memberIncident = DeliveryIncident.classify(error)
            return
        }
        switch error.code {
        case 3:
            memberErrorKey = "Delivery_Driver_Error_Invalid_Identifier"
        case 5:
            memberErrorKey = "Delivery_Driver_Error_User_Not_Found"
        case 6:
            memberErrorKey = "Delivery_Driver_Error_Already_Member"
        case 9, 10:
            memberErrorKey = "Delivery_Driver_Error_Conflict"
        default:
            memberErrorKey = "Delivery_Driver_Error_Service"
        }
    }

    func openDossier(_ record: PPDeliveryRequestRecord) {
        selectedRequestID = record.requestID
        dossier = nil
        dossierIncident = nil
        commandIncident = nil
        loadDossier(requestID: record.requestID)
    }

    func closeDossier() {
        selectedRequestID = nil
        dossier = nil
        dossierIncident = nil
        commandIncident = nil
    }

    func loadDossier(requestID: String? = nil) {
        guard let requestID = requestID ?? selectedRequestID, !requestID.isEmpty else { return }
        isLoadingDossier = true
        dossierIncident = nil
        PPDeliveryService.shared().fetchDossier(requestID: requestID) { [weak self] dossier, error in
            Task { @MainActor in
                guard let self, self.selectedRequestID == requestID else { return }
                self.isLoadingDossier = false
                if let error {
                    self.dossierIncident = DeliveryIncident.classify(error as NSError)
                    return
                }
                self.dossier = dossier
            }
        }
    }

    func execute(_ action: PPDeliveryAllowedAction,
                 driverUID: String? = nil,
                 handoverConfirmed: Bool = false) {
        guard let requestID = selectedRequestID, !isExecuting else { return }
        isExecuting = true
        commandIncident = nil
        let commandID = "admin-ios-\(action.action.lowercased())-\(UUID().uuidString)"
        PPDeliveryService.shared().execute(action: action,
                                           requestID: requestID,
                                           commandID: commandID,
                                           driverUID: driverUID,
                                           handoverConfirmed: handoverConfirmed,
                                           reason: nil) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.isExecuting = false
                if let error {
                    let classified = DeliveryIncident.classify(error as NSError)
                    self.commandIncident = classified
                    if classified.domainCode == "DELIVERY_STATE_CONFLICT" {
                        self.loadDossier(requestID: requestID)
                        self.load(refresh: true)
                    }
                    return
                }
                self.loadDossier(requestID: requestID)
                self.load(refresh: true)
            }
        }
    }

    func executeDriver(_ pending: PendingDriverCommand, completion: (@Sendable (Bool) -> Void)? = nil) {
        guard !isExecuting else { return }
        isExecuting = true
        commandIncident = nil
        let commandID = "admin-ios-driver-\(pending.action.lowercased())-\(UUID().uuidString)"
        PPDeliveryService.shared().executeDriver(action: pending.action,
                                                 driverUID: pending.driver.uid,
                                                 expectedRevision: pending.driver.revision,
                                                 commandID: commandID) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isExecuting = false
                if let error {
                    self.commandIncident = DeliveryIncident.classify(error as NSError)
                    completion?(false)
                    return
                }
                self.memberConfirmationKey = "Delivery_Driver_Command_Success"
                self.load(refresh: true)
                completion?(true)
            }
        }
    }
}

struct AdminDeliveryListView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel = DeliveryCommandCenterViewModel()
    @State private var selectedDriver: PPDeliveryDriverRecord?
    @State private var presentsInviteDriver = false

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                hero
                tabRail
                content
            }
            if viewModel.isExecuting {
                AdminLoadingOverlay(message: deliveryText("Delivery_Command_Applying"))
                    .background(Color.black.opacity(0.08))
                    .accessibilityAddTraits(.isModal)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear { viewModel.load() }
        .sheet(isPresented: Binding(
            get: { viewModel.selectedRequestID != nil },
            set: { if !$0 { viewModel.closeDossier() } }
        )) {
            DeliveryDossierSheet(viewModel: viewModel)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: Binding(
            get: { selectedDriver != nil },
            set: { if !$0 { selectedDriver = nil } }
        )) {
            if let driver = selectedDriver {
                DeliveryDriverDetailSheet(viewModel: viewModel,
                                          driver: driver,
                                          onDismiss: { selectedDriver = nil })
                    .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }
        }
        .sheet(isPresented: $presentsInviteDriver) {
            DeliveryDriverInviteSheet(viewModel: viewModel,
                                      onDismiss: { presentsInviteDriver = false })
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: - Sovereign Navigation Bar

    private var header: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            AdminSovereignNavigationBar(
                title: deliveryText("DeliveryCompany_NavTitle"),
                subtitle: Language.get("CommandCenter_Delivery_Workspace", alter: "مساحة التوصيل"),
                onBack: { close() }
            ) {
                if viewModel.isLoading || viewModel.isRefreshing {
                    ProgressView().tint(AdminSurface.primary)
                } else {
                    Button { viewModel.load(refresh: true) } label: {
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
                    .accessibilityLabel(deliveryText("CommandCenter_Refresh"))
                }
            }

            if let snapshot = viewModel.snapshot {
                HStack(spacing: 8) {
                    AdminStatusBadge(
                        text: deliveryText("DeliveryCompany_Official_Badge"),
                        status: .processing
                    )
                    Text(deliveryFreshnessText(snapshot))
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .padding(.horizontal, AdminSpacing.screenMargin)

                if snapshot.permissionSource == "legacy_official_delivery_bridge" {
                    Label(deliveryText("Delivery_Legacy_Permission_Warning"), systemImage: "exclamationmark.shield.fill")
                        .font(AdminType.captionBold)
                        .foregroundColor(.orange)
                        .accessibilityElement(children: .combine)
                        .padding(.horizontal, AdminSpacing.screenMargin)
                }
            }
        }
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AdminSurface.hairline.opacity(0.65), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.06), radius: 24, y: 12)

            Image(systemName: "truck.box.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 46, height: 46)
                .background(AdminSurface.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(22)
                .accessibilityHidden(true)

            VStack(spacing: -2) {
                Text("\(viewModel.records.count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AdminSurface.primaryText)
                Text(deliveryText("DeliveryCompany_Dashboard_Requests"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(width: 96, height: 72)
            .background(AdminSurface.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 22)
            .padding(.trailing, 20)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 0) {
                Text(deliveryText("DeliveryCompany_Dashboard_Eyebrow"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.primary)
                Text(deliveryText("DeliveryCompany_Official_Name"))
                    .font(AdminType.largeTitle)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityAddTraits(.isHeader)
                Text(deliveryText("DeliveryCompany_Dashboard_OfficialSubtitle"))
                    .font(AdminType.subheadline)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)
                    .padding(.top, 3)

                Spacer(minLength: 10)

                if viewModel.availableTabs.contains(.drivers) {
                    Button {
                        withAnimation(reduceMotion ? nil : AdminAnimation.standard) {
                            viewModel.selectedTab = .drivers
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AdminSurface.primary)
                                .frame(width: 36, height: 36)
                                .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deliveryText("DeliveryCompany_Tab_Members"))
                                    .font(AdminType.subheadlineBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                Text(deliveryText("DeliveryCompany_Dashboard_MembersShortcutSubtitle"))
                                    .font(AdminType.caption1)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AdminSurface.primaryText.opacity(0.76))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 64)
                        .background(AdminSurface.background.opacity(0.74), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(deliveryText("DeliveryCompany_Dashboard_MembersShortcutSubtitle"))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 86)
            .padding(.bottom, 18)
        }
        .frame(height: 256)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var tabRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.availableTabs) { tab in
                    Button {
                        viewModel.selectedTab = tab
                    } label: {
                        Text(deliveryText(tab.titleKey))
                            .font(AdminType.captionBold)
                            .foregroundColor(viewModel.selectedTab == tab ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(viewModel.selectedTab == tab ? AdminSurface.primary : AdminSurface.surface,
                                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(viewModel.selectedTab == tab ? AdminSurface.primary.opacity(0.20) : AdminSurface.hairline.opacity(0.65), lineWidth: 0.5)
                            }
                            .shadow(color: viewModel.selectedTab == tab ? AdminSurface.primary.opacity(0.22) : .clear,
                                    radius: viewModel.selectedTab == tab ? 16 : 0,
                                    y: viewModel.selectedTab == tab ? 8 : 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(viewModel.selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
        }
        .padding(.bottom, AdminSpacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.snapshot == nil {
            AdminLoadingOverlay(message: deliveryText("Delivery_Loading_Operations"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let incident = viewModel.incident, viewModel.snapshot == nil {
            ScrollView {
                DeliveryIncidentPanel(incident: incident, retry: { viewModel.load() })
                    .padding(AdminSpacing.screenMargin)
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    if let incident = viewModel.incident {
                        DeliveryIncidentPanel(incident: incident, retry: { viewModel.load(refresh: true) })
                    }
                    if let incident = viewModel.commandIncident, viewModel.selectedRequestID == nil {
                        DeliveryIncidentPanel(incident: incident, retry: nil)
                    }
                    if viewModel.selectedTab.isDeliveryFilter {
                        AdminSearchField(text: $viewModel.searchText, placeholder: deliveryText("Delivery_Search"))
                    }
                    switch viewModel.selectedTab {
                    case .newRequests, .accepted, .assigned, .inProgress, .delivered, .completed, .closed:
                        deliveryList(viewModel.records(for: viewModel.selectedTab), emptyKey: "DeliveryCompany_Empty_Title")
                    case .overview: overview
                    case .drivers: drivers
                    case .exceptions: exceptions
                    case .cod: codQueue
                    case .pod: podQueue
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.bottom, 32)
            }
            .refreshable { viewModel.load(refresh: true) }
        }
    }

    private var overview: some View {
        VStack(spacing: 16) {
            primaryDecision
            metrics
            availability
            fleetHealth
            if !viewModel.exceptions.isEmpty { exceptionList(Array(viewModel.exceptions.prefix(5))) }
            deliveryList(Array(viewModel.records.prefix(8)), emptyKey: "Delivery_Empty")
        }
    }

    private var primaryDecision: some View {
        let critical = viewModel.exceptions.first { $0.severity == "CRITICAL" || $0.severity == "HIGH" }
        return AdminCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: critical == nil ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(critical == nil ? .green : .orange)
                    .frame(width: 40, height: 40)
                    .background((critical == nil ? Color.green : Color.orange).opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(deliveryText(critical == nil ? "Delivery_Primary_Ready" : "Delivery_Primary_Attention"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(critical.map { deliveryEnumText($0.reasonCode) } ?? deliveryText("Delivery_Primary_No_Blocker"))
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                Spacer()
                if let critical {
                    AdminStatusBadge(text: deliveryEnumText(critical.severity), status: critical.severity == "CRITICAL" ? .error : .warning)
                }
            }
            .padding(16)
            .accessibilityElement(children: .combine)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            metric(viewModel.count("unassigned"), "Delivery_Metric_Unassigned", "tray.full", .orange)
            metric(viewModel.count("assignmentBlocked"), "Delivery_Metric_Assignment_Blocked", "person.crop.circle.badge.exclamationmark", .red)
            metric(viewModel.count("active"), "Delivery_Metric_Active", "truck.box", .blue)
            metric(viewModel.count("inTransit"), "Delivery_Metric_In_Transit", "location", AdminSurface.primary)
            metric(viewModel.count("codAttention"), "Delivery_Metric_COD_Attention", "banknote", .orange)
            metric(viewModel.count("podAttention"), "Delivery_Metric_POD_Attention", "signature", .purple)
        }
    }

    private func metric(_ value: Int, _ titleKey: String, _ symbol: String, _ color: Color) -> some View {
        AdminCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol).foregroundColor(color)
                    Spacer()
                    Text("\(value)")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AdminSurface.primaryText)
                }
                Text(deliveryText(titleKey))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(14)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var availability: some View {
        let funnel = viewModel.availabilityFunnel
        let rows = funnel["rows"] as? [[String: Any]] ?? []
        let reasons = deliveryDictionary(funnel["reasons"])
        AdminCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Delivery_Driver_Availability", symbol: "person.2.badge.gearshape")
                if rows.isEmpty {
                    Text(deliveryText("Delivery_Driver_Evidence_Empty"))
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(deliveryFunnelLabel(row["key"] as? String ?? ""))
                                .font(AdminType.subheadline)
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                            Text("\(deliveryInteger(row, "count"))")
                                .font(AdminType.headline)
                                .monospacedDigit()
                                .foregroundColor(AdminSurface.primaryText)
                        }
                    }
                }
                if !reasons.isEmpty {
                    Divider()
                    Text(deliveryText("Delivery_Why_Unavailable"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                    ForEach(reasons.keys.sorted(), id: \.self) { reason in
                        HStack {
                            Text(deliveryEnumText(reason)).font(AdminType.caption1)
                            Spacer()
                            Text("\((reasons[reason] as? NSNumber)?.intValue ?? 0)").monospacedDigit()
                        }
                        .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(16)
        }
    }

    private var fleetHealth: some View {
        let capabilities = deliveryDictionary(viewModel.snapshot?.capabilities)
        return AdminCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Delivery_Fleet_Health", symbol: "gauge.with.dots.needle.50percent")
                HStack(spacing: 14) {
                    fleetMetric(viewModel.driverCount("online"), "Delivery_Driver_Online")
                    fleetMetric(viewModel.driverCount("available"), "Delivery_Driver_Available")
                    fleetMetric(viewModel.driverCount("busy"), "Delivery_Driver_Busy")
                    fleetMetric(viewModel.driverCount("unavailable"), "Delivery_Driver_Unavailable")
                }
                Divider()
                Label(
                    deliveryText(viewModel.snapshot?.fleet.configurationState == "CONFIGURED"
                                 ? "Delivery_Fleet_Entities_Available"
                                 : "Delivery_Fleet_Entities_Not_Configured"),
                    systemImage: "truck.box"
                )
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                Label(
                    deliveryText((capabilities["map"] as? String) == "NOT_CONFIGURED"
                                 ? "Delivery_Map_Not_Configured"
                                 : "Delivery_Map_Provider_Not_Configured"),
                    systemImage: "map"
                )
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(16)
        }
    }

    private func fleetMetric(_ value: Int, _ key: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(AdminType.headline).monospacedDigit().foregroundColor(AdminSurface.primaryText)
            Text(deliveryText(key)).font(AdminType.caption1).foregroundColor(AdminSurface.secondaryText).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var drivers: some View {
        VStack(spacing: 14) {
            driverManagementHero
            if let confirmationKey = viewModel.memberConfirmationKey {
                Label(deliveryText(confirmationKey), systemImage: "checkmark.circle.fill")
                    .font(AdminType.calloutBold)
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityElement(children: .combine)
            }
            if let incident = viewModel.memberIncident {
                DeliveryIncidentPanel(incident: incident, retry: { viewModel.loadMembers() })
            }
            if let errorKey = viewModel.memberErrorKey {
                Label(deliveryText(errorKey), systemImage: "exclamationmark.triangle.fill")
                    .font(AdminType.calloutBold)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityElement(children: .combine)
            }
            if viewModel.isLoadingMembers && viewModel.companyMembers.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(AdminSurface.primary)
                    Text(deliveryText("Delivery_Driver_Loading_Members"))
                        .font(AdminType.callout)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            if viewModel.drivers.isEmpty {
                AdminEmptyStateView(symbol: "person.2.slash",
                                    title: deliveryText("Delivery_Drivers_Empty"),
                                    subtitle: deliveryText("Delivery_Driver_Evidence_Empty"))
                    .frame(minHeight: 300)
            } else {
                ForEach(viewModel.drivers, id: \.uid) { driver in
                    driverCard(driver)
                }
            }
        }
    }

    private var driverManagementHero: some View {
        let activeCount = viewModel.drivers.filter { $0.accountStatus.uppercased() == "ACTIVE" }.count
        let availableCount = viewModel.drivers.filter {
            $0.accountStatus.uppercased() == "ACTIVE" &&
                $0.canReceiveAssignments &&
                (viewModel.member(for: $0.uid)?.available ?? true)
        }.count
        return AdminCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 48, height: 48)
                        .background(AdminSurface.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(deliveryText("Delivery_Driver_Management_Title"))
                            .font(AdminType.title2)
                            .foregroundColor(AdminSurface.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(deliveryText("Delivery_Driver_Management_Subtitle"))
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    Spacer(minLength: 8)
                    if viewModel.canManageDrivers {
                        Button {
                            viewModel.prepareDriverManagementAction()
                            presentsInviteDriver = true
                        } label: {
                            Label(deliveryText("Delivery_Driver_Invite"), systemImage: "person.badge.plus")
                                .font(AdminType.captionBold)
                                .padding(.horizontal, 13)
                                .frame(minHeight: 44)
                                .foregroundColor(.white)
                                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(deliveryText("Delivery_Driver_Invite_Hint"))
                    }
                }
                HStack(spacing: 10) {
                    driverSummaryMetric("\(viewModel.drivers.count)", "Delivery_Driver_Total")
                    driverSummaryMetric("\(activeCount)", "Delivery_Driver_Active")
                    driverSummaryMetric("\(availableCount)", "Delivery_Driver_Available")
                }
            }
            .padding(18)
        }
    }

    private func driverSummaryMetric(_ value: String, _ titleKey: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(AdminType.headline)
                .monospacedDigit()
                .foregroundColor(AdminSurface.primaryText)
            Text(deliveryText(titleKey))
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, 12)
        .background(AdminSurface.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func driverCard(_ driver: PPDeliveryDriverRecord) -> some View {
        let member = viewModel.member(for: driver.uid)
        let available = driver.accountStatus.uppercased() == "ACTIVE" &&
            driver.canReceiveAssignments &&
            (member?.available ?? true)
        let availabilityColor: Color = available ? .green : .orange
        return Button {
            viewModel.prepareDriverManagementAction()
            selectedDriver = driver
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AdminSurface.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(AdminSurface.hairline.opacity(0.42), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.07), radius: 20, y: 10)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        driverAvatar(member)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(driver.displayName)
                            .font(AdminType.title3)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(driver.phone.isEmpty
                             ? driver.uid
                             : deliveryFormat("DeliveryCompany_Members_Phone_Format", driver.phone))
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                    Text(available
                         ? deliveryText("DeliveryCompany_Members_Available")
                         : deliveryText("DeliveryCompany_Members_Unavailable"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(availabilityColor)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 23)
                        .background(availabilityColor.opacity(0.10), in: Capsule())
                    }

                    HStack(spacing: 8) {
                        memberPill(deliveryEnumText(driver.shiftStatus), symbol: "clock")
                        memberPill(deliveryEnumText(driver.workState), symbol: "steeringwheel")
                        memberPill(deliveryFormat("DeliveryCompany_Members_ActiveCount_Format", driver.activeDeliveryCount),
                                   symbol: "shippingbox.fill")
                    }

                    if !driver.eligibilityReasonCodes.isEmpty {
                        Label(driver.eligibilityReasonCodes.map(deliveryEnumText).joined(separator: " · "),
                              systemImage: "info.circle")
                            .font(AdminType.caption1)
                            .foregroundColor(.orange)
                    }

                    HStack(spacing: 8) {
                        Label(deliveryText("Delivery_Driver_Open_Profile"), systemImage: "person.text.rectangle")
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primary)
                        Spacer()
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(deliveryText("Delivery_Driver_Open_Profile_Hint"))
    }

    @ViewBuilder
    private func driverAvatar(_ member: PPDeliveryCompanyMemberRecord?) -> some View {
        if let rawURL = member?.photoURL,
           let url = URL(string: rawURL),
           !rawURL.isEmpty {
            AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 48, height: 48)) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .background(AdminSurface.primary.opacity(0.10))
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .accessibilityHidden(true)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 48, height: 48)
                .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private func memberPill(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(AdminType.caption2)
            .foregroundColor(AdminSurface.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .padding(.horizontal, 9)
            .frame(minHeight: 30)
            .background(AdminSurface.background.opacity(0.78), in: Capsule())
            .frame(maxWidth: .infinity)
    }

    private func driverFact(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(deliveryText(key)).font(AdminType.caption1).foregroundColor(AdminSurface.secondaryText)
            Text(value).font(AdminType.captionBold).foregroundColor(AdminSurface.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exceptions: some View {
        exceptionList(viewModel.exceptions)
    }

    private var codQueue: some View {
        let records = viewModel.records.filter {
            !["", "NOT_APPLICABLE", "RECONCILED"].contains($0.codStatus.uppercased())
        }
        return deliveryList(records, emptyKey: "Delivery_COD_Empty")
    }

    private var podQueue: some View {
        let records = viewModel.records.filter {
            ["delivered", "completed"].contains($0.status.lowercased()) && $0.podStatus.uppercased() != "COMPLETE"
        }
        return deliveryList(records, emptyKey: "Delivery_POD_Empty")
    }

    @ViewBuilder
    private func deliveryList(_ records: [PPDeliveryRequestRecord], emptyKey: String) -> some View {
        if records.isEmpty {
            AdminEmptyStateView(symbol: "shippingbox",
                                title: deliveryText(emptyKey),
                                subtitle: deliveryText(emptyKey == "DeliveryCompany_Empty_Title"
                                                       ? "DeliveryCompany_Empty_Subtitle"
                                                       : "Delivery_Empty_Detail"))
                .frame(minHeight: 280)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(records, id: \.requestID) { record in
                    deliveryCard(record)
                }
            }
        }
    }

    private func deliveryCard(_ record: PPDeliveryRequestRecord) -> some View {
        Button { viewModel.openDossier(record) } label: {
            let statusColor = deliveryStatusColor(record.status)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AdminSurface.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(AdminSurface.hairline.opacity(0.38), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 24, y: 12)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(statusColor)
                    .frame(width: 5)
                    .padding(.vertical, 22)
                    .padding(.leading, 16)

                VStack(alignment: .leading, spacing: 0) {
                    Text(deliveryText("DeliveryCompany_Dashboard_Eyebrow"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.84))

                    HStack(alignment: .center, spacing: 10) {
                        Text(deliveryFormat("DeliveryCompany_Order_Format",
                                            record.orderNumber.isEmpty ? (record.orderID.isEmpty ? record.requestID : record.orderID) : record.orderNumber))
                            .font(AdminType.title3)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(deliveryStatusText(record.status))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 23)
                            .background(statusColor.opacity(0.10), in: Capsule())
                    }
                    .padding(.top, 6)

                    Text(deliveryFormat("DeliveryCompany_Pickup_Format", deliveryAddressText(record.pickupAddress)))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(2)
                        .padding(.top, 12)
                    Text(deliveryFormat("DeliveryCompany_Dropoff_Format", deliveryAddressText(record.dropoffAddress)))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(2)
                        .padding(.top, 6)

                    HStack(spacing: 10) {
                        Text(deliveryFormat("DeliveryCompany_Driver_Format",
                                            record.assignedDriverName.isEmpty ? deliveryText("DeliveryCompany_Unassigned") : record.assignedDriverName))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(deliveryCurrencyText(record.deliveryFee,
                                                  currency: record.cod["currency"] as? String ?? "QAR"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primary)
                            .lineLimit(1)
                    }
                    .padding(.top, 12)

                    Text(deliveryFormat("DeliveryCompany_Dates_Format",
                                        deliveryDateText(record.createdAt),
                                        deliveryDateText(record.updatedAt)))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.78))
                        .padding(.top, 8)
                }
                .padding(.top, 18)
                .padding(.bottom, 17)
                .padding(.leading, 34)
                .padding(.trailing, 16)
            }
        }
        .buttonStyle(DeliveryCompanyCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(deliveryText("Delivery_Open_Dossier_Hint"))
    }

    @ViewBuilder
    private func exceptionList(_ exceptions: [PPDeliveryExceptionRecord]) -> some View {
        if exceptions.isEmpty {
            AdminEmptyStateView(symbol: "checkmark.shield",
                                title: deliveryText("Delivery_Exceptions_Empty"),
                                subtitle: deliveryText("Delivery_Exceptions_Empty_Detail"))
                .frame(minHeight: 280)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(exceptions, id: \.exceptionID) { exception in
                    AdminCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(deliveryEnumText(exception.type)).font(AdminType.headline).foregroundColor(AdminSurface.primaryText)
                                Spacer()
                                AdminStatusBadge(text: deliveryEnumText(exception.severity),
                                                 status: exception.severity == "CRITICAL" ? .error : .warning)
                            }
                            Text(deliveryEnumText(exception.reasonCode))
                                .font(AdminType.subheadline)
                                .foregroundColor(AdminSurface.secondaryText)
                            Text(exception.deliveryJobID)
                                .font(AdminType.caption1)
                                .foregroundColor(AdminSurface.secondaryText)
                                .textSelection(.enabled)
                        }
                        .padding(15)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ key: String, symbol: String) -> some View {
        Label(deliveryText(key), systemImage: symbol)
            .font(AdminType.headline)
            .foregroundColor(AdminSurface.primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private func close() {
        if let onDismiss { onDismiss() } else { dismiss() }
    }
}

private struct DeliveryIncidentPanel: View {
    let incident: DeliveryIncident
    let retry: (() -> Void)?
    var openFulfillment: (() -> Void)? = nil

    var body: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(deliveryText(incident.stateKey), systemImage: "exclamationmark.triangle.fill")
                    .font(AdminType.headline)
                    .foregroundColor(.red)
                    .accessibilityAddTraits(.isHeader)
                incidentRow("Delivery_Error_Label_State", incident.stateKey)
                incidentRow("Delivery_Error_Label_Cause", incident.causeKey)
                incidentRow("Delivery_Error_Label_Impact", incident.impactKey)
                incidentRow("Delivery_Error_Label_Recovery", incident.recoveryKey)
                Text(incident.domainCode)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(AdminSurface.secondaryText)
                    .textSelection(.enabled)
                if incident.domainCode == "DELIVERY_AUTHORITY_MISMATCH", let openFulfillment {
                    Button(action: openFulfillment) {
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.fill")
                            Text(deliveryText("Delivery_Open_Fulfillment_Action"))
                        }
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                if let retry {
                    Button(deliveryText("Retry"), action: retry)
                        .buttonStyle(.borderedProminent)
                        .tint(AdminSurface.primary)
                }
            }
            .padding(16)
        }
    }

    private func incidentRow(_ labelKey: String, _ valueKey: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(deliveryText(labelKey)).font(AdminType.captionBold).foregroundColor(AdminSurface.secondaryText)
            Text(deliveryText(valueKey)).font(AdminType.subheadline).foregroundColor(AdminSurface.primaryText)
        }
    }
}

private struct PendingDeliveryCommand: Identifiable {
    let id = UUID()
    let action: PPDeliveryAllowedAction
    let driverUID: String?
    let handoverConfirmed: Bool
}

private struct PendingDeliveryAssignment: Identifiable {
    let id = UUID()
    let action: PPDeliveryAllowedAction
}

private struct DeliveryDossierSheet: View {
    @ObservedObject var viewModel: DeliveryCommandCenterViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingAssignment: PendingDeliveryAssignment?
    @State private var handoverConfirmed = false
    @State private var showingFulfillmentWorkspace = false

    var body: some View {
        VStack(spacing: 0) {
            sovereignHeaderBar

            ZStack {
                AdminSurface.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if viewModel.isLoadingDossier && viewModel.dossier == nil {
                            AdminLoadingOverlay(message: deliveryText("Delivery_Loading_Dossier"))
                                .frame(minHeight: 300)
                        } else if let incident = viewModel.dossierIncident {
                            DeliveryIncidentPanel(incident: incident, retry: {
                                viewModel.loadDossier()
                            }, openFulfillment: {
                                showingFulfillmentWorkspace = true
                            })
                        } else if let dossier = viewModel.dossier {
                            dossierContent(dossier)
                        }
                        if let incident = viewModel.commandIncident {
                            DeliveryIncidentPanel(incident: incident, retry: nil, openFulfillment: {
                                showingFulfillmentWorkspace = true
                            })
                        }
                    }
                    .padding(AdminSpacing.screenMargin)
                    .padding(.bottom, 32)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(item: $pendingAssignment) { pending in
            DeliveryDriverPickerSheet(
                action: pending.action,
                drivers: (viewModel.dossier?.drivers ?? []).filter {
                    $0.uid != viewModel.dossier?.record.assignedDriverUID
                },
                isExecuting: viewModel.isExecuting
            ) { driver in
                pendingAssignment = nil
                viewModel.execute(pending.action,
                                  driverUID: driver.uid,
                                  handoverConfirmed: false)
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $showingFulfillmentWorkspace) {
            AdminFulfillmentListView(session: AdminSession(source: PPAdminSessionSnapshot())) {
                showingFulfillmentWorkspace = false
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    private var sovereignHeaderBar: some View {
        HStack {
            Spacer()
            Text(deliveryText("DeliveryCompany_Detail_NavTitle"))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
            Spacer()
        }
        .overlay(alignment: Language.isRTL() ? .trailing : .leading) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.closeDossier()
                dismiss()
            }) {
                Text(deliveryText("Close"))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(AdminSurface.primary.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(AdminSurface.primary.opacity(0.20), lineWidth: 1.0))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .frame(height: 56)
        .background(AdminSurface.surface)
        .overlay(alignment: .bottom) {
            Divider().background(AdminSurface.hairline)
        }
    }

    private func presentCommandAlert(for pending: PendingDeliveryCommand) {
        let action = pending.action.action
        let title = deliveryCommandConfirmationTitle(action)
        let message = deliveryCommandConfirmationMessage(action)
        let destructive = ["REJECT", "CANCEL", "FAIL"].contains(action)
        let iconName = destructive ? "exclamationmark.triangle.fill" : "questionmark.circle.fill"
        let icon = UIImage(systemName: iconName)

        PPAlertHelper.showConfirmation(
            in: nil,
            title: title,
            subtitle: message,
            confirmButton: deliveryText("Confirm"),
            cancelButton: deliveryText("Cancel"),
            icon: icon,
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                viewModel.execute(pending.action,
                                  driverUID: pending.driverUID,
                                  handoverConfirmed: pending.handoverConfirmed)
            },
            cancelBlock: nil
        )
    }

    private func dossierContent(_ dossier: PPDeliveryDossierSnapshot) -> some View {
        let record = dossier.record
        return VStack(spacing: 14) {
            detailHero(record)

            if record.authority == "FULFILLMENT_V1" {
                deliveryCompanySurface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(deliveryText("Delivery_Fulfillment_Read_Only"), systemImage: "lock.shield")
                            .font(AdminType.subheadline)
                            .foregroundColor(AdminSurface.secondaryText)
                            .accessibilityElement(children: .combine)

                        Button(action: {
                            showingFulfillmentWorkspace = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox.fill")
                                Text(deliveryText("Delivery_Open_Fulfillment_Action"))
                            }
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                }
            }

            routeSection(record)
            assignmentSummary(record)
            dossierSection("Delivery_Dossier_Customer", symbol: "person") {
                dossierFact("Delivery_Dossier_Customer", record.customerName)
                dossierFact("Delivery_Dossier_Order", record.orderID)
            }
            dossierSection("Delivery_Dossier_Lifecycle", symbol: "point.topleft.down.to.point.bottomright.curvepath") {
                dossierFact("Delivery_Dimension_Job", deliveryEnumText(record.deliveryJobStatus))
                dossierFact("Delivery_Dimension_Carrier", deliveryEnumText(record.carrierAssignmentStatus))
                dossierFact("Delivery_Dimension_Driver", deliveryEnumText(record.driverAssignmentStatus))
                dossierFact("Delivery_Dimension_Route", deliveryEnumText(record.routeStatus))
                dossierFact("Delivery_Dimension_POD", deliveryEnumText(record.podStatus))
                dossierFact("Delivery_Dimension_COD", deliveryEnumText(record.codStatus))
                dossierFact("Delivery_Dimension_Return", deliveryEnumText(record.returnStatus))
            }
            codSection(record)
            podSection(record)
            eventSection(dossier.events.map { $0 as Any })
            commandDock(record)
        }
    }

    private func detailHero(_ record: PPDeliveryRequestRecord) -> some View {
        let color = deliveryStatusColor(record.status)
        let order = record.orderNumber.isEmpty ? (record.orderID.isEmpty ? record.requestID : record.orderID) : record.orderNumber
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(AdminSurface.hairline.opacity(0.42), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.08), radius: 24, y: 12)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 5)
                .padding(.vertical, 24)
                .padding(.leading, 17)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(deliveryStatusText(record.status))
                        .font(AdminType.captionBold)
                        .foregroundColor(color)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 26)
                        .background(color.opacity(0.10), in: Capsule())
                    Spacer()
                    Text(deliveryFormat("DeliveryCompany_Detail_Updated_Format", deliveryDateText(record.updatedAt)))
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                Text(deliveryFormat("DeliveryCompany_Order_Format", order))
                    .font(AdminType.title)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .textSelection(.enabled)
                Text(deliveryText("DeliveryCompany_Official_Name"))
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primary)
                Text(record.requestID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AdminSurface.secondaryText)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 22)
            .padding(.leading, 38)
            .padding(.trailing, 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func routeSection(_ record: PPDeliveryRequestRecord) -> some View {
        dossierSection("DeliveryCompany_Detail_Route", symbol: "arrow.triangle.turn.up.right.diamond.fill") {
            routeRow(titleKey: "DeliveryCompany_Pickup",
                     value: deliveryAddressText(record.pickupAddress),
                     symbol: "shippingbox.fill",
                     color: .orange)
            routeRow(titleKey: "DeliveryCompany_Dropoff",
                     value: deliveryAddressText(record.dropoffAddress),
                     symbol: "mappin.and.ellipse",
                     color: .green)
        }
    }

    private func routeRow(titleKey: String, value: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(deliveryText(titleKey))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)
                Text(value)
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(AdminSurface.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func assignmentSummary(_ record: PPDeliveryRequestRecord) -> some View {
        dossierSection("DeliveryCompany_Detail_Assignment", symbol: "person.crop.circle.badge.checkmark") {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 42, height: 42)
                    .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.assignedDriverName.isEmpty ? deliveryText("DeliveryCompany_Unassigned") : record.assignedDriverName)
                        .font(AdminType.title3)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(record.assignedDriverUID.isEmpty
                         ? deliveryText("DeliveryCompany_Detail_AssignmentPending")
                         : deliveryText("DeliveryCompany_Detail_AssignedDriver"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                    if !record.assignedDriverUID.isEmpty {
                        Text(record.assignedDriverUID)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(AdminSurface.secondaryText)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func dossierSection<Content: View>(_ titleKey: String,
                                               symbol: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        deliveryCompanySurface {
            VStack(alignment: .leading, spacing: 12) {
                Label(deliveryText(titleKey), systemImage: symbol)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .accessibilityAddTraits(.isHeader)
                content()
            }
            .padding(20)
        }
    }

    private func deliveryCompanySurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AdminSurface.hairline.opacity(0.42), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 20, y: 10)
    }

    private func dossierFact(_ labelKey: String, _ rawValue: String) -> some View {
        let value = rawValue.isEmpty ? deliveryText("Delivery_Not_Available") : rawValue
        return HStack(alignment: .top, spacing: 12) {
            Text(deliveryText(labelKey))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 7)
    }

    private func codSection(_ record: PPDeliveryRequestRecord) -> some View {
        let cod = deliveryDictionary(record.cod)
        let currency = cod["currency"] as? String ?? "QAR"
        return dossierSection("Delivery_Dossier_COD", symbol: "banknote") {
            dossierFact("Delivery_COD_Status", record.codStatus)
            dossierFact("Delivery_COD_Expected", deliveryCurrencyText(cod["expectedAmount"] as? NSNumber, currency: currency))
            dossierFact("Delivery_COD_Collected", deliveryCurrencyText(cod["collectedAmount"] as? NSNumber, currency: currency))
            dossierFact("Delivery_COD_Handover", deliveryDateText(cod["handoverAt"]))
            dossierFact("Delivery_COD_Reconciled", deliveryDateText(cod["reconciledAt"]))
        }
    }

    private func podSection(_ record: PPDeliveryRequestRecord) -> some View {
        let pod = deliveryDictionary(record.proofOfDelivery)
        return dossierSection("Delivery_Dossier_POD", symbol: "signature") {
            dossierFact("Delivery_POD_Status", record.podStatus)
            dossierFact("Delivery_POD_Completeness", pod["evidenceCompleteness"] as? String ?? "")
            dossierFact("Delivery_POD_Receiver", pod["receiverName"] as? String ?? "")
            dossierFact("Delivery_POD_Delivered_At", deliveryDateText(pod["deliveredAt"]))
            let photoCount = (pod["photoUrls"] as? [Any])?.count ?? 0
            dossierFact("Delivery_POD_Photos", "\(photoCount)")
        }
    }

    private func eventSection(_ events: [Any]) -> some View {
        dossierSection("Delivery_Dossier_Audit", symbol: "clock.arrow.circlepath") {
            if events.isEmpty {
                Text(deliveryText("Delivery_Events_Empty"))
                    .font(AdminType.subheadline)
                    .foregroundColor(AdminSurface.secondaryText)
            } else {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    let dict = deliveryDictionary(event)
                    let transitionArrow = Language.isRTL() ? "←" : "→"
                    VStack(alignment: .leading, spacing: 3) {
                        Text(deliveryEnumText(dict["eventType"] as? String ?? "DELIVERY_EVENT"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text("\(deliveryEnumText(dict["fromStatus"] as? String ?? "")) \(transitionArrow) \(deliveryEnumText(dict["toStatus"] as? String ?? ""))")
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(deliveryDateText(dict["createdAt"]))
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func commandDock(_ record: PPDeliveryRequestRecord) -> some View {
        let assignmentNames: Set<String> = ["ASSIGN", "REASSIGN"]
        let evidenceNames: Set<String> = ["DELIVER", "FINALIZE_POD"]
        let actions = record.allowedActions.filter {
            !evidenceNames.contains($0.action)
        }
        return Group {
            if actions.isEmpty {
                EmptyView()
            } else {
                deliveryCompanySurface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(deliveryText("DeliveryCompany_Detail_Actions"), systemImage: "bolt.fill")
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(deliveryText("Delivery_Stale_Action_Notice"))
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                        if let reconcile = actions.first(where: { $0.action == "RECONCILE_COD" }) {
                            Toggle(deliveryText("Delivery_COD_Handover_Confirmed"), isOn: $handoverConfirmed)
                                .font(AdminType.captionBold)
                            deliveryActionButton(reconcile, enabled: handoverConfirmed) {
                                let pending = PendingDeliveryCommand(action: reconcile,
                                                                     driverUID: nil,
                                                                     handoverConfirmed: true)
                                presentCommandAlert(for: pending)
                            }
                        }
                        ForEach(actions.filter { $0.action != "RECONCILE_COD" }, id: \.action) { action in
                            deliveryActionButton(action, enabled: true) {
                                if assignmentNames.contains(action.action) {
                                    pendingAssignment = PendingDeliveryAssignment(action: action)
                                } else {
                                    let pending = PendingDeliveryCommand(action: action,
                                                                         driverUID: nil,
                                                                         handoverConfirmed: false)
                                    presentCommandAlert(for: pending)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func deliveryActionButton(_ action: PPDeliveryAllowedAction,
                                      enabled: Bool,
                                      perform: @escaping () -> Void) -> some View {
        let destructive = ["REJECT", "CANCEL", "FAIL"].contains(action.action)
        let tint = destructive ? Color.red : AdminSurface.primary
        return Button(action: perform) {
            Text(deliveryCommandText(action.action))
                .font(AdminType.subheadlineBold)
                .foregroundColor(destructive ? .red : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(destructive ? Color.red.opacity(0.10) : tint,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: destructive ? .clear : tint.opacity(0.22), radius: 16, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || viewModel.isExecuting)
        .opacity((enabled && !viewModel.isExecuting) ? 1 : 0.46)
    }
}

private struct DeliveryDriverPickerSheet: View {
    let action: PPDeliveryAllowedAction
    let drivers: [PPDeliveryDriverRecord]
    let isExecuting: Bool
    let onSelect: (PPDeliveryDriverRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        pickerHero
                        if drivers.isEmpty {
                            AdminEmptyStateView(
                                symbol: "person.2.slash",
                                title: deliveryText("DeliveryCompany_NoDrivers_Title"),
                                subtitle: deliveryText("DeliveryCompany_NoDrivers_Subtitle")
                            )
                            .frame(minHeight: 300)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(drivers, id: \.uid) { driver in
                                    driverChoice(driver)
                                }
                            }
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(deliveryCommandText(action.action))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(deliveryText("Close")) { dismiss() }
                }
            }
        }
    }

    private var pickerHero: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AdminSurface.hairline.opacity(0.42), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.07), radius: 22, y: 11)
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 52, height: 52)
                    .background(AdminSurface.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(deliveryText("Delivery_Assignment_Candidates"))
                        .font(AdminType.title2)
                        .foregroundColor(AdminSurface.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text(deliveryText("DeliveryCompany_SelectDriver"))
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(20)
        }
    }

    private func driverChoice(_ driver: PPDeliveryDriverRecord) -> some View {
        let accent: Color = driver.eligible ? AdminSurface.primary : .orange
        return Button {
            guard driver.eligible && !isExecuting else { return }
            onSelect(driver)
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AdminSurface.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(driver.eligible ? AdminSurface.hairline.opacity(0.42) : Color.orange.opacity(0.20), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.06), radius: 18, y: 9)
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 46, height: 46)
                        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(driver.displayName)
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(driver.eligible
                             ? deliveryText("Delivery_Driver_Eligible")
                             : driver.eligibilityReasonCodes.map(deliveryEnumText).joined(separator: " · "))
                            .font(AdminType.caption1)
                            .foregroundColor(driver.eligible ? .green : .orange)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(deliveryFormat("DeliveryCompany_Members_ActiveCount_Format", driver.activeDeliveryCount))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(accent)
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(DeliveryCompanyCardButtonStyle())
        .disabled(!driver.eligible || isExecuting)
        .opacity(driver.eligible ? 1 : 0.68)
        .accessibilityHint(driver.eligible ? deliveryCommandText(action.action) : deliveryText("Delivery_Why_Unavailable"))
    }
}

private struct DeliveryDriverDetailSheet: View {
    @ObservedObject var viewModel: DeliveryCommandCenterViewModel
    let driver: PPDeliveryDriverRecord
    let onDismiss: () -> Void

    private var member: PPDeliveryCompanyMemberRecord? {
        viewModel.member(for: driver.uid)
    }

    private var phone: String {
        let memberPhone = member?.phone.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return memberPhone.isEmpty ? driver.phone : memberPhone
    }

    private var isAvailable: Bool {
        driver.accountStatus.uppercased() == "ACTIVE" &&
            driver.canReceiveAssignments &&
            (member?.available ?? true)
    }

    var body: some View {
        VStack(spacing: 0) {
            sovereignHeaderBar

            ZStack {
                AdminSurface.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        profileHero
                        operationalSummary
                        identityCard
                        if let incident = viewModel.memberIncident ?? viewModel.commandIncident {
                            DeliveryIncidentPanel(incident: incident, retry: nil)
                        }
                        if let errorKey = viewModel.memberErrorKey {
                            Label(deliveryText(errorKey), systemImage: "exclamationmark.triangle.fill")
                                .font(AdminType.calloutBold)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .accessibilityElement(children: .combine)
                        }
                        contactActions
                        managementActions
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
                if viewModel.isExecuting {
                    AdminLoadingOverlay(message: deliveryText("Delivery_Command_Applying"))
                        .background(Color.black.opacity(0.08))
                        .accessibilityAddTraits(.isModal)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var sovereignHeaderBar: some View {
        HStack {
            Spacer()
            Text(deliveryText("Delivery_Driver_Profile_Title"))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
            Spacer()
        }
        .overlay(alignment: Language.isRTL() ? .trailing : .leading) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            }) {
                Text(deliveryText("Close"))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(AdminSurface.primary.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(AdminSurface.primary.opacity(0.20), lineWidth: 1.0))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .frame(height: 56)
        .background(AdminSurface.surface)
        .overlay(alignment: .bottom) {
            Divider().background(AdminSurface.hairline)
        }
    }

    private func presentDriverCommandAlert(for pending: PendingDriverCommand) {
        let destructive = pending.action == "SUSPEND"
        let iconName = destructive ? "exclamationmark.triangle.fill" : "questionmark.circle.fill"
        let icon = UIImage(systemName: iconName)

        PPAlertHelper.showConfirmation(
            in: nil,
            title: deliveryText("Delivery_Confirm_Driver_Command"),
            subtitle: "\(driver.displayName) · \(deliveryCommandText(pending.action))",
            confirmButton: deliveryText("Confirm"),
            cancelButton: deliveryText("Cancel"),
            icon: icon,
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                execute(pending)
            },
            cancelBlock: nil
        )
    }

    private func presentDriverDisableAlert() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: deliveryText("Delivery_Driver_Disable_Confirm_Title"),
            subtitle: deliveryText("Delivery_Driver_Disable_Confirm_Message"),
            confirmButton: deliveryText("Confirm"),
            cancelButton: deliveryText("Cancel"),
            icon: UIImage(systemName: "person.crop.circle.badge.minus"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                viewModel.disableDriver(driver.uid) { succeeded in
                    if succeeded { onDismiss() }
                }
            },
            cancelBlock: nil
        )
    }

    private var profileHero: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(AdminSurface.hairline.opacity(0.42), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.07), radius: 24, y: 12)
            VStack(spacing: 10) {
                detailAvatar
                Text(driver.displayName)
                    .font(AdminType.title)
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(deliveryText("Delivery_Driver_Role"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 26)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                Label(isAvailable
                      ? deliveryText("DeliveryCompany_Members_Available")
                      : deliveryText("DeliveryCompany_Members_Unavailable"),
                      systemImage: isAvailable ? "checkmark.circle.fill" : "pause.circle.fill")
                    .font(AdminType.captionBold)
                    .foregroundColor(isAvailable ? .green : .orange)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private var detailAvatar: some View {
        if let rawURL = member?.photoURL,
           let url = URL(string: rawURL),
           !rawURL.isEmpty {
            AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 84, height: 84)) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
            }
            .frame(width: 84, height: 84)
            .background(AdminSurface.primary.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .accessibilityHidden(true)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 84, height: 84)
                .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var operationalSummary: some View {
        HStack(spacing: 10) {
            metric(deliveryEnumText(driver.presence), "Delivery_Driver_Presence")
            metric(deliveryEnumText(driver.shiftStatus), "Delivery_Driver_Shift")
            metric("\(driver.activeDeliveryCount)", "Delivery_Driver_Workload")
        }
    }

    private func metric(_ value: String, _ titleKey: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deliveryText(titleKey))
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
            Text(value)
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(.horizontal, 12)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var identityCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: 0) {
                Label(deliveryText("Delivery_Driver_Identity_Title"), systemImage: "person.text.rectangle")
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
                infoRow("Delivery_Driver_UID", driver.uid, semanticLTR: true)
                Divider()
                infoRow("Delivery_Driver_Phone", phone.isEmpty ? deliveryText("Delivery_Not_Available") : phone,
                        semanticLTR: !phone.isEmpty)
                Divider()
                infoRow("Delivery_Driver_Email",
                        member?.email.isEmpty == false ? member?.email ?? "" : deliveryText("Delivery_Not_Available"),
                        semanticLTR: member?.email.isEmpty == false)
                Divider()
                infoRow("Delivery_Driver_Last_Seen",
                        member?.online == true
                            ? deliveryText("Delivery_Driver_Online")
                            : deliveryDateText(member?.lastSeenAt),
                        semanticLTR: false)
            }
            .padding(18)
        }
    }

    private func infoRow(_ titleKey: String, _ value: String, semanticLTR: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(deliveryText(titleKey))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .environment(\.layoutDirection, semanticLTR ? .leftToRight : (Language.isRTL() ? .rightToLeft : .leftToRight))
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var contactActions: some View {
        if !phone.isEmpty {
            Button(action: callDriver) {
                Label(deliveryText("Delivery_Driver_Call"), systemImage: "phone.fill")
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var managementActions: some View {
        if viewModel.canManageDrivers {
            AdminCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(deliveryText("Delivery_Driver_Management_Actions"), systemImage: "slider.horizontal.3")
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    if driver.accountStatus.uppercased() == "ACTIVE" {
                        managementButton(action: driver.canReceiveAssignments ? "PAUSE" : "RESUME",
                                         destructive: false)
                        managementButton(action: "SUSPEND", destructive: true)
                    } else if driver.accountStatus.uppercased() == "SUSPENDED" {
                        managementButton(action: "REACTIVATE", destructive: false)
                    }
                    if member?.status.lowercased() == "active" {
                        Divider().padding(.vertical, 2)
                        Button {
                            presentDriverDisableAlert()
                        } label: {
                            Label(deliveryText("Delivery_Driver_Disable_Membership"), systemImage: "person.crop.circle.badge.minus")
                                .font(AdminType.subheadlineBold)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
        }
    }

    private func managementButton(action: String, destructive: Bool) -> some View {
        Button {
            let pending = PendingDriverCommand(action: action, driver: driver)
            presentDriverCommandAlert(for: pending)
        } label: {
            Label(deliveryCommandText(action), systemImage: driverActionSymbol(action))
                .font(AdminType.subheadlineBold)
                .foregroundColor(destructive ? .red : .white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(destructive ? Color.red.opacity(0.09) : AdminSurface.primary,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isExecuting)
    }

    private func execute(_ pending: PendingDriverCommand) {
        viewModel.executeDriver(pending) { succeeded in
            if succeeded { onDismiss() }
        }
    }

    private func callDriver() {
        let allowed = CharacterSet(charactersIn: "+0123456789")
        let normalized = phone.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
        guard !normalized.isEmpty, let url = URL(string: "tel://\(normalized)") else { return }
        UIApplication.shared.open(url)
    }

    private func driverActionSymbol(_ action: String) -> String {
        switch action {
        case "PAUSE": return "pause.fill"
        case "RESUME": return "play.fill"
        case "SUSPEND": return "exclamationmark.octagon.fill"
        case "REACTIVATE": return "arrow.counterclockwise.circle.fill"
        default: return "bolt.fill"
        }
    }
}

private struct DeliveryDriverInviteSheet: View {
    @ObservedObject var viewModel: DeliveryCommandCenterViewModel
    let onDismiss: () -> Void
    @State private var identifier = ""
    @FocusState private var identifierFocused: Bool

    private var canSubmit: Bool {
        !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !viewModel.isExecuting
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        inviteHero
                        AdminCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(deliveryText("Delivery_Driver_Invite_Identity_Title"))
                                    .font(AdminType.headline)
                                    .foregroundColor(AdminSurface.primaryText)
                                    .accessibilityAddTraits(.isHeader)
                                TextField(deliveryText("Delivery_Driver_Invite_Placeholder"), text: $identifier)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .focused($identifierFocused)
                                    .submitLabel(.done)
                                    .onSubmit(submit)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 54)
                                    .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(identifierFocused ? AdminSurface.primary : AdminSurface.hairline.opacity(0.65),
                                                    lineWidth: identifierFocused ? 1.5 : 0.5)
                                    }
                                Text(deliveryText("Delivery_Driver_Invite_Identity_Help"))
                                    .font(AdminType.caption1)
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                            .padding(18)
                        }
                        AdminCard {
                            HStack(spacing: 12) {
                                Image(systemName: "car.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(AdminSurface.primary)
                                    .frame(width: 42, height: 42)
                                    .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(deliveryText("Delivery_Driver_Invite_Role_Title"))
                                        .font(AdminType.caption1)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    Text(deliveryText("Delivery_Driver_Role"))
                                        .font(AdminType.headline)
                                        .foregroundColor(AdminSurface.primaryText)
                                }
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                            .padding(18)
                        }
                        if let incident = viewModel.memberIncident {
                            DeliveryIncidentPanel(incident: incident, retry: nil)
                        }
                        if let errorKey = viewModel.memberErrorKey {
                            Label(deliveryText(errorKey), systemImage: "exclamationmark.triangle.fill")
                                .font(AdminType.calloutBold)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .accessibilityElement(children: .combine)
                        }
                        Button(action: submit) {
                            Label(deliveryText("Delivery_Driver_Invite_Action"), systemImage: "person.badge.plus")
                                .font(AdminType.subheadlineBold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.45)
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
                if viewModel.isExecuting {
                    AdminLoadingOverlay(message: deliveryText("Delivery_Command_Applying"))
                        .background(Color.black.opacity(0.08))
                        .accessibilityAddTraits(.isModal)
                }
            }
            .navigationTitle(deliveryText("Delivery_Driver_Invite_Title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(deliveryText("Close"), action: onDismiss)
                }
            }
        }
        .onAppear { identifierFocused = true }
    }

    private var inviteHero: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(AdminSurface.hairline.opacity(0.42), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.07), radius: 22, y: 11)
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 54, height: 54)
                    .background(AdminSurface.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(deliveryText("Delivery_Driver_Invite_Title"))
                        .font(AdminType.title2)
                        .foregroundColor(AdminSurface.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text(deliveryText("Delivery_Driver_Invite_Subtitle"))
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(20)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        identifierFocused = false
        viewModel.inviteDriver(identifier: identifier) { succeeded in
            if succeeded { onDismiss() }
        }
    }
}

private func deliveryCommandText(_ action: String) -> String {
    switch action.uppercased() {
    case "ACCEPT": return deliveryText("Delivery_Command_Accept")
    case "REJECT": return deliveryText("Delivery_Command_Reject")
    case "ASSIGN": return deliveryText("Delivery_Command_Assign")
    case "REASSIGN": return deliveryText("Delivery_Command_Reassign")
    case "PICK_UP": return deliveryText("Delivery_Command_Pickup")
    case "START_TRANSIT": return deliveryText("Delivery_Command_Start_Transit")
    case "COMPLETE": return deliveryText("Delivery_Command_Complete")
    case "CANCEL": return deliveryText("Delivery_Command_Cancel")
    case "FAIL": return deliveryText("Delivery_Command_Fail")
    case "RECONCILE_COD": return deliveryText("Delivery_Command_Reconcile_COD")
    case "PAUSE": return deliveryText("Delivery_Driver_Pause")
    case "RESUME": return deliveryText("Delivery_Driver_Resume")
    case "SUSPEND": return deliveryText("Delivery_Driver_Suspend")
    case "REACTIVATE": return deliveryText("Delivery_Driver_Reactivate")
    default: return deliveryText("Delivery_Actions")
    }
}

private func deliveryCommandConfirmationTitle(_ action: String) -> String {
    switch action.uppercased() {
    case "ACCEPT": return deliveryText("DeliveryCompany_Confirm_Accept_Title")
    case "REJECT": return deliveryText("DeliveryCompany_Confirm_Reject_Title")
    case "COMPLETE": return deliveryText("DeliveryCompany_Confirm_Complete_Title")
    case "CANCEL": return deliveryText("DeliveryCompany_Confirm_Cancel_Title")
    default: return deliveryText("Delivery_Confirm_Command")
    }
}

private func deliveryCommandConfirmationMessage(_ action: String) -> String {
    switch action.uppercased() {
    case "ACCEPT": return deliveryText("DeliveryCompany_Confirm_Accept_Message")
    case "COMPLETE": return deliveryText("DeliveryCompany_Confirm_Complete_Message")
    default: return deliveryCommandText(action)
    }
}

private func deliveryFunnelLabel(_ key: String) -> String {
    switch key {
    case "totalRegistered": return deliveryText("Delivery_Funnel_Total")
    case "active": return deliveryText("Delivery_Funnel_Active")
    case "onShift": return deliveryText("Delivery_Funnel_On_Shift")
    case "online": return deliveryText("Delivery_Funnel_Online")
    case "locationFresh": return deliveryText("Delivery_Funnel_Location_Fresh")
    case "zoneEligible": return deliveryText("Delivery_Funnel_Zone_Eligible")
    case "capacityAvailable": return deliveryText("Delivery_Funnel_Capacity")
    case "eligibleNow": return deliveryText("Delivery_Funnel_Eligible_Now")
    default: return deliveryEnumText(key)
    }
}

private func deliveryFreshnessText(_ snapshot: PPDeliveryCommandCenterSnapshot) -> String {
    let projection = deliveryDictionary(snapshot.projection)
    guard let generatedAt = projection["generatedAt"] else { return deliveryText("Delivery_Freshness_Unknown") }
    return "\(deliveryText("Delivery_Freshness_Generated")) \(deliveryDateText(generatedAt))"
}

private struct DeliveryCompanyCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
