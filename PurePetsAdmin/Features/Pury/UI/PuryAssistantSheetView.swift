//
//  PuryAssistantSheetView.swift
//  PurePetsAdmin
//
//  Native, studio-grade category-defining operational AI assistant sheet for Pure Pets Admin.
//  Preserves operator screen position and bounded context.
//

import SwiftUI

@available(iOS 16.0, *)
struct PuryAssistantSheetView: View {
    let session: AdminSession
    @ObservedObject var router: AdminRouter
    var screenContext: PuryScreenContext? = nil

    @StateObject private var store = PuryConversationStore()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool

    init(
        session: AdminSession,
        router: AdminRouter,
        screenContext: PuryScreenContext? = nil
    ) {
        self.session = session
        self.router = router
        self.screenContext = screenContext
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AdminSurface.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header Bar
                    headerBar

                    // Context Indicator Strip
                    if let context = screenContext, !context.isEmpty {
                        screenContextStrip(context)
                    }

                    // Conversation Timeline
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: AdminSpacing.md) {
                                if store.messages.isEmpty && store.state == .idle {
                                    emptyStateView
                                } else {
                                    ForEach(store.messages) { message in
                                        messageRow(for: message)
                                            .id(message.id)
                                    }

                                    if store.state == .loading {
                                        loadingBubble
                                            .id("pury_loading_bubble")
                                    }
                                }
                            }
                            .padding(.horizontal, AdminSpacing.md)
                            .padding(.top, AdminSpacing.md)
                            .padding(.bottom, 90) // clearance for input bar
                        }
                        .onChange(of: store.messages.count) { _ in
                            scrollToBottom(proxy: proxy)
                        }
                        .onChange(of: store.state) { _ in
                            scrollToBottom(proxy: proxy)
                        }
                    }

                    Spacer(minLength: 0)
                }

                // Bottom Input Deck
                bottomInputDeck
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Pury Brand Badge
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 16/255, green: 185/255, blue: 129/255), Color(red: 5/255, green: 150/255, blue: 105/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                        .shadow(color: Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.35), radius: 6, x: 0, y: 3)

                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Language.isRTL() ? "بيوري" : "Pury")
                            .font(AdminType.title3)
                            .foregroundStyle(AdminSurface.primaryText)

                        Text("AI")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 16/255, green: 185/255, blue: 129/255), in: Capsule())
                    }

                    Text(Language.get("Pury_SubTitle", alter: "المساعد التشغيلي الموثوق"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            Spacer()

            // Language Toggle Pill
            Button {
                store.language = store.language == "ar" ? "en" : "ar"
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Text(store.language == "ar" ? "EN" : "عربي")
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AdminSurface.control, in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
            }
            .buttonStyle(.plain)

            // Clear Conversation
            if !store.messages.isEmpty {
                Button {
                    store.clearHistory()
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.control, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Pury_Clear_Chat", alter: "مسح المحادثة"))
            }

            // Dismiss Button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(AdminSurface.control, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.get("Close", alter: "إغلاق"))
        }
        .padding(.horizontal, AdminSpacing.md)
        .padding(.vertical, 12)
        .background(AdminSurface.surface)
        .overlay(
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Screen Context Strip

    private func screenContextStrip(_ context: PuryScreenContext) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "location.viewfinder")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))

            Text(context.displayLabel)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminSurface.primaryText)
                .environment(\.layoutDirection, .leftToRight)

            Spacer()

            Text(Language.get("Pury_Context_Bound", alter: "سياق نشط"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, AdminSpacing.md)
        .padding(.vertical, 7)
        .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.06))
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .fill(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.1))
                    .frame(width: 72, height: 72)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
            }

            VStack(spacing: 6) {
                Text(Language.get("Pury_Welcome_Title", alter: "مرحباً! أنا بيوري، مساعدك التشغيلي"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)

                Text(Language.get("Pury_Welcome_Desc", alter: "اطرح أي سؤال حول المخزون، الطلبات، النزلاء في الفندق، أو تقارير المبيعات، وسأجيبك من واقع البيانات المحدثة مباشرة."))
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Quick Prompt Chips
            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("Pury_Quick_Prompts", alter: "اقتراحات سريعة:"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .padding(.horizontal, 4)

                if let ctx = screenContext, !ctx.isEmpty {
                    if ctx.stayId != nil || ctx.reservationId != nil {
                        quickPromptChip(Language.get("Pury_Prompt_ContextStay", alter: "ما هي المهام الطبية وحالة الرعاية لهذه الإقامة؟"))
                    } else if ctx.entityType == "order" || ctx.route?.contains("order") == true {
                        quickPromptChip(Language.get("Pury_Prompt_ContextOrder", alter: "ما هو ملخص حالة وسجل تتبع هذا الطلب؟"))
                    } else if ctx.entityType == "product" || ctx.route?.contains("product") == true || ctx.route?.contains("access") == true {
                        quickPromptChip(Language.get("Pury_Prompt_ContextProduct", alter: "ما هي حالة المخزون والمبيعات لهذا المنتج؟"))
                    }
                }

                quickPromptChip(Language.get("Pury_Prompt_Hotel", alter: "ما هي حالة الإشغال اليوم في فندق الحيوانات؟"))
                quickPromptChip(Language.get("Pury_Prompt_LowStock", alter: "ابحث عن المنتجات التي أوشكت على النفاد في المستودع"))
                quickPromptChip(Language.get("Pury_Prompt_PendingOrders", alter: "كم عدد الطلبات المعلقة بانتظار الشحن حالياً؟"))
                quickPromptChip(Language.get("Pury_Prompt_KpiSummary", alter: "ملخص مؤشرات الأداء والمبيعات لهذا الأسبوع"))
            }
            .padding(.horizontal, AdminSpacing.sm)

            Spacer(minLength: 60)
        }
    }

    private func quickPromptChip(_ prompt: String) -> some View {
        Button {
            Task {
                await store.sendMessage(prompt, screenContext: screenContext)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: Language.isRTL() ? "arrow.up.left.circle.fill" : "arrow.up.right.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))

                Text(prompt)
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message Rows

    @ViewBuilder
    private func messageRow(for message: PuryMessage) -> some View {
        if message.role == .user {
            userBubble(message)
        } else {
            modelBubble(message)
        }
    }

    private func userBubble(_ message: PuryMessage) -> some View {
        HStack {
            Spacer(minLength: 40)

            Text(message.text)
                .font(AdminType.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Color(red: 16/255, green: 185/255, blue: 129/255),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
    }

    private func modelBubble(_ message: PuryMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Text Response
            if !message.text.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
                        .padding(.top, 4)

                    Text(message.text)
                        .font(AdminType.body)
                        .foregroundStyle(AdminSurface.primaryText)
                        .textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )
            }

            // Structured Result Cards
            if let structured = message.metadata?.structuredData {
                if let cards = structured.cards, !cards.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(cards) { card in
                            structuredCardView(card)
                        }
                    }
                }

                if let blocks = structured.dataBlocks, !blocks.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(blocks) { block in
                            dataBlockView(block)
                        }
                    }
                }
            }

            // Tier 3 Confirmation Card
            if let action = message.metadata?.confirmationAction,
               message.metadata?.confirmationRequired == true,
               store.activeProposal?.token == action.token {
                confirmationCard(action)
            }
        }
    }

    // MARK: - Structured Cards Rendering

    private func structuredCardView(_ card: PuryCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)

                    if let sub = card.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(AdminType.caption1)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                if let status = card.status, !status.isEmpty {
                    statusPill(status)
                }
            }

            if let details = card.details, !details.isEmpty {
                Divider()
                    .overlay(AdminSurface.hairline)

                VStack(spacing: 6) {
                    ForEach(details) { field in
                        HStack {
                            Text(field.label)
                                .font(AdminType.caption1)
                                .foregroundStyle(AdminSurface.secondaryText)
                            Spacer()
                            Text(field.value)
                                .font(AdminType.caption1Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                                .environment(\.layoutDirection, field.type == "code" ? .leftToRight : .rightToLeft)
                        }
                    }
                }
            }

            // Action Route deep-link button
            if let entityType = card.entityType, let entityId = card.entityId, !entityId.isEmpty {
                Button {
                    handleDeepLink(entityType: entityType, entityId: entityId)
                } label: {
                    HStack(spacing: 6) {
                        Text(Language.get("Pury_View_Record", alter: "فتح السجل في لوحة الإدارة"))
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(AdminSurface.primary)

                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private func dataBlockView(_ block: PuryDataBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(block.fields) { field in
                HStack {
                    Text(field.label)
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text(field.value)
                        .font(AdminType.caption1Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statusPill(_ status: String) -> some View {
        Text(status)
            .font(AdminType.caption2Bold)
            .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.12), in: Capsule())
    }

    // MARK: - Confirmation Card View

    private func confirmationCard(_ action: PuryConfirmationAction) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 245/255, green: 158/255, blue: 11/255))

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Pury_Confirm_Title", alter: "مطلوب تأكيد العملية"))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Pury_Confirm_Subtitle", alter: "تعديل محمي يتطلب موافقتك الصريحة"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                if let perm = action.permissionRequired {
                    Text(perm)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 6))
                        .environment(\.layoutDirection, .leftToRight)
                }
            }

            if let warnings = action.warnings, !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(red: 239/255, green: 68/255, blue: 68/255))
                            Text(warning)
                                .font(AdminType.caption1)
                                .foregroundStyle(Color(red: 239/255, green: 68/255, blue: 68/255))
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if let updates = action.updates, !updates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Pury_Proposed_Changes", alter: "التعديلات المقترحة:"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    ForEach(Array(updates.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Spacer()
                            Text(updates[key] ?? "")
                                .font(AdminType.caption1Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                    }
                }
                .padding(10)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10))
            }

            // Confirmation Buttons Row
            HStack(spacing: 12) {
                Button {
                    Task {
                        await store.confirmAction(action, screenContext: screenContext)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(Language.get("Pury_Confirm_Btn", alter: "تأكيد وتنفيذ"))
                            .font(AdminType.subheadlineBold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Color(red: 16/255, green: 185/255, blue: 129/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    store.cancelAction()
                } label: {
                    Text(Language.get("Cancel", alter: "إلغاء"))
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(maxWidth: 90)
                        .padding(.vertical, 12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Loading Bubble

    private var loadingBubble: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(Color(red: 16/255, green: 185/255, blue: 129/255))
                .scaleEffect(0.85)

            Text(Language.get("Pury_Thinking", alter: "بيوري يراجع البيانات المصرح بها..."))
                .font(AdminType.caption1)
                .foregroundStyle(AdminSurface.secondaryText)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Bottom Input Deck

    private var bottomInputDeck: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(AdminSurface.hairline)

            HStack(spacing: 10) {
                // Text Input Field
                HStack(spacing: 8) {
                    TextField(
                        Language.get("Pury_Input_Placeholder", alter: "اسأل بيوري عن أي تفاصيل تشغيلية..."),
                        text: $store.currentInputText,
                        axis: .vertical
                    )
                    .font(AdminType.body)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        submitInput()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(isInputFocused ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1)
                )

                // Send Button
                Button {
                    submitInput()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                store.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.state == .loading
                                    ? AdminSurface.control
                                    : Color(red: 16/255, green: 185/255, blue: 129/255)
                            )
                            .frame(width: 42, height: 42)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(
                                store.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.state == .loading
                                    ? AdminSurface.secondaryText
                                    : .white
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(store.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.state == .loading)
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, 10)
            .background(AdminSurface.surface)
        }
    }

    // MARK: - Actions & Navigation

    private func submitInput() {
        let text = store.currentInputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isInputFocused = false
        Task {
            await store.sendMessage(text, screenContext: screenContext)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if store.state == .loading {
                proxy.scrollTo("pury_loading_bubble", anchor: .bottom)
            } else if let last = store.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func handleDeepLink(entityType: String, entityId: String) {
        dismiss()
        switch entityType.lowercased() {
        case "order", "orders":
            router.presentedRoute = .paymentOrder(entityId)
        case "petaccessories", "product":
            router.presentedRoute = .accessories
        case "livepet", "livepets":
            router.presentedRoute = .livePets
        case "hotel", "stay", "reservation":
            router.presentedRoute = .hotel
        case "userscol", "user":
            router.presentedRoute = .users
        case "staff_users", "staff":
            router.presentedRoute = .staff
        case "branches", "branch":
            router.presentedRoute = .branches
        default:
            break
        }
    }
}
