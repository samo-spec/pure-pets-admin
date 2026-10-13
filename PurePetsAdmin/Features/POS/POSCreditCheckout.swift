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

struct POSCreditInstallmentDraft: Identifiable {
    let id = UUID()
    var date = Date()
    var amount = ""
}

struct POSCreditCheckoutSheet: View {
    @ObservedObject var model: POSFastSellViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var depositText = "0.00"
    @State private var method = "cash"
    @State private var reference = ""
    @State private var dueDate = Date()
    @State private var usesInstallments = false
    @State private var installments = [POSCreditInstallmentDraft()]
    @State private var delivery = false
    @State private var reviewing = false
    @State private var accepted = false
    @State private var localError: String?
    @State private var showsCustomerPicker = false
    @FocusState private var editingAmount: Bool

    private func label(_ key: String) -> String { Language.get(key, alter: nil) }
    private func money(_ minor: Int) -> String { POSReceiptFormat.currency(Double(minor) / 100, code: "QAR") }
    private var totalMinor: Int { POSMoney.minorUnits(model.cartTotal) }
    private var depositMinor: Int? { Self.minor(depositText) }
    private var pending: Bool { (depositMinor ?? 0) > 0 && method != "cash" }
    private var amountDueMinor: Int { max(0, totalMinor - (pending ? 0 : (depositMinor ?? 0))) }
    private var draftIdentity: String {
        let cart = model.cartItems.map { "\($0.id):\($0.quantity):\($0.quantityGroupID):\($0.lineTotal):\($0.unitIDs)" }.joined(separator: ";")
        return "\(depositText)|\(method)|\(reference)|\(dueDate)|\(usesInstallments)|\(delivery)|\(installments.map { "\($0.date):\($0.amount)" })|\(model.cartTotal)|\(model.selectedCustomer?.id ?? "")|\(cart)|\(model.salesChannel.rawValue)|\(Language.isRTL())"
    }
    @State private var confirmsCancellation = false
    private var isRecovery: Bool { model.creditRecovery != nil || model.creditRecoveryError != nil }
    private var allowedMethods: [String] {
        guard let context = model.creditContext else { return [] }
        return ["cash", "card", "cheque", "bank_transfer", "fawry"].filter {
            context.receiptAccounts[$0] != nil && ($0 == "cash" || context.pendingTendersEnabled)
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentStep: Int {
        guard model.creditContext != nil else { return 0 }
        return reviewing ? 2 : 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !isRecovery {
                        introduction
                        journey
                    }
                    if isRecovery {
                        panel { recovery }
                    } else if model.isLoadingCreditContext {
                        loadingState
                    } else if let context = model.creditContext {
                        readyState(context)
                        panel { summary(context) }
                        panel {
                            if reviewing {
                                agreement(context)
                            } else {
                                terms(context)
                            }
                        }
                        if let message = localError ?? model.creditError {
                            notice(message, color: AdminSurface.crimson, symbol: "exclamationmark.circle")
                        }
                    } else {
                        selectionState
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(label("POS_Credit_PaymentMethod"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(label("POS_Credit_Close")) { dismiss() }
                        .disabled(model.isCheckoutBusy)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(label("POS_Credit_Done")) { editingAmount = false }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isRecovery && !model.isLoadingCreditContext && (model.creditContext != nil || model.canIssueCredit) { actionDock }
            }
            .overlay {
                if model.isSubmitting {
                    ProgressView()
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel(label("POS_Credit_Loading"))
                }
            }
            .interactiveDismissDisabled(model.isCheckoutBusy)
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .onAppear { model.loadCreditContext() }
            .onChange(of: draftIdentity) { _ in reviewing = false; accepted = false }
            .onChange(of: model.creditContext?.policyVersion) { _ in reviewing = false; accepted = false }
            .onChange(of: model.creditContext?.accountVersion) { _ in reviewing = false; accepted = false }
            .onChange(of: model.creditContext?.checkoutContextHash) { _ in reviewing = false; accepted = false }
            .onChange(of: allowedMethods) { methods in
                if !methods.contains(method) { method = methods.first ?? "" }
            }
            .sheet(isPresented: $showsCustomerPicker, onDismiss: { model.loadCreditContext() }) {
                POSCustomerPickerSheet(currentSelected: model.selectedCustomer, canCreateCustomer: false) { customer in
                    model.selectedCustomer = customer
                    showsCustomerPicker = false
                }
            }
        }
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(label("POS_Credit_Title"))
                    .font(AdminType.title)
                    .foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(label("POS_Credit_CheckoutHint"))
                    .font(AdminType.body)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "creditcard.fill")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 58, height: 58)
                .background(AdminSurface.primarySoft, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var journey: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                stage("POS_Credit_StepCustomer", number: 0)
                Rectangle().fill(AdminSurface.hairline).frame(maxWidth: .infinity).frame(height: 1)
                stage("POS_Credit_StepTerms", number: 1)
                Rectangle().fill(AdminSurface.hairline).frame(maxWidth: .infinity).frame(height: 1)
                stage("POS_Credit_StepReview", number: 2)
            }
            VStack(alignment: .leading, spacing: 10) {
                stage("POS_Credit_StepCustomer", number: 0)
                stage("POS_Credit_StepTerms", number: 1)
                stage("POS_Credit_StepReview", number: 2)
            }
        }
        .accessibilityElement(children: .contain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: currentStep)
    }

