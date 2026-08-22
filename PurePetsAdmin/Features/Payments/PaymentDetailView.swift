import SwiftUI

// MARK: - Admin Payment Detail View
/// Redesigned to NextGen V6 standards: Apple Design Award caliber UI/UX.
struct AdminPaymentDetailView: View {
    let orderID: String
    let session: Any? // Optional session parameter
    var onDismiss: (() -> Void)? = nil

    @StateObject private var viewModel: PaymentDetailViewModel
    @State private var pendingOfficialAction: String?
    @State private var officialActionNote = ""

    init(orderID: String, session: Any? = nil, onDismiss: (() -> Void)? = nil) {
        self.orderID = orderID
        self.session = session
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: PaymentDetailViewModel(orderID: orderID))
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(AdminSurface.primary)
            } else if let error = viewModel.errorMessage {
                errorState(message: error)
            } else if let record = viewModel.record {
                ScrollView {
                    VStack(spacing: AdminSpacing.sectionSpacing) {
                        headerSection(record)
                        customerSection(record)
                        paymentSummarySection(record)
                        actionsSection(for: record)
                        itemsSection(record)
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.vertical, AdminSpacing.md)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .navigationTitle(Language.get("PaymentMgmt_DetailsTitle", alter: "تفاصيل الدفع"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadData()
        }
        .alert(officialActionTitle(pendingOfficialAction), isPresented: Binding(
            get: { pendingOfficialAction != nil },
            set: { if !$0 { pendingOfficialAction = nil } }
        )) {
            TextField(Language.get("PaymentMgmt_Value_AdminNote", alter: ""), text: $officialActionNote)
            Button(Language.get("Confirm", alter: "")) {
                guard let action = pendingOfficialAction else { return }
                let note = officialActionNote.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingOfficialAction = nil
                officialActionNote = ""
                viewModel.transitionOfficialFulfillment(action: action, note: note)
            }
            Button(Language.get("Cancel", alter: ""), role: .cancel) {
                pendingOfficialAction = nil
                officialActionNote = ""
            }
        } message: {
            Text(Language.get("PaymentMgmt_OfficialFulfillment_Confirm", alter: ""))
        }
    }

    @ViewBuilder
    private func actionsSection(for record: PPPaymentAdminRecord) -> some View {
        if record.fulfillmentVersion == 1 {
            AdminDetailCard(
                title: Language.get("PaymentMgmt_OfficialFulfillment_Title", alter: ""),
                icon: "shippingbox.and.arrow.backward"
            ) {
                if viewModel.officialFulfillmentLoading {
                    ProgressView(Language.get("PaymentMgmt_OfficialFulfillment_Loading", alter: ""))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let error = viewModel.officialFulfillmentError {
                    Text(error)
                        .font(AdminType.subheadline)
                        .foregroundColor(Color(UIColor.ppError))
                    Button(Language.get("Retry", alter: "")) {
                        viewModel.reloadOfficialFulfillment()
                    }
                    .buttonStyle(.bordered)
                } else if let fulfillment = viewModel.officialFulfillment {
                    detailRow(
                        title: Language.get("PaymentMgmt_Field_OrderStatus", alter: ""),
                        value: PPPaymentAdminDisplayTitleForOrderStatus(fulfillment.status)
                    )
                    ForEach(viewModel.officialActions, id: \.self) { action in
                        actionButton(
                            title: officialActionTitle(action),
                            color: officialActionColor(action)
                        ) {
                            officialActionNote = ""
                            pendingOfficialAction = action
                        }
                        .disabled(viewModel.officialActionInFlight)
                    }
                } else {
                    Text(Language.get("PaymentMgmt_OfficialFulfillment_None", alter: ""))
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
        } else {
            VStack(spacing: AdminSpacing.sm) {
                if PPPaymentAdminRecord.canApproveOrderStatus(record.rawStatus) && (PPPaymentAdminRecord.normalizedStatusString(record.paymentMethodId as String?) != "cash") {
                    actionButton(title: Language.get("PaymentMgmt_Action_ApprovePayment_Title", alter: "Approve Payment"),
                                 color: Color(UIColor.ppSuccess)) {
                        viewModel.approveOrder()
                    }
                }
                
                if PPPaymentAdminRecord.canMarkOrderProcessing(forOrder: record) {
                    actionButton(title: Language.get("PaymentMgmt_Action_MarkProcessing_Title", alter: "Mark Processing"),
                                 color: Color(UIColor.ppInfo)) {
                        viewModel.markProcessing()
                    }
                }
                
                if PPPaymentAdminRecord.canMarkOrderShippedStatus(record.rawStatus) {
                    actionButton(title: Language.get("PaymentMgmt_Action_MarkShipped_Title", alter: "Mark Shipped"),
                                 color: Color.blue) {
                        viewModel.markShipped()
                    }
                }
                
                if PPPaymentAdminRecord.canMarkOrderDeliveredStatus(record.rawStatus) {
                    actionButton(title: Language.get("PaymentMgmt_Action_MarkDelivered_Title", alter: "Mark Delivered"),
                                 color: Color(UIColor.ppSuccess)) {
                        viewModel.markDelivered()
                    }
                }
                
                if PPPaymentAdminRecord.canCancelOrderStatus(record.rawStatus) {
                    actionButton(title: Language.get("PaymentMgmt_Action_CancelOrder_Title", alter: "Cancel Order"),
                                 color: Color(UIColor.ppError)) {
                        viewModel.cancelOrder()
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.bottom, AdminSpacing.lg)
        }
    }

    private func officialActionTitle(_ action: String?) -> String {
        let keys: [String: String] = [
            "accept": "PaymentMgmt_OfficialFulfillment_Action_Accept",
            "reject": "PaymentMgmt_OfficialFulfillment_Action_Reject",
            "start_preparing": "PaymentMgmt_OfficialFulfillment_Action_StartPreparing",
            "mark_ready": "PaymentMgmt_OfficialFulfillment_Action_MarkReady",
            "request_delivery": "PaymentMgmt_OfficialFulfillment_Action_RequestDelivery",
            "confirm_handover": "PaymentMgmt_OfficialFulfillment_Action_ConfirmHandover",
            "cancel_request": "PaymentMgmt_OfficialFulfillment_Action_Cancel",
        ]
        guard let action, let key = keys[action] else {
            return Language.get("PaymentMgmt_OfficialFulfillment_Title", alter: "")
        }
        return Language.get(key, alter: "")
    }

    private func officialActionColor(_ action: String) -> Color {
        switch action {
        case "reject", "cancel_request": return Color(UIColor.ppError)
        case "accept", "mark_ready": return Color(UIColor.ppSuccess)
        case "request_delivery": return Color(UIColor.ppQuickActionCommunity)
        default: return Color(UIColor.ppInfo)
        }
    }

    @ViewBuilder
    private func actionButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(AdminType.body.weight(.semibold))
                Spacer()
            }
            .frame(height: 48)
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(AdminRadius.button)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func headerSection(_ record: PPPaymentAdminRecord) -> some View {
        VStack(spacing: AdminSpacing.sm) {
            Text("\(Language.get("PaymentMgmt_Order_ID", alter: "طلب")) #\(record.displayOrderReference() as String? ?? orderID)")
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.center)
            
            Text(PPPaymentAdminDisplayTitleForOrderStatus(record.rawStatus as String? ?? ""))
                .font(AdminType.subheadlineBold)
                .foregroundColor(AdminSurface.primary)
                .padding(.horizontal, AdminSpacing.base)
                .padding(.vertical, AdminSpacing.sm)
                .background(AdminSurface.primarySoft)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AdminSpacing.base)
        .padding(.bottom, AdminSpacing.md)
    }

    @ViewBuilder
    private func customerSection(_ record: PPPaymentAdminRecord) -> some View {
        AdminDetailCard(
            title: Language.get("PaymentMgmt_Customer", alter: "العميل"),
            icon: "person.crop.circle.fill"
        ) {
            detailRow(
                title: Language.get("PaymentMgmt_Customer_Name", alter: "الاسم"),
                value: record.userDisplayName as String? ?? "-"
            )
            detailRow(
                title: Language.get("PaymentMgmt_Email", alter: "البريد الإلكتروني"),
                value: record.userEmail as String? ?? "-"
            )
        }
    }

    @ViewBuilder
    private func paymentSummarySection(_ record: PPPaymentAdminRecord) -> some View {
        AdminDetailCard(
            title: Language.get("PaymentMgmt_Payment", alter: "الدفع"),
            icon: "creditcard.fill"
        ) {
            detailRow(
                title: Language.get("PaymentMgmt_Total", alter: "الإجمالي"),
                value: formatCurrency(record.totalAmount, currency: record.currency)
            )
            if let method = (record.paymentMethodId as String?) ?? (record.paymentTypeKey as String?), !method.isEmpty {
                detailRow(
                    title: Language.get("PaymentMgmt_Payment_Method", alter: "طريقة الدفع"),
                    value: method.capitalized
                )
            }
            if let date = record.createdAt as Date? {
                detailRow(
                    title: Language.get("PaymentMgmt_Created", alter: "التاريخ"),
                    value: formatDate(date)
                )
            }
        }
    }
    
    @ViewBuilder
    private func itemsSection(_ record: PPPaymentAdminRecord) -> some View {
        if let items = record.items as? [[String: Any]], !items.isEmpty {
            AdminDetailCard(
                title: Language.get("PaymentMgmt_Items", alter: "العناصر"),
                icon: "bag.fill"
            ) {
                VStack(spacing: AdminSpacing.md) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                                Text(item["name"] as? String ?? "-")
                                    .font(AdminType.body)
                                    .foregroundColor(AdminSurface.primaryText)
                                
                                if let qty = item["quantity"] as? Int {
                                    Text("\(Language.get("PaymentMgmt_Qty", alter: "الكمية")): \(qty)")
                                        .font(AdminType.subheadline)
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                            }
                            Spacer()
                        }
                        
                        if index < items.count - 1 {
                            Divider()
                                .background(AdminSurface.hairline)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func errorState(message: String) -> some View {
        VStack(spacing: AdminSpacing.base) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: AdminIconSize.xl))
                .foregroundColor(.red)
            Text(message)
                .font(AdminType.body)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.center)
            Button(Language.get("Retry", alter: "إعادة المحاولة")) {
                viewModel.loadData()
            }
            .buttonStyle(.borderedProminent)
            .tint(AdminSurface.primary)
            .clipShape(Capsule())
            .padding(.top, AdminSpacing.sm)
        }
        .padding(AdminSpacing.xl)
    }

    // MARK: - Reusables
    
    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AdminType.subheadline)
                .foregroundColor(AdminSurface.secondaryText)
            Spacer(minLength: AdminSpacing.base)
            Text(value)
                .font(AdminType.subheadlineBold)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(Language.isRTL() ? .leading : .trailing)
        }
        .padding(.vertical, AdminSpacing.xxs)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double, currency: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "SAR"
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: Language.currentLanguageCode() == "ar" ? "ar" : "en")
        return formatter.string(from: date)
    }
}

