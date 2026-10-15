import Foundation
import SwiftUI

// Presentation values only. PPPOSService owns the callable boundary and Infra
// recalculates eligibility, money, terms and approvals at commit.
struct POSCreditContext: Decodable, Sendable {
    struct AgreementTemplate: Decodable, Sendable {
        let id: String
        let version: Int
        let ar: String
        let en: String
    }
    let customerId: String
    let customerName: String
    let branchId: String
    let currency: String
    let policyVersion: Int
    let accountVersion: Int
    let limitMinor: Int
    let outstandingMinor: Int
    let pendingAmountMinor: Int
    let overdueMinor: Int
    let businessDateKey: String
    let timeZone: String
    let checkoutContextHash: String
    let agreementTemplate: AgreementTemplate
    let receiptAccounts: [String: String]
    let pendingTendersEnabled: Bool
}

struct POSCreditReceiptSummary: Decodable, Sendable {
    struct Agreement: Decodable, Sendable {
        let dueDateKey: String
        let wording: [String: String]
        let interpolationValues: [String: String]
        let locale: String
    }
    let transactionId: String
    let invoiceId: String
    let customerId: String
    let branchId: String
    let currency: String
    let total: Double
    let amountPaidMinor: Int
    let amountDueMinor: Int
    let pendingAmountMinor: Int
    let agreement: Agreement

    var totalMinor: Int { POSMoney.minorUnits(total) }
    var wording: String { agreement.wording[agreement.locale] ?? "" }
    var customerName: String { agreement.interpolationValues["customer"] ?? "" }

    static func confirmed(_ data: Data, for record: POSCreditPendingStore.Record) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        let envelope = try JSONDecoder().decode(POSCreditPendingStore.Envelope.self, from: record.requestJSON)
        guard value.currency == "QAR", value.branchId == record.branchID,
              value.customerId == envelope.payload.settlement.customerId,
              !value.transactionId.isEmpty, !value.invoiceId.isEmpty, value.total.isFinite,
              value.total > 0, value.total < 1_000_000_000_000,
              value.totalMinor == POSMoney.minorUnits(envelope.payload.total),
              value.amountPaidMinor >= 0, value.amountDueMinor >= 0,
              value.amountPaidMinor <= value.totalMinor,
              value.amountDueMinor == value.totalMinor - value.amountPaidMinor,
              value.pendingAmountMinor >= 0, value.pendingAmountMinor <= value.amountDueMinor,
              ["ar", "en"].contains(value.agreement.locale), !value.wording.isEmpty else {
            throw POSCreditPendingStore.StoreError.invalidRecord
        }
        return value
    }
}

/// One atomic, file-protected financial intent. Never re-create a command from
/// current cart state after timeout or relaunch, and never replay another actor.
enum POSCreditPendingStore {
    struct Envelope: Decodable {
        struct Payload: Decodable {
            struct Settlement: Decodable { let type: String; let contractVersion: Int; let customerId: String }
            let branchId: String
            let paymentMethod: String
            let total: Double
            let settlement: Settlement
        }
        let action: String
        let commandId: String
        let payload: Payload
    }
    struct Record: Codable, Sendable {
        let actorUID: String
        let branchID: String
        let commandID: String
        let requestJSON: Data
        let createdAt: Date
        var attempts: Int
        var confirmedResultJSON: Data?
        var approvalRequestJSON: Data?
    }
    enum StoreError: Error { case anotherCommand, invalidRecord }