    private func stage(_ key: String, number: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: number < currentStep ? "checkmark.circle.fill" :
                    number == currentStep ? "circle.inset.filled" : "circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(number <= currentStep ? AdminSurface.primary : AdminSurface.secondaryText)
            Text(label(key))
                .font(number == currentStep ? AdminType.subheadlineBold : AdminType.subheadline)
                .foregroundStyle(number == currentStep ? AdminSurface.primaryText : AdminSurface.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(key))
        .accessibilityValue(label(number < currentStep ? "POS_Credit_StepDone" :
                                  number == currentStep ? "POS_Credit_StepCurrent" : "POS_Credit_StepUpcoming"))
    }

    private var loadingState: some View {
        panel {
            HStack(alignment: .center, spacing: 18) {
                ProgressView().tint(AdminSurface.primary).controlSize(.large)
                VStack(alignment: .leading, spacing: 5) {
                    Text(label("POS_Credit_Loading")).font(AdminType.title3)
                    Text(label("POS_Credit_LoadingDetail"))
                        .font(AdminType.body)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        }
        .accessibilityIdentifier("pos.credit.loading")
    }

    private var selectionState: some View {
        panel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: model.selectedCustomer == nil ?
                          "person.crop.circle.badge.plus" : "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(model.selectedCustomer == nil ? AdminSurface.primary : AdminSurface.amber)
                        .frame(width: 54, height: 54)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 17))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label(model.selectedCustomer == nil ? "POS_Credit_NeedsCustomer" : "POS_Credit_NeedsVerification"))
                            .font(AdminType.title2)
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let customer = model.selectedCustomer {
                            Text(customer.name)
                                .font(AdminType.bodyBold)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let message = model.creditError ?? model.creditAccessMessage {
                    notice(message, color: AdminSurface.amber, symbol: "info.circle")
                } else {
                    Text(label("POS_Credit_SelectCustomer"))
                        .font(AdminType.body)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.selectedCustomer != nil && model.canIssueCredit {
                    Text(label("POS_Credit_RefreshHelp"))
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("pos.credit.needsContext")
    }

    private func readyState(_ context: POSCreditContext) -> some View {
        panel {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 48, height: 48)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label("POS_Credit_ContextReady"))
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.primary)
                    Text(context.customerName)
                        .font(AdminType.title3)
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("pos.credit.contextReady")
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AdminSurface.hairline.opacity(0.65), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
    }

