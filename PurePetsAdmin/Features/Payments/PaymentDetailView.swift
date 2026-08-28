import SwiftUI

// MARK: - Admin Payment Detail View

/// Native status dossier for one live order. Routing, authorization, data loading,
/// and mutations remain owned by the existing Admin route and payment services.
struct AdminPaymentDetailView: View {
    let orderID: String
    let session: AdminSession?
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PaymentDetailViewModel

    init(orderID: String, session: AdminSession? = nil, onDismiss: (() -> Void)? = nil) {
        self.orderID = orderID
        self.session = session
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: PaymentDetailViewModel(orderID: orderID))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AdminSurface.background,
                    AdminSurface.primarySoft.opacity(0.16),
                    AdminSurface.background,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeader
                detailContent
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .navigationBarHidden(true)
        .onAppear {
            if viewModel.record == nil, !viewModel.isLoading {
                viewModel.loadData()
            }
        }
    }

    // MARK: - Screen States

    @ViewBuilder
    private var detailContent: some View {
        if let record = viewModel.record {
            orderContent(record)
        } else if viewModel.isLoading {
            loadingState
        } else {
            errorState(
                message: viewModel.errorMessage
                    ?? Language.get("PaymentMgmt_Error_UpdateOrder", alter: "")
            )
        }
    }

    private var loadingState: some View {
        VStack(spacing: AdminSpacing.base) {
            ProgressView()
                .scaleEffect(1.12)
                .tint(AdminSurface.primary)
            Text(Language.get("PaymentMgmt_Loading_PaymentDetails", alter: ""))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
            Text(Language.get("PaymentDetail_Loading_Source", alter: ""))
                .font(AdminType.subheadline)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AdminSpacing.xl)
        .accessibilityElement(children: .combine)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: AdminSpacing.base) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: AdminIconSize.xl, weight: .semibold))
                .foregroundColor(Color(UIColor.ppError))
                .accessibilityHidden(true)
            Text(Language.get("Error", alter: ""))
                .font(AdminType.title3)
                .foregroundColor(AdminSurface.primaryText)
            Text(message)
                .font(AdminType.body)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                viewModel.loadData()
            } label: {
                Label(Language.get("Retry", alter: ""), systemImage: "arrow.clockwise")
                    .font(AdminType.calloutBold)
                    .frame(minWidth: 132, minHeight: AdminTouchTarget.comfortable)
            }
            .buttonStyle(.borderedProminent)
            .tint(AdminSurface.primary)
            .clipShape(Capsule())
            .padding(.top, AdminSpacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AdminSpacing.xl)
    }

    // MARK: - Dossier Header

    private var dossierHeader: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack(spacing: AdminSpacing.md) {
                Button(action: closeScreen) {
                    HStack(spacing: 6) {
                        Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(Language.get("Back", alter: ""))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .frame(minHeight: AdminTouchTarget.minimum)
                }
                .buttonStyle(.plain)

                Spacer(minLength: AdminSpacing.base)

                Button {
                    viewModel.loadData()
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.10))
                            .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                        if viewModel.isBusy {
                            ProgressView().tint(AdminSurface.primary)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AdminSurface.primary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isBusy)
                .accessibilityLabel(Language.get("PaymentDetail_Refresh", alter: ""))
                .accessibilityHint(Language.get("PaymentDetail_Refresh_Hint", alter: ""))
            }

            Text(
                Language.get("PaymentMgmt_Title_List", alter: "")
                    + " / "
                    + Language.get("PaymentMgmt_Title_Details", alter: "")
            )
            .font(AdminType.caption1)
            .foregroundColor(AdminSurface.secondaryText)

            Text(Language.get("PaymentMgmt_Title_Details", alter: ""))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
        .padding(.bottom, AdminSpacing.sm)
        .background(AdminSurface.background.opacity(0.96))
    }

    private func closeScreen() {
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    // MARK: - Live Order Content

    private func orderContent(_ record: PPPaymentAdminRecord) -> some View {
        ScrollView {
            LazyVStack(spacing: AdminSpacing.base) {
                briefingSection(record)

                if viewModel.isPerformingAction || viewModel.officialActionInFlight {
                    PaymentDetailFeedbackBanner(
                        message: Language.get("PaymentMgmt_Loading_OrderUpdate", alter: ""),
                        tint: AdminSurface.primary,
                        symbol: "arrow.triangle.2.circlepath",
                        showsProgress: true
                    )
                } else if viewModel.isLoading {
                    PaymentDetailFeedbackBanner(
                        message: Language.get("PaymentMgmt_Loading_PaymentDetails", alter: ""),
                        tint: AdminSurface.primary,
                        symbol: "arrow.clockwise",
                        showsProgress: true
                    )
                } else if let error = viewModel.errorMessage {
                    PaymentDetailFeedbackBanner(
                        message: error,
                        tint: Color(UIColor.ppError),
                        symbol: "exclamationmark.triangle.fill",
                        actionTitle: Language.get("Retry", alter: ""),
                        action: { viewModel.loadData() }
                    )
                } else if let success = viewModel.lastSuccessMessage {
                    PaymentDetailFeedbackBanner(
                        message: success,
                        tint: Color(UIColor.ppSuccess),
                        symbol: "checkmark.circle.fill"
                    )
                }

                actionsSection(record)
                overviewSection(record)
                customerSection(record)
                paymentSection(record)
                itemsSection(record)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, AdminSpacing.sm)
            .padding(.bottom, AdminSpacing.xxl)
        }
        .refreshable { viewModel.loadData() }
    }

    // MARK: - Decision Briefing

    private func briefingSection(_ record: PPPaymentAdminRecord) -> some View {
        let status = statusPresentation(for: record)
        let decision = nextDecision(for: record)
        let reference = record.displayOrderReference() as String? ?? orderID

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .fill(AdminSurface.control)
            Capsule()
                .fill(status.tint)
                .frame(width: AdminSpacing.xs)
                .padding(.vertical, AdminSpacing.md)

            VStack(alignment: .leading, spacing: AdminSpacing.md) {
                HStack(alignment: .center, spacing: AdminSpacing.md) {
                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(status.tint)
                        .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                        .background(
                            status.tint.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                        Text(Language.get("PaymentDetail_Context", alter: ""))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text("#\(reference)")
                        .font(AdminType.title2)
                        .foregroundColor(AdminSurface.primaryText)
                        .textSelection(.enabled)
                        .environment(\.layoutDirection, .leftToRight)
                        Text(paymentMethodTitle(record))
                            .font(AdminType.subheadline)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    Spacer(minLength: AdminSpacing.sm)
                }

                HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.sm) {
                    Text(status.title)
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(status.tint)
                    Spacer(minLength: AdminSpacing.sm)
                    Text(formatCurrency(record.totalAmount, currency: record.currency as String?))
                        .font(AdminType.title3)
                        .foregroundColor(AdminSurface.primaryText)
                        .monospacedDigit()
                        .environment(\.layoutDirection, .leftToRight)
                }
                .padding(.horizontal, AdminSpacing.md)
                .frame(minHeight: AdminTouchTarget.minimum)
                .background(
                    status.tint.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(labelValueAccessibility(
                    label: Language.get("PaymentMgmt_Field_Status", alter: ""),
                    value: status.title
                ))

                Divider().background(AdminSurface.hairline)

                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    Text(Language.get("PaymentDetail_NextAction", alter: ""))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                    HStack(alignment: .top, spacing: AdminSpacing.sm) {
                        Image(systemName: decision.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(decision.tint)
                            .padding(.top, 3)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                            Text(decision.title)
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)
                            Text(decision.subtitle)
                                .font(AdminType.subheadline)
                                .foregroundColor(AdminSurface.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.vertical, AdminSpacing.md)
            .padding(.leading, AdminSpacing.lg)
            .padding(.trailing, AdminSpacing.md)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin)
        }
        .accessibilityElement(children: .contain)
    }

    private func statusPresentation(for record: PPPaymentAdminRecord) -> PaymentDetailStatusPresentation {
        let rawStatus = record.rawStatus as String? ?? ""
        let title = PPPaymentAdminDisplayTitleForOrderStatus(rawStatus)
        if PPPaymentAdminRecord.isFailureLikeStatus(rawStatus)
            || PPPaymentAdminRecord.isCancelledLikeStatus(rawStatus) {
            return .init(title: title, tint: Color(UIColor.ppError))
        }
        if PPPaymentAdminRecord.isDeliveredLikeStatus(rawStatus)
            || PPPaymentAdminRecord.isPaidLikeStatus(rawStatus) {
            return .init(title: title, tint: Color(UIColor.ppSuccess))
        }
        if PPPaymentAdminRecord.isShippedLikeStatus(rawStatus) {
            return .init(title: title, tint: Color(UIColor.ppQuickActionCommunity))
        }
        if PPPaymentAdminRecord.isProcessingLikeStatus(rawStatus) {
            return .init(title: title, tint: Color(UIColor.ppInfo))
        }
        if PPPaymentAdminRecord.canApproveOrderStatus(rawStatus) {
            return .init(title: title, tint: Color(UIColor.ppWarning))
        }
        return .init(title: title, tint: AdminSurface.primary)
    }

    private func nextDecision(for record: PPPaymentAdminRecord) -> PaymentDetailDecision {
        guard canManagePayments else {
            return .init(
                title: Language.get("PaymentDetail_ReadOnly_Title", alter: ""),
                subtitle: Language.get("PaymentDetail_ReadOnly_Subtitle", alter: ""),
                symbol: "lock.shield.fill",
                tint: Color(UIColor.ppWarning)
            )
        }
        if record.fulfillmentVersion == 1 {
            if viewModel.officialFulfillmentLoading {
                return .init(
                    title: Language.get("PaymentMgmt_OfficialFulfillment_Loading", alter: ""),
                    subtitle: Language.get("PaymentDetail_Loading_Source", alter: ""),
                    symbol: "arrow.triangle.2.circlepath",
                    tint: AdminSurface.primary
                )
            }
            if let error = viewModel.officialFulfillmentError {
                return .init(
                    title: Language.get("PaymentMgmt_OfficialFulfillment_NotManageable", alter: ""),
                    subtitle: error,
                    symbol: "exclamationmark.triangle.fill",
                    tint: Color(UIColor.ppError)
                )
            }
            if let first = viewModel.officialActions.first {
                return .init(
                    title: officialActionTitle(first),
                    subtitle: Language.get("PaymentMgmt_OfficialFulfillment_Action_Subtitle", alter: ""),
                    symbol: officialActionSymbol(first),
                    tint: officialActionColor(first)
                )
            }
        } else {
            let actions = legacyActions(for: record)
            if let first = actions.first(where: { !$0.isDestructive }) ?? actions.first {
                return .init(
                    title: first.title,
                    subtitle: first.subtitle,
                    symbol: first.symbol,
                    tint: first.tint
                )
            }
        }
        return .init(
            title: Language.get("PaymentDetail_NoAction_Title", alter: ""),
            subtitle: Language.get("PaymentDetail_NoAction_Subtitle", alter: ""),
            symbol: "checkmark.seal.fill",
            tint: Color(UIColor.ppSuccess)
        )
    }

    // MARK: - Actions

    private func actionsSection(_ record: PPPaymentAdminRecord) -> some View {
        PaymentDetailSection(
            title: record.fulfillmentVersion == 1
                ? Language.get("PaymentMgmt_OfficialFulfillment_Title", alter: "")
                : Language.get("PaymentMgmt_Section_AdminActions", alter: ""),
            symbol: record.fulfillmentVersion == 1
                ? "shippingbox.and.arrow.backward"
                : "bolt.shield.fill"
        ) {
            if !canManagePayments {
                PaymentDetailInlineState(
                    title: Language.get("PaymentDetail_ReadOnly_Title", alter: ""),
                    subtitle: Language.get("PaymentDetail_ReadOnly_Subtitle", alter: ""),
                    symbol: "lock.shield.fill",
                    tint: Color(UIColor.ppWarning)
                )
            } else if record.fulfillmentVersion == 1 {
                officialActionsContent
            } else {
                legacyActionsContent(record)
            }
        }
    }

    @ViewBuilder
    private var officialActionsContent: some View {
        if viewModel.officialFulfillmentLoading {
            HStack(spacing: AdminSpacing.sm) {
                ProgressView().tint(AdminSurface.primary)
                Text(Language.get("PaymentMgmt_OfficialFulfillment_Loading", alter: ""))
                    .font(AdminType.subheadline)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable, alignment: .center)
        } else if let error = viewModel.officialFulfillmentError {
            PaymentDetailInlineState(
                title: Language.get("PaymentMgmt_OfficialFulfillment_NotManageable", alter: ""),
                subtitle: error,
                symbol: "exclamationmark.triangle.fill",
                tint: Color(UIColor.ppError),
                actionTitle: Language.get("Retry", alter: ""),
                action: { viewModel.reloadOfficialFulfillment() }
            )
        } else if let fulfillment = viewModel.officialFulfillment {
            PaymentDetailFieldRow(
                label: Language.get("PaymentMgmt_Field_OrderStatus", alter: ""),
                value: PPPaymentAdminDisplayTitleForOrderStatus(fulfillment.status)
            )
            if !viewModel.officialActions.isEmpty {
                Divider().background(AdminSurface.hairline)
            }
            ForEach(Array(viewModel.officialActions.enumerated()), id: \.element) { index, action in
                PaymentDetailActionButton(
                    title: officialActionTitle(action),
                    subtitle: Language.get("PaymentMgmt_OfficialFulfillment_Action_Subtitle", alter: ""),
                    symbol: officialActionSymbol(action),
                    tint: officialActionColor(action),
                    isPrimary: index == 0,
                    isBusy: viewModel.isBusy
                ) { requestOfficialAction(action) }
            }
        } else {
            PaymentDetailInlineState(
                title: Language.get("PaymentDetail_NoAction_Title", alter: ""),
                subtitle: Language.get("PaymentMgmt_OfficialFulfillment_None", alter: ""),
                symbol: "checkmark.seal.fill",
                tint: Color(UIColor.ppSuccess)
            )
        }
    }

    @ViewBuilder
    private func legacyActionsContent(_ record: PPPaymentAdminRecord) -> some View {
        let actions = legacyActions(for: record)
        if actions.isEmpty {
            PaymentDetailInlineState(
                title: Language.get("PaymentDetail_NoAction_Title", alter: ""),
                subtitle: Language.get("PaymentDetail_NoAction_Subtitle", alter: ""),
                symbol: "checkmark.seal.fill",
                tint: Color(UIColor.ppSuccess)
            )
        } else {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                PaymentDetailActionButton(
                    title: action.title,
                    subtitle: action.subtitle,
                    symbol: action.symbol,
                    tint: action.tint,
                    isPrimary: index == 0 && !action.isDestructive,
                    isBusy: viewModel.isBusy
                ) { requestLegacyAction(action) }
            }
        }
    }

    private func legacyActions(for record: PPPaymentAdminRecord) -> [PaymentDetailLegacyAction] {
        var actions: [PaymentDetailLegacyAction] = []
        let rawStatus = record.rawStatus as String? ?? ""
        let paymentMethod = PPPaymentAdminRecord.normalizedStatusString(record.paymentMethodId as String?)
        if PPPaymentAdminRecord.canApproveOrderStatus(rawStatus), paymentMethod != "cash" {
            actions.append(.approve)
        }
        if PPPaymentAdminRecord.canMarkOrderProcessing(forOrder: record) {
            actions.append(.processing)
        }
        if PPPaymentAdminRecord.canMarkOrderShippedStatus(rawStatus) {
            actions.append(.shipped)
        }
        if PPPaymentAdminRecord.canMarkOrderDeliveredStatus(rawStatus) {
            actions.append(.delivered)
        }
        if PPPaymentAdminRecord.canCollectCashPayment(forOrder: record) {
            actions.append(.collectPayment)
        }
        if PPPaymentAdminRecord.canCancelOrderStatus(rawStatus) {
            actions.append(.cancel)
        }
        return actions
    }

    private var canManagePayments: Bool {
        session?.hasPermission("payments.manage") == true
    }

    private func requestLegacyAction(_ action: PaymentDetailLegacyAction) {
        presentActionPrompt(
            title: action.title,
            confirmation: action.confirmation,
            prompt: action.prompt,
            defaultNote: viewModel.defaultNote(for: action.callableAction)
        ) { note in viewModel.perform(action, note: note) }
    }

    private func requestOfficialAction(_ action: String) {
        let title = officialActionTitle(action)
        presentActionPrompt(
            title: title,
            confirmation: Language.get("PaymentMgmt_OfficialFulfillment_Confirm", alter: ""),
            prompt: Language.get("PaymentMgmt_OfficialFulfillment_Prompt", alter: ""),
            defaultNote: String(
                format: Language.get("PaymentMgmt_OfficialFulfillment_DefaultNote", alter: ""),
                title
            )
        ) { note in viewModel.transitionOfficialFulfillment(action: action, note: note) }
    }

    private func presentActionPrompt(
        title: String,
        confirmation: String,
        prompt: String,
        defaultNote: String,
        action: @escaping (String) -> Void
    ) {
        let subtitle = String(
            format: Language.get("PaymentDetail_ActionPrompt_Format", alter: ""),
            confirmation,
            prompt
        )
        PPAlertHelper.showTextPrompt(
            in: nil,
            title: title,
            subtitle: subtitle,
            placeholder: Language.get("PaymentMgmt_Value_AdminNote", alter: ""),
            initialText: nil,
            confirmText: Language.get("Confirm", alter: ""),
            cancelText: Language.get("Cancel", alter: ""),
            secureEntry: false,
            keyboardType: .default
        ) { text in
            guard let text else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.count < 3 {
                viewModel.showValidationError(
                    Language.get("PaymentMgmt_Prompt_NoteRequired_Subtitle", alter: "")
                )
                return
            }
            let resolvedNote = trimmed.isEmpty ? defaultNote : trimmed
            guard resolvedNote.count >= 3 else {
                viewModel.showValidationError(
                    Language.get("PaymentMgmt_Error_AdminNoteRequired", alter: "")
                )
                return
            }
            action(resolvedNote)
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

    private func officialActionSymbol(_ action: String) -> String {
        switch action {
        case "accept": return "checkmark.circle.fill"
        case "reject": return "xmark.circle.fill"
        case "start_preparing": return "shippingbox.fill"
        case "mark_ready": return "checkmark.seal.fill"
        case "request_delivery": return "truck.box.fill"
        case "confirm_handover": return "person.crop.circle.badge.checkmark"
        case "cancel_request": return "xmark.octagon.fill"
        default: return "arrow.right.circle.fill"
        }
    }

    // MARK: - Information Sections

    private func overviewSection(_ record: PPPaymentAdminRecord) -> some View {
        PaymentDetailSection(
            title: Language.get("PaymentMgmt_Section_Overview", alter: ""),
            symbol: "doc.text.fill"
        ) {
            PaymentDetailFieldRow(
                label: Language.get("PaymentMgmt_Field_OrderStatus", alter: ""),
                value: PPPaymentAdminDisplayTitleForOrderStatus(record.rawStatus as String? ?? "")
            )
            Divider().background(AdminSurface.hairline)
            PaymentDetailFieldRow(
                label: Language.get("PaymentMgmt_Field_OrderReference", alter: ""),
                value: record.displayOrderReference() as String? ?? orderID,
                technical: true
            )
            Divider().background(AdminSurface.hairline)
            PaymentDetailFieldRow(
                label: Language.get("PaymentMgmt_Field_Created", alter: ""),
                value: formatDate(record.createdAt as Date?),
                technical: true
            )
            Divider().background(AdminSurface.hairline)
            PaymentDetailFieldRow(
                label: Language.get("PaymentMgmt_Field_Updated", alter: ""),
                value: formatDate(record.updatedAt as Date?),
                technical: true
            )
        }
    }

    private func customerSection(_ record: PPPaymentAdminRecord) -> some View {
        PaymentDetailSection(
            title: Language.get("PaymentMgmt_Field_Customer", alter: ""),
            symbol: "person.crop.circle.fill"
        ) {
            PaymentDetailFieldRow(
                label: Language.get("PaymentDetail_Field_Name", alter: ""),
                value: valueOrUnavailable(record.userDisplayName as String?)
            )
            Divider().background(AdminSurface.hairline)
            PaymentDetailFieldRow(
                label: Language.get("PaymentMgmt_Field_Email", alter: ""),
                value: valueOrUnavailable(record.userEmail as String?),
                technical: true
            )
        }
    }

    private func paymentSection(_ record: PPPaymentAdminRecord) -> some View {
        PaymentDetailSection(
            title: Language.get("PaymentMgmt_Section_Payments", alter: ""),
            symbol: "creditcard.fill"
        ) {
            PaymentDetailFieldRow(
                label: Language.get("PaymentMgmt_Field_Total", alter: ""),
                value: formatCurrency(record.totalAmount, currency: record.currency as String?),
                technical: true,
                emphasized: true
            )
            Divider().background(AdminSurface.hairline)
            PaymentDetailFieldRow(
                label: Language.get("PaymentMgmt_Field_PaymentMethod", alter: ""),
                value: paymentMethodTitle(record)
            )
            if !(record.paymentStatus as String? ?? "").isEmpty {
                Divider().background(AdminSurface.hairline)
                PaymentDetailFieldRow(
                    label: Language.get("PaymentMgmt_Field_PaymentStatus", alter: ""),
                    value: PPPaymentAdminDisplayTitleForOrderStatus(record.paymentStatus)
                )
            }
            if !(record.verificationStatus as String? ?? "").isEmpty {
                Divider().background(AdminSurface.hairline)
                PaymentDetailFieldRow(
                    label: Language.get("PaymentMgmt_Field_Verification", alter: ""),
                    value: PPPaymentAdminDisplayTitleForVerificationStatus(record.verificationStatus)
                )
            }
            if !(record.transactionId as String? ?? "").isEmpty {
                Divider().background(AdminSurface.hairline)
                PaymentDetailFieldRow(
                    label: Language.get("PaymentMgmt_Field_Transaction", alter: ""),
                    value: record.transactionId,
                    technical: true
                )
            }
        }
    }

    private func itemsSection(_ record: PPPaymentAdminRecord) -> some View {
        let items = record.items as? [[String: Any]] ?? []
        return PaymentDetailSection(
            title: Language.get("PaymentMgmt_Section_Items", alter: ""),
            symbol: "bag.fill"
        ) {
            if items.isEmpty {
                PaymentDetailInlineState(
                    title: Language.get("PaymentMgmt_Placeholder_NoItemsTitle", alter: ""),
                    subtitle: Language.get("PaymentMgmt_Placeholder_NoItemsSubtitle", alter: ""),
                    symbol: "bag.badge.minus",
                    tint: AdminSurface.secondaryText
                )
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    PaymentDetailItemRow(
                        name: valueOrUnavailable(item["name"] as? String),
                        quantity: quantityText(item["quantity"])
                    )
                    if index < items.count - 1 {
                        Divider().background(AdminSurface.hairline)
                    }
                }
            }
        }
    }

    // MARK: - Formatting

    private func valueOrUnavailable(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty
            ? Language.get("PaymentMgmt_Value_NotAvailable", alter: "")
            : trimmed
    }

    private func paymentMethodTitle(_ record: PPPaymentAdminRecord) -> String {
        let candidates = [
            record.paymentProvider as String?,
            record.paymentMethodId as String?,
            record.paymentTypeKey as String?,
        ]
        for candidate in candidates {
            let method = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !method.isEmpty {
                return PPPaymentAdminDisplayTitleForPaymentMethod(method)
            }
        }
        return Language.get("PaymentMgmt_Value_NotAvailable", alter: "")
    }

    private func quantityText(_ value: Any?) -> String {
        if let number = value as? NSNumber {
            return NumberFormatter.localizedString(from: number, number: .decimal)
        }
        if let string = value as? String,
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return string
        }
        return Language.get("PaymentMgmt_Value_NotAvailable", alter: "")
    }

    private func formatCurrency(_ value: Double, currency: String?) -> String {
        let currencyCode = currency?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedCode = currencyCode.isEmpty ? "QAR" : currencyCode
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .currency
        formatter.currencyCode = resolvedCode
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.2f %@", value, resolvedCode == "QAR" ? Language.get("QAR", alter: "ر.ق") : resolvedCode)
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else {
            return Language.get("PaymentMgmt_Value_NotAvailable", alter: "")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(
            identifier: Language.currentLanguageCode() == "ar" ? "ar" : "en"
        )
        return formatter.string(from: date)
    }

    private func labelValueAccessibility(label: String, value: String) -> String {
        String(
            format: Language.get("PaymentDetail_LabelValue_Accessibility_Format", alter: ""),
            label,
            value
        )
    }
}

// MARK: - Presentation Models

private struct PaymentDetailStatusPresentation {
    let title: String
    let tint: Color
}

private struct PaymentDetailDecision {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
}

fileprivate enum PaymentDetailLegacyAction: String, Identifiable {
    case approve
    case processing
    case shipped
    case delivered
    case collectPayment
    case cancel

    var id: String { rawValue }

    var callableAction: String {
        switch self {
        case .approve: return "order_approve"
        case .processing: return "order_mark_processing"
        case .shipped: return "order_mark_shipped"
        case .delivered: return "order_mark_delivered"
        case .collectPayment: return "order_collect_payment"
        case .cancel: return "order_cancel"
        }
    }

    var title: String { Language.get(titleKey, alter: "") }
    var subtitle: String { Language.get(subtitleKey, alter: "") }
    var prompt: String { Language.get(promptKey, alter: "") }
    var confirmation: String { Language.get(confirmationKey, alter: "") }
    var successMessage: String { Language.get(successKey, alter: "") }

    var symbol: String {
        switch self {
        case .approve: return "checkmark.seal.fill"
        case .processing: return "arrow.triangle.2.circlepath"
        case .shipped: return "shippingbox.fill"
        case .delivered: return "checkmark.circle.fill"
        case .collectPayment: return "banknote.fill"
        case .cancel: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .approve, .delivered, .collectPayment: return Color(UIColor.ppSuccess)
        case .processing: return Color(UIColor.ppInfo)
        case .shipped: return Color(UIColor.ppQuickActionCommunity)
        case .cancel: return Color(UIColor.ppError)
        }
    }

    var isDestructive: Bool { self == .cancel }

    private var titleKey: String {
        switch self {
        case .approve: return "PaymentMgmt_Action_ApprovePayment_Title"
        case .processing: return "PaymentMgmt_Action_MarkProcessing_Title"
        case .shipped: return "PaymentMgmt_Action_MarkShipped_Title"
        case .delivered: return "PaymentMgmt_Action_MarkDelivered_Title"
        case .collectPayment: return "PaymentMgmt_Action_CollectPayment_Title"
        case .cancel: return "PaymentMgmt_Action_CancelOrder_Title"
        }
    }

    private var subtitleKey: String {
        switch self {
        case .approve: return "PaymentMgmt_Action_ApprovePayment_Subtitle"
        case .processing: return "PaymentMgmt_Action_MarkProcessing_Subtitle"
        case .shipped: return "PaymentMgmt_Action_MarkShipped_Subtitle"
        case .delivered: return "PaymentMgmt_Action_MarkDelivered_Subtitle"
        case .collectPayment: return "PaymentMgmt_Action_CollectPayment_Subtitle"
        case .cancel: return "PaymentMgmt_Action_CancelOrder_Subtitle"
        }
    }

    private var promptKey: String {
        switch self {
        case .approve: return "PaymentMgmt_Prompt_OrderApproveNote"
        case .processing: return "PaymentMgmt_Prompt_OrderProcessingNote"
        case .shipped: return "PaymentMgmt_Prompt_OrderShippedNote"
        case .delivered: return "PaymentMgmt_Prompt_OrderDeliveredNote"
        case .collectPayment: return "PaymentMgmt_Prompt_OrderCollectPaymentNote"
        case .cancel: return "PaymentMgmt_Prompt_OrderCancelNote"
        }
    }

    private var confirmationKey: String {
        switch self {
        case .approve: return "PaymentMgmt_Confirm_OrderApprove"
        case .processing: return "PaymentMgmt_Confirm_OrderProcessing"
        case .shipped: return "PaymentMgmt_Confirm_OrderShipped"
        case .delivered: return "PaymentMgmt_Confirm_OrderDelivered"
        case .collectPayment: return "PaymentMgmt_Confirm_OrderCollectPayment"
        case .cancel: return "PaymentMgmt_Confirm_OrderCancel"
        }
    }

    private var successKey: String {
        switch self {
        case .approve: return "PaymentMgmt_Success_OrderApprove"
        case .processing: return "PaymentMgmt_Success_OrderProcessing"
        case .shipped: return "PaymentMgmt_Success_OrderShipped"
        case .delivered: return "PaymentMgmt_Success_OrderDelivered"
        case .collectPayment: return "PaymentMgmt_Success_OrderCollectPayment"
        case .cancel: return "PaymentMgmt_Success_OrderCancel"
        }
    }
}

// MARK: - Detail Components

private struct PaymentDetailSection<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: AdminIconSize.medium, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    .background(
                        AdminSurface.primary.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    )
                    .accessibilityHidden(true)
                Text(title)
                    .font(AdminType.title3)
                    .foregroundColor(AdminSurface.primaryText)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(AdminSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin)
        }
    }
}

