//
//  POSCustomerCreditPolicySheet.swift
//  PurePetsAdmin
//
//  Production-ready, crash-safe customer credit policy editor.
//  Configures and approves customer credit limits and terms for POS "Pay Later".
//

import SwiftUI
import FirebaseAuth

@MainActor
final class POSCustomerCreditPolicyViewModel: ObservableObject {
    let customerID: String
    let customerName: String
    let customerPhone: String
    let branchID: String
    let branchName: String

    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var errorMessage: String? = nil
    @Published var successMessage: String? = nil

    // Policy fields
    @Published var enabled: Bool = true
    @Published var limitText: String = "5000"
    @Published var reason: String = ""
    @Published var currentVersion: Int = 0
    @Published var hasLoadedExisting = false
    @Published var initialLimitMinor: Int = 0
    @Published var initialEnabled: Bool = false

    init(customerID: String, customerName: String, customerPhone: String, branchID: String, branchName: String) {
        self.customerID = customerID
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.branchID = branchID
        self.branchName = branchName
        self.reason = Language.isRTL() ? "اعتماد سياسة وتسهيلات البيع الآجل للعميل" : "Approved credit limit and terms"
    }

    var actorUID: String? {
        Auth.auth().currentUser?.uid
    }

    var limitMinor: Int? {
        POSCreditCheckoutSheet.minor(limitText)
    }

    var formattedCurrentLimit: String {
        POSReceiptFormat.currency(Double(initialLimitMinor) / 100.0, code: "QAR")
    }

    func loadPolicy() {
        guard let actorUID, !actorUID.isEmpty, !customerID.isEmpty, !branchID.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        let payload: [String: Any] = [
            "contractVersion": 1,
            "action": "list",
            "branchId": branchID,
            "customerId": customerID,
            "currency": "QAR"
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys) else {
            isLoading = false
            return
        }

        PPPOSService.shared().callCreditOperation("posCreditReviewCommand", request: requestData, actorUID: actorUID) { [weak self] responseData, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false

                if let error = error {
                    // Non-fatal on load: default to 5,000 QAR enabled
                    print("⚠️ [POSCreditPolicy] Load review notice: \(error.localizedDescription)")
                    self.hasLoadedExisting = true
                    return
                }

                guard let responseData,
                      let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                      let policy = json["policy"] as? [String: Any] else {
                    self.hasLoadedExisting = true
                    return
                }

                let ver = (policy["version"] as? NSNumber)?.intValue ?? 0
                let isEn = (policy["enabled"] as? Bool) ?? false
                let limit = (policy["limitMinor"] as? NSNumber)?.intValue ?? 0

                self.currentVersion = ver
                self.initialLimitMinor = limit
                self.initialEnabled = isEn
                self.hasLoadedExisting = true

                if ver > 0 {
                    self.enabled = isEn
                    let qar = Double(limit) / 100.0
                    self.limitText = String(format: "%.0f", qar)
                } else {
                    self.enabled = true
                    self.limitText = "5000"
                }
            }
        }
    }

    func savePolicy(onSuccess: @escaping @MainActor @Sendable () -> Void) {
        guard let actorUID, !actorUID.isEmpty else {
            errorMessage = Language.get("POS_Credit_SessionRequired", alter: "جلسة الموظف غير صالحة.")
            return
        }
        guard let limit = limitMinor, limit >= 0 else {
            errorMessage = Language.get("POS_Credit_InvalidAmount", alter: "يرجى إدخال سقف ائتمان صالح.")
            return
        }

        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (Language.isRTL() ? "اعتماد سياسة وتسهيلات البيع الآجل للعميل" : "Approved customer credit policy")
            : reason.trimmingCharacters(in: .whitespacesAndNewlines)

        isSubmitting = true
        errorMessage = nil

        let commandId = "policy_cmd_\(UUID().uuidString.prefix(12))"
        let payload: [String: Any] = [
            "contractVersion": 1,
            "action": "setPolicy",
            "commandId": commandId,
            "branchId": branchID,
            "customerId": customerID,
            "currency": "QAR",
            "expectedVersion": currentVersion,
            "enabled": enabled,
            "limitMinor": limit,
            "reason": cleanReason
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys) else {
            isSubmitting = false
            errorMessage = Language.get("POS_Credit_StorageFailed", alter: "تعذر معالجة الطلب.")
            return
        }

        PPPOSService.shared().callCreditOperation("posCreditPolicyCommand", request: requestData, actorUID: actorUID) { [weak self] responseData, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSubmitting = false

                if let error = error {
                    let nsError = error as NSError
                    let details = nsError.userInfo["details"] as? [String: Any]
                        ?? nsError.userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any]
                        ?? [:]
                    let domainCode = details["domainCode"] as? String ?? ""

                    if domainCode == "POS_CREDIT_DISABLED" {
                        self.errorMessage = Language.get("POS_Credit_Disabled", alter: "البيع الآجل غير مفعل لهذا الفرع.")
                    } else if nsError.code == 7 {
                        self.errorMessage = Language.get("POS_Credit_PermissionDenied", alter: "ليس لديك صلاحية لإدارة سياسات الائتمان.")
                    } else {
                        self.errorMessage = nsError.localizedDescription
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }

                guard let responseData,
                      let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                      json["ok"] as? Bool == true else {
                    self.errorMessage = Language.get("POS_Credit_Unavailable", alter: "تعذر حفظ سياسة الائتمان.")
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }

                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.successMessage = Language.get("POS_Credit_PolicySaved", alter: "تم حفظ واعتماد سياسة الائتمان بنجاح.")

                POSCustomerCreditStore.shared.invalidate(customerID: self.customerID, branchID: self.branchID)
                POSCustomerCreditStore.shared.loadCreditSummary(for: self.customerID, branchID: self.branchID)

                try? await Task.sleep(nanoseconds: 300_000_000)
                onSuccess()
            }
        }
    }
}

