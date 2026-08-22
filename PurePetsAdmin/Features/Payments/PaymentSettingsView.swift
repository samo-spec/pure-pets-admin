//
//  PaymentSettingsView.swift
//  PurePetsAdmin
//
//  Settings form: delivery fee, COD toggle, online payment toggle. Save button.
//

import SwiftUI

// MARK: - Payment Settings ViewModel

@MainActor
final class PaymentSettingsViewModel: ObservableObject {
    @Published var deliveryFeeString: String = ""
    @Published var cashOnDeliveryEnabled: Bool = true
    @Published var onlinePaymentEnabled: Bool = true
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var saveSuccess = false

    private var originalSettings: PPPaymentAdminSettings?

    var hasChanges: Bool {
        guard let original = originalSettings else { return false }
        let fee = Double(deliveryFeeString) ?? 0
        return abs(fee - original.deliveryFee) > 0.001
            || cashOnDeliveryEnabled != original.cashOnDeliveryEnabled
            || onlinePaymentEnabled != original.onlinePaymentEnabled
    }

    func load() {
        isLoading = true
        errorMessage = nil
        PPPaymentManagementService.shared().loadPaymentSettings { [weak self] settings, error in
            let deliveryFee = settings?.deliveryFee
            let cashOnDeliveryEnabled = settings?.cashOnDeliveryEnabled
            let onlinePaymentEnabled = settings?.onlinePaymentEnabled
            let errorDescription = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let errorDescription {
                    self.errorMessage = errorDescription
                    return
                }
                if let deliveryFee, let cashOnDeliveryEnabled, let onlinePaymentEnabled {
                    let persistedSettings = PPPaymentAdminSettings()
                    persistedSettings.deliveryFee = deliveryFee
                    persistedSettings.cashOnDeliveryEnabled = cashOnDeliveryEnabled
                    persistedSettings.onlinePaymentEnabled = onlinePaymentEnabled
                    self.originalSettings = persistedSettings
                    self.deliveryFeeString = String(format: "%.2f", deliveryFee)
                    self.cashOnDeliveryEnabled = cashOnDeliveryEnabled
                    self.onlinePaymentEnabled = onlinePaymentEnabled
                }
            }
        }
    }

    func save() {
        guard let original = originalSettings else { return }
        let settings = PPPaymentAdminSettings()
        settings.deliveryFee = Double(deliveryFeeString) ?? original.deliveryFee
        settings.cashOnDeliveryEnabled = cashOnDeliveryEnabled
        settings.onlinePaymentEnabled = onlinePaymentEnabled

        isSaving = true
        errorMessage = nil
        saveSuccess = false
        PPPaymentManagementService.shared().savePaymentSettings(settings) { [weak self] saved, error in
            let deliveryFee = saved?.deliveryFee
            let cashOnDeliveryEnabled = saved?.cashOnDeliveryEnabled
            let onlinePaymentEnabled = saved?.onlinePaymentEnabled
            let errorDescription = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }
                self.isSaving = false
                if let errorDescription {
                    self.errorMessage = errorDescription
                    return
                }
                if let deliveryFee, let cashOnDeliveryEnabled, let onlinePaymentEnabled {
                    let persistedSettings = PPPaymentAdminSettings()
                    persistedSettings.deliveryFee = deliveryFee
                    persistedSettings.cashOnDeliveryEnabled = cashOnDeliveryEnabled
                    persistedSettings.onlinePaymentEnabled = onlinePaymentEnabled
                    self.originalSettings = persistedSettings
                    self.deliveryFeeString = String(format: "%.2f", deliveryFee)
                    self.cashOnDeliveryEnabled = cashOnDeliveryEnabled
                    self.onlinePaymentEnabled = onlinePaymentEnabled
                    self.saveSuccess = true
                }
            }
        }
    }
}

// MARK: - Payment Settings View

