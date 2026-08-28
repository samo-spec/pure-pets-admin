import SwiftUI
import FirebaseFirestore

extension PPDeliveryRequestRecord: @unchecked Sendable {}
extension PPDeliveryDriverRecord: @unchecked Sendable {}
extension PPDeliveryExceptionRecord: @unchecked Sendable {}
extension PPDeliveryAllowedAction: @unchecked Sendable {}
extension PPDeliveryCommandCenterSnapshot: @unchecked Sendable {}
extension PPDeliveryDossierSnapshot: @unchecked Sendable {}
extension PPDeliveryCommandResult: @unchecked Sendable {}

private func deliveryText(_ key: String) -> String {
    Language.get(key, alter: nil)
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
    case "assigned_to_driver", "picked_up", "in_transit": return .info
    case "offered", "accepted_by_company", "pending": return .warning
    default: return .neutral
    }
}

private func deliveryStatusText(_ status: String) -> String {
    switch status.lowercased() {
    case "offered": return deliveryText("Delivery_Status_Offered")
    case "accepted_by_company": return deliveryText("Delivery_Status_Accepted")
    case "assigned_to_driver": return deliveryText("Delivery_Status_Assigned")
    case "picked_up": return deliveryText("Delivery_Status_PickedUp")
    case "in_transit": return deliveryText("Delivery_Status_InTransit")
    case "delivered": return deliveryText("Delivery_Status_Delivered")
    case "completed": return deliveryText("Delivery_Status_Completed")
    case "cancelled": return deliveryText("Delivery_Status_Cancelled")
    case "rejected": return deliveryText("Delivery_Status_Rejected")
    case "failed": return deliveryText("Delivery_Status_Failed")
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
    case overview
    case deliveries
    case drivers
    case exceptions
    case cod
    case pod

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .overview: return "Delivery_Tab_Overview"
        case .deliveries: return "Delivery_Tab_Deliveries"
        case .drivers: return "Delivery_Tab_Drivers"
        case .exceptions: return "Delivery_Tab_Exceptions"
        case .cod: return "Delivery_Tab_COD"
        case .pod: return "Delivery_Tab_POD"
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
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingDossier = false
    @Published private(set) var isExecuting = false
    @Published private(set) var incident: DeliveryIncident?
    @Published private(set) var dossierIncident: DeliveryIncident?
    @Published private(set) var commandIncident: DeliveryIncident?
    @Published var searchText = ""
    @Published var selectedTab: DeliveryAdminTab = .overview
    @Published var selectedRequestID: String?

    var records: [PPDeliveryRequestRecord] { snapshot?.records ?? [] }
    var drivers: [PPDeliveryDriverRecord] { snapshot?.drivers ?? [] }
    var exceptions: [PPDeliveryExceptionRecord] { snapshot?.exceptions ?? [] }

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

    var availableTabs: [DeliveryAdminTab] {
        guard let snapshot else { return [.overview, .deliveries] }
        let permissions = Set(snapshot.permissions)
        let legacy = snapshot.permissionSource == "legacy_official_delivery_bridge"
        var result: [DeliveryAdminTab] = [.overview, .deliveries]
        if legacy || permissions.contains("delivery.driver.view") { result.append(.drivers) }
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
            }
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

    func executeDriver(_ pending: PendingDriverCommand) {
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
                }
                self.load(refresh: true)
            }
        }
    }
}

