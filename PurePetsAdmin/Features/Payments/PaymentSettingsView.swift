//
//  PaymentSettingsView.swift
//  PurePetsAdmin
//
//  Category-Defining Payment Basics & Delivery Tariff Command Center.
//  Reinvented from first principles for iPhone (compact) and iPad (adaptive 2-column cockpit).
//

import SwiftUI
import UIKit

// MARK: - Payment Settings ViewModel

@MainActor
final class PaymentSettingsViewModel: ObservableObject {
    @Published var deliveryFee: Double = 0.0
    @Published var deliveryFeeString: String = "0.00"
    @Published var cashOnDeliveryEnabled: Bool = true
    @Published var onlinePaymentEnabled: Bool = true

    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastUpdatedBy: String?

    @Published private(set) var isLoading: Bool = true
    @Published private(set) var isSaving: Bool = false
    @Published var errorMessage: String?
    @Published var saveSuccess: Bool = false
    @Published var showInterlockWarning: Bool = false

    // Simulator interactive state
    @Published var simulatedPaymentMethod: String = "online"

    private(set) var originalSettings: PPPaymentAdminSettings?

    var hasChanges: Bool {
        guard let original = originalSettings else { return false }
        let currentFee = Double(deliveryFeeString) ?? deliveryFee
        let feeChanged = abs(currentFee - original.deliveryFee) > 0.001
        let codChanged = cashOnDeliveryEnabled != original.cashOnDeliveryEnabled
        let onlineChanged = onlinePaymentEnabled != original.onlinePaymentEnabled
        return feeChanged || codChanged || onlineChanged
    }

    var pendingChangesCount: Int {
        guard let original = originalSettings else { return 0 }
        var count = 0
        let currentFee = Double(deliveryFeeString) ?? deliveryFee
        if abs(currentFee - original.deliveryFee) > 0.001 { count += 1 }
        if cashOnDeliveryEnabled != original.cashOnDeliveryEnabled { count += 1 }
        if onlinePaymentEnabled != original.onlinePaymentEnabled { count += 1 }
        return count
    }

    var isFreeDelivery: Bool {
        let fee = Double(deliveryFeeString) ?? deliveryFee
        return fee < 0.001
    }

    var canDisableCOD: Bool {
        onlinePaymentEnabled
    }

    var canDisableOnline: Bool {
        cashOnDeliveryEnabled
    }

    var isValid: Bool {
        let fee = Double(deliveryFeeString) ?? deliveryFee
        return fee >= 0.0 && (cashOnDeliveryEnabled || onlinePaymentEnabled)
    }

    // MARK: - Intent Actions

