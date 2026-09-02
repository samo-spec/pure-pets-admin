import SwiftUI

// MARK: - Admin Payment Detail View (NextGen V6 Reimagined)

/// Flagship native dossier for order management, payment settlement, customer profile,
/// and live operational commands in PurePets Admin.
struct AdminPaymentDetailView: View {
    let orderID: String
    let session: AdminSession?
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PaymentDetailViewModel
    @State private var copiedToastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    init(orderID: String, session: AdminSession? = nil, onDismiss: (() -> Void)? = nil) {
        self.orderID = orderID
        self.session = session
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: PaymentDetailViewModel(orderID: orderID))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Ambient Atmospheric Background
            LinearGradient(
                colors: [
                    AdminSurface.background,
                    AdminSurface.primarySoft.opacity(0.14),
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

            // Floating Copy Notification Toast
            if let message = copiedToastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(UIColor.ppSuccess))
                        Text(message)
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.85), in: Capsule(style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, AdminSpacing.xl)
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: copiedToastMessage)
                .zIndex(100)
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
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.10))
                    .frame(width: 64, height: 64)
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(AdminSurface.primary)
            }
            Text(Language.get("PaymentMgmt_Loading_PaymentDetails", alter: "جارٍ تحميل تفاصيل الطلب..."))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
            Text(Language.get("PaymentDetail_Loading_Source", alter: "مزامنة السجلات المباشرة مع الخادم"))
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
            ZStack {
                Circle()
                    .fill(Color(UIColor.ppError).opacity(0.12))
                    .frame(width: 68, height: 68)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color(UIColor.ppError))
                    .accessibilityHidden(true)
            }
            Text(Language.get("Error", alter: "حدث خطأ"))
                .font(AdminType.title3)
                .foregroundColor(AdminSurface.primaryText)
            Text(message)
                .font(AdminType.body)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                viewModel.loadData()
            } label: {
                Label(Language.get("Retry", alter: "إعادة المحاولة"), systemImage: "arrow.clockwise")
                    .font(AdminType.calloutBold)
                    .frame(minWidth: 140, minHeight: AdminTouchTarget.comfortable)
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
        HStack(spacing: AdminSpacing.md) {
            // Tactile Back Button
            Button(action: closeScreen) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 44, height: 44)
                    .background(AdminSurface.surface, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 1.0))
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
            }
            .buttonStyle(NextGenScaleButtonStyle())
            .accessibilityLabel(Language.get("Back", alter: "رجوع"))

            // Title & Scope
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("PaymentMgmt_Title_Details", alter: "ملف الطلب والمدفوعات"))
                    .font(AdminType.title3)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(UIColor.ppSuccess))
                        .frame(width: 6, height: 6)
                    Text(Language.get("PaymentDetail_LiveFeed", alter: "بث تشغيلي مباشر"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }

            Spacer(minLength: 0)

            // Refresh Action
            Button {
                triggerHaptic()
                viewModel.loadData()
            } label: {
                ZStack {
                    Circle()
                        .fill(AdminSurface.surface)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 1.0))
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                    if viewModel.isBusy {
                        ProgressView().tint(AdminSurface.primary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                    }
                }
            }
            .buttonStyle(NextGenScaleButtonStyle())
            .disabled(viewModel.isBusy)
            .accessibilityLabel(Language.get("PaymentDetail_Refresh", alter: "تحديث"))
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
        .padding(.bottom, AdminSpacing.sm)
        .background(AdminSurface.background.opacity(0.94))
    }

    private func closeScreen() {
        triggerHaptic()
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    // MARK: - Live Order Content

    private func orderContent(_ record: PPPaymentAdminRecord) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: AdminSpacing.base) {
                briefingSection(record)

                if viewModel.isPerformingAction || viewModel.officialActionInFlight {
                    PaymentDetailFeedbackBanner(
                        message: Language.get("PaymentMgmt_Loading_OrderUpdate", alter: "جارٍ تنفيذ العملية وتحديث السجل..."),
                        tint: AdminSurface.primary,
                        symbol: "arrow.triangle.2.circlepath",
                        showsProgress: true
                    )
                } else if viewModel.isLoading {
                    PaymentDetailFeedbackBanner(
                        message: Language.get("PaymentMgmt_Loading_PaymentDetails", alter: "جارٍ مزامنة تفاصيل الطلب..."),
                        tint: AdminSurface.primary,
                        symbol: "arrow.clockwise",
                        showsProgress: true
                    )
                } else if let error = viewModel.errorMessage {
                    PaymentDetailFeedbackBanner(
                        message: error,
                        tint: Color(UIColor.ppError),
                        symbol: "exclamationmark.triangle.fill",
                        actionTitle: Language.get("Retry", alter: "إعادة المحاولة"),
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
            .padding(.top, AdminSpacing.xs)
            .padding(.bottom, AdminSpacing.xxl + 20)
        }
        .refreshable { viewModel.loadData() }
    }

    // MARK: - 1. Executive Decision Apex (Crown Briefing Chamber)

    private func briefingSection(_ record: PPPaymentAdminRecord) -> some View {
        let status = statusPresentation(for: record)
        let decision = nextDecision(for: record)
        let reference = record.displayOrderReference() as String? ?? orderID

        return VStack(alignment: .leading, spacing: AdminSpacing.md) {
            // Top Row: Ref & Live Status Pill
            HStack(alignment: .center, spacing: AdminSpacing.sm) {
                // Order Reference Pill with Copy
                Button {
                    copyToClipboard(text: reference, label: Language.get("PaymentMgmt_Field_OrderReference", alter: "رقم الطلب"))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                        Text("#\(reference)")
                            .font(.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline))
                            .foregroundColor(AdminSurface.primaryText)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.primary.opacity(0.08), in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).stroke(AdminSurface.primary.opacity(0.20), lineWidth: 1.0))
                }
                .buttonStyle(NextGenScaleButtonStyle())

                Spacer(minLength: 0)

                // Live Status Radar Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(status.tint)
                        .frame(width: 8, height: 8)
                        .shadow(color: status.tint.opacity(0.6), radius: 3)
                    Text(status.title)
                        .font(AdminType.captionBold)
                        .foregroundColor(status.tint)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(status.tint.opacity(0.12), in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(status.tint.opacity(0.3), lineWidth: 1.0))
            }

            // Financial & Method Horizon
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("PaymentMgmt_Field_Total", alter: "المبلغ الإجمالي"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(formatCurrency(record.totalAmount, currency: record.currency as String?))
                        .font(.custom("Beiruti-Bold", size: 28, relativeTo: .largeTitle))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: AdminSpacing.sm)

                // Payment Method Badge
                HStack(spacing: 5) {
                    Image(systemName: paymentMethodIcon(record))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                    Text(paymentMethodTitle(record))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1.0))
            }

            // Next Authorized Operational Move
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(decision.tint)
                    Text(Language.get("PaymentDetail_NextAction", alter: "الإجراء التشغيلي الموصى به"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(decision.tint)
                }

                HStack(alignment: .center, spacing: AdminSpacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(decision.tint.opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: decision.symbol)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(decision.tint)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(decision.title)
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(decision.subtitle)
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(AdminSpacing.md)
            .background(decision.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(decision.tint.opacity(0.20), lineWidth: 1.0))
        }
        .padding(AdminSpacing.cardPadding)
        .background(
            ZStack {
                AdminSurface.surface
                RadialGradient(
                    colors: [status.tint.opacity(0.08), Color.clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 260
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1.0)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 4)
    }

    // MARK: - 2. Overview Section (Reimagined Bento Chrono Grid)

    private func overviewSection(_ record: PPPaymentAdminRecord) -> some View {
        let reference = record.displayOrderReference() as String? ?? orderID
        let statusTitle = PPPaymentAdminDisplayTitleForOrderStatus(record.rawStatus as String? ?? "")

        return PaymentDetailSection(
            title: Language.get("PaymentMgmt_Section_Overview", alter: "نظرة عامة والبيانات الزمنية"),
            symbol: "doc.text.fill"
        ) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                // Tile 1: Order Reference
                BentoInfoCard(
                    title: Language.get("PaymentMgmt_Field_OrderReference", alter: "رقم الطلب"),
                    value: reference,
                    symbol: "number.square.fill",
                    tint: AdminSurface.primary,
                    onTap: {
                        copyToClipboard(text: reference, label: Language.get("PaymentMgmt_Field_OrderReference", alter: "رقم الطلب"))
                    }
                )

                // Tile 2: Order Status
                BentoInfoCard(
                    title: Language.get("PaymentMgmt_Field_OrderStatus", alter: "حالة الطلب"),
                    value: statusTitle,
                    symbol: "bolt.ring.closed",
                    tint: statusPresentation(for: record).tint
                )

                // Tile 3: Created Date
                BentoInfoCard(
                    title: Language.get("PaymentMgmt_Field_Created", alter: "تاريخ الإنشاء"),
                    value: formatDate(record.createdAt as Date?),
                    symbol: "calendar.badge.clock",
                    tint: Color(UIColor.ppInfo)
                )

                // Tile 4: Last Updated
                BentoInfoCard(
                    title: Language.get("PaymentMgmt_Field_Updated", alter: "آخر تحديث"),
                    value: formatDate(record.updatedAt as Date?),
                    symbol: "arrow.triangle.2.circlepath.circle.fill",
                    tint: Color(UIColor.ppQuickActionCommunity)
                )
            }
        }
    }

    // MARK: - 3. Customer Section (VIP Passport Chamber)

    private func customerSection(_ record: PPPaymentAdminRecord) -> some View {
        let name = valueOrUnavailable(record.userDisplayName as String?)
        let email = valueOrUnavailable(record.userEmail as String?)
        let initials = userInitials(from: name)

        return PaymentDetailSection(
            title: Language.get("PaymentMgmt_Field_Customer", alter: "ملف العميل والاتصال"),
            symbol: "person.crop.circle.fill"
        ) {
            VStack(spacing: AdminSpacing.md) {
                HStack(alignment: .center, spacing: AdminSpacing.md) {
                    // Customer Initials Monogram Avatar
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 54, height: 54)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .shadow(color: AdminSurface.primary.opacity(0.22), radius: 6, y: 2)

                        Text(initials)
                            .font(.custom("Beiruti-Bold", size: 20, relativeTo: .headline))
                            .foregroundColor(.white)

                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(UIColor.ppSuccess))
                            .background(Color.white, in: Circle())
                            .offset(x: 2, y: 2)
                    }

                    // Customer Details
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)

                        Text(email)
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                // Customer Actions Bar
                HStack(spacing: AdminSpacing.sm) {
                    Button {
                        copyToClipboard(text: email, label: Language.get("PaymentMgmt_Field_Email", alter: "البريد الإلكتروني"))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Copy", alter: "نسخ البريد"))
                                .font(AdminType.captionBold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundColor(AdminSurface.primary)
                        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(NextGenScaleButtonStyle())
                }
            }
        }
    }

    // MARK: - 4. Payments Section (Luxury Settlement Ledger)

    private func paymentSection(_ record: PPPaymentAdminRecord) -> some View {
        let total = formatCurrency(record.totalAmount, currency: record.currency as String?)
        let method = paymentMethodTitle(record)
        let methodIcon = paymentMethodIcon(record)
        let payStatus = record.paymentStatus as String? ?? ""
        let verification = record.verificationStatus as String? ?? ""
        let txId = record.transactionId as String? ?? ""

        return PaymentDetailSection(
            title: Language.get("PaymentMgmt_Section_Payments", alter: "المدفوعات والتسوية المالية"),
            symbol: "creditcard.fill"
        ) {
            VStack(spacing: AdminSpacing.md) {
                // Hero Settlement Card
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("PaymentMgmt_Field_Total", alter: "المبلغ الإجمالي المسجل"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(total)
                            .font(.custom("Beiruti-Bold", size: 24, relativeTo: .title2))
                            .foregroundColor(AdminSurface.primaryText)
                    }

                    Spacer(minLength: 0)

                    // Payment Method Chip
                    HStack(spacing: 6) {
                        Image(systemName: methodIcon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                        Text(method)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AdminSurface.primary.opacity(0.09), in: Capsule(style: .continuous))
                }
                .padding(AdminSpacing.md)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1.0))

                // Verification & Transaction Details (if available)
                if !payStatus.isEmpty || !verification.isEmpty || !txId.isEmpty {
                    VStack(spacing: 8) {
                        if !payStatus.isEmpty {
                            DetailAttributeRow(
                                label: Language.get("PaymentMgmt_Field_PaymentStatus", alter: "حالة الدفع"),
                                value: PPPaymentAdminDisplayTitleForOrderStatus(payStatus),
                                icon: "checkmark.seal"
                            )
                        }
                        if !verification.isEmpty {
                            DetailAttributeRow(
                                label: Language.get("PaymentMgmt_Field_Verification", alter: "التحقق والاعتماد"),
                                value: PPPaymentAdminDisplayTitleForVerificationStatus(verification),
                                icon: "shield.lefthalf.filled.badge.checkmark"
                            )
                        }
                        if !txId.isEmpty {
                            DetailAttributeRow(
                                label: Language.get("PaymentMgmt_Field_Transaction", alter: "رقم المعاملة"),
                                value: txId,
                                icon: "barcode.viewfinder",
                                onCopy: {
                                    copyToClipboard(text: txId, label: Language.get("PaymentMgmt_Field_Transaction", alter: "رقم المعاملة"))
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - 5. Items Section (Package Manifest Gallery)

    private func itemsSection(_ record: PPPaymentAdminRecord) -> some View {
        let items = record.items as? [[String: Any]] ?? []

        return PaymentDetailSection(
            title: Language.get("PaymentMgmt_Section_Items", alter: "بيان الأصناف والطرود"),
            symbol: "bag.fill"
        ) {
            if items.isEmpty {
                PaymentDetailInlineState(
                    title: Language.get("PaymentMgmt_Placeholder_NoItemsTitle", alter: "لا توجد أصناف مرفقة"),
                    subtitle: Language.get("PaymentMgmt_Placeholder_NoItemsSubtitle", alter: "لم يتم تسجيل عناصر تفصيلية في بيانات هذا الطلب."),
                    symbol: "bag.badge.minus",
                    tint: AdminSurface.secondaryText
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        PaymentDetailItemRow(
                            name: valueOrUnavailable(item["name"] as? String),
                            quantity: quantityText(item["quantity"]),
                            index: index + 1
                        )
                    }
                }
            }
        }
    }

    // MARK: - 6. Actions Section (Command Dock)

    private func actionsSection(_ record: PPPaymentAdminRecord) -> some View {
        PaymentDetailSection(
            title: record.fulfillmentVersion == 1
                ? Language.get("PaymentMgmt_OfficialFulfillment_Title", alter: "أوامر التنفيذ والشحن")
                : Language.get("PaymentMgmt_Section_AdminActions", alter: "إجراءات الإدارة والتنفيذ"),
            symbol: record.fulfillmentVersion == 1
                ? "shippingbox.and.arrow.backward"
                : "bolt.shield.fill"
        ) {
            if !canManagePayments {
                PaymentDetailInlineState(
                    title: Language.get("PaymentDetail_ReadOnly_Title", alter: "وضع العرض فقط"),
                    subtitle: Language.get("PaymentDetail_ReadOnly_Subtitle", alter: "لا يملك حساب الموظف صلاحية payments.manage لتنفيذ عمليات التغيير."),
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
                Text(Language.get("PaymentMgmt_OfficialFulfillment_Loading", alter: "جارٍ تحميل إشارات التنفيذ..."))
                    .font(AdminType.subheadline)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable, alignment: .center)
        } else if let error = viewModel.officialFulfillmentError {
            PaymentDetailInlineState(
                title: viewModel.officialFulfillmentErrorTitle ?? Language.get("PaymentMgmt_OfficialFulfillment_LoadFailed_Title", alter: "تعذر التحقق من سجل التنفيذ الرسمي"),
                subtitle: error,
                symbol: "exclamationmark.triangle.fill",
                tint: Color(UIColor.ppError),
                actionTitle: Language.get("Retry", alter: "إعادة المحاولة"),
                action: { viewModel.reloadOfficialFulfillment() }
            )
        } else if let fulfillment = viewModel.officialFulfillment {
            PaymentDetailFieldRow(
                label: Language.get("PaymentMgmt_Field_OrderStatus", alter: "حالة التنفيذ الحالية"),
                value: PPPaymentAdminDisplayTitleForOrderStatus(fulfillment.status)
            )
            if !viewModel.officialActions.isEmpty {
                Divider().background(AdminSurface.hairline)
            }
            ForEach(Array(viewModel.officialActions.enumerated()), id: \.element) { index, action in
                PaymentDetailActionButton(
                    title: officialActionTitle(action),
                    subtitle: Language.get("PaymentMgmt_OfficialFulfillment_Action_Subtitle", alter: "تحديث الحالة المعتمدة لهذا الطلب"),
                    symbol: officialActionSymbol(action),
                    tint: officialActionColor(action),
                    isPrimary: index == 0,
                    isBusy: viewModel.isBusy
                ) { requestOfficialAction(action) }
            }
        } else {
            PaymentDetailInlineState(
                title: Language.get("PaymentMgmt_OfficialFulfillment_Missing_Title", alter: "يحتاج التنفيذ الرسمي إلى تهيئة"),
                subtitle: Language.get("PaymentMgmt_OfficialFulfillment_Missing_Subtitle", alter: "لا يوجد سجل تنفيذ رسمي مرتبط بهذا الطلب بعد. اختر الإجراء المعتمد التالي لإنشاء السجل الرسمي وتحديث الطلب بأمان."),
                symbol: "shippingbox.and.arrow.backward.fill",
                tint: Color(UIColor.ppWarning)
            )
            if !viewModel.missingOfficialFulfillmentActions.isEmpty {
                Divider().background(AdminSurface.hairline)
            }
            ForEach(Array(viewModel.missingOfficialFulfillmentActions.enumerated()), id: \.element) { index, action in
                PaymentDetailActionButton(
                    title: officialActionTitle(action),
                    subtitle: Language.get("PaymentMgmt_OfficialFulfillment_Initialize_Action_Subtitle", alter: "ينشئ سجل التنفيذ الرسمي ثم يطبق هذا الإجراء المعتمد."),
                    symbol: officialActionSymbol(action),
                    tint: officialActionColor(action),
                    isPrimary: index == 0,
                    isBusy: viewModel.isBusy
                ) { requestOfficialInitializationAction(action) }
            }
        }
    }

    @ViewBuilder
    private func legacyActionsContent(_ record: PPPaymentAdminRecord) -> some View {
        let actions = legacyActions(for: record)
        if actions.isEmpty {
            PaymentDetailInlineState(
                title: Language.get("PaymentDetail_NoAction_Title", alter: "لا توجد إجراءات متاحة"),
                subtitle: Language.get("PaymentDetail_NoAction_Subtitle", alter: "هذا الطلب وصل إلى حالته النهائية."),
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
        PPPaymentManagementService.shared().currentAdminCanManagePayments()
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
            confirmation: Language.get("PaymentMgmt_OfficialFulfillment_Confirm", alter: "تأكيد تنفيذ الإجراء"),
            prompt: Language.get("PaymentMgmt_OfficialFulfillment_Prompt", alter: "يرجى كتابة الملاحظة الإدارية لتسجيلها في مسار التدقيق."),
            defaultNote: String(
                format: Language.get("PaymentMgmt_OfficialFulfillment_DefaultNote", alter: "إجراء إداري: %@"),
                title
            )
        ) { note in viewModel.transitionOfficialFulfillment(action: action, note: note) }
    }

    private func requestOfficialInitializationAction(_ action: String) {
        let title = officialActionTitle(action)
        presentActionPrompt(
            title: title,
            confirmation: Language.get("PaymentMgmt_OfficialFulfillment_Initialize_Confirm", alter: "سيُنشئ النظام سجل التنفيذ الرسمي المفقود، ثم يطبق الإجراء المعتمد ويسجله في سجل التدقيق."),
            prompt: Language.get("PaymentMgmt_OfficialFulfillment_Prompt", alter: "أضف ملاحظة تشغيلية قصيرة. سيُسجّل الإجراء في سجل تدقيق التنفيذ."),
            defaultNote: String(
                format: Language.get("PaymentMgmt_OfficialFulfillment_DefaultNote", alter: "إجراء موظف المدفوعات: %@"),
                title
            )
        ) { note in viewModel.initializeOfficialFulfillment(action: action, note: note) }
    }

    private func presentActionPrompt(
        title: String,
        confirmation: String,
        prompt: String,
        defaultNote: String,
        action: @escaping (String) -> Void
    ) {
        let subtitle = String(
            format: Language.get("PaymentDetail_ActionPrompt_Format", alter: "%@\n%@"),
            confirmation,
            prompt
        )
        PPAlertHelper.showTextPrompt(
            in: nil,
            title: title,
            subtitle: subtitle,
            placeholder: Language.get("PaymentMgmt_Value_AdminNote", alter: "الملاحظة الإدارية (مطلوبة)"),
            initialText: nil,
            confirmText: Language.get("Confirm", alter: "تأكيد"),
            cancelText: Language.get("Cancel", alter: "إلغاء"),
            secureEntry: false,
            keyboardType: .default
        ) { text in
            guard let text else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.count < 3 {
                viewModel.showValidationError(
                    Language.get("PaymentMgmt_Prompt_NoteRequired_Subtitle", alter: "يجب ألا تقل الملاحظة عن 3 أحرف.")
                )
                return
            }
            let resolvedNote = trimmed.isEmpty ? defaultNote : trimmed
            guard resolvedNote.count >= 3 else {
                viewModel.showValidationError(
                    Language.get("PaymentMgmt_Error_AdminNoteRequired", alter: "الملاحظة الإدارية مطلوبة لتوثيق الإجراء.")
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
            return Language.get("PaymentMgmt_OfficialFulfillment_Title", alter: "إجراء رسمي")
        }
        return Language.get(key, alter: action)
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
                title: Language.get("PaymentDetail_ReadOnly_Title", alter: "وضع العرض فقط"),
                subtitle: Language.get("PaymentDetail_ReadOnly_Subtitle", alter: "الصلاحية مقيدة لحسابك"),
                symbol: "lock.shield.fill",
                tint: Color(UIColor.ppWarning)
            )
        }
        if record.fulfillmentVersion == 1 {
            if viewModel.officialFulfillmentLoading {
                return .init(
                    title: Language.get("PaymentMgmt_OfficialFulfillment_Loading", alter: "مزامنة التنفيذ..."),
                    subtitle: Language.get("PaymentDetail_Loading_Source", alter: "جلب إشارات الخادم"),
                    symbol: "arrow.triangle.2.circlepath",
                    tint: AdminSurface.primary
                )
            }
            if let error = viewModel.officialFulfillmentError {
                return .init(
                    title: viewModel.officialFulfillmentErrorTitle ?? Language.get("PaymentMgmt_OfficialFulfillment_LoadFailed_Title", alter: "تعذر التحقق من سجل التنفيذ الرسمي"),
                    subtitle: error,
                    symbol: "exclamationmark.triangle.fill",
                    tint: Color(UIColor.ppError)
                )
            }
            if let first = viewModel.officialActions.first {
                return .init(
                    title: officialActionTitle(first),
                    subtitle: Language.get("PaymentMgmt_OfficialFulfillment_Action_Subtitle", alter: "الخطوة التالية المعتمدة"),
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
            title: Language.get("PaymentDetail_NoAction_Title", alter: "الطلب مستقر"),
            subtitle: Language.get("PaymentDetail_NoAction_Subtitle", alter: "لا توجد إجراءات إضافية مطلوبة"),
            symbol: "checkmark.seal.fill",
            tint: Color(UIColor.ppSuccess)
        )
    }

    // MARK: - Helpers & Formatters

    private func copyToClipboard(text: String, label: String) {
        UIPasteboard.general.string = text
        triggerHaptic()
        toastTask?.cancel()
        copiedToastMessage = String(format: Language.get("CopiedFormat", alter: "تم نسخ %@ بنجاح"), label)
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            copiedToastMessage = nil
        }
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    private func userInitials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if let first = parts.first?.prefix(1), let second = parts.dropFirst().first?.prefix(1) {
            return "\(first)\(second)".uppercased()
        } else if !name.isEmpty {
            return String(name.prefix(2)).uppercased()
        }
        return "PP"
    }

    private func valueOrUnavailable(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty
            ? Language.get("PaymentMgmt_Value_NotAvailable", alter: "غير متوفر")
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
        return Language.get("PaymentMgmt_Value_NotAvailable", alter: "نقدًا")
    }

    private func paymentMethodIcon(_ record: PPPaymentAdminRecord) -> String {
        let raw = (record.paymentMethodId as String? ?? record.paymentProvider as String? ?? "").lowercased()
        if raw.contains("cash") || raw.contains("cod") {
            return "banknote.fill"
        }
        if raw.contains("apple") {
            return "applelogo"
        }
        if raw.contains("qib") || raw.contains("card") || raw.contains("credit") {
            return "creditcard.fill"
        }
        return "creditcard.fill"
    }

    private func quantityText(_ value: Any?) -> String {
        if let number = value as? NSNumber {
            return NumberFormatter.localizedString(from: number, number: .decimal)
        }
        if let string = value as? String,
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return string
        }
        return "1"
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
            return Language.get("PaymentMgmt_Value_NotAvailable", alter: "غير مسجل")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(
            identifier: Language.currentLanguageCode() == "ar" ? "ar" : "en"
        )
        return formatter.string(from: date)
    }
}

// MARK: - Bento Info Card

private struct BentoInfoCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(tint)
                    Text(title)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if onTap != nil {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
                    }
                }

                Text(value)
                    .font(.custom("Beiruti-Bold", size: 15, relativeTo: .body))
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 1.0)
            )
        }
        .buttonStyle(NextGenScaleButtonStyle())
        .disabled(onTap == nil)
    }
}