// MARK: - Admin Detail Card
private struct AdminDetailCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: AdminIconSize.medium, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                Text(title)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
            }
            .padding(.bottom, AdminSpacing.xs)
            
            content()
        }
        .padding(AdminSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface)
        .cornerRadius(AdminRadius.card)
        .shadow(color: AdminShadow.elevated.color, radius: AdminShadow.elevated.radius, y: AdminShadow.elevated.y)
    }
}

// MARK: - View Model
@MainActor
class PaymentDetailViewModel: ObservableObject {
    private func performAction(_ action: @escaping (PPPaymentManagementService, PPPaymentAdminRecord, @escaping (PPPaymentAdminRecord?, Error?) -> Void) -> Void) {
        guard let record = record, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let service = PPPaymentManagementService.shared()
        action(service, record) { [weak self] updatedRecord, error in
            Task { @MainActor in
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else if let updatedRecord = updatedRecord {
                    self?.record = updatedRecord
                }
            }
        }
    }
    
    func approveOrder() { performAction { $0.approveOrder($1, note: nil, completion: $2) } }
    func markProcessing() { performAction { $0.markOrderProcessing($1, note: nil, completion: $2) } }
    func markShipped() { performAction { $0.markOrderShipped($1, note: nil, completion: $2) } }
    func markDelivered() { performAction { $0.markOrderDelivered($1, note: nil, completion: $2) } }
    func cancelOrder() { performAction { $0.cancelOrder($1, note: nil, completion: $2) } }

