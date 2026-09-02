//
//  PaymentListView.swift
//  PurePetsAdmin
//
//  Full SwiftUI payment management list. Header with stats, search bar,
//  status filter chips, date range picker, list of order cards. Pull to refresh.
//  Tap navigates to detail via AdminRouter.
//

import SwiftUI
import FirebaseFirestore

// MARK: - Sendable Conformance

extension PPPaymentAdminRecord: @unchecked Sendable {}

// MARK: - Payment List ViewModel

@MainActor
final class PaymentListViewModel: ObservableObject {
    @Published private(set) var records: [PPPaymentAdminRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String? = nil
    @Published var searchText: String = ""
    @Published var selectedStatusFilter: String? = nil
    @Published var selectedDateRange: PPPaymentAdminDateRange = .all

    private var nextCursor: DocumentSnapshot? = nil
    private let pageSize: Int = 20
    private var hasMorePages = true

    var statusFilterKeys: [String] {
        PPPaymentAdminRecord.quickStatusFilterKeys() as? [String] ?? []
    }

    var statsTotal: Int { records.count }
    var statsPending: Int {
        records.filter {
            PPPaymentAdminRecord.canApproveOrderStatus($0.rawStatus ?? "")
        }.count
    }
    var statsProcessing: Int {
        records.filter {
            PPPaymentAdminRecord.isProcessingLikeStatus($0.rawStatus ?? "")
        }.count
    }

    func statusDisplayTitle(_ key: String) -> String {
        PPPaymentAdminDisplayTitleForWorkflowStatus(key)
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        nextCursor = nil
        hasMorePages = true

        let filters = buildFilters()
        PPPaymentManagementService.shared().fetchOrders(
            with: filters,
            pageSize: pageSize,
            startAfter: nil
        ) { [weak self] records, cursor, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.records = records ?? []
                self.nextCursor = cursor
                self.hasMorePages = cursor != nil
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        let filters = buildFilters()
        PPPaymentManagementService.shared().fetchOrders(
            with: filters,
            pageSize: pageSize,
            startAfter: nil
        ) { [weak self] records, cursor, error in
            Task { @MainActor in
                guard let self else { return }
                self.isRefreshing = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.records = records ?? []
                self.nextCursor = cursor
                self.hasMorePages = cursor != nil
            }
        }
    }

    func loadMoreIfNeeded() {
        guard !isLoading, hasMorePages, let cursor = nextCursor else { return }
        isLoading = true
        let filters = buildFilters()
        PPPaymentManagementService.shared().fetchOrders(
            with: filters,
            pageSize: pageSize,
            startAfter: cursor
        ) { [weak self] records, cursor, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.records.append(contentsOf: records)
                self.nextCursor = cursor
                self.hasMorePages = cursor != nil
            }
        }
    }

    func toggleStatusFilter(_ key: String) {
        if selectedStatusFilter == key {
            selectedStatusFilter = nil
        } else {
            selectedStatusFilter = key
        }
        load()
    }

    func setDateRange(_ range: PPPaymentAdminDateRange) {
        selectedDateRange = range
        load()
    }

    private func buildFilters() -> PPPaymentManagementFilters {
        let filters = PPPaymentManagementFilters()
        filters.statusKey = selectedStatusFilter ?? ""
        filters.searchText = searchText.isEmpty ? "" : searchText
        filters.dateRange = selectedDateRange
        return filters
    }
}

// MARK: - Payment List View

struct AdminPaymentListView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PaymentListViewModel()
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedOrderID: String?