struct AdminDeliveryListView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = DeliveryCommandCenterViewModel()
    @State private var pendingDriverCommand: PendingDriverCommand?

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
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
        .alert(item: $pendingDriverCommand) { pending in
            Alert(
                title: Text(deliveryText("Delivery_Confirm_Driver_Command")),
                message: Text("\(pending.driver.displayName) · \(deliveryCommandText(pending.action))"),
                primaryButton: .destructive(Text(deliveryText("Confirm"))) {
                    viewModel.executeDriver(pending)
                },
                secondaryButton: .cancel(Text(deliveryText("Cancel")))
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack {
                Button(action: close) {
                    HStack(spacing: 6) {
                        Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                        Text(deliveryText("Back"))
                    }
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primary)
                    .frame(minHeight: 44)
                }
                Spacer()
                if viewModel.isLoading || viewModel.isRefreshing {
                    ProgressView().tint(AdminSurface.primary)
                } else {
                    Button { viewModel.load(refresh: true) } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(AdminSurface.primary.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AdminSurface.primary)
                    .accessibilityLabel(deliveryText("Refresh"))
                }
            }

            Text(deliveryText("Delivery_Command_Center_Title"))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)
                .accessibilityAddTraits(.isHeader)
            if let snapshot = viewModel.snapshot {
                let carrier = deliveryDictionary(snapshot.carrier)
                HStack(spacing: 8) {
                    AdminStatusBadge(
                        text: (carrier["name"] as? String) ?? deliveryText("Delivery_Carrier_Unknown"),
                        status: .info
                    )
                    Text(deliveryFreshnessText(snapshot))
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                if snapshot.permissionSource == "legacy_official_delivery_bridge" {
                    Label(deliveryText("Delivery_Legacy_Permission_Warning"), systemImage: "exclamationmark.shield.fill")
                        .font(AdminType.captionBold)
                        .foregroundColor(.orange)
                        .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
        .padding(.bottom, AdminSpacing.sm)
        .background(AdminSurface.background)
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
                            .padding(.horizontal, 14)
                            .frame(minHeight: 38)
                            .background(viewModel.selectedTab == tab ? AdminSurface.primary : AdminSurface.control,
                                        in: Capsule())
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
                    switch viewModel.selectedTab {
                    case .overview: overview
                    case .deliveries: deliveries
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

    private var deliveries: some View {
        VStack(spacing: 12) {
            AdminSearchField(text: $viewModel.searchText, placeholder: deliveryText("Delivery_Search"))
            deliveryList(viewModel.filteredRecords, emptyKey: "Delivery_Empty")
        }
    }

    private var drivers: some View {
        VStack(spacing: 10) {
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

    private func driverCard(_ driver: PPDeliveryDriverRecord) -> some View {
        let canManage = viewModel.snapshot?.permissionSource == "legacy_official_delivery_bridge" ||
            (viewModel.snapshot?.permissions.contains("delivery.driver.manage") == true)
        return AdminCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(driver.displayName).font(AdminType.headline).foregroundColor(AdminSurface.primaryText)
                        Text(driver.uid).font(AdminType.caption1).foregroundColor(AdminSurface.secondaryText).textSelection(.enabled)
                    }
                    Spacer()
                    AdminStatusBadge(text: deliveryEnumText(driver.accountStatus),
                                     status: driver.accountStatus == "ACTIVE" ? .success : .error)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 8)], spacing: 8) {
                    driverFact("Delivery_Driver_Presence", deliveryEnumText(driver.presence))
                    driverFact("Delivery_Driver_Shift", deliveryEnumText(driver.shiftStatus))
                    driverFact("Delivery_Driver_Work_State", deliveryEnumText(driver.workState))
                    driverFact("Delivery_Driver_Workload", driver.maxConcurrentDeliveries.map { "\(driver.activeDeliveryCount) / \($0.intValue)" } ?? "\(driver.activeDeliveryCount)")
                }
                if !driver.eligibilityReasonCodes.isEmpty {
                    Label(driver.eligibilityReasonCodes.map(deliveryEnumText).joined(separator: " · "),
                          systemImage: "info.circle")
                        .font(AdminType.caption1)
                        .foregroundColor(.orange)
                }
                if canManage {
                    HStack {
                        Button(deliveryText(driver.canReceiveAssignments ? "Delivery_Driver_Pause" : "Delivery_Driver_Resume")) {
                            pendingDriverCommand = PendingDriverCommand(action: driver.canReceiveAssignments ? "PAUSE" : "RESUME", driver: driver)
                        }
                        .buttonStyle(.bordered)
                        if driver.accountStatus == "ACTIVE" {
                            Button(deliveryText("Delivery_Driver_Suspend"), role: .destructive) {
                                pendingDriverCommand = PendingDriverCommand(action: "SUSPEND", driver: driver)
                            }
                            .buttonStyle(.bordered)
                        } else if driver.accountStatus == "SUSPENDED" {
                            Button(deliveryText("Delivery_Driver_Reactivate")) {
                                pendingDriverCommand = PendingDriverCommand(action: "REACTIVATE", driver: driver)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .font(AdminType.captionBold)
                }
            }
            .padding(16)
        }
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
                                subtitle: deliveryText("Delivery_Empty_Detail"))
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
            AdminCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.orderNumber.isEmpty ? record.orderID : record.orderNumber)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)
                            Text("\(deliveryText("Delivery_Revision")) \(record.revision)")
                                .font(AdminType.caption1)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        Spacer()
                        AdminStatusBadge(text: deliveryStatusText(record.status), status: deliveryStatusBadge(record.status))
                    }
                    HStack {
                        Label(record.customerName.isEmpty ? deliveryText("Delivery_UnknownCustomer") : record.customerName,
                              systemImage: "person")
                        Spacer()
                        Label(record.assignedDriverName.isEmpty ? deliveryText("Delivery_DriverUnassigned") : record.assignedDriverName,
                              systemImage: "steeringwheel")
                    }
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                    HStack {
                        Text(deliveryCurrencyText(record.deliveryFee, currency: record.cod["currency"] as? String ?? "QAR"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primary)
                        Spacer()
                        AdminStatusBadge(text: record.authority == "FULFILLMENT_V1" ? deliveryText("Delivery_Authority_Fulfillment") : deliveryText("Delivery_Authority_Company"), status: .neutral)
                    }
                }
                .padding(15)
            }
        }
        .buttonStyle(.plain)
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