struct POSCustomerCreditPolicySheet: View {
    @StateObject private var viewModel: POSCustomerCreditPolicyViewModel
    let onPolicySaved: @MainActor @Sendable () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool

    init(customerID: String, customerName: String, customerPhone: String, branchID: String, branchName: String, onPolicySaved: @escaping @MainActor @Sendable () -> Void) {
        _viewModel = StateObject(wrappedValue: POSCustomerCreditPolicyViewModel(
            customerID: customerID,
            customerName: customerName,
            customerPhone: customerPhone,
            branchID: branchID,
            branchName: branchName
        ))
        self.onPolicySaved = onPolicySaved
    }

    private let presetLimits = [1000, 2500, 5000, 10000, 25000]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Customer & Branch Identity Hero Card
                    heroCard

                    // Status & Diagnostic Badge
                    statusBanner

                    // Main Configuration Form Card
                    configurationCard

                    // Reason / Operational Notes
                    notesCard

                    // Error Notice
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AdminSurface.crimson)
                            Text(error)
                                .font(PPBrandFont.regular(13, relativeTo: .footnote))
                                .foregroundStyle(AdminSurface.crimson)
                            Spacer()
                        }
                        .padding(12)
                        .background(AdminSurface.crimson.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Success Notice
                    if let success = viewModel.successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AdminSurface.emerald)
                            Text(success)
                                .font(PPBrandFont.bold(13, relativeTo: .footnote))
                                .foregroundStyle(AdminSurface.emerald)
                            Spacer()
                        }
                        .padding(12)
                        .background(AdminSurface.emerald.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Actions
                    VStack(spacing: 10) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            isAmountFocused = false
                            viewModel.savePolicy {
                                onPolicySaved()
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isSubmitting {
                                    ProgressView().tint(.white).scaleEffect(0.9)
                                } else {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                Text(Language.get("POS_Credit_SaveAndApproveCTA", alter: "حفظ واعتماد سياسة الائتمان"))
                                    .font(PPBrandFont.bold(16, relativeTo: .headline))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: AdminSurface.primary.opacity(0.24), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSubmitting || viewModel.isLoading)

                        // Secondary Link to Full Ledger
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            pushPOSCreditAccount(customerID: viewModel.customerID, branchID: viewModel.branchID, initialTab: "administration")
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet.rectangle.portrait")
                                Text(Language.get("POS_Credit_OpenFullLedger", alter: "عرض الحساب والمديونيات التفصيلية"))
                            }
                            .font(PPBrandFont.bold(13, relativeTo: .footnote))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                }
                .padding(16)
                .frame(maxWidth: 580)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("POS_Credit_PolicyEditorTitle", alter: "سياسة وتسهيلات البيع الآجل"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("POS_Credit_Close", alter: "إلغاء")) {
                        dismiss()
                    }
                    .font(PPBrandFont.bold(15, relativeTo: .callout))
                    .foregroundStyle(AdminSurface.primary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(Language.get("POS_Credit_Done", alter: "تم")) {
                        isAmountFocused = false
                    }
                    .font(PPBrandFont.bold(15, relativeTo: .callout))
                    .foregroundStyle(AdminSurface.primary)
                }
            }
            .onAppear {
                viewModel.loadPolicy()
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Subviews

    private var heroCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.12))
                    .frame(width: 52, height: 52)
                Text(String(viewModel.customerName.prefix(1)).uppercased())
                    .font(PPBrandFont.bold(20, relativeTo: .title2))
                    .foregroundStyle(AdminSurface.primary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.customerName)
                    .font(PPBrandFont.bold(16, relativeTo: .headline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(viewModel.customerPhone)
                        .font(PPBrandFont.medium(14, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .environment(\.layoutDirection, .leftToRight)
                }
                HStack(spacing: 6) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(viewModel.branchName)
                        .font(PPBrandFont.regular(13, relativeTo: .footnote))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AdminSurface.hairline))
    }

    private var statusBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: viewModel.initialEnabled && viewModel.currentVersion > 0 ? "checkmark.shield.fill" : "shield.slash.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(viewModel.initialEnabled && viewModel.currentVersion > 0 ? AdminSurface.emerald : AdminSurface.amber)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.initialEnabled && viewModel.currentVersion > 0
                     ? Language.get("POS_Credit_StatusApproved", alter: "سياسة الائتمان معتمدة ونشطة")
                     : Language.get("POS_Credit_NeedsVerification", alter: "تتطلب سياسة الائتمان الاعتماد والتحقق"))
                    .font(PPBrandFont.bold(14, relativeTo: .subheadline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(viewModel.initialEnabled && viewModel.currentVersion > 0
                     ? String(format: Language.get("POS_Credit_CurrentLimitSub", alter: "السقف الحالي: %@"), viewModel.formattedCurrentLimit)
                     : Language.get("POS_Credit_PolicyRequired", alter: "يحتاج هذا العميل إلى اعتماد سياسة وسقف ائتمان لهذا الفرع قبل البيع الآجل."))
                    .font(PPBrandFont.regular(13, relativeTo: .footnote))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (viewModel.initialEnabled && viewModel.currentVersion > 0 ? AdminSurface.emerald : AdminSurface.amber).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Enable Toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("POS_Credit_EnableSales", alter: "تفعيل البيع الآجل"))
                        .font(PPBrandFont.bold(15, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("POS_Credit_EnableSalesHint", alter: "السماح للعميل بالشراء الآجل وسداد الفاتورة لاحقاً"))
                        .font(PPBrandFont.regular(13, relativeTo: .footnote))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()
                Toggle("", isOn: $viewModel.enabled)
                    .labelsHidden()
                    .tint(AdminSurface.emerald)
            }

            Divider().overlay(AdminSurface.hairline)

            // Credit Limit Field
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Language.get("POS_Credit_LimitLabel", alter: "سقف الائتمان (ر.ق)"))
                        .font(PPBrandFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                    Spacer()
                    Text(Language.isRTL() ? "ر.ق." : "QAR")
                        .font(PPBrandFont.bold(13, relativeTo: .footnote))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                HStack(spacing: 8) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 24)

                    TextField("5000", text: $viewModel.limitText)
                        .font(PPBrandFont.bold(20, relativeTo: .title3))
                        .foregroundStyle(AdminSurface.primaryText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.leading)
                        .focused($isAmountFocused)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AdminSurface.hairline))

                // Quick preset pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(presetLimits, id: \.self) { preset in
                            let isSelected = viewModel.limitText == "\(preset)"
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.limitText = "\(preset)"
                            } label: {
                                Text(formattedPresetLabel(preset))
                                    .font(PPBrandFont.bold(13, relativeTo: .caption))
                                    .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? AdminSurface.primary : AdminSurface.control, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AdminSurface.hairline))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Language.get("POS_Credit_ReasonLabel", alter: "ملاحظات الاعتماد والاتفاق"))
                .font(PPBrandFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: Language.isRTL() ? "text.alignright" : "text.alignleft")
                    .font(.system(size: 14))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(width: 20)

                TextField(Language.get("POS_Credit_ReasonPlaceholder", alter: "ملاحظات حول سقف الائتمان وتسهيلات السداد..."), text: $viewModel.reason)
                    .font(PPBrandFont.regular(14, relativeTo: .subheadline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AdminSurface.hairline))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AdminSurface.hairline))
    }

    private func formattedPresetLabel(_ preset: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        let formattedNumber = formatter.string(from: NSNumber(value: preset)) ?? "\(preset)"
        let currencySuffix = Language.isRTL() ? "ر.ق." : "QAR"
        return "\(formattedNumber) \(currencySuffix)"
    }
}