private struct PaymentDetailFieldRow: View {
    let label: String
    let value: String
    var technical = false
    var emphasized = false

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            Text(label)
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)
            Text(value)
                .font(emphasized ? AdminType.title3 : AdminType.body)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.leading)
                .environment(
                    \.layoutDirection,
                    technical ? .leftToRight : (Language.isRTL() ? .rightToLeft : .leftToRight)
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: technical && Language.isRTL() ? .trailing : .leading
                )
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: Language.get("PaymentDetail_LabelValue_Accessibility_Format", alter: ""),
                label,
                value
            )
        )
    }
}

private struct PaymentDetailItemRow: View {
    let name: String
    let quantity: String

    var body: some View {
        HStack(alignment: .top, spacing: AdminSpacing.md) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 36, height: 36)
                .background(
                    AdminSurface.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                Text(name)
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    String(
                        format: Language.get("PaymentDetail_Quantity_Format", alter: ""),
                        quantity
                    )
                )
                .font(AdminType.subheadline)
                .foregroundColor(AdminSurface.secondaryText)
                .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PaymentDetailActionButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let isPrimary: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AdminSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isPrimary ? .white : tint)
                    .frame(width: 36, height: 36)
                    .background(
                        isPrimary ? Color.white.opacity(0.16) : tint.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundColor(isPrimary ? .white : AdminSurface.primaryText)
                    Text(subtitle)
                        .font(AdminType.caption1)
                        .foregroundColor(isPrimary ? Color.white.opacity(0.84) : AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AdminSpacing.sm)
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isPrimary ? Color.white.opacity(0.84) : tint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, AdminSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.expanded, alignment: .leading)
            .background(
                isPrimary ? tint : tint.opacity(0.055),
                in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                    .stroke(isPrimary ? Color.clear : tint.opacity(0.26), lineWidth: AdminStroke.thin)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? AdminOpacity.disabled : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }
}