    init(session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.session = session
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationView {
            paymentListContent
                .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var paymentListContent: some View {
        VStack(spacing: 0) {
            dossierHeaderView
            statsHeader
            searchAndFilterBar
            Divider().background(AdminSurface.hairline)

            if viewModel.isLoading && viewModel.records.isEmpty {
                Spacer()
                ProgressView()
                    .tint(AdminSurface.primary)
                    .scaleEffect(1.2)
                Spacer()
            } else if !viewModel.records.isEmpty {
                ordersList
            } else if let error = viewModel.errorMessage {
                Spacer()
                AdminErrorBanner(message: error) { viewModel.refresh() }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                Spacer()
            } else {
                Spacer()
                AdminEmptyStateView(
                    symbol: "doc.text.magnifyingglass",
                    title: Language.get("PaymentMgmt_No_Orders", alter: "لا توجد طلبات"),
                    subtitle: Language.get("PaymentMgmt_No_Orders_Sub", alter: "لم يتم العثور على أي طلبات تطابق معايير البحث"),
                    actionTitle: Language.get("Refresh", alter: "تحديث"),
                    action: { viewModel.refresh() }
                )
                Spacer()
            }
        }
        .background(AdminSurface.background)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .background(paymentDetailPushLink)
        .onAppear {
            if viewModel.records.isEmpty { viewModel.load() }
        }
    }

    private var paymentDetailPushLink: some View {
        NavigationLink(
            destination: paymentDetailDestination,
            isActive: Binding(
                get: { selectedOrderID != nil },
                set: { isActive in
                    if !isActive {
                        selectedOrderID = nil
                    }
                }
            )
        ) {
            EmptyView()
        }
        .hidden()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var paymentDetailDestination: some View {
        if let orderID = selectedOrderID {
            AdminPaymentDetailView(orderID: orderID, session: session) {
                selectedOrderID = nil
            }
            .navigationBarHidden(true)
        } else {
            EmptyView()
        }
    }

    // MARK: - Dossier Header (PPAccessoryEditorView Pattern)

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack {
                Button(action: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(Language.get("Back", alter: "رجوع"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .frame(minHeight: 44)
                }

                Spacer()

                if viewModel.isLoading || viewModel.isRefreshing {
                    ProgressView()
                        .tint(AdminSurface.primary)
                } else {
                    Button(action: {
                        viewModel.refresh()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AdminSurface.primary)
                            .frame(width: 36, height: 36)
                            .background(AdminSurface.primary.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                }
            }

            Text(Language.get("CommandCenter_Payments_Workspace", alter: "مساحة المدفوعات") + " / " + Language.get("PaymentMgmt_Dashboard_Title", alter: "إدارة المدفوعات"))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(Language.get("PaymentMgmt_Dashboard_Title", alter: "إدارة المدفوعات"))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) {
                    viewModel.refresh()
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: AdminSpacing.md) {
            StatPill(
                title: Language.get("PaymentMgmt_Total", alter: "الإجمالي"),
                value: "\(viewModel.statsTotal)",
                color: AdminSurface.primary,
                symbol: "tray.full.fill"
            )
            StatPill(
                title: Language.get("PaymentMgmt_Pending", alter: "معلق"),
                value: "\(viewModel.statsPending)",
                color: .orange,
                symbol: "clock.fill"
            )
            StatPill(
                title: Language.get("PaymentMgmt_Processing", alter: "قيد المعالجة"),
                value: "\(viewModel.statsProcessing)",
                color: .blue,
                symbol: "arrow.triangle.2.circlepath"
            )
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.sm)
    }

    // MARK: - Search & Filter Bar

    private var searchAndFilterBar: some View {
        VStack(spacing: AdminSpacing.sm) {
            AdminSearchField(
                text: $viewModel.searchText,
                placeholder: Language.get("PaymentMgmt_Search_Placeholder", alter: "ابحث برقم الطلب أو المستخدم أو طريقة الدفع")
            )
            .onChange(of: viewModel.searchText) { _ in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    viewModel.load()
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AdminSpacing.sm) {
                    ForEach(viewModel.statusFilterKeys, id: \.self) { key in
                        FilterChip(
                            title: viewModel.statusDisplayTitle(key),
                            isSelected: viewModel.selectedStatusFilter == key
                        ) {
                            viewModel.toggleStatusFilter(key)
                        }
                    }

                    Divider().frame(height: 28).background(AdminSurface.hairline)

                    ForEach(dateRangeOptions, id: \.self) { range in
                        FilterChip(
                            title: dateRangeTitle(range),
                            isSelected: viewModel.selectedDateRange == range,
                            symbol: dateRangeSymbol(range)
                        ) {
                            viewModel.setDateRange(range)
                        }
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
            }
        }
        .padding(.vertical, AdminSpacing.sm)
    }

    // MARK: - Orders List

    private var ordersList: some View {
        ScrollView {
            LazyVStack(spacing: AdminSpacing.sm) {
                ForEach(Array(viewModel.records.enumerated()), id: \.element.orderId) { idx, record in
                    Button {
                        selectedOrderID = record.orderId
                    } label: {
                        PaymentOrderCard(record: record)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if idx >= viewModel.records.count - 4 {
                            viewModel.loadMoreIfNeeded()
                        }
                    }
                }

                if viewModel.isLoading && !viewModel.records.isEmpty {
                    ProgressView().tint(AdminSurface.primary).padding()
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, AdminSpacing.sm)
        }
        .refreshable { await refreshAction() }
    }

    private func refreshAction() async {
        viewModel.refresh()
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    // MARK: - Helpers

    private var dateRangeOptions: [PPPaymentAdminDateRange] {
        [.all, .today, .last7Days, .last30Days, .last90Days]
    }

    private func dateRangeTitle(_ range: PPPaymentAdminDateRange) -> String {
        switch range {
        case .all:
            return Language.get("DateRange_All", alter: "الكل")
        case .today:
            return Language.get("DateRange_Today", alter: "اليوم")
        case .last7Days:
            return Language.get("DateRange_7Days", alter: "٧ أيام")
        case .last30Days:
            return Language.get("DateRange_30Days", alter: "٣٠ يوم")
        case .last90Days:
            return Language.get("DateRange_90Days", alter: "٩٠ يوم")
        @unknown default:
            return Language.get("DateRange_All", alter: "الكل")
        }
    }

    private func dateRangeSymbol(_ range: PPPaymentAdminDateRange) -> String? {
        switch range {
        case .all: return "infinity"
        case .today: return "sun.max.fill"
        case .last7Days: return "calendar"
        case .last30Days: return "calendar"
        case .last90Days: return "calendar.badge.clock"
        @unknown default: return nil
        }
    }
}

// MARK: - Subviews

private struct StatPill: View {
    let title: String
    let value: String
    let color: Color
    let symbol: String

    var body: some View {
        HStack(spacing: AdminSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .monospacedDigit()
                Text(title)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .stroke(AdminSurface.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .medium))
                }
                Text(title)
                    .font(AdminType.captionBold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? AdminSurface.primary
                    : AdminSurface.control,
                in: Capsule()
            )
            .foregroundColor(
                isSelected
                    ? .white
                    : AdminSurface.secondaryText
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.clear : AdminSurface.hairline,
                        lineWidth: 1
                    )
            )
        }
        .frame(minHeight: AdminTouchTarget.minimum)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PaymentOrderCard: View {
    let record: PPPaymentAdminRecord

    var body: some View {
        VStack(spacing: AdminSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(record.displayOrderReference())")
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(record.userDisplayName ?? record.userEmail ?? "")
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                Spacer()
                statusBadge
            }

            HStack {
                Label(
                    formatCurrency(record.totalAmount),
                    systemImage: "dollarsign.circle.fill"
                )
                .font(AdminType.footnoteBold)
                .foregroundColor(AdminSurface.primaryText)

                Spacer()

                if hasOpenRequests {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.system(size: 10))
                        Text(Language.get("PaymentMgmt_Open_Request", alter: "طلب مفتوح"))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.10), in: Capsule())
                }

                Text(formattedDate(record.createdAt))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            if !primaryItems.isEmpty {
                Divider().background(AdminSurface.hairline)
                Text(primaryItems)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .stroke(AdminSurface.hairline)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var statusBadge: some View {
        let statusKey = record.workflowStatusKey()
        let displayTitle = PPPaymentAdminDisplayTitleForWorkflowStatus(statusKey)
        let badgeStatus: AdminStatusBadge.Status = {
            if PPPaymentAdminRecord.isPaidLikeStatus(statusKey) { return .success }
            if PPPaymentAdminRecord.isCancelledLikeStatus(statusKey) { return .error }
            if PPPaymentAdminRecord.isFailureLikeStatus(statusKey) { return .error }
            if PPPaymentAdminRecord.isProcessingLikeStatus(statusKey) { return .processing }
            if PPPaymentAdminRecord.isShippedLikeStatus(statusKey) { return .info }
            if PPPaymentAdminRecord.isDeliveredLikeStatus(statusKey) { return .success }
            return .warning
        }()
        return AdminStatusBadge(text: displayTitle, status: badgeStatus)
    }

    private var hasOpenRequests: Bool {
        record.hasOpenRequests()
    }

    private var primaryItems: String {
        guard let items = record.items as? [[String: Any]], !items.isEmpty else { return "" }
        return items.prefix(3).compactMap { $0["name"] as? String }.joined(separator: "، ")
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = (
            record.currency.isEmpty == false
        ) ? record.currency : "QAR"
        formatter.locale = Locale(identifier: Language.currentLanguageCode() == "ar" ? "ar_QA" : "en_QA")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "QAR %.2f", value)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: Language.currentLanguageCode() == "ar" ? "ar" : "en")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ObjC Hosting Bridge

@objc public final class PaymentListHostingController: UIViewController {
    private var hostingController: UIHostingController<AdminPaymentListView>?
    private let session: AdminSession

    init(session: AdminSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.ppBackground
        let root = AdminPaymentListView(session: session) { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        }
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}