    private static func url() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("POSCredit", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var protectedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(values)
        return directory.appendingPathComponent("pending-v1.json")
    }
    static func load() throws -> Record? {
        let file = try url()
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let value = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file))
        try validate(value)
        return value
    }
    private static func validate(_ value: Record) throws {
        guard !value.actorUID.isEmpty, !value.branchID.isEmpty, !value.commandID.isEmpty,
              !value.requestJSON.isEmpty, value.requestJSON.count <= 256_000, value.attempts > 0 else { throw StoreError.invalidRecord }
        let request = try JSONDecoder().decode(Envelope.self, from: value.requestJSON)
        guard request.action == "create", request.commandId == value.commandID,
              request.payload.branchId == value.branchID, request.payload.paymentMethod == "credit",
              request.payload.settlement.type == "credit", request.payload.settlement.contractVersion == 1,
              !request.payload.settlement.customerId.isEmpty, request.payload.total.isFinite,
              request.payload.total > 0, request.payload.total < 1_000_000_000_000 else { throw StoreError.invalidRecord }
        if let result = value.confirmedResultJSON { _ = try POSCreditReceiptSummary.confirmed(result, for: value) }
    }
    static func save(_ record: Record) throws {
        try validate(record)
        if let existing = try load() {
            guard existing.actorUID == record.actorUID, existing.branchID == record.branchID,
                  existing.commandID == record.commandID, existing.requestJSON == record.requestJSON else { throw StoreError.anotherCommand }
        }
        try JSONEncoder().encode(record).write(to: url(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func clear(commandID: String) throws {
        guard let record = try load(), record.commandID == commandID else { throw StoreError.anotherCommand }
        try FileManager.default.removeItem(at: url())
    }
}

enum POSCreditCheckoutError: LocalizedError {
    case dateRollover(contextDate: String, currentDate: String)
    case invalidDeposit
    case invalidInstallmentAmount
    case referenceRequired
    case referenceTooLong
    case dueDatePrecedesToday
    case installmentPrecedesToday
    case installmentSumMismatch
    case customerMismatch
    case receiptAccountMissing

    var errorDescription: String? {
        switch self {
        case .dateRollover:
            return Language.get("POS_Credit_DateRolloverNotice", alter: "انتقلت دورة العمل إلى يوم جديد. يرجى تحديث بيانات الائتمان للمتابعة.")
        case .dueDatePrecedesToday, .installmentPrecedesToday:
            return Language.get("POS_Credit_DueDatePast", alter: "تاريخ الاستحقاق يجب ألا يسبق تاريخ اليوم.")
        case .referenceRequired:
            return Language.get("POS_Credit_ReferenceRequired", alter: "مرجع الدفعة الأولى مطلوب عند الدفع بغير النقد.")
        case .referenceTooLong:
            return Language.get("POS_Credit_ReferenceTooLong", alter: "مرجع الدفعة الأولى لا يمكن أن يتجاوز 200 حرف.")
        case .installmentSumMismatch:
            return Language.get("POS_Credit_InvalidTerms", alter: "راجع المبالغ والتواريخ ومرجع الدفعة. يجب أن يساوي مجموع الأقساط المبلغ المتبقي بعد الدفعة الأولى.")
        case .invalidDeposit:
            return Language.get("POS_Credit_InvalidDeposit", alter: "مبلغ الدفعة الأولى غير صالح.")
        case .invalidInstallmentAmount:
            return Language.get("POS_Credit_InvalidInstallmentAmount", alter: "مبلغ القسط غير صالح ويجب أن يكون أكبر من صفر.")
        case .customerMismatch:
            return Language.get("POS_Credit_CustomerRequired", alter: "تغير العميل المحدد. يرجى إعادة اختيار العميل.")
        case .receiptAccountMissing:
            return Language.get("POS_Credit_Unavailable", alter: "حساب استلام الدفعة غير مهيأ لهذا الفرع.")
        }
    }
}

struct POSCreditInstallmentDraft: Identifiable {
    let id = UUID()
    var date = Date()
    var amount = ""
}

private struct PPCreditPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct POSCreditCheckoutSheet: View {
    @ObservedObject var model: POSFastSellViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var heroAmountSize: CGFloat = 44

    @State private var depositText = "0.00"
    @State private var method = "cash"
    @State private var reference = ""
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var usesInstallments = false
    @State private var installments = [POSCreditInstallmentDraft()]
    @State private var delivery = false
    @State private var reviewing = false
    @State private var accepted = false
    @State private var localError: String?
    @State private var showsCustomerPicker = false
    @State private var showsCreditAccountSheet = false
    @State private var showsPolicyEditorSheet = false
    @State private var isRefreshingEligibility = false
    @State private var selectedDepositPreset: Int? = 0
    @State private var selectedDueDatePreset: Int? = 30
    @FocusState private var editingAmount: Bool

    private func label(_ key: String) -> String { Language.get(key, alter: nil) }
    private func money(_ minor: Int) -> String { POSReceiptFormat.currency(Double(minor) / 100, code: "QAR") }
    private var totalMinor: Int { POSMoney.minorUnits(model.cartTotal) }
    private var depositMinor: Int? { Self.minor(depositText) }
    private var pending: Bool { (depositMinor ?? 0) > 0 && method != "cash" }
    private var amountDueMinor: Int { max(0, totalMinor - (pending ? 0 : (depositMinor ?? 0))) }

    private var activeBranchID: String {
        BranchContextStore.shared.activeBranch?.branchID ?? ""
    }

    private var activeBranchName: String {
        BranchContextStore.shared.activeBranch?.localizedName() ?? Language.get("POS_CurrentBranch", alter: "الفرع الحالي")
    }

    private var canManageCreditAccount: Bool {
        guard !activeBranchID.isEmpty else { return false }
        if let staff = PPStaffAuth.shared().cachedCurrentStaff, staff.isAdmin() { return true }
        return POSCreditAccountCopy.permitted("pos.credit.read", branchID: activeBranchID)
    }

    private var draftIdentity: String {
        let cart = model.cartItems.map { "\($0.id):\($0.quantity):\($0.quantityGroupID):\($0.lineTotal):\($0.unitIDs)" }.joined(separator: ";")
        return "\(depositText)|\(method)|\(reference)|\(dueDate)|\(usesInstallments)|\(delivery)|\(installments.map { "\($0.date):\($0.amount)" })|\(model.cartTotal)|\(model.selectedCustomer?.id ?? "")|\(cart)|\(model.salesChannel.rawValue)|\(Language.isRTL())"
    }

    private var isRecovery: Bool { model.creditRecovery != nil || model.creditRecoveryError != nil }

    private var allowedMethods: [String] {
        guard let context = model.creditContext else { return [] }
        return ["cash", "card", "cheque", "bank_transfer", "fawry"].filter {
            context.receiptAccounts[$0] != nil && ($0 == "cash" || context.pendingTendersEnabled)
        }
    }

    private var currentStep: Int {
        guard model.creditContext != nil else { return 0 }
        return reviewing ? 2 : 1
    }

    private var isBusinessDateRolledOver: Bool {
        guard let context = model.creditContext else { return false }
        return day(Date(), context) != context.businessDateKey
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !isRecovery {
                        creditOverview
                    }

                    if isRecovery {
                        panel { recoverySection }
                    } else if model.isLoadingCreditContext || isRefreshingEligibility {
                        loadingCard
                    } else if let context = model.creditContext {
                        customerCard(context: context)
                        if reviewing {
                            panel { reviewAgreementSection(context: context) }
                        } else {
                            panel { termsAtelierSection(context: context) }
                        }
                    } else {
                        unresolvedCustomerCard
                    }

                    if isBusinessDateRolledOver {
                        noticeCard(label("POS_Credit_DateRolloverNotice"), color: AdminSurface.amber, symbol: "clock.arrow.circlepath")
                    }

                    if let message = localError ?? model.creditError {
                        let isApprovalRequired = isRecovery && model.creditRecovery?.approvalRequestJSON != nil
                        let isDuplicateNotice = isApprovalRequired && (message == label("POS_Credit_ApprovalRequired") || message == POSCreditAccountCopy.text("ApprovalRequested"))
                        if !isDuplicateNotice, (model.selectedCustomer != nil || message != label("POS_Credit_SelectCustomer")) {
                            let isSuccess = message == POSCreditAccountCopy.text("ApprovalRequested")
                            let isInfo = message == POSCreditAccountCopy.text("Cancelled")
                            let color = isSuccess ? AdminSurface.primary : (isInfo ? AdminSurface.amber : AdminSurface.crimson)
                            let symbol = isSuccess ? "checkmark.circle.fill" : (isInfo ? "info.circle.fill" : "exclamationmark.triangle.fill")
                            noticeCard(message, color: color, symbol: symbol)
                        }
                    }
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 110)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: AdminSpacing.xxs) {
                        Text(label("POS_Credit_PaymentMethod"))
                            .font(PPBrandFont.bold(Language.isRTL() ? 18 : 16, relativeTo: .headline))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .accessibilityLabel(label("POS_Credit_Title"))
                            .accessibilityAddTraits(.isHeader)
                        // Recovery omits the overview, so retain its branch/cart context here.
                        if isRecovery {
                            HStack(spacing: 3) {
                                Text(activeBranchName)
                                Text("·")
                                Text(label("POS_Items"))
                                Text(":")
                                Text(headerNumber(model.cartItems.count))
                                    .font(PPBrandFont.bold(Language.isRTL() ? 13 : 11, relativeTo: .caption))
                            }
                            .font(PPBrandFont.regular(Language.isRTL() ? 13 : 11, relativeTo: .caption))
                            .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .frame(minWidth: AdminTouchTarget.minimum, minHeight: AdminTouchTarget.minimum)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label("POS_Credit_Close"))
                    .accessibilityIdentifier("pos.credit.close")
                    .disabled(model.isCheckoutBusy)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        editingAmount = false
                    } label: {
                        Text(label("POS_Credit_Done"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isRecovery && !model.isLoadingCreditContext && (model.creditContext != nil || model.canIssueCredit) {
                    floatingActionDock
                }
            }
            .overlay {
                if model.isSubmitting {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView()
                                .tint(AdminSurface.primary)
                                .controlSize(.large)
                            Text(label("POS_Credit_Loading"))
                                .font(AdminType.headlineBold)
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                        .padding(26)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
                    }
                }
            }
            .interactiveDismissDisabled(model.isCheckoutBusy)
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .onAppear {
                model.loadCreditContext()
            }
            .onChange(of: draftIdentity) { _ in reviewing = false; accepted = false }
            .onChange(of: model.creditContext?.policyVersion) { _ in reviewing = false; accepted = false }
            .onChange(of: model.creditContext?.accountVersion) { _ in reviewing = false; accepted = false }
            .onChange(of: model.creditContext?.checkoutContextHash) { _ in reviewing = false; accepted = false }
            .onChange(of: scenePhase) { phase in
                if phase == .active && isBusinessDateRolledOver {
                    model.loadCreditContext()
                    reviewing = false
                    accepted = false
                }
            }
            .onChange(of: model.creditContext?.businessDateKey) { newDateKey in
                if let newDateKey, let context = model.creditContext {
                    if day(dueDate, context) < newDateKey {
                        dueDate = Calendar.current.date(byAdding: .day, value: selectedDueDatePreset ?? 30, to: Date()) ?? Date()
                    }
                }
            }
            .onChange(of: allowedMethods) { methods in
                if !methods.contains(method) { method = methods.first ?? "" }
            }
            .sheet(isPresented: $showsCustomerPicker, onDismiss: { model.loadCreditContext() }) {
                POSCustomerPickerSheet(currentSelected: model.selectedCustomer, canCreateCustomer: false) { customer in
                    model.selectedCustomer = customer
                    showsCustomerPicker = false
                }
            }
            .sheet(isPresented: $showsCreditAccountSheet, onDismiss: { model.loadCreditContext() }) {
                if let customer = model.selectedCustomer, !activeBranchID.isEmpty {
                    POSCreditAccountSheet(customerID: customer.id, branchID: activeBranchID)
                }
            }
            .sheet(isPresented: $showsPolicyEditorSheet, onDismiss: { model.loadCreditContext() }) {
                if let customer = model.selectedCustomer, !activeBranchID.isEmpty {
                    POSCustomerCreditPolicySheet(
                        customerID: customer.id,
                        customerName: customer.name,
                        customerPhone: customer.phone,
                        branchID: activeBranchID,
                        branchName: activeBranchName
                    ) {
                        model.loadCreditContext()
                    }
                }
            }
        }
    }

    // MARK: - Credit Overview

    private var creditOverview: some View {
        VStack(spacing: 0) {
            heroFinancingCard
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: AdminStroke.hairline)
                .padding(.horizontal, AdminSpacing.lg)
                .accessibilityHidden(true)
            journeyTracker
                .padding(AdminSpacing.base)
        }
        .background {
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                        .fill(LinearGradient(
                            colors: [AdminSurface.primary.opacity(0.055), .clear],
                            startPoint: .top,
                            endPoint: .center
                        ))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pos.credit.overview")
    }

    private var headerLocale: Locale {
        Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
    }

    private func headerNumber(_ value: Int) -> String {
        value.formatted(.number.locale(headerLocale))
    }

    private var heroFinancingCard: some View {
        VStack(spacing: AdminSpacing.base) {
            VStack(spacing: AdminSpacing.xs) {
                Text(label("POS_Credit_TotalFinanced"))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                Text(money(totalMinor))
                    .font(PPBrandFont.bold(heroAmountSize, relativeTo: .largeTitle))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.6)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(label("POS_Credit_TotalFinanced"))
                    .accessibilityValue(money(totalMinor))
                    .accessibilityIdentifier("pos.credit.amountDue")
            }

            heroContext

            if model.salesChannel == .wholesale || model.creditHasLiveItems || delivery {
                // Qualifiers wrap independently without competing with the amount.
                VStack(spacing: AdminSpacing.sm) {
                    if model.salesChannel == .wholesale {
                        heroQualifier(label("POS_Channel_Wholesale"), symbol: "shippingbox", color: AdminSurface.secondaryText)
                    }
                    if model.creditHasLiveItems {
                        heroQualifier(label("POS_Credit_SupervisorBadge"), symbol: "pawprint.fill", color: AdminSurface.amber)
                    }
                    if delivery {
                        heroQualifier(label("POS_Credit_Delivery"), symbol: "shippingbox.fill", color: AdminSurface.primary)
                    }
                }
            }
        }
        .padding(AdminSpacing.lg)
    }

    private var heroContext: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AdminSpacing.md) {
                heroBranch
                Circle()
                    .fill(AdminSurface.secondaryText)
                    .frame(width: 3, height: 3)
                    .accessibilityHidden(true)
                heroItemCount
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(spacing: AdminSpacing.xs) {
                heroBranch
                heroItemCount
            }
        }
        .font(AdminType.footnote)
        .foregroundStyle(AdminSurface.secondaryText)
        .multilineTextAlignment(.center)
    }

    private var heroBranch: some View {
        HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.xs) {
            Image(systemName: "building.2")
                .font(.footnote)
                .accessibilityHidden(true)
            Text(activeBranchName)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heroItemCount: some View {
        HStack(spacing: 3) {
            Text(label("POS_Items"))
            Text(":")
            Text(headerNumber(model.cartItems.count))
                .font(PPBrandFont.bold(14, relativeTo: .footnote))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func heroQualifier(_ title: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.sm) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(AdminType.footnoteBold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
    }

    // MARK: - 3-Step Journey Stepper

    private var journeyTitles: [String] {
        [label("POS_Credit_Step1_Short"), label("POS_Credit_Step2_Short"), label("POS_Credit_Step3_Short")]
    }

    private var journeyTracker: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AdminSpacing.base) {
                    ForEach(journeyTitles.indices, id: \.self) { index in
                        stepIndicator(index: index, vertical: true)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(journeyTitles.indices, id: \.self) { index in
                        stepIndicator(index: index, vertical: false)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label("POS_Credit_Progress"))
        .accessibilityIdentifier("pos.credit.progress")
    }

    private func stepIndicator(index: Int, vertical: Bool) -> some View {
        let layout = vertical
            ? AnyLayout(HStackLayout(alignment: .center, spacing: AdminSpacing.md))
            : AnyLayout(VStackLayout(alignment: .center, spacing: AdminSpacing.sm))

        return layout {
            ZStack {
                if !vertical {
                    HStack(spacing: 0) {
                        stepConnector(isActive: index <= currentStep)
                            .opacity(index == 0 ? 0 : 1)
                        Color.clear.frame(width: 44, height: 2)
                        stepConnector(isActive: index < currentStep)
                            .opacity(index == journeyTitles.count - 1 ? 0 : 1)
                    }
                    .accessibilityHidden(true)
                }
                stepMarker(index: index)
            }
            .frame(width: vertical ? 36 : nil, height: 36)

            Text(journeyTitles[index])
                .font(AdminType.footnoteBold)
                .foregroundStyle(index == currentStep ? AdminSurface.primaryText : AdminSurface.secondaryText)
                .multilineTextAlignment(vertical ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: vertical ? .leading : .center)
                .padding(.horizontal, vertical ? 0 : AdminSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: vertical ? .leading : .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(journeyTitles[index])
        .accessibilityValue(String(
            format: label("POS_Credit_StepAccessibility"),
            headerNumber(index + 1), headerNumber(journeyTitles.count),
            label(index < currentStep ? "POS_Credit_StepDone" : index == currentStep ? "POS_Credit_StepCurrent" : "POS_Credit_StepUpcoming")
        ))
        .accessibilityIdentifier("pos.credit.step.\(index)")
    }

    private func stepMarker(index: Int) -> some View {
        let isDone = index < currentStep
        let isCurrent = index == currentStep

        return ZStack {
            Circle()
                .strokeBorder(isCurrent ? AdminSurface.primary.opacity(0.3) : .clear, lineWidth: AdminStroke.thin)
                .frame(width: 36, height: 36)
            Circle()
                .fill(isCurrent ? AdminSurface.primary : isDone ? AdminSurface.primary.opacity(0.1) : AdminSurface.control)
                .frame(width: 28, height: 28)
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
            } else {
                Text(headerNumber(index + 1))
                    .font(PPBrandFont.bold(14, relativeTo: .caption))
                    .foregroundStyle(isCurrent ? .white : AdminSurface.secondaryText)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentStep)
        .accessibilityHidden(true)
    }

    private func stepConnector(isActive: Bool) -> some View {
        Capsule()
            .fill(isActive ? AdminSurface.primary.opacity(0.35) : AdminSurface.hairline)
            .frame(height: AdminStroke.thin)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isActive)
    }

    // MARK: - Customer & Eligibility State Views

    private var loadingCard: some View {
        panel {
            HStack(spacing: 16) {
                ProgressView()
                    .tint(AdminSurface.primary)
                    .controlSize(.large)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label("POS_Credit_Loading"))
                        .font(AdminType.headlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(label("POS_Credit_LoadingDetail"))
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
        }
        .accessibilityIdentifier("pos.credit.loading")
    }

    private var unresolvedCustomerCard: some View {
        panel {
            VStack(alignment: .leading, spacing: 18) {
                if let customer = model.selectedCustomer {
                    // Customer selected, but eligibility could not be confirmed
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.amber.opacity(0.15))
                                .frame(width: 52, height: 52)
                            Text(customer.initials)
                                .font(AdminType.headlineBold)
                                .foregroundStyle(AdminSurface.amber)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(customer.name)
                                    .font(AdminType.title3Bold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(AdminSurface.amber)
                                    .font(.system(size: 15))
                            }
                            Text(customer.phone)
                                .font(PPBrandFont.medium(14, relativeTo: .subheadline))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        Spacer()
                    }

                    // Explicit Diagnostic Guidance
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "shield.slash.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(AdminSurface.amber)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(label(model.creditError != nil ? "POS_Credit_NeedsVerification" : "POS_Credit_CustomerBadge_NeedsPolicy"))
                                    .font(AdminType.subheadlineBold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                Text(model.creditError ?? label("POS_Credit_PolicyRequired"))
                                    .font(AdminType.footnote)
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                    // Tactical resolution buttons
                    VStack(spacing: 10) {
                        // Direct Entry: Set Customer Terms & Credit Policy
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showsPolicyEditorSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text(Language.get("POS_Credit_SetPolicyCTA", alter: "إعداد واعتماد سياسة البيع الآجل"))
                                Spacer()
                                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                    .font(.caption.weight(.bold))
                            }
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: AdminSurface.primary.opacity(0.24), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pos.credit.setPolicy")

                        if canManageCreditAccount {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showsCreditAccountSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "list.bullet.rectangle.portrait")
                                    Text(label("POS_Credit_ManageAccount"))
                                }
                                .font(AdminType.footnoteBold)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 38)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 10) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showsCustomerPicker = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                    Text(label("POS_Credit_ChangeCustomer"))
                                }
                                .font(AdminType.subheadlineBold)
                                .foregroundStyle(AdminSurface.primaryText)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                isRefreshingEligibility = true
                                model.loadCreditContext()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    isRefreshingEligibility = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text(label("POS_Credit_RetryVerification"))
                                }
                                .font(AdminType.subheadlineBold)
                                .foregroundStyle(AdminSurface.primary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(AdminSurface.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    // No customer selected state
                    VStack(alignment: .center, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.primary.opacity(0.12))
                                .frame(width: 64, height: 64)
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(AdminSurface.primary)
                        }

                        VStack(spacing: 4) {
                            Text(label("POS_Credit_NeedsCustomer"))
                                .font(AdminType.title3Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(label("POS_Credit_SelectCustomer"))
                                .font(AdminType.subheadline)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showsCustomerPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(AdminSurface.primary.opacity(0.12))
                                        .frame(width: 42, height: 42)
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(AdminSurface.primary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(label("POS_Credit_ChooseCustomer"))
                                        .font(AdminType.headlineBold)
                                        .foregroundStyle(AdminSurface.primaryText)
                                    Text(label("POS_Credit_SearchDirectoryOrAdd"))
                                        .font(AdminType.caption)
                                        .foregroundStyle(AdminSurface.secondaryText)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(AdminSurface.primary)
                                    .frame(width: 28, height: 28)
                                    .background(AdminSurface.primary.opacity(0.08), in: Circle())
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AdminSurface.primarySoft.opacity(0.45))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(AdminSurface.primary.opacity(0.20), lineWidth: 1.2)
                            )
                        }
                        .buttonStyle(PPCreditPressableButtonStyle())
                        .accessibilityIdentifier("pos.credit.chooseCustomer")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .accessibilityIdentifier("pos.credit.needsContext")
    }

    private func customerCard(context: POSCreditContext) -> some View {
        panel {
            VStack(spacing: 16) {
                // Header row: Customer identity & Verification pill
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primarySoft)
                            .frame(width: 52, height: 52)
                        Text(model.selectedCustomer?.initials ?? "PP")
                            .font(AdminType.headlineBold)
                            .foregroundStyle(AdminSurface.primary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(context.customerName)
                                .font(AdminType.title3Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(AdminSurface.emerald)
                                .font(.system(size: 15))
                        }
                        if let phone = model.selectedCustomer?.phone, !phone.isEmpty {
                            Text(phone)
                                .font(PPBrandFont.medium(14, relativeTo: .subheadline))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }

                    Spacer()

                    Button {
                        showsCustomerPicker = true
                    } label: {
                        Text(label("POS_Credit_ChangeCustomer"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AdminSurface.primary.opacity(0.09), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Divider().opacity(0.6)

                // Credit Utilization Gauges & Numbers
                HStack(spacing: 10) {
                    creditMetricBox(
                        title: label("POS_Credit_CreditLimit"),
                        amount: context.limitMinor,
                        tint: AdminSurface.primaryText
                    )
                    creditMetricBox(
                        title: label("POS_Credit_CurrentBalance"),
                        amount: context.outstandingMinor,
                        tint: context.outstandingMinor > 0 ? AdminSurface.amber : AdminSurface.secondaryText
                    )
                    creditMetricBox(
                        title: label("POS_Credit_AvailableCredit"),
                        amount: max(0, context.limitMinor - context.outstandingMinor),
                        tint: AdminSurface.emerald
                    )
                }

                // Visual Credit Horizon Bar
                VStack(alignment: .leading, spacing: 6) {
                    let totalLimit = max(1, context.limitMinor)
                    let currentPct = min(1.0, Double(context.outstandingMinor) / Double(totalLimit))
                    let newSalePct = min(1.0 - currentPct, Double(amountDueMinor) / Double(totalLimit))
                    let isExceeding = (context.outstandingMinor + amountDueMinor) > context.limitMinor

                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            // Existing debt
                            if currentPct > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(AdminSurface.amber)
                                    .frame(width: max(4, geo.size.width * CGFloat(currentPct)))
                            }
                            // New sale
                            if newSalePct > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isExceeding ? AdminSurface.crimson : AdminSurface.primary)
                                    .frame(width: max(4, geo.size.width * CGFloat(newSalePct)))
                            }
                            // Available headroom
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AdminSurface.control)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 8)
                    .clipShape(Capsule())

                    if isExceeding {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .foregroundStyle(AdminSurface.amber)
                            Text(label("POS_Credit_ApprovalRequired"))
                                .font(AdminType.caption)
                                .foregroundStyle(AdminSurface.amber)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .accessibilityIdentifier("pos.credit.contextReady")
    }

    private func creditMetricBox(title: String, amount: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(PPBrandFont.medium(11, relativeTo: .caption2))
                .foregroundStyle(AdminSurface.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(money(amount))
                .font(PPBrandFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Terms Atelier (Step 2)

    private func termsAtelierSection(context: POSCreditContext) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(label("POS_Credit_ConfigureTerms"))
                .font(AdminType.headlineBold)
                .foregroundStyle(AdminSurface.primaryText)

            // Initial Deposit Block
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(label("POS_Credit_Deposit"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                    Spacer()
                    if (depositMinor ?? 0) > 0 {
                        Text(money(depositMinor ?? 0))
                            .font(PPBrandFont.bold(16, relativeTo: .subheadline))
                            .foregroundStyle(AdminSurface.emerald)
                    }
                }

                // Preset Chips
                HStack(spacing: 8) {
                    depositPresetChip(title: label("POS_Credit_PresetNoDeposit"), minor: 0, tag: 0)
                    depositPresetChip(title: "25%", minor: totalMinor * 25 / 100, tag: 25)
                    depositPresetChip(title: "50%", minor: totalMinor * 50 / 100, tag: 50)
                }

                // Custom Amount Input
                HStack {
                    Image(systemName: "banknote")
                        .foregroundStyle(AdminSurface.secondaryText)
                    TextField("0.00", text: $depositText)
                        .keyboardType(.decimalPad)
                        .font(PPBrandFont.bold(17, relativeTo: .body))
                        .focused($editingAmount)
                        .onChange(of: depositText) { _ in
                            selectedDepositPreset = nil
                        }
                    Text(Language.isRTL() ? "ر.ق." : "QAR")
                        .font(PPBrandFont.bold(14, relativeTo: .footnote))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14))

                // Deposit Tender Selection
                if (depositMinor ?? 0) > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(label("POS_Credit_DepositMethod"))
                            .font(AdminType.footnoteBold)
                            .foregroundStyle(AdminSurface.secondaryText)

                        if allowedMethods.isEmpty {
                            noticeCard(label("POS_Credit_NoTender"), color: AdminSurface.amber, symbol: "info.circle")
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(allowedMethods, id: \.self) { val in
                                        tenderMethodPill(val)
                                    }
                                }
                            }
                        }

                        if method != "cash" {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(label("POS_Credit_Reference"))
                                        .font(AdminType.footnoteBold)
                                        .foregroundStyle(AdminSurface.secondaryText)
                                    Text("*")
                                        .foregroundStyle(AdminSurface.crimson)
                                }
                                TextField(label("POS_Credit_Reference"), text: $reference)
                                    .font(AdminType.body)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 46)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
                                Text(label("POS_Credit_PendingHint"))
                                    .font(AdminType.caption)
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Divider()

            // Repayment Schedule Block
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(label("POS_Credit_Remaining"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                    Spacer()
                    Text(money(amountDueMinor))
                        .font(PPBrandFont.bold(18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primary)
                }

                // Mode Picker
                HStack(spacing: 8) {
                    modePickerTab(title: label("POS_Credit_PayFullOnDue"), isSelected: !usesInstallments) {
                        usesInstallments = false
                    }
                    modePickerTab(title: label("POS_Credit_PayInstallments"), isSelected: usesInstallments) {
                        usesInstallments = true
                    }
                }

                if !usesInstallments {
                    // Single Due Date Atelier
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            dueDatePresetChip(title: label("POS_Credit_Preset7Days"), days: 7)
                            dueDatePresetChip(title: label("POS_Credit_Preset15Days"), days: 15)
                            dueDatePresetChip(title: label("POS_Credit_Preset30Days"), days: 30)
                            dueDatePresetChip(title: label("POS_Credit_Preset60Days"), days: 60)
                        }

                        DatePicker(label("POS_Credit_DueDate"), selection: $dueDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .frame(minHeight: 46)
                            .padding(.horizontal, 12)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    // Installments Plan Atelier
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(label("POS_Credit_Installments"))
                                .font(AdminType.footnoteBold)
                                .foregroundStyle(AdminSurface.secondaryText)
                            Spacer()
                            Button {
                                splitInstallmentsEvenly()
                            } label: {
                                Text(label("POS_Credit_SplitEvenly"))
                                    .font(AdminType.caption)
                                    .foregroundStyle(AdminSurface.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AdminSurface.primarySoft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach($installments) { $entry in
                            HStack(alignment: .center, spacing: 10) {
                                DatePicker("", selection: $entry.date, displayedComponents: .date)
                                    .labelsHidden()
                                    .frame(maxWidth: 140)

                                TextField("0.00", text: $entry.amount)
                                    .keyboardType(.decimalPad)
                                    .font(PPBrandFont.bold(16, relativeTo: .body))
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 42)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))

                                if installments.count > 1 {
                                    Button(role: .destructive) {
                                        installments.removeAll { $0.id == entry.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(AdminSurface.crimson)
                                            .font(.system(size: 20))
                                    }
                                }
                            }
                            .padding(10)
                            .background(AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                        }

                        if installments.count < 12 {
                            Button {
                                installments.append(POSCreditInstallmentDraft())
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text(label("POS_Credit_AddInstallment"))
                                }
                                .font(AdminType.footnoteBold)
                                .foregroundStyle(AdminSurface.primary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            // Delivery Toggle
            Toggle(isOn: $delivery) {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(AdminSurface.primary)
                    Text(label("POS_Credit_Delivery"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            .tint(AdminSurface.primary)
            .frame(minHeight: 44)
        }
    }

    private func depositPresetChip(title: String, minor: Int, tag: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedDepositPreset = tag
            depositText = String(format: "%.2f", Double(minor) / 100)
        } label: {
            Text(title)
                .font(PPBrandFont.bold(13, relativeTo: .footnote))
                .foregroundStyle(selectedDepositPreset == tag ? .white : AdminSurface.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selectedDepositPreset == tag ? AdminSurface.primary : AdminSurface.control, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func tenderMethodPill(_ val: String) -> some View {
        let isSelected = method == val
        let iconName: String = {
            switch val {
            case "cash": return "banknote"
            case "card": return "creditcard"
            case "cheque": return "doc.text"
            case "bank_transfer": return "arrow.left.arrow.right"
            case "fawry": return "bolt.fill"
            default: return "circle"
            }
        }()

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            method = val
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .bold))
                Text(POSReceiptFormat.paymentMethod(val))
                    .font(AdminType.footnoteBold)
            }
            .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? AdminSurface.primary : AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func modePickerTab(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(isSelected ? AdminType.subheadlineBold : AdminType.subheadline)
                .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(isSelected ? AdminSurface.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: isSelected ? .black.opacity(0.06) : .clear, radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .padding(3)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
    }

    private func dueDatePresetChip(title: String, days: Int) -> some View {
        let isSelected = selectedDueDatePreset == days

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedDueDatePreset = days
            dueDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        } label: {
            Text(title)
                .font(PPBrandFont.bold(12, relativeTo: .caption))
                .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? AdminSurface.primary : AdminSurface.control, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func splitInstallmentsEvenly() {
        guard !installments.isEmpty, amountDueMinor > 0 else { return }
        let count = installments.count
        let share = amountDueMinor / count
        let remainder = amountDueMinor % count

        for i in 0..<count {
            let part = share + (i == count - 1 ? remainder : 0)
            installments[i].amount = String(format: "%.2f", Double(part) / 100)
            installments[i].date = Calendar.current.date(byAdding: .month, value: i + 1, to: Date()) ?? Date()
        }
    }

    // MARK: - Review & Agreement (Step 3)

    private func reviewAgreementSection(context: POSCreditContext) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(label("POS_Credit_StepReview"))
                    .font(AdminType.headlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                Text(label("POS_Credit_AtSale"))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            // Financial Summary Rows
            VStack(spacing: 8) {
                moneyRow("POS_Credit_Total", totalMinor)
                moneyRow("POS_Credit_CollectedNow", pending ? 0 : (depositMinor ?? 0))
                if pending {
                    moneyRow("POS_Credit_Pending", depositMinor ?? 0)
                }
                Divider()
                moneyRow("POS_Credit_Remaining", amountDueMinor, prominent: true)
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16))

            // Dynamic Agreement Document Box
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(AdminSurface.primary)
                    Text(label("POS_Credit_Agreement"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Text(agreementWording(context))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                    )
            }

            // Customer Acceptance Toggle
            Toggle(isOn: $accepted) {
                Text(label("POS_Credit_AcceptTerms"))
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(AdminSurface.emerald)
            .padding(14)
            .background(accepted ? AdminSurface.emerald.opacity(0.1) : AdminSurface.control, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("pos.credit.acceptTerms")

            let (projectedBalance, overflow) = context.outstandingMinor.addingReportingOverflow(amountDueMinor)
            if context.overdueMinor > 0 || overflow || projectedBalance > context.limitMinor || delivery || model.deliveryFee > 0 || model.creditHasLiveItems {
                noticeCard(label("POS_Credit_ApprovalRequired"), color: AdminSurface.amber, symbol: "exclamationmark.shield.fill")
            }
        }
    }

    // MARK: - Floating Bottom Action Dock

    private var floatingActionDock: some View {
        VStack(spacing: 8) {
            if let context = model.creditContext {
                if isBusinessDateRolledOver {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isRefreshingEligibility = true
                        localError = nil
                        model.loadCreditContext()
                        reviewing = false
                        accepted = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            isRefreshingEligibility = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text(label("POS_Credit_Reload"))
                                .font(AdminType.headlineBold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(.white)
                        .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pos.credit.reload")
                } else if reviewing {
                    Button {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        do {
                            let settlement = try settlement(context)
                            guard accepted else { return }
                            if model.submitCreditOrder(settlement: settlement) { localError = nil }
                        } catch let error as POSCreditCheckoutError {
                            localError = error.errorDescription
                            if case .dateRollover = error {
                                model.loadCreditContext()
                                reviewing = false
                                accepted = false
                            }
                        } catch {
                            localError = label("POS_Credit_InvalidTerms")
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                            Text(label("POS_Credit_Complete"))
                                .font(AdminType.headlineBold)
                            Spacer()
                            Text(money(amountDueMinor))
                                .font(PPBrandFont.bold(17, relativeTo: .headline))
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(.white)
                        .background(accepted ? AdminSurface.emerald : AdminSurface.primary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isCheckoutBusy || !accepted)
                    .accessibilityIdentifier("pos.credit.confirm")

                    Button {
                        reviewing = false
                        accepted = false
                    } label: {
                        Text(label("POS_Credit_EditTerms"))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(AdminSurface.primary)
                            .frame(maxWidth: .infinity, minHeight: 38)
                    }
                } else {
                    Button {
                        editingAmount = false
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        do {
                            _ = try settlement(context)
                            reviewing = true
                            localError = nil
                        } catch let error as POSCreditCheckoutError {
                            localError = error.errorDescription
                            if case .dateRollover = error {
                                model.loadCreditContext()
                                reviewing = false
                                accepted = false
                            }
                        } catch {
                            localError = label("POS_Credit_InvalidTerms")
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(label("POS_Credit_NextToReview"))
                                .font(AdminType.headlineBold)
                            Spacer()
                            Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                                .font(.headline.weight(.bold))
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(.white)
                        .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isCheckoutBusy)
                    .accessibilityIdentifier("pos.credit.nextStep")
                }
            } else if model.selectedCustomer != nil {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isRefreshingEligibility = true
                    model.loadCreditContext()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        isRefreshingEligibility = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text(label("POS_Credit_Reload"))
                            .font(AdminType.headlineBold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.white)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pos.credit.reload")
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showsCustomerPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 18, weight: .bold))
                        Text(label("POS_Credit_ChooseCustomerToProceed"))
                            .font(AdminType.headlineBold)
                        Spacer()
                        Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(.white)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: AdminSurface.primary.opacity(0.24), radius: 10, y: 4)
                }
                .buttonStyle(PPCreditPressableButtonStyle())
                .accessibilityIdentifier("pos.credit.chooseCustomer")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    // MARK: - Recovery Section

    private var isApprovalRequired: Bool {
        model.creditRecovery?.approvalRequestJSON != nil
    }

    private var isApprovalRequested: Bool {
        model.creditError == POSCreditAccountCopy.text("ApprovalRequested")
    }

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: isApprovalRequired ? "person.crop.circle.badge.checkmark" : "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(AdminSurface.primary)
                Text(label(isApprovalRequired ? "POS_Credit_ApprovalRequiredTitle" : "POS_Credit_RecoveryTitle"))
                    .font(AdminType.title3Bold)
                    .foregroundStyle(AdminSurface.primaryText)
            }

            Text(model.creditRecoveryError ?? label(isApprovalRequired ? "POS_Credit_ApprovalRequiredBody" : (model.creditRecovery?.confirmedResultJSON == nil ? "POS_Credit_RecoveryUnknown" : "POS_Credit_RecoveryConfirmed")))
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if isApprovalRequired {
                if isApprovalRequested {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                        Text(label("POS_Credit_ApprovalRequestedStatus"))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Button {
                        model.requestCreditIssueApproval()
                    } label: {
                        HStack(spacing: 8) {
                            if model.isCheckoutBusy {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Text(POSCreditAccountCopy.text("RequestApproval"))
                                .font(AdminType.headlineBold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isCheckoutBusy)
                }

                if let record = model.creditRecovery, let envelope = try? JSONDecoder().decode(POSCreditPendingStore.Envelope.self, from: record.requestJSON) {
                    POSCreditAccountLink(customerID: envelope.payload.settlement.customerId, branchID: record.branchID)
                }
            }

            HStack(spacing: 10) {
                if let record = model.creditRecovery, record.confirmedResultJSON == nil {
                    Button(role: .destructive) {
                        promptCancelPendingCreditSale()
                    } label: {
                        Text(label("POS_Credit_CancelRecovery"))
                            .font(AdminType.subheadlineBold)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isCheckoutBusy)
                }

                Button {
                    model.recoverCreditSale()
                } label: {
                    HStack(spacing: 6) {
                        if model.isCheckoutBusy {
                            ProgressView().tint(.white)
                        } else if isApprovalRequired {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        Text(label(isApprovalRequired ? "POS_Credit_CompleteAfterApproval" : "POS_Credit_Recover"))
                            .font(AdminType.headlineBold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(model.isCheckoutBusy || model.creditRecovery == nil)
            }
        }
    }

    private func promptCancelPendingCreditSale() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        PPAlertHelper.showDestructiveConfirmation(
            in: nil,
            title: label("POS_Credit_CancelRecovery"),
            subtitle: label("POS_Credit_CancelRecoveryNotice"),
            confirmButton: label("POS_Credit_CancelRecovery"),
            cancelButton: Language.get("Cancel", alter: "تراجع"),
            icon: UIImage(systemName: "exclamationmark.triangle.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                model.cancelCreditIssue()
            },
            cancelBlock: nil
        )
    }

    // MARK: - Primitives & Helpers

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AdminSurface.hairline.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 10, y: 3)
    }

    private func noticeCard(_ message: String, color: Color, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 16, weight: .bold))
                .accessibilityHidden(true)
            Text(message)
                .font(AdminType.subheadline)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func moneyRow(_ key: String, _ value: Int, prominent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label(key))
                .font(prominent ? AdminType.headlineBold : AdminType.subheadline)
                .foregroundStyle(prominent ? AdminSurface.primaryText : AdminSurface.secondaryText)
            Spacer(minLength: 12)
            Text(money(value))
                .font(prominent ? PPBrandFont.bold(18, relativeTo: .title3) : PPBrandFont.bold(15, relativeTo: .subheadline))
                .foregroundStyle(prominent ? AdminSurface.primary : AdminSurface.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func day(_ date: Date, _ context: POSCreditContext) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: context.timeZone)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func settlement(_ context: POSCreditContext) throws -> [String: Any] {
        guard let deposit = depositMinor, deposit >= 0, deposit <= totalMinor, totalMinor > 0 else {
            throw POSCreditCheckoutError.invalidDeposit
        }
        guard context.customerId == model.selectedCustomer?.id else {
            throw POSCreditCheckoutError.customerMismatch
        }
        guard day(Date(), context) == context.businessDateKey else {
            throw POSCreditCheckoutError.dateRollover(contextDate: context.businessDateKey, currentDate: day(Date(), context))
        }

        var terms: [String: Any]
        if usesInstallments {
            let rows = try installments.map { entry -> [String: Any] in
                guard let amount = Self.minor(entry.amount), amount > 0 else {
                    throw POSCreditCheckoutError.invalidInstallmentAmount
                }
                guard day(entry.date, context) >= context.businessDateKey else {
                    throw POSCreditCheckoutError.installmentPrecedesToday
                }
                return ["dueDateKey": day(entry.date, context), "amountMinor": amount]
            }
            guard rows.reduce(0, { $0 + ($1["amountMinor"] as? Int ?? 0) }) == totalMinor - deposit else {
                throw POSCreditCheckoutError.installmentSumMismatch
            }
            terms = ["type": "installments", "installments": rows]
        } else {
            guard day(dueDate, context) >= context.businessDateKey else {
                throw POSCreditCheckoutError.dueDatePrecedesToday
            }
            terms = ["type": "fixed_due", "dueDateKey": day(dueDate, context)]
        }

        var tender: [String: Any] = ["amountMinor": deposit]
        if deposit > 0 {
            guard let account = context.receiptAccounts[method] else {
                throw POSCreditCheckoutError.receiptAccountMissing
            }
            let trimmedRef = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedRef.count <= 200 else {
                throw POSCreditCheckoutError.referenceTooLong
            }
            guard method == "cash" || (context.pendingTendersEnabled && !trimmedRef.isEmpty) else {
                throw POSCreditCheckoutError.referenceRequired
            }
            tender["method"] = method
            tender["accountId"] = account
            tender["reference"] = trimmedRef
        }

        return ["type": "credit", "contractVersion": 1, "customerId": context.customerId,
                "expectedPolicyVersion": context.policyVersion, "expectedAccountVersion": context.accountVersion,
                "checkoutContextHash": context.checkoutContextHash,
                "terms": terms, "deposit": tender, "agreementLocale": Language.isRTL() ? "ar" : "en",
                "termsAccepted": true, "agreementTemplateId": context.agreementTemplate.id,
                "agreementTemplateVersion": context.agreementTemplate.version, "fulfillment": (delivery || model.deliveryFee > 0) ? "delivery" : "counter"]
    }

    private func agreementWording(_ context: POSCreditContext) -> String {
        let deposit = depositMinor ?? 0
        func decimal(_ minor: Int) -> String { "\(minor / 100).\(String(format: "%02d", minor % 100))" }
        var schedule = deposit > 0 ? ["\(context.businessDateKey): \(decimal(deposit))"] : []
        if usesInstallments {
            schedule += installments.sorted {
                let first = day($0.date, context), second = day($1.date, context)
                return first == second ? (Self.minor($0.amount) ?? 0) < (Self.minor($1.amount) ?? 0) : first < second
            }.map { "\(day($0.date, context)): \(decimal(Self.minor($0.amount) ?? 0))" }
        } else if totalMinor > deposit {
            schedule.append("\(day(dueDate, context)): \(decimal(totalMinor - deposit))")
        }
        let values = ["customer": context.customerName, "currency": context.currency,
                      "total": decimal(totalMinor), "deposit": decimal(deposit),
                      "due": decimal(totalMinor - deposit), "schedule": schedule.joined(separator: "; ")]
        return values.reduce(Language.isRTL() ? context.agreementTemplate.ar : context.agreementTemplate.en) { result, pair in
            result.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }

    static func minor(_ raw: String) -> Int? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "٫", with: ".").map { character -> String in
                if let value = character.wholeNumberValue { return String(value) }
                return String(character)
            }.joined()
        guard normalized.range(of: #"^\d{1,10}(\.\d{0,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let number = NSDecimalNumber(decimal: decimal * 100)
        guard number.compare(NSDecimalNumber(value: 9_007_199_254_740_991)) != .orderedDescending else { return nil }
        return number.intValue
    }
}