private struct PaymentDetailFeedbackBanner: View {
    let message: String
    let tint: Color
    let symbol: String
    var showsProgress = false
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: AdminSpacing.sm) {
            if showsProgress {
                ProgressView().tint(tint)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tint)
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(AdminType.subheadline)
                .foregroundColor(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AdminSpacing.sm)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(AdminType.captionBold)
                    .foregroundColor(tint)
                    .frame(minHeight: AdminTouchTarget.minimum)
            }
        }
        .padding(.horizontal, AdminSpacing.md)
        .padding(.vertical, AdminSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable, alignment: .leading)
        .background(
            tint.opacity(0.08),
            in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: AdminStroke.thin)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PaymentDetailInlineState: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AdminSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: AdminIconSize.large, weight: .semibold))
                .foregroundColor(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(AdminType.subheadline)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(AdminType.calloutBold)
                    .foregroundColor(tint)
                    .frame(minHeight: AdminTouchTarget.minimum)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AdminSpacing.md)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - View Model

@MainActor
final class PaymentDetailViewModel: ObservableObject {
    let orderID: String

    @Published var record: PPPaymentAdminRecord?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?
    @Published var lastSuccessMessage: String?
    @Published var officialFulfillment: PPFulfillmentRecord?
    @Published var officialFulfillmentLoading = false
    @Published var officialFulfillmentError: String?
    @Published var officialActionInFlight = false