    func load() {
        isLoading = true
        errorMessage = nil
        showInterlockWarning = false

        PPPaymentManagementService.shared().loadPaymentSettings { [weak self] settings, error in
            let fee = settings?.deliveryFee
            let cod = settings?.cashOnDeliveryEnabled
            let online = settings?.onlinePaymentEnabled
            let updatedDate = settings?.updatedAt
            let updater = settings?.updatedBy
            let errText = error?.localizedDescription

            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let errText {
                    self.errorMessage = errText
                    return
                }

                if let fee, let cod, let online {
                    let persisted = PPPaymentAdminSettings()
                    persisted.deliveryFee = fee
                    persisted.cashOnDeliveryEnabled = cod
                    persisted.onlinePaymentEnabled = online
                    persisted.updatedAt = updatedDate
                    persisted.updatedBy = updater

                    self.originalSettings = persisted
                    self.deliveryFee = fee
                    self.deliveryFeeString = String(format: "%.2f", fee)
                    self.cashOnDeliveryEnabled = cod
                    self.onlinePaymentEnabled = online
                    self.lastUpdatedAt = updatedDate
                    self.lastUpdatedBy = updater

                    // Adjust simulator default
                    if online {
                        self.simulatedPaymentMethod = "online"
                    } else if cod {
                        self.simulatedPaymentMethod = "cod"
                    }
                }
            }
        }
    }

    func setDeliveryFeePreset(_ amount: Double) {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        feedback.impactOccurred()

        withAnimation(AdminAnimation.standard) {
            deliveryFee = max(0.0, amount)
            deliveryFeeString = String(format: "%.2f", deliveryFee)
        }
    }

    func adjustDeliveryFee(by step: Double) {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        feedback.impactOccurred()

        let current = Double(deliveryFeeString) ?? deliveryFee
        let updated = max(0.0, current + step)
        withAnimation(AdminAnimation.standard) {
            deliveryFee = updated
            deliveryFeeString = String(format: "%.2f", updated)
        }
    }

    func toggleCOD() {
        if cashOnDeliveryEnabled && !canDisableCOD {
            let notification = UINotificationFeedbackGenerator()
            notification.prepare()
            notification.notificationOccurred(.warning)
            withAnimation(AdminAnimation.standard) {
                showInterlockWarning = true
            }
            return
        }

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        feedback.impactOccurred()

        withAnimation(AdminAnimation.standard) {
            cashOnDeliveryEnabled.toggle()
            showInterlockWarning = false
            if !cashOnDeliveryEnabled && simulatedPaymentMethod == "cod" {
                simulatedPaymentMethod = "online"
            }
        }
    }

    func toggleOnlinePayment() {
        if onlinePaymentEnabled && !canDisableOnline {
            let notification = UINotificationFeedbackGenerator()
            notification.prepare()
            notification.notificationOccurred(.warning)
            withAnimation(AdminAnimation.standard) {
                showInterlockWarning = true
            }
            return
        }

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        feedback.impactOccurred()

        withAnimation(AdminAnimation.standard) {
            onlinePaymentEnabled.toggle()
            showInterlockWarning = false
            if !onlinePaymentEnabled && simulatedPaymentMethod == "online" {
                simulatedPaymentMethod = "cod"
            }
        }
    }

    func resetToOriginal() {
        guard let original = originalSettings else { return }
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        feedback.impactOccurred()

        withAnimation(AdminAnimation.standard) {
            deliveryFee = original.deliveryFee
            deliveryFeeString = String(format: "%.2f", original.deliveryFee)
            cashOnDeliveryEnabled = original.cashOnDeliveryEnabled
            onlinePaymentEnabled = original.onlinePaymentEnabled
            showInterlockWarning = false
        }
    }

    func save() {
        guard let original = originalSettings else { return }
        let parsedFee = Double(deliveryFeeString) ?? deliveryFee
        guard parsedFee >= 0.0 else {
            errorMessage = Language.get("PaymentMgmt_Settings_Error_InvalidDeliveryFee", alter: "أدخل رسوم توصيل صحيحة أكبر من أو تساوي 0.")
            return
        }
        guard cashOnDeliveryEnabled || onlinePaymentEnabled else {
            errorMessage = Language.get("PaymentMgmt_Settings_Error_NoMethodEnabled", alter: "يجب تفعيل طريقة دفع واحدة على الأقل.")
            return
        }

        let settings = PPPaymentAdminSettings()
        settings.deliveryFee = parsedFee
        settings.cashOnDeliveryEnabled = cashOnDeliveryEnabled
        settings.onlinePaymentEnabled = onlinePaymentEnabled

        isSaving = true
        errorMessage = nil
        saveSuccess = false

        PPPaymentManagementService.shared().savePaymentSettings(settings) { [weak self] saved, error in
            let fee = saved?.deliveryFee
            let cod = saved?.cashOnDeliveryEnabled
            let online = saved?.onlinePaymentEnabled
            let updatedDate = saved?.updatedAt
            let updater = saved?.updatedBy
            let errText = error?.localizedDescription

            Task { @MainActor in
                guard let self else { return }
                self.isSaving = false
                if let errText {
                    self.errorMessage = errText
                    let notify = UINotificationFeedbackGenerator()
                    notify.notificationOccurred(.error)
                    return
                }

                if let fee, let cod, let online {
                    let persisted = PPPaymentAdminSettings()
                    persisted.deliveryFee = fee
                    persisted.cashOnDeliveryEnabled = cod
                    persisted.onlinePaymentEnabled = online
                    persisted.updatedAt = updatedDate
                    persisted.updatedBy = updater

                    self.originalSettings = persisted
                    self.deliveryFee = fee
                    self.deliveryFeeString = String(format: "%.2f", fee)
                    self.cashOnDeliveryEnabled = cod
                    self.onlinePaymentEnabled = online
                    self.lastUpdatedAt = updatedDate
                    self.lastUpdatedBy = updater
                    self.saveSuccess = true

                    let notify = UINotificationFeedbackGenerator()
                    notify.notificationOccurred(.success)
                }
            }
        }
    }
}