// MARK: - Detail Attribute Row

private struct DetailAttributeRow: View {
    let label: String
    let value: String
    let icon: String
    var onCopy: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: AdminSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 28, height: 28)
                .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(label)
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            Spacer(minLength: AdminSpacing.sm)

            Text(value)
                .font(AdminType.body)
                .foregroundColor(AdminSurface.primaryText)
                .lineLimit(1)

            if let onCopy {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .buttonStyle(NextGenScaleButtonStyle())
            }
        }
        .padding(.vertical, 4)
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
            // Section Header
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        AdminSurface.primary.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .accessibilityHidden(true)

                Text(title)
                    .font(AdminType.title3)
                    .foregroundColor(AdminSurface.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)
            }

            content
        }
        .padding(AdminSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1.0)
        }
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 3)
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
    }
}

private struct PaymentDetailItemRow: View {
    let name: String
    let quantity: String
    var index: Int = 1

    var body: some View {
        HStack(alignment: .center, spacing: AdminSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AdminSurface.primary.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // Quantity Capsule
            HStack(spacing: 3) {
                Text("×")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AdminSurface.primary)
                Text(quantity)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AdminSurface.control, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1.0))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(isPrimary ? .white : tint)
                    .frame(width: 40, height: 40)
                    .background(
                        isPrimary ? Color.white.opacity(0.18) : tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundColor(isPrimary ? .white : AdminSurface.primaryText)
                    Text(subtitle)
                        .font(AdminType.caption1)
                        .foregroundColor(isPrimary ? Color.white.opacity(0.85) : AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AdminSpacing.sm)

                Image(systemName: "chevron.backward")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isPrimary ? Color.white.opacity(0.85) : tint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, AdminSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                isPrimary
                    ? LinearGradient(colors: [tint, tint.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [tint.opacity(0.07), tint.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isPrimary ? Color.clear : tint.opacity(0.24), lineWidth: 1.0)
            }
            .shadow(color: isPrimary ? tint.opacity(0.25) : Color.clear, radius: 8, y: 3)
        }
        .buttonStyle(NextGenScaleButtonStyle())
        .disabled(isBusy)
        .opacity(isBusy ? AdminOpacity.disabled : 1)
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
                    .font(.system(size: 16, weight: .bold))
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
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1.0)
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
                .font(.system(size: 28, weight: .bold))
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(tint.opacity(0.12), in: Capsule(style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AdminSpacing.md)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - NextGen Scale Button Style

private struct NextGenScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Presentation Models & Enums

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
    @Published var officialFulfillmentErrorTitle: String?
    @Published var officialFulfillmentError: String?
    @Published var officialActionInFlight = false

    private var pendingSuccessMessage: String?
    private var pendingOfficialInitializationSuccessMessage: String?

    var officialActions: [String] {
        guard let officialFulfillment else { return [] }
        return PPFulfillmentService.availableOfficialActions(forStatus: officialFulfillment.status)
    }

    var missingOfficialFulfillmentActions: [String] {
        guard let record,
              record.fulfillmentVersion == 1,
              officialFulfillment == nil,
              officialFulfillmentError == nil else { return [] }
        return PPFulfillmentService.availableOfficialActions(forStatus: "new_request")
    }

    var isBusy: Bool {
        isLoading || isPerformingAction || officialActionInFlight || officialFulfillmentLoading
    }

    private func showOfficialFulfillmentFeedback(
        titleKey: String,
        titleFallback: String,
        subtitleKey: String,
        subtitleFallback: String
    ) {
        officialFulfillmentErrorTitle = Language.get(titleKey, alter: titleFallback)
        officialFulfillmentError = Language.get(subtitleKey, alter: subtitleFallback)
    }

    private func showOfficialFulfillmentError(_ error: Error, duringAction: Bool) {
        let nsError = error as NSError
        guard nsError.domain == "PPFulfillmentService" else {
            showOfficialFulfillmentFeedback(
                titleKey: duringAction
                    ? "PaymentMgmt_OfficialFulfillment_ActionFailed_Title"
                    : "PaymentMgmt_OfficialFulfillment_LoadFailed_Title",
                titleFallback: duringAction
                    ? "لم يُحدّث سجل التنفيذ الرسمي"
                    : "تعذر التحقق من سجل التنفيذ الرسمي",
                subtitleKey: duringAction
                    ? "PaymentMgmt_OfficialFulfillment_ActionFailed_Subtitle"
                    : "PaymentMgmt_OfficialFulfillment_LoadFailed_Subtitle",
                subtitleFallback: duringAction
                    ? "لم يُطبّق الإجراء. حدّث الطلب قبل إعادة المحاولة."
                    : "تعذر التحقق من سجل التنفيذ الرسمي. حدّث الطلب، وإذا استمرت المشكلة فتأكد من صلاحيات الموظف أو تواصل مع المسؤول."
            )
            return
        }

        switch nsError.code {
        case 410, 411:
            showOfficialFulfillmentFeedback(
                titleKey: "PaymentMgmt_OfficialFulfillment_AccessRestricted_Title",
                titleFallback: "وصول سجل التنفيذ الرسمي مقيّد",
                subtitleKey: "PaymentMgmt_OfficialFulfillment_AccessRestricted_Subtitle",
                subtitleFallback: "لا يملك حساب الموظف صلاحية الوصول إلى سجل التنفيذ هذا ضمن النطاق الحالي."
            )
        case 412:
            showOfficialFulfillmentFeedback(
                titleKey: "PaymentMgmt_OfficialFulfillment_SessionChanged_Title",
                titleFallback: "تغيّرت جلسة الموظف",
                subtitleKey: "PaymentMgmt_OfficialFulfillment_SessionChanged_Subtitle",
                subtitleFallback: "حدّث الطلب بعد استعادة جلسة الموظف."
            )
        case 414:
            showOfficialFulfillmentFeedback(
                titleKey: "PaymentMgmt_OfficialFulfillment_NeedsReview_Title",
                titleFallback: "يحتاج سجل التنفيذ الرسمي إلى مراجعة",
                subtitleKey: "PaymentMgmt_OfficialFulfillment_NeedsReview_Subtitle",
                subtitleFallback: "يوجد أكثر من سجل تنفيذ رسمي مرتبط بالطلب؛ لم يُجرَ أي تغيير."
            )
        case 415:
            showOfficialFulfillmentFeedback(
                titleKey: "PaymentMgmt_OfficialFulfillment_NotManageable_Title",
                titleFallback: "تعذر إدارة سجل التنفيذ الرسمي",
                subtitleKey: "PaymentMgmt_OfficialFulfillment_NotManageable",
                subtitleFallback: "سجل التنفيذ ليس طلبًا رسميًا لبيور بتس أو يقع خارج نطاق صلاحيات الموظف."
            )
        case 416:
            showOfficialFulfillmentFeedback(
                titleKey: "PaymentMgmt_OfficialFulfillment_ActionFailed_Title",
                titleFallback: "لم يُحدّث سجل التنفيذ الرسمي",
                subtitleKey: "PaymentMgmt_OfficialFulfillment_InvalidCommand",
                subtitleFallback: "حدّث الطلب وأدخل ملاحظة موظف صحيحة قبل المتابعة."
            )
        default:
            showOfficialFulfillmentFeedback(
                titleKey: duringAction
                    ? "PaymentMgmt_OfficialFulfillment_ActionFailed_Title"
                    : "PaymentMgmt_OfficialFulfillment_LoadFailed_Title",
                titleFallback: duringAction
                    ? "لم يُحدّث سجل التنفيذ الرسمي"
                    : "تعذر التحقق من سجل التنفيذ الرسمي",
                subtitleKey: duringAction
                    ? "PaymentMgmt_OfficialFulfillment_ActionFailed_Subtitle"
                    : "PaymentMgmt_OfficialFulfillment_LoadFailed_Subtitle",
                subtitleFallback: duringAction
                    ? "لم يُطبّق الإجراء. حدّث الطلب قبل إعادة المحاولة."
                    : "تعذر التحقق من سجل التنفيذ الرسمي. حدّث الطلب، وإذا استمرت المشكلة فتأكد من صلاحيات الموظف أو تواصل مع المسؤول."
            )
        }
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
        officialFulfillmentErrorTitle = nil
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
                    self.pendingOfficialInitializationSuccessMessage = nil
                    self.showOfficialFulfillmentError(error, duringAction: false)
                    return
                }
                self.officialFulfillment = fulfillment
                if fulfillment != nil, let pendingSuccess = self.pendingOfficialInitializationSuccessMessage {
                    self.lastSuccessMessage = pendingSuccess
                    self.pendingOfficialInitializationSuccessMessage = nil
                } else if fulfillment == nil, self.pendingOfficialInitializationSuccessMessage != nil {
                    self.pendingOfficialInitializationSuccessMessage = nil
                    self.showOfficialFulfillmentFeedback(
                        titleKey: "PaymentMgmt_OfficialFulfillment_Initialize_Unconfirmed_Title",
                        titleFallback: "لا يزال التنفيذ الرسمي قيد المزامنة",
                        subtitleKey: "PaymentMgmt_OfficialFulfillment_Initialize_Unconfirmed",
                        subtitleFallback: "تم قبول الأمر، لكن لم يظهر سجل التنفيذ الرسمي بعد. حدّث الطلب وراجعه قبل إعادة المحاولة."
                    )
                }
            }
        }
    }

    func transitionOfficialFulfillment(action: String, note: String) {
        guard let fulfillment = officialFulfillment, !isBusy else { return }
        let safeNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard safeNote.count >= 3 else {
            showOfficialFulfillmentFeedback(
                titleKey: "PaymentMgmt_OfficialFulfillment_ActionFailed_Title",
                titleFallback: "لم يُحدّث سجل التنفيذ الرسمي",
                subtitleKey: "PaymentMgmt_Prompt_NoteRequired_Subtitle",
                subtitleFallback: "أضف ملاحظة تشغيلية قبل المتابعة."
            )
            return
        }
        officialActionInFlight = true
        officialFulfillmentErrorTitle = nil
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
                    self.showOfficialFulfillmentError(error, duringAction: true)
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

    func initializeOfficialFulfillment(action: String, note: String) {
        guard let record,
              record.fulfillmentVersion == 1,
              officialFulfillment == nil,
              !isBusy else { return }
        let safeNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedParentStatus = PPPaymentAdminRecord
            .normalizedStatusString(record.rawStatus as String?)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedActions = PPFulfillmentService.availableOfficialActions(forStatus: "new_request")
        guard !expectedParentStatus.isEmpty,
              allowedActions.contains(action),
              safeNote.count >= 3 else {
            showOfficialFulfillmentFeedback(
                titleKey: "PaymentMgmt_OfficialFulfillment_ActionFailed_Title",
                titleFallback: "لم يُحدّث سجل التنفيذ الرسمي",
                subtitleKey: "PaymentMgmt_OfficialFulfillment_InvalidCommand",
                subtitleFallback: "حدّث الطلب وأدخل ملاحظة موظف صحيحة قبل المتابعة."
            )
            return
        }
        officialActionInFlight = true
        officialFulfillmentErrorTitle = nil
        officialFulfillmentError = nil
        errorMessage = nil
        lastSuccessMessage = nil
        PPFulfillmentService.shared().initializeAndTransitionOfficialFulfillment(
            orderID: record.orderId,
            expectedParentStatus: expectedParentStatus,
            action: action,
            note: safeNote,
            commandID: UUID().uuidString
        ) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.officialActionInFlight = false
                if let error {
                    self.showOfficialFulfillmentError(error, duringAction: true)
                    return
                }
                self.pendingOfficialInitializationSuccessMessage = Language.get(
                    "PaymentMgmt_OfficialFulfillment_Initialize_Success",
                    alter: "تم إنشاء سجل التنفيذ الرسمي وتحديث الطلب."
                )
                self.loadData()
            }
        }
    }
}