    private var pendingSuccessMessage: String?

    var officialActions: [String] {
        guard let officialFulfillment else { return [] }
        return PPFulfillmentService.availableOfficialActions(forStatus: officialFulfillment.status)
    }

    var isBusy: Bool {
        isLoading || isPerformingAction || officialActionInFlight || officialFulfillmentLoading
    }

    init(orderID: String) {
        self.orderID = orderID
    }

    fileprivate func defaultNote(for action: String) -> String {
        PPPaymentManagementService.shared().defaultAdminNote(
            forOrderID: orderID,
            action: action
        )
    }

    fileprivate func perform(_ action: PaymentDetailLegacyAction, note: String) {
        performAction(successMessage: action.successMessage) { service, record, completion in
            switch action {
            case .approve: service.approveOrder(record, note: note, completion: completion)
            case .processing: service.markOrderProcessing(record, note: note, completion: completion)
            case .shipped: service.markOrderShipped(record, note: note, completion: completion)
            case .delivered: service.markOrderDelivered(record, note: note, completion: completion)
            case .collectPayment: service.collectOrderPayment(record, note: note, completion: completion)
            case .cancel: service.cancelOrder(record, note: note, completion: completion)
            }
        }
    }

    func showValidationError(_ message: String) {
        errorMessage = message
        lastSuccessMessage = nil
    }