struct AdminPaymentSettingsView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PaymentSettingsViewModel()
    @FocusState private var focusedField: Bool

    init(session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.session = session
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView

                if viewModel.isLoading {
                    Spacer()
                    ProgressView().tint(AdminSurface.primary).scaleEffect(1.2)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: AdminSpacing.lg) {
                            deliveryFeeCard
                            togglesCard
                            saveButton
                            Spacer()
                        }
                        .padding(AdminSpacing.screenMargin)
                    }
                }
            }

            if viewModel.isSaving {
                AdminLoadingOverlay(message: Language.get("PaymentMgmt_Saving", alter: "جارٍ الحفظ..."))
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear { viewModel.load() }
        .alert(
            Language.get("PaymentMgmt_Saved", alter: "تم الحفظ"),
            isPresented: $viewModel.saveSuccess
        ) {
            Button(Language.get("OK", alter: "موافق")) {}
        } message: {
            Text(Language.get("PaymentMgmt_Saved_Message", alter: "تم حفظ الإعدادات بنجاح"))
        }
        .alert(
            Language.get("Error", alter: "\u{062e}\u{0637}\u{0623}"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button(Language.get("OK", alter: "\u{0645}\u{0648}\u{0627}\u{0641}\u{0642}")) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
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

                if viewModel.isLoading || viewModel.isSaving {
                    ProgressView()
                        .tint(AdminSurface.primary)
                } else {
                    Button(action: { viewModel.load() }) {
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

            Text(Language.get("CommandCenter_Payments_Workspace", alter: "مساحة المدفوعات") + " / " + Language.get("PaymentMgmt_Dashboard_Settings_Title", alter: "إعدادات الدفع"))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(Language.get("PaymentMgmt_Dashboard_Settings_Title", alter: "إعدادات الدفع"))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) { viewModel.load() }
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
    }

    private var deliveryFeeCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: AdminSpacing.md) {
                Label(
                    Language.get("PaymentMgmt_Delivery_Fee", alter: "\u{0631}\u{0633}\u{0648}\u{0645} \u{0627}\u{0644}\u{062a}\u{0648}\u{0635}\u{064a}\u{0644}"),
                    systemImage: "shippingbox.fill"
                )
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)

                HStack(spacing: AdminSpacing.sm) {
                    Text("SAR")
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.secondaryText)
                    TextField("0.00", text: $viewModel.deliveryFeeString)
                        .keyboardType(.decimalPad)
                        .font(AdminType.title2)
                        .foregroundColor(AdminSurface.primaryText)
                        .focused($focusedField)
                        .multilineTextAlignment(.leading)
                }
                .padding(AdminSpacing.md)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
            }
            .padding(AdminSpacing.base)
        }
    }

    private var togglesCard: some View {
        AdminCard {
            VStack(spacing: 0) {
                ToggleRow(
                    title: Language.get("PaymentMgmt_COD", alter: "\u{0627}\u{0644}\u{062f}\u{0641}\u{0639} \u{0639}\u{0646}\u{062f} \u{0627}\u{0644}\u{0627}\u{0633}\u{062a}\u{0644}\u{0627}\u{0645}"),
                    subtitle: Language.get("PaymentMgmt_COD_Sub", alter: "\u{0627}\u{0644}\u{0633}\u{0645}\u{0627}\u{062d} \u{0628}\u{0627}\u{0644}\u{062f}\u{0641}\u{0639} \u{0646}\u{0642}\u{062f}\u{064b}\u{0627} \u{0639}\u{0646}\u{062f} \u{0627}\u{0644}\u{062a}\u{0648}\u{0635}\u{064a}\u{0644}"),
                    symbol: "banknote.fill",
                    isOn: $viewModel.cashOnDeliveryEnabled
                )
                Divider().background(AdminSurface.hairline).padding(.leading, 56)
                ToggleRow(
                    title: Language.get("PaymentMgmt_Online", alter: "\u{0627}\u{0644}\u{062f}\u{0641}\u{0639} \u{0627}\u{0644}\u{0625}\u{0644}\u{0643}\u{062a}\u{0631}\u{0648}\u{0646}\u{064a}"),
                    subtitle: Language.get("PaymentMgmt_Online_Sub", alter: "\u{0627}\u{0644}\u{0633}\u{0645}\u{0627}\u{062d} \u{0628}\u{0627}\u{0644}\u{062f}\u{0641}\u{0639} \u{0639}\u{0628}\u{0631} \u{0627}\u{0644}\u{0628}\u{0637}\u{0627}\u{0642}\u{0627}\u{062a} \u{0627}\u{0644}\u{0628}\u{0646}\u{0643}\u{064a}\u{0629}"),
                    symbol: "creditcard.fill",
                    isOn: $viewModel.onlinePaymentEnabled
                )
            }
            .padding(AdminSpacing.base)
        }
    }

    private var saveButton: some View {
        Button {
            viewModel.save()
        } label: {
            Text(Language.get("Save", alter: "\u{062d}\u{0641}\u{0638}"))
                .font(AdminType.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AdminTouchTarget.comfortable)
        }
        .buttonStyle(.borderedProminent)
        .tint(AdminSurface.primary)
        .disabled(!viewModel.hasChanges || viewModel.isSaving)
        .opacity(viewModel.hasChanges ? 1 : AdminOpacity.disabled)
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: AdminSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 32, height: 32)
                .background(AdminSurface.primarySoft.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                Text(subtitle)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AdminSurface.primary)
                .frame(minWidth: AdminTouchTarget.minimum, minHeight: AdminTouchTarget.minimum)
        }
        .padding(.vertical, AdminSpacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
@objc public final class PaymentSettingsHostingController: UIViewController {
    private var host: UIHostingController<AdminPaymentSettingsView>?
    public override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .ppBackground
        let root = AdminPaymentSettingsView(session: AdminSession(source: PPAdminSessionSnapshot()))
        let h = UIHostingController(rootView: root); h.view.backgroundColor = .clear
        addChild(h); view.addSubview(h.view); h.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([h.view.topAnchor.constraint(equalTo: view.topAnchor), h.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), h.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), h.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        h.didMove(toParent: self); host = h
    }
    public override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: animated) }
}
}