    let orderID: String
    
    @Published var record: PPPaymentAdminRecord?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var officialFulfillment: PPFulfillmentRecord?
    @Published var officialFulfillmentLoading = false
    @Published var officialFulfillmentError: String?
    @Published var officialActionInFlight = false

    var officialActions: [String] {
        guard let officialFulfillment else { return [] }
        return PPFulfillmentService.availableOfficialActions(forStatus: officialFulfillment.status)
    }
    
    init(orderID: String) {
        self.orderID = orderID
    }
    
    func loadData() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        let service = PPPaymentManagementService.shared()
        service.loadFullRecord(forOrderID: orderID) { [weak self] record, error in
            Task { @MainActor in
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else if let record = record {
                    self?.record = record
                    self?.loadOfficialFulfillment(for: record)
                } else {
                    self?.errorMessage = Language.get("PaymentMgmt_Error", alter: "حدث خطأ أثناء جلب التفاصيل")
                }
            }
        }
    }

    func reloadOfficialFulfillment() {
        guard let record else { return }
        loadOfficialFulfillment(for: record)
    }

    private func loadOfficialFulfillment(for record: PPPaymentAdminRecord) {
        officialFulfillment = nil
        officialFulfillmentError = nil
        guard record.fulfillmentVersion == 1 else {
            officialFulfillmentLoading = false
            return
        }
        officialFulfillmentLoading = true
        let ids = record.fulfillmentOrderIDs as? [String] ?? []
        PPFulfillmentService.shared().fetchOfficialFulfillment(
            parentOrderID: record.orderId,
            fulfillmentIDs: ids
        ) { [weak self] fulfillment, error in
            Task { @MainActor in
                guard let self, self.record?.orderId == record.orderId else { return }
                self.officialFulfillmentLoading = false
                self.officialFulfillment = fulfillment
                self.officialFulfillmentError = error?.localizedDescription
            }
        }
    }

    func transitionOfficialFulfillment(action: String, note: String) {
        guard let fulfillment = officialFulfillment, !officialActionInFlight else { return }
        let safeNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard safeNote.count >= 3 else {
            officialFulfillmentError = Language.get("PaymentMgmt_Prompt_NoteRequired_Subtitle", alter: "")
            return
        }
        officialActionInFlight = true
        officialFulfillmentError = nil
        PPFulfillmentService.shared().transitionOfficialFulfillment(
            fulfillment,
            expectedStatus: fulfillment.status,
            action: action,
            note: safeNote,
            commandID: UUID().uuidString
        ) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.officialActionInFlight = false
                if let error {
                    self.officialFulfillment = nil
                    self.officialFulfillmentError = error.localizedDescription
                } else {
                    self.loadData()
                }
            }
        }
    }
}