    func loadData() {
        guard !isBusy else { return }
        isLoading = true
        errorMessage = nil
        PPPaymentManagementService.shared().loadFullRecord(forOrderID: orderID) { [weak self] record, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let record else {
                    self.errorMessage = Language.get("PaymentMgmt_Error_UpdateOrder", alter: "")
                    return
                }
                self.record = record
                if let pendingSuccessMessage = self.pendingSuccessMessage {
                    self.lastSuccessMessage = pendingSuccessMessage
                    self.pendingSuccessMessage = nil
                }
                self.loadOfficialFulfillment(for: record)
            }
        }
    }

    func reloadOfficialFulfillment() {
        guard let record, !isBusy, !officialFulfillmentLoading else { return }
        loadOfficialFulfillment(for: record)
    }

    private func performAction(
        successMessage: String,
        action: @escaping (
            PPPaymentManagementService,
            PPPaymentAdminRecord,
            @escaping (PPPaymentAdminRecord?, Error?) -> Void
        ) -> Void
    ) {
        guard let record, !isBusy else { return }
        isPerformingAction = true
        errorMessage = nil
        lastSuccessMessage = nil
        action(PPPaymentManagementService.shared(), record) { [weak self] updatedRecord, error in
            Task { @MainActor in
                guard let self else { return }
                self.isPerformingAction = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let updatedRecord else {
                    self.errorMessage = Language.get("PaymentMgmt_Error_UpdateOrder", alter: "")
                    return
                }
                self.record = updatedRecord
                self.lastSuccessMessage = successMessage
                self.loadOfficialFulfillment(for: updatedRecord)
            }
        }
    }

    private func loadOfficialFulfillment(for record: PPPaymentAdminRecord) {
        officialFulfillmentError = nil
        guard record.fulfillmentVersion == 1 else {
            officialFulfillment = nil
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
                if let error {
                    self.officialFulfillmentError = error.localizedDescription
                    return
                }
                self.officialFulfillment = fulfillment
            }
        }
    }

    func transitionOfficialFulfillment(action: String, note: String) {
        guard let fulfillment = officialFulfillment, !isBusy else { return }
        let safeNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard safeNote.count >= 3 else {
            officialFulfillmentError = Language.get(
                "PaymentMgmt_Prompt_NoteRequired_Subtitle",
                alter: ""
            )
            return
        }
        officialActionInFlight = true
        officialFulfillmentError = nil
        errorMessage = nil
        lastSuccessMessage = nil
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
                    return
                }
                self.pendingSuccessMessage = Language.get(
                    "PaymentMgmt_OfficialFulfillment_Success",
                    alter: ""
                )
                self.loadData()
            }
        }
    }
}