// MARK: - Root View

struct AdminPaymentSettingsView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel = PaymentSettingsViewModel()

    init(session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.session = session
        self.onDismiss = onDismiss
    }

    private var isPadRegular: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                sovereignHeaderView

                if viewModel.isLoading {
                    Spacer()
                    VStack(spacing: AdminSpacing.md) {
                        ProgressView()
                            .tint(AdminSurface.primary)
                            .scaleEffect(1.3)
                        Text(Language.get("PaymentMgmt_Settings_Loading", alter: "جارِ تحميل أساسيات الدفع"))
                            .font(AdminType.callout)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    Spacer()
                } else {
                    if isPadRegular {
                        iPadTwoColumnCockpit
                    } else {
                        iPhoneSingleColumnCockpit
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
            Text(Language.get("PaymentMgmt_Settings_Saved", alter: "تم تحديث أساسيات الدفع بنجاح"))
        }
        .alert(
            Language.get("Error", alter: "خطأ"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button(Language.get("OK", alter: "موافق")) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Sovereign Header

    private var sovereignHeaderView: some View {
        VStack(alignment: .leading, spacing: 0) {
            AdminSovereignNavigationBar(
                title: Language.get("PaymentMgmt_Settings_Title", alter: "أساسيات الدفع"),
                subtitle: Language.get("CommandCenter_Payments_Workspace", alter: "مساحة المدفوعات"),
                onBack: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
            ) {
                HStack(spacing: AdminSpacing.sm) {
                    if viewModel.hasChanges && !isPadRegular {
                        Button {
                            viewModel.resetToOriginal()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AdminSurface.secondaryText)
                                .frame(width: 44, height: 44)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Language.get("PaymentMgmt_Settings_Revert", alter: "تراجع عن التعديلات"))
                    }

                    Button {
                        viewModel.load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(width: 44, height: 44)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                            )
                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                }
            }

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) { viewModel.load() }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.xs)
            }
        }
    }

    // MARK: - iPhone Single Column Cockpit

    private var iPhoneSingleColumnCockpit: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: AdminSpacing.lg) {
                    if viewModel.showInterlockWarning {
                        interlockWarningBanner
                    }

                    deliveryTariffStudioCard

                    gatewaySwitchboardCard

                    customerCheckoutSimulatorCard

                    auditGovernanceCard

                    // Spacer for bottom command bar clearance
                    Color.clear.frame(height: 88)
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, AdminSpacing.md)
                .padding(.bottom, AdminSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)

            iPhoneFloatingCommandBar
        }
    }

    // MARK: - iPad Adaptive Two-Column Cockpit

    private var iPadTwoColumnCockpit: some View {
        HStack(alignment: .top, spacing: AdminSpacing.xl) {
            // Left / Leading Column: Controls Deck
            ScrollView {
                VStack(spacing: AdminSpacing.lg) {
                    if viewModel.showInterlockWarning {
                        interlockWarningBanner
                    }

                    deliveryTariffStudioCard

                    gatewaySwitchboardCard

                    Color.clear.frame(height: AdminSpacing.base)
                }
                .padding(.leading, AdminSpacing.screenMargin)
                .padding(.trailing, AdminSpacing.sm)
                .padding(.top, AdminSpacing.md)
                .padding(.bottom, AdminSpacing.xxl)
            }
            .frame(maxWidth: .infinity)
            .scrollDismissesKeyboard(.interactively)

            // Right / Trailing Column: Intelligence & Live Simulator
            ScrollView {
                VStack(spacing: AdminSpacing.lg) {
                    customerCheckoutSimulatorCard

                    auditGovernanceCard

                    iPadActionConsoleCard

                    Color.clear.frame(height: AdminSpacing.base)
                }
                .padding(.leading, AdminSpacing.sm)
                .padding(.trailing, AdminSpacing.screenMargin)
                .padding(.top, AdminSpacing.md)
                .padding(.bottom, AdminSpacing.xxl)
            }
            .frame(width: 390)
        }
    }

    // MARK: - Hero Delivery Tariff Studio Card

    private var deliveryTariffStudioCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                // Header with badge
                HStack(alignment: .center, spacing: AdminSpacing.sm) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.primarySoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("PaymentMgmt_Settings_Field_DeliveryFee", alter: "رسوم التوصيل"))
                            .font(AdminType.headlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("PaymentMgmt_Dashboard_Settings_Subtitle", alter: "التعرفة المطبقة على شحنات المتجر"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    if viewModel.isFreeDelivery {
                        HStack(spacing: 4) {
                            Circle().fill(AdminSurface.emerald).frame(width: 7, height: 7)
                            Text(Language.get("PaymentMgmt_Settings_FreeDelivery_Badge", alter: "توصيل مجاني"))
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.emerald)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AdminSurface.emerald.opacity(0.12), in: Capsule())
                    } else {
                        HStack(spacing: 4) {
                            Text(Language.get("PaymentMgmt_Settings_StandardDelivery_Badge", alter: "تعرفة الشحن الثابتة"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AdminSurface.control, in: Capsule())
                    }
                }

                // Numerical Hero Readout & Micro-Steppers
                VStack(spacing: AdminSpacing.md) {
                    HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.sm) {
                        Text(viewModel.deliveryFeeString)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(AdminSurface.primaryText)
                            .contentTransition(.numericText())

                        Text(Language.get("QAR", alter: "ر.ق"))
                            .font(AdminType.headlineBold)
                            .foregroundColor(AdminSurface.secondaryText)

                        Spacer()

                        // Micro Steppers
                        HStack(spacing: 6) {
                            stepperButton(label: "-1", step: -1.0)
                            stepperButton(label: "+1", step: 1.0)
                            stepperButton(label: "+5", step: 5.0)
                        }
                    }
                    .padding(AdminSpacing.base)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                    )

                    // Quick Qatar Tariff Presets
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(Language.get("PaymentMgmt_Settings_Presets_Title", alter: "خيارات التعرفة السريعة (قطر)"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)

                        presetChipsRow
                    }
                }

                // Backend Note Footnote
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
                        .padding(.top, 1)

                    Text(Language.get("PaymentMgmt_Settings_Footer_DeliveryFee", alter: "يقوم الباك إند بكتابة رسوم التوصيل داخل كل طلب جديد حتى تظل الإجماليات متطابقة في التطبيقين."))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(AdminSpacing.base)
        }
    }

    private func stepperButton(label: String, step: Double) -> some View {
        Button {
            viewModel.adjustDeliveryFee(by: step)
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AdminSurface.primaryText)
                .frame(minWidth: 42, minHeight: 38)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step > 0 ? "زيادة \(Int(step)) ر.ق" : "إنقاص \(Int(abs(step))) ر.ق")
    }

    private var presetChipsRow: some View {
        let presets: [(label: String, amount: Double)] = [
            (Language.get("Free", alter: "مجاني (0)"), 0.0),
            ("10", 10.0),
            ("15", 15.0),
            ("20", 20.0),
            ("25", 25.0),
            ("30", 30.0)
        ]

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.amount) { item in
                    let isSelected = abs(viewModel.deliveryFee - item.amount) < 0.001
                    Button {
                        viewModel.setDeliveryFeePreset(item.amount)
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.label)
                                .font(AdminType.captionBold)
                            if item.amount > 0 {
                                Text(Language.get("QAR", alter: "ر.ق"))
                                    .font(AdminType.caption2)
                            }
                        }
                        .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(
                            isSelected ? AdminSurface.primary : AdminSurface.control,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.8)
                        )
                        .shadow(color: isSelected ? AdminSurface.primary.opacity(0.24) : Color.clear, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Gateway Switchboard Card

    private var gatewaySwitchboardCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                HStack(alignment: .center, spacing: AdminSpacing.sm) {
                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.primarySoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("PaymentMgmt_Settings_Section_Methods", alter: "طرق الدفع عند إتمام الشراء"))
                            .font(AdminType.headlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("PaymentMgmt_Settings_Footer_Methods", alter: "إدارة البوابات المعروضة في شاشة سلة الشراء"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                VStack(spacing: 0) {
                    // Cash on Delivery
                    gatewayTile(
                        iconName: "banknote.fill",
                        title: Language.get("PaymentMgmt_Settings_Field_CashOnDelivery", alter: "الدفع عند الاستلام"),
                        subtitle: Language.get("PaymentMgmt_Settings_COD_Description", alter: "استلام نقدي مباشر عبر مندوب التوصيل مع إيصال رقمي فوري."),
                        isEnabled: viewModel.cashOnDeliveryEnabled,
                        canToggle: viewModel.canDisableCOD,
                        badges: ["COD", "Cash"]
                    ) {
                        viewModel.toggleCOD()
                    }

                    Divider()
                        .background(AdminSurface.hairline)
                        .padding(.vertical, AdminSpacing.sm)

                    // Online Payments (QIB)
                    gatewayTile(
                        iconName: "creditcard.fill",
                        title: Language.get("PaymentMgmt_Settings_Field_OnlinePayments", alter: "الدفع الإلكتروني"),
                        subtitle: Language.get("PaymentMgmt_Settings_Online_Description", alter: "دفع فوري مشفر عبر QIB يدعم بطاقات الخصم/الائتمان و Apple Pay."),
                        isEnabled: viewModel.onlinePaymentEnabled,
                        canToggle: viewModel.canDisableOnline,
                        badges: ["QIB Gateway", "Apple Pay", "Visa / Master"]
                    ) {
                        viewModel.toggleOnlinePayment()
                    }
                }
            }
            .padding(AdminSpacing.base)
        }
    }

    private func gatewayTile(
        iconName: String,
        title: String,
        subtitle: String,
        isEnabled: Bool,
        canToggle: Bool,
        badges: [String],
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: AdminSpacing.md) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isEnabled ? AdminSurface.primary : AdminSurface.secondaryText)
                .frame(width: 40, height: 40)
                .background(
                    isEnabled ? AdminSurface.primarySoft.opacity(0.20) : AdminSurface.control,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)

                    if isEnabled {
                        Text(Language.get("PaymentMgmt_Settings_Status_Active", alter: "نشط"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.emerald)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.emerald.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Text(Language.get("PaymentMgmt_Settings_Status_Inactive", alter: "معطل"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }

                Text(subtitle)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                // Sub-badges
                HStack(spacing: 6) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .padding(.top, 2)
            }

            Spacer()

            // Custom Switch with Lock indicator
            Button {
                action()
            } label: {
                ZStack {
                    Capsule()
                        .fill(isEnabled ? AdminSurface.primary : AdminSurface.control)
                        .frame(width: 52, height: 32)
                        .overlay(
                            Capsule()
                                .strokeBorder(isEnabled ? Color.clear : AdminSurface.hairline, lineWidth: 1)
                        )

                    HStack {
                        if isEnabled {
                            Spacer()
                        }
                        Circle()
                            .fill(Color.white)
                            .frame(width: 26, height: 26)
                            .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                            .overlay(
                                Group {
                                    if !canToggle && isEnabled {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                }
                            )
                            .padding(.horizontal, 3)
                        if !isEnabled {
                            Spacer()
                        }
                    }
                    .frame(width: 52)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title): \(isEnabled ? "مفعل" : "معطل")")
        }
        .padding(.vertical, AdminSpacing.xs)
    }

    // MARK: - Interlock Warning Banner

    private var interlockWarningBanner: some View {
        HStack(alignment: .top, spacing: AdminSpacing.sm) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 18))
                .foregroundColor(AdminSurface.amber)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Warning", alter: "تنبيه تشغيلي"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.amber)
                Text(Language.get("PaymentMgmt_Settings_Safety_Interlock", alter: "حماية تدفق الطلبات: يجب إبقاء وسيلة دفع واحدة على الأقل مفعلة لمنع توقف سلة الشراء."))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.amber.opacity(0.4), lineWidth: 0.8)
        )
    }

    // MARK: - Live Customer Checkout Simulator Card

    private var customerCheckoutSimulatorCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: AdminSpacing.md) {
                HStack(alignment: .center, spacing: AdminSpacing.sm) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.primarySoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(Language.get("PaymentMgmt_Settings_Simulator_Title", alter: "محاكاة تجربة إتمام الطلب (العميل)"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("PaymentMgmt_Settings_Simulator_Sub", alter: "انعكاس فوري لكيفية ظهور هذه الرسوم وطرق الدفع في تطبيق العميل"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                // Simulated Customer Cart Card
                VStack(spacing: AdminSpacing.sm) {
                    // Sample Item
                    HStack {
                        Image(systemName: "bag.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(Language.get("PaymentMgmt_Settings_Simulator_CartSample", alter: "طعام قطط رويال كانين (2 كجم) × 1"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.primaryText)
                        Spacer()
                        Text("185.00 " + Language.get("QAR", alter: "ر.ق"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.primaryText)
                    }

                    Divider().background(AdminSurface.hairline)

                    // Subtotal
                    HStack {
                        Text(Language.get("PaymentMgmt_Settings_Simulator_Subtotal", alter: "المجموع الفرعي"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                        Spacer()
                        Text("185.00 " + Language.get("QAR", alter: "ر.ق"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    // Delivery Line
                    HStack {
                        Text(Language.get("PaymentMgmt_Settings_Simulator_Delivery", alter: "رسوم التوصيل"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                        Spacer()
                        if viewModel.isFreeDelivery {
                            Text(Language.get("PaymentMgmt_Settings_FreeDelivery_Badge", alter: "توصيل مجاني"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.emerald)
                        } else {
                            Text(String(format: "%.2f %@", viewModel.deliveryFee, Language.get("QAR", alter: "ر.ق")))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.primaryText)
                        }
                    }

                    Divider().background(AdminSurface.hairline)

                    // Grand Total
                    let grandTotal = 185.0 + viewModel.deliveryFee
                    HStack {
                        Text(Language.get("PaymentMgmt_Settings_Simulator_Total", alter: "الإجمالي النهائي"))
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Spacer()
                        Text(String(format: "%.2f %@", grandTotal, Language.get("QAR", alter: "ر.ق")))
                            .font(AdminType.headlineBold)
                            .foregroundColor(AdminSurface.primary)
                    }

                    // Simulated Payment Method Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Language.get("PaymentMgmt_Settings_Simulator_MethodsLabel", alter: "خيارات الدفع المتاحة في السلة"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.top, 4)

                        HStack(spacing: 8) {
                            if viewModel.onlinePaymentEnabled {
                                simulatedOptionPill(
                                    title: Language.get("PaymentMgmt_Settings_Field_OnlinePayments", alter: "الدفع الإلكتروني"),
                                    icon: "creditcard.fill",
                                    tag: "online"
                                )
                            }

                            if viewModel.cashOnDeliveryEnabled {
                                simulatedOptionPill(
                                    title: Language.get("PaymentMgmt_Settings_Field_CashOnDelivery", alter: "الدفع عند الاستلام"),
                                    icon: "banknote.fill",
                                    tag: "cod"
                                )
                            }
                        }
                    }
                }
                .padding(AdminSpacing.md)
                .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                )
            }
            .padding(AdminSpacing.base)
        }
    }

    private func simulatedOptionPill(title: String, icon: String, tag: String) -> some View {
        let isSelected = viewModel.simulatedPaymentMethod == tag
        return Button {
            withAnimation(AdminAnimation.fast) {
                viewModel.simulatedPaymentMethod = tag
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(AdminType.caption2Bold)
            }
            .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                isSelected ? AdminSurface.primarySoft.opacity(0.20) : AdminSurface.surface,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Audit & Governance Card

    private var auditGovernanceCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                HStack(spacing: AdminSpacing.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AdminSurface.emerald)
                    Text(Language.get("PaymentMgmt_Settings_Audit_Title", alter: "سجل الحوكمة والامتثال"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let date = viewModel.lastUpdatedAt {
                        let formatter = DateFormatter()
                        let _ = formatter.locale = Locale.current
                        let _ = formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy h:mm a")
                        let dateStr = formatter.string(from: date)
                        let updater = viewModel.lastUpdatedBy ?? Language.get("PaymentMgmt_Value_SystemDefault", alter: "النظام")
                        Text(String(format: Language.get("PaymentMgmt_Settings_Footer_Metadata_Format", alter: "آخر تحديث: %@\nتم التحديث بواسطة: %@"), dateStr, updater))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    } else {
                        Text(Language.get("PaymentMgmt_Settings_Footer_Metadata", alter: "جارِ تحميل إعدادات الدفع الحالية..."))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Text(Language.get("PaymentMgmt_Settings_Audit_Backend", alter: "محرك التحديث: Cloud Function (updateCommercePaymentSettings)"))
                        .font(.system(size: 11))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.8))

                    Text(Language.get("PaymentMgmt_Settings_Audit_Scope", alter: "نطاق الصلاحيات: مدير المدفوعات (CommerceConfig/payments)"))
                        .font(.system(size: 11))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.8))
                }
            }
            .padding(AdminSpacing.base)
        }
    }

    // MARK: - iPhone Floating Command Bar

    private var iPhoneFloatingCommandBar: some View {
        VStack(spacing: 0) {
            Divider().background(AdminSurface.hairline)

            HStack(spacing: AdminSpacing.md) {
                if viewModel.hasChanges {
                    Button {
                        viewModel.resetToOriginal()
                    } label: {
                        Text(Language.get("Cancel", alter: "إلغاء"))
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.secondaryText)
                            .frame(minHeight: AdminTouchTarget.comfortable)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    viewModel.save()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(
                            viewModel.hasChanges
                            ? String(format: Language.get("PaymentMgmt_Settings_Changes_Pending", alter: "%d تعديل بانتظار الحفظ"), viewModel.pendingChangesCount)
                            : Language.get("PaymentMgmt_Settings_Save", alter: "حفظ")
                        )
                        .font(AdminType.headlineBold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AdminTouchTarget.comfortable)
                    .background(
                        viewModel.hasChanges ? AdminSurface.primary : AdminSurface.primary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                    )
                    .foregroundColor(.white)
                    .shadow(color: viewModel.hasChanges ? AdminSurface.primary.opacity(0.30) : Color.clear, radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.hasChanges || viewModel.isSaving)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - iPad Action Console Card

    private var iPadActionConsoleCard: some View {
        AdminCard {
            VStack(spacing: AdminSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("CommandCenter_Actions", alter: "إجراءات التحكم"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                        if viewModel.hasChanges {
                            Text(String(format: Language.get("PaymentMgmt_Settings_Changes_Pending", alter: "%d تعديل بانتظار الحفظ"), viewModel.pendingChangesCount))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.amber)
                        } else {
                            Text(Language.get("TactilePad_Matched_Badge", alter: "متطابق مع الإعدادات السحابية"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.emerald)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: AdminSpacing.sm) {
                    if viewModel.hasChanges {
                        Button {
                            viewModel.resetToOriginal()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                Text(Language.get("PaymentMgmt_Settings_Revert", alter: "تراجع"))
                            }
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AdminTouchTarget.comfortable)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("z", modifiers: .command)
                    }

                    Button {
                        viewModel.save()
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            Text(Language.get("PaymentMgmt_Settings_Save_CTA", alter: "اعتماد وحفظ الإعدادات"))
                                .font(AdminType.headlineBold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AdminTouchTarget.comfortable)
                        .background(
                            viewModel.hasChanges ? AdminSurface.primary : AdminSurface.primary.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                        )
                        .foregroundColor(.white)
                        .shadow(color: viewModel.hasChanges ? AdminSurface.primary.opacity(0.28) : Color.clear, radius: 8, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.hasChanges || viewModel.isSaving)
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
            .padding(AdminSpacing.base)
        }
    }
}

// MARK: - Hosting Controllers

@objc public final class PaymentSettingsHostingController: UIViewController {
    private var host: UIViewController?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all
        let root = AdminPaymentSettingsView(session: AdminSession(source: PPAdminSessionSnapshot()))
        let h = UIHostingController(rootView: root.ignoresSafeArea())
        h.view.backgroundColor = .clear
        h.extendedLayoutIncludesOpaqueBars = true
        h.edgesForExtendedLayout = .all
        addChild(h)
        view.addSubview(h.view)
        h.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            h.view.topAnchor.constraint(equalTo: view.topAnchor),
            h.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            h.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            h.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        h.didMove(toParent: self)
        host = h
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

