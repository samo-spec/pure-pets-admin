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

    // Living Avatar & Motion States
    @State private var ambientPulse: Bool = false
    @State private var avatarShimmer: Bool = false

    private var isRTL: Bool {
        if store.language == "ar" { return true }
        if store.language == "en" { return false }
        return Language.isRTL()
    }

    init(
        session: AdminSession,
        router: AdminRouter,
        screenContext: PuryScreenContext? = nil
    ) {
        PPBrandFont.registerIfNeeded()
        self.session = session
        self.router = router
        self.screenContext = screenContext
    }

    var body: some View {
        ZStack {
            // Ambient Atmospheric Background
            ambientAtmosphere

            VStack(spacing: 0) {
                // Top Executive Navigation Bar
                executiveHeaderBar

                // Context Indicator Strip
                if let context = screenContext, !context.isEmpty {
                    contextIndicatorStrip(context)
                }

                // Conversation Timeline
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            if store.messages.isEmpty && store.state == .idle {
                                livingEmptyStateView
                                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            } else {
                                ForEach(store.messages) { message in
                                    messageStreamRow(for: message)
                                        .id(message.id)
                                }

                                if store.state == .loading {
                                    thinkingBubble
                                        .id("pury_thinking_bubble")
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 110) // clearance for floating input dock
                    }
                    .onChange(of: store.messages.count) { _ in
                        scrollToLatest(proxy: proxy)
                    }
                    .onChange(of: store.state) { _ in
                        scrollToLatest(proxy: proxy)
                    }
                }

                Spacer(minLength: 0)
            }

            // Floating Tactile Input Dock
            VStack {
                Spacer()
                floatingInputDock
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        .onAppear {
            PPBrandFont.registerIfNeeded()
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                ambientPulse = true
            }
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                avatarShimmer = true
            }
        }
    }

    // MARK: - Ambient Atmosphere

    private var ambientAtmosphere: some View {
        ZStack {
            AdminSurface.background
                .ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 16/255, green: 185/255, blue: 129/255).opacity(ambientPulse ? 0.12 : 0.05),
                            Color(red: 59/255, green: 130/255, blue: 246/255).opacity(ambientPulse ? 0.06 : 0.02),
                            Color.clear
                        ],
                        center: .top,
                        startRadius: 40,
                        endRadius: 360
                    )
                )
                .frame(width: 460, height: 460)
                .position(x: UIScreen.main.bounds.width / 2, y: 120)
                .ignoresSafeArea()
        }
    }

    // MARK: - Executive Header Bar

    private var executiveHeaderBar: some View {
        HStack(spacing: 12) {
            // Dismiss / Close Button
            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(AdminSurface.control)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))

                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRTL ? "إغلاق" : "Close")

            // Living Avatar & Persona
            HStack(spacing: 10) {
                livingAvatarBeacon(size: 38)

                VStack(alignment: isRTL ? .trailing : .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isRTL ? "بيوري" : "Pury")
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primaryText)

                        Text("AI")
                            .font(PPBrandFont.bold(size: 10, relativeTo: .caption2))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 16/255, green: 185/255, blue: 129/255), Color(red: 5/255, green: 150/255, blue: 105/255)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Capsule()
                            )
                    }

                    // Live Subtitle Indicator
                    HStack(spacing: 5) {
                        Circle()
                            .fill(store.state == .loading ? Color(red: 245/255, green: 158/255, blue: 11/255) : Color(red: 16/255, green: 185/255, blue: 129/255))
                            .frame(width: 6, height: 6)
                            .scaleEffect(ambientPulse ? 1.2 : 0.8)

                        Text(headerStatusSubtitle)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }

            Spacer()

            // Language Switcher Pill
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    store.language = isRTL ? "en" : "ar"
                }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isRTL ? "English" : "العربية")
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(AdminSurface.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.control, in: Capsule())
                .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
            }
            .buttonStyle(.plain)

            // Clear Chat Action
            if !store.messages.isEmpty {
                Button {
                    store.clearHistory()
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.control)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))

                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRTL ? "مسح المحادثة" : "Clear Chat")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            AdminSurface.surface.opacity(0.85)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var headerStatusSubtitle: String {
        switch store.state {
        case .idle:
            return isRTL ? "شريكك التشغيلي الذكي" : "Smart Operations Partner"
        case .loading:
            return isRTL ? "يراجع البيانات الحية..." : "Analyzing live data..."
        case .confirmationRequired:
            return isRTL ? "بانتظار موافقتك..." : "Awaiting approval..."
        case .denied, .error:
            return isRTL ? "تنبيه تشغيلي" : "Operational Alert"
        case .conflictStale:
            return isRTL ? "بيانات محدثة" : "Updated Records"
        default:
            return isRTL ? "شريكك التشغيلي الذكي" : "Smart Operations Partner"
        }
    }

    // MARK: - Living Avatar Beacon

    private func livingAvatarBeacon(size: CGFloat) -> some View {
        PuryAvatar(
            size: size,
            isLiving: true,
            isThinking: store.state == .loading,
            showStatusRing: size >= 32,
            showAmbientAura: size >= 32
        )
    }

    // MARK: - Context Indicator Strip

    private func contextIndicatorStrip(_ context: PuryScreenContext) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))

            Text(context.displayLabel)
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 16/255, green: 185/255, blue: 129/255))
                    .frame(width: 6, height: 6)

                Text(isRTL ? "سياق نشط" : "Active Context")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.06))
        .overlay(
            Rectangle()
                .fill(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.15))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Living Operational Radar (Reinvented Empty State)

    private var livingEmptyStateView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            // Radiant Synaptic Beacon Hero
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 16/255, green: 185/255, blue: 129/255).opacity(ambientPulse ? 0.24 : 0.08),
                                Color(red: 59/255, green: 130/255, blue: 246/255).opacity(ambientPulse ? 0.12 : 0.03),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 24,
                            endRadius: 85
                        )
                    )
                    .frame(width: 170, height: 170)

                livingAvatarBeacon(size: 72)
            }

            // Warm Executive Greeting & Mission Banner
            VStack(spacing: 8) {
                Text(executiveGreetingTitle)
                    .font(PPBrandFont.bold(size: 23, relativeTo: .title2))
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)

                Text(isRTL
                     ? "أنا هنا للإجابة فوراً عن إشغال الفندق، تنبيهات المخزون، أوامر التجهيز، ومؤشرات الأداء من واقع البيانات الحية المعتمدة."
                     : "Ready to assist with hotel occupancy, inventory radar, fulfillment queue, and platform sales from verified live data.")
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
            }

            // 4 Sculpted Operational Catalyst Pods (2 x 2)
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    operationalCatalystPod(
                        icon: "building.2.crop.circle.fill",
                        accentGradient: [Color(red: 16/255, green: 185/255, blue: 129/255), Color(red: 20/255, green: 184/255, blue: 166/255)],
                        badge: isRTL ? "🏨 الفندق النشط" : "🏨 Hotel Stays",
                        title: isRTL ? "حالة إشغال الفندق" : "Hotel Occupancy",
                        subtitle: isRTL ? "فحص الغرف والنزلاء" : "Live rooms & active stays",
                        prompt: isRTL ? "ما هي حالة الإشغال اليوم في فندق الحيوانات؟" : "What is the hotel occupancy and active stays today?"
                    )

                    operationalCatalystPod(
                        icon: "exclamationmark.triangle.fill",
                        accentGradient: [Color(red: 245/255, green: 158/255, blue: 11/255), Color(red: 239/255, green: 68/255, blue: 68/255)],
                        badge: isRTL ? "📦 رادار المخزون" : "📦 Low Stock",
                        title: isRTL ? "نواقص المخزون" : "Inventory Alerts",
                        subtitle: isRTL ? "المنتجات أوشكت على النفاد" : "Items reaching threshold",
                        prompt: isRTL ? "ما هي المنتجات التي أوشكت على النفاد في المتجر؟" : "What products are currently running low on stock?"
                    )
                }

                HStack(spacing: 12) {
                    operationalCatalystPod(
                        icon: "shippingbox.fill",
                        accentGradient: [Color(red: 59/255, green: 130/255, blue: 246/255), Color(red: 99/255, green: 102/255, blue: 241/255)],
                        badge: isRTL ? "🚚 أوامر التجهيز" : "🚚 Fulfillments",
                        title: isRTL ? "الطلبات المعلقة" : "Pending Orders",
                        subtitle: isRTL ? "جاهزية الشحن والتسليم" : "Orders awaiting dispatch",
                        prompt: isRTL ? "كم عدد الطلبات المعلقة بانتظار التجهيز والشحن؟" : "How many orders are awaiting fulfillment and shipping?"
                    )

                    operationalCatalystPod(
                        icon: "chart.line.uptrend.xyaxis",
                        accentGradient: [Color(red: 139/255, green: 92/255, blue: 246/255), Color(red: 236/255, green: 72/255, blue: 153/255)],
                        badge: isRTL ? "📊 نبض الأداء" : "📊 Performance",
                        title: isRTL ? "ملخص المبيعات" : "Weekly Metrics",
                        subtitle: isRTL ? "الإيرادات والنمو التشغيلي" : "Revenue & platform KPIs",
                        prompt: isRTL ? "قدم لي ملخصاً شاملاً لمؤشرات الأداء والمبيعات لهذا الأسبوع" : "Summarize platform sales and operational KPIs for this week"
                    )
                }
            }
            .padding(.horizontal, 4)

            // Quick Telemetry Accelerator Tray
            quickTelemetryTray

            Spacer(minLength: 32)
        }
    }

    private var executiveGreetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let isMorning = hour < 12
        if isRTL {
            return isMorning ? "صباح الخير! أنا بيوري 🐾" : "مساء الخير! أنا بيوري 🐾"
        } else {
            return isMorning ? "Good morning! I'm Pury 🐾" : "Good evening! I'm Pury 🐾"
        }
    }

    private func operationalCatalystPod(
        icon: String,
        accentGradient: [Color],
        badge: String,
        title: String,
        subtitle: String,
        prompt: String
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                await store.sendMessage(prompt, screenContext: screenContext)
            }
        } label: {
            VStack(alignment: isRTL ? .trailing : .leading, spacing: 10) {
                // Top Row: Icon squircle + Badge
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accentGradient.first?.opacity(0.18) ?? .clear, accentGradient.last?.opacity(0.10) ?? .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)

                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(accentGradient.first ?? AdminSurface.primary)
                    }

                    Spacer()

                    Text(badge)
                        .font(PPBrandFont.bold(size: 11, relativeTo: .caption2))
                        .foregroundStyle(accentGradient.first ?? AdminSurface.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((accentGradient.first ?? Color.gray).opacity(0.10), in: Capsule())
                }

                // Title and Subtitle
                VStack(alignment: isRTL ? .trailing : .leading, spacing: 3) {
                    Text(title)
                        .font(PPBrandFont.bold(size: 15, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(isRTL ? .trailing : .leading)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .multilineTextAlignment(isRTL ? .trailing : .leading)
                        .lineLimit(1)
                }

                // Action Prompt Cue
                HStack(spacing: 5) {
                    Text(isRTL ? "استعلام مباشر" : "Live Query")
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(accentGradient.first ?? AdminSurface.primary)

                    Image(systemName: isRTL ? "arrow.left" : "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accentGradient.first ?? AdminSurface.primary)
                }
                .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
            .background(
                AdminSurface.surface
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [accentGradient.first?.opacity(0.35) ?? AdminSurface.hairline, AdminSurface.hairline],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: (accentGradient.first ?? Color.black).opacity(0.06), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Telemetry Accelerator Tray

    private var quickTelemetryTray: some View {
        VStack(alignment: isRTL ? .trailing : .leading, spacing: 8) {
            Text(isRTL ? "استعلامات سريعة بنقرة واحدة" : "Instant Telemetry Accelerators")
                .font(PPBrandFont.medium(size: 12, relativeTo: .caption))
                .foregroundStyle(AdminSurface.secondaryText)
                .padding(.horizontal, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickTelemetryChip(
                        icon: "stethoscope",
                        title: isRTL ? "كادر الأطباء" : "Veterinarians",
                        prompt: isRTL ? "كم عدد الأطباء البيطريين المسجلين في النظام؟" : "How many veterinarians are registered in the system?"
                    )

                    quickTelemetryChip(
                        icon: "heart.circle.fill",
                        title: isRTL ? "طلبات التبني" : "Adoption Requests",
                        prompt: isRTL ? "ما هي أحدث طلبات التبني المسجلة؟" : "What are the latest adoption requests?"
                    )

                    quickTelemetryChip(
                        icon: "building.2.fill",
                        title: isRTL ? "نزلاء الفندق" : "Hotel Guests",
                        prompt: isRTL ? "ما هي قائمة الحيوانات المقيمة بالفندق حالياً؟" : "List active hotel guests currently staying."
                    )

                    quickTelemetryChip(
                        icon: "shippingbox.fill",
                        title: isRTL ? "جرد المخزون" : "Stock Audit",
                        prompt: isRTL ? "ملخص سريع لأهم أصناف المخزون المتوفرة" : "Quick audit summary of available product inventory."
                    )
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.top, 6)
    }

    private func quickTelemetryChip(icon: String, title: String, prompt: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                await store.sendMessage(prompt, screenContext: screenContext)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))

                Text(title)
                    .font(PPBrandFont.medium(size: 12, relativeTo: .caption))
                    .foregroundStyle(AdminSurface.primaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AdminSurface.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message Stream Rows

    @ViewBuilder
    private func messageStreamRow(for message: PuryMessage) -> some View {
        if message.role == .user {
            userMessageBubble(message)
        } else {
            puryMessageBubble(message)
        }
    }

    private func userMessageBubble(_ message: PuryMessage) -> some View {
        HStack {
            Spacer(minLength: 44)

            Text(message.text)
                .font(PPBrandFont.medium(size: 15, relativeTo: .body))
                .foregroundStyle(.white)
                .multilineTextAlignment(isRTL ? .trailing : .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 16/255, green: 185/255, blue: 129/255),
                            Color(red: 5/255, green: 150/255, blue: 105/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .shadow(color: Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.25), radius: 6, x: 0, y: 3)
        }
    }

    private func puryMessageBubble(_ message: PuryMessage) -> some View {
        VStack(alignment: isRTL ? .trailing : .leading, spacing: 12) {
            // Pury Identity Header
            HStack(spacing: 8) {
                livingAvatarBeacon(size: 24)

                Text(isRTL ? "بيوري" : "Pury")
                    .font(PPBrandFont.bold(size: 13, relativeTo: .caption))
                    .foregroundStyle(AdminSurface.primaryText)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 16/255, green: 185/255, blue: 129/255))
                        .frame(width: 5, height: 5)
                    Text(isRTL ? "بيانات حية" : "Live data")
                        .font(PPBrandFont.medium(size: 10, relativeTo: .caption2))
                        .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.12), in: Capsule())

                Spacer()

                // Copy Text Button
                if !message.text.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.text
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRTL ? "نسخ" : "Copy")
                }
            }

            // Category-Defining Dynamic Answer Orchestrator
            purySmartAnswerView(message)

            if let action = message.metadata?.confirmationAction,
               message.metadata?.confirmationRequired == true,
               store.activeProposal?.token == action.token {
                PuryActionConfirmationCard(
                    action: action,
                    onConfirm: {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        Task {
                            await store.confirmAction(action, screenContext: screenContext)
                        }
                    },
                    onCancel: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.cancelAction()
                    }
                )
            }
        }
    }

    // MARK: - Category-Defining Dynamic Answer Orchestrator

    private func purySmartAnswerView(_ message: PuryMessage) -> some View {
        let structured = message.metadata?.structuredData

        let validCards: [PuryCard] = (structured?.cards ?? []).filter { card in
            let title = card.cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasDetails = !(card.details?.isEmpty ?? true)
            return !title.isEmpty || hasDetails
        }

        let technicalFieldKeys: Set<String> = [
            "isdeleted", "deleted", "isblocked", "blocked", "accesskindtype", "kindtype", "kind_type",
            "showinappmarket", "visibleinapp", "show_in_app", "docid", "raw", "payload", "__name__",
            "fcmtoken", "createdatmillis", "updatedatmillis", "hash", "version"
        ]

        let validBlocks: [PuryDataBlock] = (structured?.dataBlocks ?? []).compactMap { block in
            let cleanFields = block.fields.filter { field in
                let key = field.cleanLabel.lowercased().replacingOccurrences(of: "_", with: "")
                return !technicalFieldKeys.contains(key)
            }
            guard !cleanFields.isEmpty else { return nil }
            return PuryDataBlock(id: block.id, type: block.type, collection: block.collection, fields: cleanFields)
        }

        return VStack(alignment: isRTL ? .trailing : .leading, spacing: 12) {
            // Model prose is always rendered as prose. Only server-generated
            // structuredData may become operational cards or record surfaces.
            if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(message.text)
                    .font(PPBrandFont.regular(size: 15, relativeTo: .body))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineSpacing(5)
                    .multilineTextAlignment(isRTL ? .trailing : .leading)
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                    .background(AdminSurface.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                    )
                    .accessibilityLabel(message.text)
            }

            if !validCards.isEmpty {
                VStack(spacing: 10) {
                    ForEach(validCards) { card in
                        semanticCardView(card)
                    }
                }
                .accessibilityElement(children: .contain)
            }

            if !validBlocks.isEmpty {
                VStack(spacing: 10) {
                    ForEach(validBlocks) { block in
                        PuryRecordCardView(block: block, isRTL: isRTL) { entityType, entityId in
                            handleDeepLink(entityType: entityType, entityId: entityId)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func telemetryGridView(_ items: [PuryTelemetryItem]) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                telemetryMetricCard(item)
            }
        }
    }

    private func telemetryMetricCard(_ item: PuryTelemetryItem) -> some View {
        Button {
            if let route = item.deepLinkRoute {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                handleDeepLink(entityType: route, entityId: "")
            }
        } label: {
            HStack(spacing: 12) {
                // Category Icon in Squircle
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(item.tint.opacity(0.14))
                        .frame(width: 42, height: 42)

                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(item.tint)
                }

                // Title and Subtitle
                VStack(alignment: isRTL ? .trailing : .leading, spacing: 2) {
                    Text(item.title)
                        .font(PPBrandFont.bold(size: 15, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(isRTL ? .trailing : .leading)
                        .lineLimit(1)

                    if let sub = item.subtitle {
                        Text(sub)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(isRTL ? .trailing : .leading)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Living Metric Count Badge
                let isZero = item.count == "0" || item.count == "٠"
                PuryInfoPill(item.count, tone: isZero ? .neutral : .emerald, isSmall: false)

                // Directional navigation chevron if deep link available
                if item.deepLinkRoute != nil {
                    Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                        .padding(.leading, 2)
                }
            }
            .padding(12)
            .background(AdminSurface.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func editorialAdvisoryCallout(_ noticeText: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 245/255, green: 158/255, blue: 11/255))
                .padding(.top, 2)

            Text(noticeText)
                .font(PPBrandFont.regular(size: 13, relativeTo: .footnote))
                .foregroundStyle(AdminSurface.secondaryText)
                .lineSpacing(4)
                .multilineTextAlignment(isRTL ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
        .background(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.25), lineWidth: 0.75)
        )
    }

    // MARK: - Domain Semantic Card View

    private func semanticCardView(_ card: PuryCard) -> some View {
        VStack(alignment: isRTL ? .trailing : .leading, spacing: 12) {
            // Header Row
            HStack(alignment: .top, spacing: 10) {
                // Card Category Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardIconColor(card).opacity(0.12))
                        .frame(width: 40, height: 40)

                    Image(systemName: cardIconName(card))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(cardIconColor(card))
                }

                VStack(alignment: isRTL ? .trailing : .leading, spacing: 3) {
                    Text(card.cleanTitle)
                        .font(PPBrandFont.bold(size: 15, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(isRTL ? .trailing : .leading)
                        .lineLimit(2)

                    if let sub = card.cleanSubtitle {
                        Text(sub)
                            .font(AdminType.caption1)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(isRTL ? .trailing : .leading)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if let badge = card.badge ?? card.status, !badge.isEmpty {
                    statusPill(badge)
                }
            }

            // Details Grid
            if let details = card.details, !details.isEmpty {
                Divider()
                    .overlay(AdminSurface.hairline)

                VStack(spacing: 8) {
                    ForEach(details) { field in
                        HStack {
                            Text(field.cleanLabel)
                                .font(AdminType.caption1)
                                .foregroundStyle(AdminSurface.secondaryText)
                            Spacer()
                            Text(field.cleanValue)
                                .font(PPBrandFont.medium(size: 13, relativeTo: .caption))
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                    }
                }
            }

            // Interactive Navigation CTA
            if let route = card.actionRoute ?? card.entityType, !route.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    handleDeepLink(entityType: route, entityId: card.entityId ?? "")
                } label: {
                    HStack(spacing: 6) {
                        Text(actionLabelForEntity(route))
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(AdminSurface.primary)

                        Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)

                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(AdminSurface.control)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private func cardIconName(_ card: PuryCard) -> String {
        let lower = (card.entityType ?? "").lowercased()
        if card.isHotelCard || lower.contains("hotel") || lower.contains("stay") { return "building.2.fill" }
        if card.isProductCard || lower.contains("product") || lower.contains("stock") || lower.contains("accessory") { return "shippingbox.fill" }
        if card.isOrderCard || lower.contains("order") { return "bag.fill" }
        if lower.contains("pet") || lower.contains("adopt") { return "pawprint.fill" }
        if lower.contains("vet") || lower.contains("staff") { return "stethoscope" }
        if lower.contains("user") { return "person.2.fill" }
        if lower.contains("branch") { return "mappin.and.ellipse" }
        return "doc.text.fill"
    }

    private func cardIconColor(_ card: PuryCard) -> Color {
        let lower = (card.entityType ?? "").lowercased()
        if card.isHotelCard || lower.contains("hotel") || lower.contains("stay") { return Color(red: 16/255, green: 185/255, blue: 129/255) }
        if card.isProductCard || lower.contains("product") || lower.contains("stock") || lower.contains("accessory") { return Color(red: 245/255, green: 158/255, blue: 11/255) }
        if card.isOrderCard || lower.contains("order") { return Color(red: 59/255, green: 130/255, blue: 246/255) }
        if lower.contains("pet") || lower.contains("adopt") { return Color(red: 236/255, green: 72/255, blue: 153/255) }
        if lower.contains("vet") || lower.contains("staff") { return Color(red: 20/255, green: 184/255, blue: 166/255) }
        if lower.contains("user") { return Color(red: 99/255, green: 102/255, blue: 241/255) }
        if lower.contains("branch") { return Color(red: 249/255, green: 115/255, blue: 22/255) }
        return Color(red: 139/255, green: 92/255, blue: 246/255)
    }

    private func actionLabelForEntity(_ entityType: String) -> String {
        let lower = entityType.lowercased()
        if lower.contains("hotel") || lower.contains("stay") {
            return isRTL ? "فتح لوحة تحكم الفندق" : "Open Hotel Dashboard"
        }
        if lower.contains("order") {
            return isRTL ? "عرض تفاصيل الطلب" : "View Order Details"
        }
        if lower.contains("product") || lower.contains("stock") || lower.contains("access") {
            return isRTL ? "إدارة المنتج في المخزن" : "Manage Product Stock"
        }
        if lower.contains("pet") || lower.contains("adopt") {
            return isRTL ? "عرض إعلانات الحيوانات" : "View Pet Listings"
        }
        if lower.contains("staff") || lower.contains("vet") {
            return isRTL ? "عرض الكادر الطبي" : "View Medical Staff"
        }
        if lower.contains("user") {
            return isRTL ? "عرض المستخدمين" : "View Users"
        }
        if lower.contains("branch") {
            return isRTL ? "عرض تفاصيل الفرع" : "View Branch Details"
        }
        return isRTL ? "فتح السجل في لوحة الإدارة" : "View Record in Admin"
    }

    private func statusPill(_ status: String) -> some View {
        let cleanStatus = PuryModelsSanitizer.cleanText(status)
        let lower = cleanStatus.lowercased()
        let tone: PuryPillTone
        if lower.contains("نشط") || lower.contains("مكتمل") || lower.contains("active") || lower.contains("متوفر") || lower.contains("متاح") {
            tone = .emerald
        } else if lower.contains("معلق") || lower.contains("حرج") || lower.contains("pending") || lower.contains("منخفض") {
            tone = .amber
        } else if lower.contains("ملغي") || lower.contains("نفد") || lower.contains("cancelled") || lower.contains("مرفوض") {
            tone = .crimson
        } else {
            tone = .emerald
        }
        return PuryInfoPill(cleanStatus, tone: tone, isSmall: true)
    }

    // MARK: - Thinking Bubble

    private var thinkingBubble: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color(red: 16/255, green: 185/255, blue: 129/255))
                .scaleEffect(0.9)

            Text(isRTL ? "بيوري يراجع البيانات المصرح بها ويجهز الإجابة..." : "Pury is analyzing authorized records...")
                .font(PPBrandFont.medium(size: 13, relativeTo: .caption))
                .foregroundStyle(AdminSurface.secondaryText)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Floating Input Dock

    private var floatingInputDock: some View {
        VStack(spacing: 8) {
            // Contextual Suggestion Pills (if in chat)
            if !store.messages.isEmpty && store.state == .idle {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        suggestionChip(isRTL ? "🏨 إشغال الفندق" : "🏨 Hotel Occupancy")
                        suggestionChip(isRTL ? "📦 نواقص المخزون" : "📦 Low Stock")
                        suggestionChip(isRTL ? "🚚 الطلبات المعلقة" : "🚚 Pending Orders")
                        suggestionChip(isRTL ? "📊 المبيعات اليوم" : "📊 Today's Sales")
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Glass Input Pill Container
            HStack(spacing: 10) {
                // Text Field
                TextField(
                    isRTL ? "اسأل بيوري عن أي تفاصيل تشغيلية..." : "Ask Pury any operational question...",
                    text: $store.currentInputText,
                    axis: .vertical
                )
                .font(PPBrandFont.regular(size: 15, relativeTo: .body))
                .multilineTextAlignment(isRTL ? .trailing : .leading)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit {
                    submitInput()
                }

                // Send Button with Kinetic Glow
                Button {
                    submitInput()
                } label: {
                    let hasText = !store.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ZStack {
                        Circle()
                            .fill(
                                hasText && store.state != .loading
                                    ? LinearGradient(
                                        colors: [Color(red: 16/255, green: 185/255, blue: 129/255), Color(red: 5/255, green: 150/255, blue: 105/255)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [AdminSurface.control, AdminSurface.control],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                            .frame(width: 42, height: 42)
                            .shadow(
                                color: hasText ? Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.35) : Color.clear,
                                radius: 6,
                                x: 0,
                                y: 3
                            )

                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(hasText && store.state != .loading ? .white : AdminSurface.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                .disabled(store.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.state == .loading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                AdminSurface.surface.opacity(0.95)
                    .background(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(isInputFocused ? Color(red: 16/255, green: 185/255, blue: 129/255) : AdminSurface.hairline, lineWidth: isInputFocused ? 1.5 : 0.75)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func suggestionChip(_ label: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.currentInputText = label
            submitInput()
        } label: {
            Text(label)
                .font(PPBrandFont.medium(size: 12, relativeTo: .caption))
                .foregroundStyle(AdminSurface.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AdminSurface.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions & Navigation

    private func submitInput() {
        let text = store.currentInputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isInputFocused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await store.sendMessage(text, screenContext: screenContext)
        }
    }

    private func scrollToLatest(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if store.state == .loading {
                proxy.scrollTo("pury_thinking_bubble", anchor: .bottom)
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
        case "petaccessories", "product", "accessories":
            router.presentedRoute = .accessories
        case "livepet", "livepets":
            router.presentedRoute = .livePets
        case "hotel", "stay", "reservation", "hotelstays":
            router.presentedRoute = .hotel
        case "userscol", "user", "users":
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

// MARK: - Category-Defining Living Info Pill & Status Capsule

public enum PuryPillTone: Sendable {
    case emerald
    case amber
    case crimson
    case cobalt
    case violet
    case currency
    case neutral

    public var tintColor: Color {
        switch self {
        case .emerald: return Color(red: 16/255, green: 185/255, blue: 129/255)
        case .amber: return Color(red: 245/255, green: 158/255, blue: 11/255)
        case .crimson: return Color(red: 239/255, green: 68/255, blue: 68/255)
        case .cobalt: return Color(red: 59/255, green: 130/255, blue: 246/255)
        case .violet: return Color(red: 139/255, green: 92/255, blue: 246/255)
        case .currency: return Color(red: 16/255, green: 185/255, blue: 129/255)
        case .neutral: return AdminSurface.secondaryText
        }
    }
}

public struct PuryInfoPill: View {
    public let text: String
    public let icon: String?
    public let tone: PuryPillTone
    public let isPulse: Bool
    public let copyable: Bool
    public let isSmall: Bool

    @State private var copied: Bool = false

    public init(
        _ text: String,
        icon: String? = nil,
        tone: PuryPillTone = .neutral,
        isPulse: Bool = false,
        copyable: Bool = false,
        isSmall: Bool = false
    ) {
        self.text = text
        self.icon = icon
        self.tone = tone
        self.isPulse = isPulse
        self.copyable = copyable
        self.isSmall = isSmall
    }

    public var body: some View {
        Button {
            guard copyable else { return }
            UIPasteboard.general.string = text
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                copied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { copied = false }
            }
        } label: {
            HStack(spacing: 5) {
                if copied {
                    Image(systemName: "checkmark")
                        .font(.system(size: isSmall ? 9 : 11, weight: .bold))
                        .foregroundStyle(tone.tintColor)
                } else if isPulse {
                    Circle()
                        .fill(tone.tintColor)
                        .frame(width: isSmall ? 5 : 6, height: isSmall ? 5 : 6)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: isSmall ? 9 : 11, weight: .bold))
                        .foregroundStyle(tone.tintColor)
                }

                Text(text)
                    .font(PPBrandFont.bold(size: isSmall ? 11 : 13, relativeTo: isSmall ? .caption2 : .caption))
                    .foregroundStyle(tone.tintColor)

                if copyable && !copied {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(tone.tintColor.opacity(0.6))
                }
            }
            .padding(.horizontal, isSmall ? 8 : 12)
            .padding(.vertical, isSmall ? 4 : 6)
            .background(tone.tintColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tone.tintColor.opacity(0.28), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .disabled(!copyable)
    }
}

// MARK: - Living Product Stock Showcase Card

public struct PuryProductItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let quantity: Int
    public let price: String?
    public let category: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        quantity: Int,
        price: String? = nil,
        category: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.quantity = quantity
        self.price = price
        self.category = category
    }
}

public struct PuryProductCardView: View {
    public let product: PuryProductItem
    public let isRTL: Bool
    public let onManageStock: () -> Void

    public var body: some View {
        VStack(alignment: isRTL ? .trailing : .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Category Squircle Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(productIconColor.opacity(0.14))
                        .frame(width: 44, height: 44)

                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(productIconColor)
                }

                // Title & Category
                VStack(alignment: isRTL ? .trailing : .leading, spacing: 3) {
                    Text(product.title)
                        .font(PPBrandFont.bold(size: 16, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(isRTL ? .trailing : .leading)
                        .lineLimit(2)

                    if let sub = product.subtitle ?? product.category {
                        Text(sub)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(isRTL ? .trailing : .leading)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Price Capsule
                if let price = product.price, !price.isEmpty {
                    PuryInfoPill(price, tone: .currency, isSmall: false)
                }
            }

            // Stock Urgency & Visual Filament
            VStack(alignment: isRTL ? .trailing : .leading, spacing: 6) {
                HStack {
                    stockStatusPill
                    Spacer()
                    Text(stockStatusLabel)
                        .font(AdminType.caption2Medium)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                // Visual Filament Bar
                GeometryReader { geo in
                    ZStack(alignment: isRTL ? .trailing : .leading) {
                        Capsule()
                            .fill(AdminSurface.hairline.opacity(0.8))
                            .frame(height: 5)

                        Capsule()
                            .fill(stockFilamentColor)
                            .frame(width: max(8, geo.size.width * stockFillPercentage), height: 5)
                    }
                }
                .frame(height: 5)
            }

            Divider()
                .overlay(AdminSurface.hairline)

            // Direct 1-Tap Stock Action
            Button(action: onManageStock) {
                HStack(spacing: 6) {
                    Text(isRTL ? "إدارة المنتج في المخزن" : "Manage Product Stock")
                        .font(AdminType.caption1Bold)
                        .foregroundStyle(AdminSurface.primary)

                    Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)

                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
    }

    private var productIconColor: Color {
        if product.quantity == 0 { return Color(red: 239/255, green: 68/255, blue: 68/255) }
        if product.quantity <= 3 { return Color(red: 245/255, green: 158/255, blue: 11/255) }
        return Color(red: 16/255, green: 185/255, blue: 129/255)
    }

    private var stockFilamentColor: Color {
        if product.quantity == 0 { return Color(red: 239/255, green: 68/255, blue: 68/255) }
        if product.quantity <= 3 { return Color(red: 245/255, green: 158/255, blue: 11/255) }
        return Color(red: 16/255, green: 185/255, blue: 129/255)
    }

    private var stockFillPercentage: CGFloat {
        if product.quantity == 0 { return 0.05 }
        if product.quantity <= 3 { return CGFloat(product.quantity) / 10.0 }
        return min(1.0, CGFloat(product.quantity) / 20.0)
    }

    private var stockStatusPill: some View {
        if product.quantity == 0 {
            return PuryInfoPill(isRTL ? "نفد من المخزون" : "Out of Stock", tone: .crimson, isSmall: true)
        } else if product.quantity <= 3 {
            return PuryInfoPill(isRTL ? "مخزون حرج" : "Low Stock", tone: .amber, isPulse: true, isSmall: true)
        } else {
            return PuryInfoPill(isRTL ? "متوفر" : "In Stock", tone: .emerald, isSmall: true)
        }
    }

    private var stockStatusLabel: String {
        if product.quantity == 0 {
            return isRTL ? "0 وحدات متبقية" : "0 units remaining"
        } else {
            return isRTL ? "\(product.quantity) وحدات متوفرة" : "\(product.quantity) units available"
        }
    }
}

// MARK: - Sculpted Operational Record Card

public struct PuryRecordCardView: View {
    public let block: PuryDataBlock
    public let isRTL: Bool
    public var onDeepLink: ((String, String) -> Void)? = nil
    @State private var isExpanded: Bool = false

    public var body: some View {
        VStack(alignment: isRTL ? .trailing : .leading, spacing: 10) {
            // Header with block collection or type
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 99/255, green: 102/255, blue: 241/255).opacity(0.12))
                        .frame(width: 32, height: 32)

                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 99/255, green: 102/255, blue: 241/255))
                }

                Text(blockTitle)
                    .font(PPBrandFont.bold(size: 14, relativeTo: .subheadline))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                PuryInfoPill("#\(block.id.prefix(6))", tone: .cobalt, copyable: true, isSmall: true)
            }

            Divider()
                .overlay(AdminSurface.hairline)

            // Filtered Human Fields
            let visibleFields = isExpanded ? block.fields : Array(block.fields.prefix(4))
            VStack(spacing: 8) {
                ForEach(visibleFields) { field in
                    HStack(alignment: .center) {
                        Text(localizedLabel(field.cleanLabel))
                            .font(AdminType.caption1)
                            .foregroundStyle(AdminSurface.secondaryText)

                        Spacer()

                        fieldValueView(field)
                    }
                }
            }

            // Progressive Disclosure
            if block.fields.count > 4 {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded
                            ? (isRTL ? "إخفاء التفاصيل" : "Show less")
                            : (isRTL ? "عرض المزيد (+\(block.fields.count - 4))" : "Show more (+\(block.fields.count - 4))")
                        )
                        .font(PPBrandFont.medium(size: 12, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.primary)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }

            // Interactive Navigation Action if route available
            if let actionTitle = actionTitleForBlock(block) {
                Divider()
                    .overlay(AdminSurface.hairline)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDeepLink?(block.collection ?? block.type, block.id)
                } label: {
                    HStack(spacing: 6) {
                        Text(actionTitle)
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(AdminSurface.primary)

                        Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AdminSurface.control)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var blockTitle: String {
        if let col = block.collection, !col.isEmpty {
            return localizedCollectionName(col)
        }
        return isRTL ? "بيانات السجل" : "Record Details"
    }

    private func localizedCollectionName(_ col: String) -> String {
        guard isRTL else { return col }
        let lower = col.lowercased()
        if lower.contains("access") || lower.contains("product") { return "منتج المخزن" }
        if lower.contains("hotel") || lower.contains("stay") { return "إقامة فندقية" }
        if lower.contains("order") { return "أمر شراء" }
        if lower.contains("user") { return "ملف المستخدم" }
        if lower.contains("branch") { return "بيانات الفرع" }
        if lower.contains("staff") || lower.contains("vet") { return "الكادر الطبي" }
        return col
    }

    private func localizedLabel(_ label: String) -> String {
        guard isRTL else { return label }
        let lower = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "price": return "السعر"
        case "quantity", "stock": return "الكمية المتوفرة"
        case "status": return "الحالة"
        case "category": return "التصنيف"
        case "name", "title": return "الاسم"
        case "description": return "الوصف"
        case "phone", "phonenumber": return "رقم الهاتف"
        case "email": return "البريد الإلكتروني"
        case "createdat", "created_at": return "تاريخ الإنشاء"
        case "updatedat", "updated_at": return "آخر تحديث"
        default: return label
        }
    }

    private func actionTitleForBlock(_ block: PuryDataBlock) -> String? {
        let target = (block.collection ?? block.type).lowercased()
        if target.contains("access") || target.contains("product") {
            return isRTL ? "إدارة هذا المنتج في المخزن" : "Manage Product in Catalog"
        }
        if target.contains("hotel") || target.contains("stay") {
            return isRTL ? "فتح تفاصيل الإقامة الفندقية" : "View Hotel Stay Details"
        }
        if target.contains("order") {
            return isRTL ? "عرض تفاصيل الطلب" : "View Order Details"
        }
        if target.contains("user") {
            return isRTL ? "عرض ملف المستخدم" : "View User Profile"
        }
        if target.contains("branch") {
            return isRTL ? "عرض تفاصيل الفرع" : "View Branch Details"
        }
        return isRTL ? "عرض السجل في لوحة الإدارة" : "View Record in Admin"
    }

    @ViewBuilder
    private func fieldValueView(_ field: PuryField) -> some View {
        let val = field.cleanValue
        let valLower = val.lowercased()

        if val.contains("ر.ق") || val.contains("QAR") || val.contains("ريال") || field.cleanLabel.lowercased().contains("price") {
            PuryInfoPill(val, tone: .currency, isSmall: true)
        } else if ["active", "نشط", "مكتمل", "completed", "متاح", "available", "true"].contains(valLower) {
            PuryInfoPill(valLower == "true" ? (isRTL ? "مفعّل" : "Active") : val, tone: .emerald, isSmall: true)
        } else if ["pending", "معلق", "قيد الانتظار", "draft", "مسودة"].contains(valLower) {
            PuryInfoPill(val, tone: .amber, isSmall: true)
        } else if ["cancelled", "ملغي", "مرفوض", "rejected", "out_of_stock", "نفد", "false"].contains(valLower) {
            PuryInfoPill(valLower == "false" ? (isRTL ? "معطّل" : "Disabled") : val, tone: .crimson, isSmall: true)
        } else {
            Text(val)
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(isRTL ? .trailing : .leading)
        }
    }
}

// MARK: - High-Craft Native Markdown Table Card

public struct PuryTableData: Identifiable, Equatable {
    public let id: String = UUID().uuidString
    public let headers: [String]
    public let rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }
}

public struct PuryMarkdownTableCard: View {
    public let table: PuryTableData
    public let isRTL: Bool

    public var body: some View {
        VStack(alignment: isRTL ? .trailing : .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header Row
                    HStack(spacing: 0) {
                        ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                            Text(header)
                                .font(PPBrandFont.bold(size: 13, relativeTo: .caption))
                                .foregroundStyle(AdminSurface.primaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(minWidth: 100, alignment: isRTL ? .trailing : .leading)

                            if index < table.headers.count - 1 {
                                Divider().overlay(AdminSurface.hairline)
                            }
                        }
                    }
                    .background(AdminSurface.control.opacity(0.8))

                    Divider().overlay(AdminSurface.hairline)

                    // Data Rows
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                                Text(cell)
                                    .font(PPBrandFont.regular(size: 13, relativeTo: .caption))
                                    .foregroundStyle(AdminSurface.primaryText)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(minWidth: 100, alignment: isRTL ? .trailing : .leading)

                                if colIndex < row.count - 1 {
                                    Divider().overlay(AdminSurface.hairline.opacity(0.5))
                                }
                            }
                        }
                        .background(rowIndex % 2 == 1 ? AdminSurface.control.opacity(0.25) : AdminSurface.surface)

                        if rowIndex < table.rows.count - 1 {
                            Divider().overlay(AdminSurface.hairline.opacity(0.35))
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }
}

// MARK: - Studio Content & Telemetry Engine

public struct PuryTelemetryItem: Identifiable, Equatable {
    public let id: String = UUID().uuidString
    public let title: String
    public let subtitle: String?
    public let count: String
    public let icon: String
    public let tint: Color
    public let collectionKey: String?
    public let deepLinkRoute: String?

    public init(
        title: String,
        subtitle: String? = nil,
        count: String,
        icon: String,
        tint: Color,
        collectionKey: String? = nil,
        deepLinkRoute: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.count = count
        self.icon = icon
        self.tint = tint
        self.collectionKey = collectionKey
        self.deepLinkRoute = deepLinkRoute
    }
}

public struct PuryParsedMessageContent {
    public let introNarrative: String?
    public let products: [PuryProductItem]
    public let tables: [PuryTableData]
    public let telemetryItems: [PuryTelemetryItem]
    public let advisoryNotices: [String]
    public let outroNotice: String?
    public let cleanFullText: String

    public init(
        introNarrative: String?,
        products: [PuryProductItem],
        tables: [PuryTableData],
        telemetryItems: [PuryTelemetryItem],
        advisoryNotices: [String],
        outroNotice: String?,
        cleanFullText: String
    ) {
        self.introNarrative = introNarrative
        self.products = products
        self.tables = tables
        self.telemetryItems = telemetryItems
        self.advisoryNotices = advisoryNotices
        self.outroNotice = outroNotice
        self.cleanFullText = cleanFullText
    }
}

public enum PuryContentParser {
    public static func parse(_ rawText: String, isRTL: Bool) -> PuryParsedMessageContent {
        let lines = rawText.components(separatedBy: .newlines)
        var introLines: [String] = []
        var outroLines: [String] = []
        var products: [PuryProductItem] = []
        var tables: [PuryTableData] = []
        var telemetryItems: [PuryTelemetryItem] = []
        var advisoryNotices: [String] = []
        var foundStructuredItem = false

        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                i += 1
                continue
            }

            // 1. Table Detection
            if line.contains("|") {
                var tableLines: [String] = []
                while i < lines.count && lines[i].contains("|") {
                    let tLine = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !tLine.isEmpty {
                        tableLines.append(tLine)
                    }
                    i += 1
                }
                if let table = parseMarkdownTable(tableLines) {
                    foundStructuredItem = true
                    tables.append(table)
                } else {
                    for tl in tableLines {
                        if foundStructuredItem { outroLines.append(cleanMarkdown(tl)) }
                        else { introLines.append(cleanMarkdown(tl)) }
                    }
                }
                continue
            }

            // 2. Advisory / Notice Detection (💡, ⚠️, ملاحظة, تنبيه)
            if isAdvisoryNoticeLine(line) {
                let cleanNotice = cleanMarkdown(line)
                if !cleanNotice.isEmpty {
                    advisoryNotices.append(cleanNotice)
                }
                i += 1
                continue
            }

            // 3. Product with Stock & Price Detection
            if let product = parseProductLine(line, isRTL: isRTL) {
                foundStructuredItem = true
                products.append(product)
                i += 1
                continue
            }

            // 4. Metric Telemetry Line Detection
            if let metric = parseMetricLine(line, isRTL: isRTL) {
                foundStructuredItem = true
                telemetryItems.append(metric)
                i += 1
                continue
            }

            // 5. Conversational narrative line
            let cleaned = cleanMarkdown(line)
            if !cleaned.isEmpty {
                if foundStructuredItem {
                    outroLines.append(cleaned)
                } else {
                    introLines.append(cleaned)
                }
            }
            i += 1
        }

        let intro = introLines.isEmpty ? nil : introLines.joined(separator: "\n")
        let outro = outroLines.isEmpty ? nil : outroLines.joined(separator: "\n")
        let full = cleanMarkdown(rawText)

        return PuryParsedMessageContent(
            introNarrative: intro,
            products: products,
            tables: tables,
            telemetryItems: telemetryItems,
            advisoryNotices: advisoryNotices,
            outroNotice: outro,
            cleanFullText: full
        )
    }

    private static func isAdvisoryNoticeLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("ملاحظة") || lower.contains("تنبيه") || lower.contains("تنويه") ||
           lower.contains("💡") || lower.contains("⚠️") || lower.contains("note:") || lower.contains("warning:") {
            return true
        }
        return false
    }

    private static func parseProductLine(_ line: String, isRTL: Bool) -> PuryProductItem? {
        guard line.hasPrefix("*") || line.hasPrefix("-") || line.hasPrefix("•") else {
            return nil
        }

        var text = line
        if text.hasPrefix("*") || text.hasPrefix("-") || text.hasPrefix("•") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        let parts = text.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }

        let rawKey = parts[0].trimmingCharacters(in: .whitespaces)
        let rawVal = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)

        let title = cleanMarkdown(rawKey)
        let cleanVal = cleanMarkdown(rawVal)

        // Check if value contains product stock or pricing keywords
        let lowerVal = cleanVal.lowercased()
        let hasStock = lowerVal.contains("متوفر") || lowerVal.contains("وحدات") || lowerVal.contains("وحدة") ||
                       lowerVal.contains("قطعة") || lowerVal.contains("كمية") || lowerVal.contains("مخزون") ||
                       lowerVal.contains("نفد") || lowerVal.contains("available") || lowerVal.contains("stock")
        let hasPrice = lowerVal.contains("ر.ق") || lowerVal.contains("ريال") || lowerVal.contains("qar") ||
                       lowerVal.contains("qr") || lowerVal.contains("بسعر") || lowerVal.contains("سعر") ||
                       lowerVal.contains("price")

        guard hasStock || hasPrice else { return nil }

        // Extract quantity:
        var quantity = 0
        if lowerVal.contains("نفد") {
            quantity = 0
        } else {
            let patterns = [
                #"(?:متوفر|الكمية|مخزون|stock)\s*:?\s*(\d+)"#,
                #"(\d+)\s*(?:وحدة|وحدات|قطع|قطعة|units)"#
            ]
            for pat in patterns {
                if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
                   let match = regex.firstMatch(in: cleanVal, options: [], range: NSRange(location: 0, length: cleanVal.utf16.count)),
                   match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: cleanVal),
                   let qty = Int(cleanVal[range]) {
                    quantity = qty
                    break
                }
            }
        }

        // Extract price:
        var priceString: String? = nil
        let pricePattern = #"(?:بسعر|سعر)?\s*(\d+(?:\.\d+)?)\s*(ر\.ق|ريال|QAR|qr)?"#
        if let regex = try? NSRegularExpression(pattern: pricePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: cleanVal, options: [], range: NSRange(location: 0, length: cleanVal.utf16.count)),
           let fullRange = Range(match.range(at: 0), in: cleanVal) {
            let matchedPrice = cleanVal[fullRange].trimmingCharacters(in: .whitespaces)
            if matchedPrice.contains("ر.ق") || matchedPrice.contains("ريال") || matchedPrice.contains("QAR") {
                priceString = matchedPrice.replacingOccurrences(of: "بسعر", with: "").trimmingCharacters(in: .whitespaces)
            } else if let numRange = Range(match.range(at: 1), in: cleanVal) {
                let num = cleanVal[numRange]
                priceString = isRTL ? "\(num) ر.ق." : "\(num) QAR"
            }
        }

        return PuryProductItem(
            title: title,
            quantity: quantity,
            price: priceString,
            category: isRTL ? "مخزون المتجر" : "Store Catalog"
        )
    }

    private static func parseMetricLine(_ line: String, isRTL: Bool) -> PuryTelemetryItem? {
        guard line.hasPrefix("*") || line.hasPrefix("-") || line.hasPrefix("•") else {
            return nil
        }

        var text = line
        if text.hasPrefix("*") || text.hasPrefix("-") || text.hasPrefix("•") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        let parts = text.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }

        let rawKey = parts[0].trimmingCharacters(in: .whitespaces)
        let rawVal = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)

        let count = cleanMarkdown(rawVal).trimmingCharacters(in: .whitespaces)
        guard !count.isEmpty else { return nil }

        // Must be a genuine short metric (max 25 characters)
        guard count.count <= 25 else { return nil }

        let cleanKey = cleanMarkdown(rawKey)

        var collectionKey: String? = nil
        var displayTitle = cleanKey

        if let openParen = cleanKey.range(of: "("),
           let closeParen = cleanKey.range(of: ")", range: openParen.upperBound..<cleanKey.endIndex) {
            let inside = String(cleanKey[openParen.upperBound..<closeParen.lowerBound]).trimmingCharacters(in: .whitespaces)
            collectionKey = inside.lowercased()
            let beforeParen = String(cleanKey[..<openParen.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !beforeParen.isEmpty {
                displayTitle = beforeParen
            }
        }

        let meta = resolveCollectionMetadata(collectionKey: collectionKey, title: displayTitle, isRTL: isRTL)

        return PuryTelemetryItem(
            title: meta.title,
            subtitle: meta.subtitle,
            count: count,
            icon: meta.icon,
            tint: meta.tint,
            collectionKey: collectionKey,
            deepLinkRoute: meta.deepLinkRoute
        )
    }

    private static func parseMarkdownTable(_ lines: [String]) -> PuryTableData? {
        guard lines.count >= 2 else { return nil }

        // Parse header row
        let headerRow = lines[0].components(separatedBy: "|")
            .map { cleanMarkdown($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !headerRow.isEmpty else { return nil }

        // Find data rows (skip delimiter line)
        var rows: [[String]] = []
        for line in lines.dropFirst() {
            if line.contains("---") { continue }

            let cols = line.components(separatedBy: "|")
                .map { cleanMarkdown($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if !cols.isEmpty {
                rows.append(cols)
            }
        }

        guard !rows.isEmpty else { return nil }
        return PuryTableData(headers: headerRow, rows: rows)
    }

    private static func resolveCollectionMetadata(
        collectionKey: String?,
        title: String,
        isRTL: Bool
    ) -> (title: String, subtitle: String?, icon: String, tint: Color, deepLinkRoute: String?) {
        let key = (collectionKey ?? "").lowercased()
        let lowerTitle = title.lowercased()

        if key.contains("vet") || lowerTitle.contains("بيطر") || lowerTitle.contains("أطباء") || lowerTitle.contains("طبيب") {
            return (
                title: isRTL ? "الأطباء البيطريون" : "Veterinarians",
                subtitle: isRTL ? "كادر طبي معتمد" : "Certified Medical Staff",
                icon: "stethoscope",
                tint: Color(red: 20/255, green: 184/255, blue: 166/255),
                deepLinkRoute: "staff"
            )
        } else if key.contains("pet_ad") || key.contains("petad") || lowerTitle.contains("إعلان") || lowerTitle.contains("اعلان") {
            return (
                title: isRTL ? "إعلانات الحيوانات" : "Pet Listings",
                subtitle: isRTL ? "إعلانات منشورة" : "Active Listings",
                icon: "pawprint.fill",
                tint: Color(red: 245/255, green: 158/255, blue: 11/255),
                deepLinkRoute: "livePets"
            )
        } else if key.contains("service") || lowerTitle.contains("خدمات") || lowerTitle.contains("خدمة") {
            return (
                title: isRTL ? "عروض الخدمات" : "Service Offers",
                subtitle: isRTL ? "باقات مفعّلة" : "Active Service Packages",
                icon: "sparkles.rectangle.stack.fill",
                tint: Color(red: 139/255, green: 92/255, blue: 246/255),
                deepLinkRoute: "hotel"
            )
        } else if key.contains("adopt") || lowerTitle.contains("تبني") {
            return (
                title: isRTL ? "طلبات التبني" : "Adoption Requests",
                subtitle: isRTL ? "حيوانات مؤهلة" : "Eligible for Adoption",
                icon: "heart.circle.fill",
                tint: Color(red: 236/255, green: 72/255, blue: 153/255),
                deepLinkRoute: "livePets"
            )
        } else if key.contains("accessory") || key.contains("product") || key.contains("stock") || lowerTitle.contains("منتج") || lowerTitle.contains("مخزون") {
            return (
                title: isRTL ? "منتجات المتجر" : "Store Products",
                subtitle: isRTL ? "المخزون المسجل" : "Catalog Inventory",
                icon: "shippingbox.fill",
                tint: Color(red: 59/255, green: 130/255, blue: 246/255),
                deepLinkRoute: "accessories"
            )
        } else if key.contains("order") || lowerTitle.contains("طلب") {
            return (
                title: isRTL ? "أوامر الشراء" : "Orders Queue",
                subtitle: isRTL ? "طلبات معتمدة" : "Active Orders",
                icon: "bag.fill",
                tint: Color(red: 16/255, green: 185/255, blue: 129/255),
                deepLinkRoute: "orders"
            )
        } else if key.contains("hotel") || key.contains("stay") || lowerTitle.contains("فندق") || lowerTitle.contains("إقامة") {
            return (
                title: isRTL ? "إشغال الفندق" : "Hotel Stays",
                subtitle: isRTL ? "نزلاء حاليون" : "Current Guests",
                icon: "building.2.fill",
                tint: Color(red: 16/255, green: 185/255, blue: 129/255),
                deepLinkRoute: "hotel"
            )
        } else if key.contains("user") || lowerTitle.contains("مستخدم") {
            return (
                title: isRTL ? "المستخدمين" : "Registered Users",
                subtitle: isRTL ? "حسابات نشطة" : "Platform Accounts",
                icon: "person.2.fill",
                tint: Color(red: 99/255, green: 102/255, blue: 241/255),
                deepLinkRoute: "users"
            )
        } else if key.contains("branch") || lowerTitle.contains("فرع") {
            return (
                title: isRTL ? "فروع بيور بيتس" : "Branches",
                subtitle: isRTL ? "مواقع تشغيلية" : "Active Locations",
                icon: "mappin.and.ellipse",
                tint: Color(red: 249/255, green: 115/255, blue: 22/255),
                deepLinkRoute: "branches"
            )
        }

        return (
            title: title.isEmpty ? (collectionKey ?? (isRTL ? "عنصر تشغيلي" : "Operational Metric")) : title,
            subtitle: collectionKey,
            icon: "chart.bar.fill",
            tint: Color(red: 16/255, green: 185/255, blue: 129/255),
            deepLinkRoute: nil
        )
    }

    public static func cleanMarkdown(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        if result.hasPrefix("* ") || result.hasPrefix("- ") || result.hasPrefix("• ") {
            result = String(result.dropFirst(2))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