private struct DeliveryDossierSheet: View {
    @ObservedObject var viewModel: DeliveryCommandCenterViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingCommand: PendingDeliveryCommand?
    @State private var handoverConfirmed = false

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                AdminSurface.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if viewModel.isLoadingDossier && viewModel.dossier == nil {
                            AdminLoadingOverlay(message: deliveryText("Delivery_Loading_Dossier"))
                                .frame(minHeight: 300)
                        } else if let incident = viewModel.dossierIncident {
                            DeliveryIncidentPanel(incident: incident, retry: {
                                viewModel.loadDossier()
                            })
                        } else if let dossier = viewModel.dossier {
                            dossierContent(dossier)
                        }
                        if let incident = viewModel.commandIncident {
                            DeliveryIncidentPanel(incident: incident, retry: nil)
                        }
                    }
                    .padding(AdminSpacing.screenMargin)
                    .padding(.bottom, 110)
                }
                if let record = viewModel.dossier?.record {
                    commandDock(record)
                }
            }
            .navigationTitle(viewModel.dossier?.record.orderNumber ?? deliveryText("Delivery_Dossier_Title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(deliveryText("Close")) {
                        viewModel.closeDossier()
                        dismiss()
                    }
                }
            }
        }
        .alert(item: $pendingCommand) { pending in
            Alert(
                title: Text(deliveryText("Delivery_Confirm_Command")),
                message: Text(deliveryCommandText(pending.action.action)),
                primaryButton: .destructive(Text(deliveryText("Confirm"))) {
                    viewModel.execute(pending.action,
                                      driverUID: pending.driverUID,
                                      handoverConfirmed: pending.handoverConfirmed)
                },
                secondaryButton: .cancel(Text(deliveryText("Cancel")))
            )
        }
    }

    private func dossierContent(_ dossier: PPDeliveryDossierSnapshot) -> some View {
        let record = dossier.record
        return VStack(spacing: 14) {
            AdminCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        AdminStatusBadge(text: deliveryStatusText(record.status), status: deliveryStatusBadge(record.status))
                        Spacer()
                        Text("\(deliveryText("Delivery_Revision")) \(record.revision)")
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    Text(record.orderNumber.isEmpty ? record.requestID : record.orderNumber)
                        .font(AdminType.title2)
                        .foregroundColor(AdminSurface.primaryText)
                        .textSelection(.enabled)
                    Text(record.authority == "FULFILLMENT_V1" ? deliveryText("Delivery_Authority_Fulfillment_Detail") : deliveryText("Delivery_Authority_Company_Detail"))
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .padding(16)
            }

            if record.authority == "FULFILLMENT_V1" {
                AdminCard {
                    Label(deliveryText("Delivery_Fulfillment_Read_Only"), systemImage: "lock.shield")
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(16)
                        .accessibilityElement(children: .combine)
                }
            }

            dossierSection("Delivery_Dossier_Customer", symbol: "person") {
                dossierFact("Delivery_Dossier_Customer", record.customerName)
                dossierFact("Delivery_Dossier_Order", record.orderID)
            }
            dossierSection("Delivery_Dossier_Locations", symbol: "mappin.and.ellipse") {
                dossierFact("Delivery_Dossier_Pickup", deliveryAddressText(record.pickupAddress))
                dossierFact("Delivery_Dossier_Dropoff", deliveryAddressText(record.dropoffAddress))
            }
            dossierSection("Delivery_Dossier_Assignment", symbol: "steeringwheel") {
                dossierFact("Delivery_Dossier_Carrier", record.carrierName)
                dossierFact("Delivery_Dossier_Driver", record.assignedDriverName)
                dossierFact("Delivery_Dossier_Driver_UID", record.assignedDriverUID)
            }
            dossierSection("Delivery_Dossier_Lifecycle", symbol: "point.topleft.down.to.point.bottomright.curvepath") {
                dossierFact("Delivery_Dimension_Job", record.deliveryJobStatus)
                dossierFact("Delivery_Dimension_Carrier", record.carrierAssignmentStatus)
                dossierFact("Delivery_Dimension_Driver", record.driverAssignmentStatus)
                dossierFact("Delivery_Dimension_Route", record.routeStatus)
                dossierFact("Delivery_Dimension_POD", record.podStatus)
                dossierFact("Delivery_Dimension_COD", record.codStatus)
                dossierFact("Delivery_Dimension_Return", record.returnStatus)
            }
            codSection(record)
            podSection(record)
            assignmentSection(record, dossier: dossier)
            eventSection(dossier.events.map { $0 as Any })
        }
    }

    private func dossierSection<Content: View>(_ titleKey: String,
                                               symbol: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        AdminCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(deliveryText(titleKey), systemImage: symbol)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .accessibilityAddTraits(.isHeader)
                content()
            }
            .padding(16)
        }
    }

    private func dossierFact(_ labelKey: String, _ rawValue: String) -> some View {
        let value = rawValue.isEmpty ? deliveryText("Delivery_Not_Available") : deliveryEnumText(rawValue)
        return VStack(alignment: .leading, spacing: 2) {
            Text(deliveryText(labelKey)).font(AdminType.caption1).foregroundColor(AdminSurface.secondaryText)
            Text(value).font(AdminType.subheadline).foregroundColor(AdminSurface.primaryText).textSelection(.enabled)
        }
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

    @ViewBuilder
    private func assignmentSection(_ record: PPDeliveryRequestRecord,
                                   dossier: PPDeliveryDossierSnapshot) -> some View {
        if let action = record.allowedAction(named: "ASSIGN") ?? record.allowedAction(named: "REASSIGN") {
            let drivers = dossier.drivers.filter { $0.uid != record.assignedDriverUID }
            dossierSection("Delivery_Assignment_Candidates", symbol: "person.crop.circle.badge.checkmark") {
                if drivers.isEmpty {
                    Text(deliveryText("Delivery_Drivers_Empty"))
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                } else {
                    ForEach(drivers, id: \.uid) { driver in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(driver.displayName).font(AdminType.subheadline).foregroundColor(AdminSurface.primaryText)
                                Text(driver.eligible
                                     ? deliveryText("Delivery_Driver_Eligible")
                                     : driver.eligibilityReasonCodes.map(deliveryEnumText).joined(separator: " · "))
                                    .font(AdminType.caption1)
                                    .foregroundColor(driver.eligible ? .green : .orange)
                            }
                            Spacer()
                            Button(deliveryText(action.action == "REASSIGN" ? "Delivery_Command_Reassign" : "Delivery_Command_Assign")) {
                                pendingCommand = PendingDeliveryCommand(action: action,
                                                                        driverUID: driver.uid,
                                                                        handoverConfirmed: false)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AdminSurface.primary)
                            .disabled(!driver.eligible || viewModel.isExecuting)
                        }
                        .padding(.vertical, 4)
                    }
                }
                availabilityFunnel(dossier.availabilityFunnel)
            }
        }
    }

    @ViewBuilder
    private func availabilityFunnel(_ raw: Any?) -> some View {
        let funnel = deliveryDictionary(raw)
        let reasons = deliveryDictionary(funnel["reasons"])
        if !reasons.isEmpty {
            Divider()
            Text(deliveryText("Delivery_Why_Unavailable"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
            ForEach(reasons.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(deliveryEnumText(key)).font(AdminType.caption1)
                    Spacer()
                    Text("\((reasons[key] as? NSNumber)?.intValue ?? 0)").monospacedDigit()
                }
                .foregroundColor(AdminSurface.secondaryText)
            }
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
                    let value = deliveryDictionary(event)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(deliveryEnumText(value["eventType"] as? String ?? "DELIVERY_EVENT"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text("\(deliveryEnumText(value["fromStatus"] as? String ?? "")) → \(deliveryEnumText(value["toStatus"] as? String ?? ""))")
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(deliveryDateText(value["createdAt"]))
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
            !assignmentNames.contains($0.action) && !evidenceNames.contains($0.action)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(deliveryText("Delivery_Stale_Action_Notice"))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
            if let reconcile = actions.first(where: { $0.action == "RECONCILE_COD" }) {
                HStack(alignment: .center) {
                    Toggle(deliveryText("Delivery_COD_Handover_Confirmed"), isOn: $handoverConfirmed)
                        .font(AdminType.captionBold)
                    Button(deliveryCommandText(reconcile.action)) {
                            pendingCommand = PendingDeliveryCommand(action: reconcile,
                                                                    driverUID: nil,
                                                                    handoverConfirmed: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AdminSurface.primary)
                    .disabled(!handoverConfirmed || viewModel.isExecuting)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(actions.filter { $0.action != "RECONCILE_COD" }, id: \.action) { action in
                        Button(deliveryCommandText(action.action)) {
                            pendingCommand = PendingDeliveryCommand(action: action,
                                                                    driverUID: nil,
                                                                    handoverConfirmed: false)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(["REJECT", "CANCEL", "FAIL", "COMPLETE"].contains(action.action) ? .red : AdminSurface.primary)
                        .disabled(viewModel.isExecuting)
                    }
                }
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
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