    private func notice(_ message: String, color: Color, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 17, weight: .semibold))
                .accessibilityHidden(true)
            Text(message)
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .combine)
    }

    private var actionDock: some View {
        VStack(spacing: 8) {
            if let context = model.creditContext {
                Button {
                    editingAmount = false
                    do {
                        let settlement = try settlement(context)
                        if reviewing {
                            guard accepted else { return }
                            if model.submitCreditOrder(settlement: settlement) { localError = nil }
                        } else {
                            reviewing = true
                            localError = nil
                        }
                    } catch {
                        localError = label("POS_Credit_InvalidTerms")
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(label(reviewing ? "POS_Credit_Complete" : "POS_Credit_Review"))
                            .font(AdminType.headlineBold)
                        Spacer(minLength: 0)
                        Image(systemName: reviewing ? "checkmark.seal.fill" : "arrow.forward")
                    }
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(.white)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(model.isCheckoutBusy || (reviewing && !accepted))
                .opacity(model.isCheckoutBusy || (reviewing && !accepted) ? 0.45 : 1)
                .accessibilityIdentifier("pos.credit.confirm")
                if reviewing {
                    Button(label("POS_Credit_EditTerms")) {
                        reviewing = false
                        accepted = false
                    }
                    .font(AdminType.bodyBold)
                    .foregroundStyle(AdminSurface.primary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(model.isCheckoutBusy)
                }
            } else if !model.isLoadingCreditContext && model.canIssueCredit {
                Button {
                    if model.selectedCustomer == nil {
                        showsCustomerPicker = true
                    } else {
                        model.loadCreditContext()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(label(model.selectedCustomer == nil ? "POS_Credit_ChooseCustomer" : "POS_Credit_Reload"))
                            .font(AdminType.headlineBold)
                        Spacer(minLength: 0)
                        Image(systemName: model.selectedCustomer == nil ? "person.crop.circle.badge.plus" : "arrow.clockwise")
                    }
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(.white)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pos.credit.nextStep")
                if model.selectedCustomer != nil {
                    Button(label("POS_Credit_ChooseCustomer")) { showsCustomerPicker = true }
                        .font(AdminType.bodyBold)
                        .foregroundStyle(AdminSurface.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentStep)
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.title).foregroundStyle(AdminSurface.primary)
            Text(label("POS_Credit_RecoveryTitle")).font(AdminType.title2)
            Text(model.creditRecoveryError ?? label(model.creditRecovery?.confirmedResultJSON == nil ? "POS_Credit_RecoveryUnknown" : "POS_Credit_RecoveryConfirmed"))
                .font(AdminType.body).fixedSize(horizontal: false, vertical: true)
            if let error = model.creditError { messageView(error) }
            if model.creditRecovery?.approvalRequestJSON != nil {
                Button(POSCreditAccountCopy.text("RequestApproval")) { model.requestCreditIssueApproval() }.disabled(model.isCheckoutBusy)
                if let record = model.creditRecovery, let envelope = try? JSONDecoder().decode(POSCreditPendingStore.Envelope.self, from: record.requestJSON) {
                    POSCreditAccountLink(customerID: envelope.payload.settlement.customerId, branchID: record.branchID)
                }
            }
            if let record = model.creditRecovery, record.confirmedResultJSON == nil {
                Button(label("POS_Credit_CancelRecovery"), role: .destructive) { confirmsCancellation = true }
                    .disabled(model.isCheckoutBusy).frame(minHeight: 44)
                    .confirmationDialog(label("POS_Credit_CancelRecoveryNotice"), isPresented: $confirmsCancellation, titleVisibility: .visible) {
                        Button(label("POS_Credit_CancelRecovery"), role: .destructive) { model.cancelCreditIssue() }
                    }
            }
            Button(label("POS_Credit_Recover")) { model.recoverCreditSale() }
                .buttonStyle(.borderedProminent).tint(AdminSurface.primary).frame(minHeight: 48)
                .disabled(model.isCheckoutBusy || model.creditRecovery == nil)
        }
    }
    private func summary(_ context: POSCreditContext) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(label("POS_Credit_SaleSnapshot"))
                .font(AdminType.headlineBold)
                .foregroundStyle(AdminSurface.primaryText)
            VStack(alignment: .leading, spacing: 4) {
                Text(label("POS_Credit_Remaining"))
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.secondaryText)
                HStack {
                    Text(money(amountDueMinor))
                        .font(AdminType.title)
                        .foregroundStyle(AdminSurface.primaryText)
                        .monospacedDigit()
                        .environment(\.layoutDirection, .leftToRight)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("pos.credit.amountDue")
                    Spacer(minLength: 0)
                }
            }
            Divider()
            moneyRow("POS_Credit_Total", totalMinor)
            moneyRow("POS_Credit_CollectedNow", pending ? 0 : (depositMinor ?? 0))
            if pending { moneyRow("POS_Credit_Pending", depositMinor ?? 0) }
            Text(String(format: label("POS_Credit_ExistingBalance"), money(context.outstandingMinor), money(context.limitMinor)))
                .font(AdminType.footnote)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            let (projectedBalance, overflow) = context.outstandingMinor.addingReportingOverflow(amountDueMinor)
            if context.overdueMinor > 0 || overflow ||
               projectedBalance > context.limitMinor ||
               delivery || model.deliveryFee > 0 || model.creditHasLiveItems {
                notice(label("POS_Credit_ApprovalRequired"), color: AdminSurface.amber, symbol: "exclamationmark.shield")
            }
        }
    }
    private func terms(_ context: POSCreditContext) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(label("POS_Credit_ConfigureTerms"))
                .font(AdminType.headlineBold)
                .foregroundStyle(AdminSurface.primaryText)
            field("POS_Credit_Deposit", text: $depositText, keyboard: .decimalPad)
            if (depositMinor ?? 0) > 0 {
                if allowedMethods.isEmpty {
                    notice(label("POS_Credit_NoTender"), color: AdminSurface.amber, symbol: "info.circle")
                } else {
                    Picker(label("POS_Credit_DepositMethod"), selection: $method) {
                        ForEach(allowedMethods, id: \.self) { value in
                            Text(POSReceiptFormat.paymentMethod(value)).tag(value)
                        }
                    }
                    .frame(minHeight: 44)
                }
                if method != "cash" {
                    field("POS_Credit_Reference", text: $reference)
                    Text(label("POS_Credit_PendingHint"))
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            Toggle(label("POS_Credit_Delivery"), isOn: $delivery).frame(minHeight: 44)
            Toggle(label("POS_Credit_Installments"), isOn: $usesInstallments).frame(minHeight: 44)
            if usesInstallments {
                ForEach($installments) { $entry in
                    VStack(alignment: .leading, spacing: 10) {
                        DatePicker(label("POS_Credit_DueDate"), selection: $entry.date, displayedComponents: .date)
                            .frame(minHeight: 44)
                        field("POS_Credit_InstallmentAmount", text: $entry.amount, keyboard: .decimalPad)
                        if installments.count > 1 {
                            Button(role: .destructive) {
                                installments.removeAll { $0.id == entry.id }
                            } label: {
                                Text(label("POS_Credit_RemoveInstallment"))
                            }
                            .frame(minHeight: 44)
                        }
                    }
                    .padding(14)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16))
                }
                if installments.count < 24 {
                    Button {
                        installments.append(POSCreditInstallmentDraft())
                    } label: {
                        Label(label("POS_Credit_AddInstallment"), systemImage: "plus.circle.fill")
                    }
                    .frame(minHeight: 44)
                }
            } else {
                DatePicker(label("POS_Credit_DueDate"), selection: $dueDate, displayedComponents: .date)
                    .frame(minHeight: 44)
            }
        }
        .tint(AdminSurface.primary)
        .environment(\.timeZone, TimeZone(identifier: context.timeZone) ?? .current)
        .environment(\.calendar, Calendar(identifier: .gregorian))
    }
    private func agreement(_ context: POSCreditContext) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(label("POS_Credit_Agreement"))
                .font(AdminType.headlineBold)
                .foregroundStyle(AdminSurface.primaryText)
            Text(agreementWording(context))
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Toggle(label("POS_Credit_AcceptTerms"), isOn: $accepted)
                .tint(AdminSurface.primary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("pos.credit.acceptTerms")
        }
    }
    private func messageView(_ value: String) -> some View {
        notice(value, color: AdminSurface.amber, symbol: "info.circle")
    }
    private func moneyRow(_ key: String, _ value: Int, prominent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label(key)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Text(money(value)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
        }
        .font(prominent ? AdminType.title2 : AdminType.body)
        .accessibilityElement(children: .combine)
    }
    private func field(_ key: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label(key))
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.secondaryText)
            TextField(label(key), text: text)
                .keyboardType(keyboard)
                .font(AdminType.body)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14))
                .focused($editingAmount)
                .accessibilityLabel(label(key))
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
        guard let deposit = depositMinor, deposit >= 0, deposit <= totalMinor, totalMinor > 0,
              context.customerId == model.selectedCustomer?.id, day(Date(), context) == context.businessDateKey else { throw POSCreditPendingStore.StoreError.invalidRecord }
        var terms: [String: Any]
        if usesInstallments {
            let rows = try installments.map { entry -> [String: Any] in
                guard let amount = Self.minor(entry.amount), amount > 0, day(entry.date, context) >= context.businessDateKey else { throw POSCreditPendingStore.StoreError.invalidRecord }
                return ["dueDateKey": day(entry.date, context), "amountMinor": amount]
            }
            guard rows.reduce(0, { $0 + ($1["amountMinor"] as? Int ?? 0) }) == totalMinor - deposit else { throw POSCreditPendingStore.StoreError.invalidRecord }
            terms = ["type": "installments", "installments": rows]
        } else {
            guard day(dueDate, context) >= context.businessDateKey else { throw POSCreditPendingStore.StoreError.invalidRecord }
            terms = ["type": "fixed_due", "dueDateKey": day(dueDate, context)]
        }
        var tender: [String: Any] = ["amountMinor": deposit]
        if deposit > 0 {
            guard let account = context.receiptAccounts[method],
                  reference.trimmingCharacters(in: .whitespacesAndNewlines).count <= 200,
                  method == "cash" || (context.pendingTendersEnabled && !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { throw POSCreditPendingStore.StoreError.invalidRecord }
            tender["method"] = method; tender["accountId"] = account
            tender["reference"] = reference.trimmingCharacters(in: .whitespacesAndNewlines)
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
