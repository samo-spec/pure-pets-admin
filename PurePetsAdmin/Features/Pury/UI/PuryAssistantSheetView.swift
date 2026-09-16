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
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text("AI")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
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
        ZStack {
            // Pulsing Wave Ring
            Circle()
                .strokeBorder(
                    (store.state == .loading ? Color(red: 139/255, green: 92/255, blue: 246/255) : Color(red: 16/255, green: 185/255, blue: 129/255)).opacity(ambientPulse ? 0.35 : 0.08),
                    lineWidth: 1.5
                )
                .frame(width: size + (ambientPulse ? 10 : 2), height: size + (ambientPulse ? 10 : 2))

            // Secondary Filament Aura
            Circle()
                .strokeBorder(
                    Color.white.opacity(0.15),
                    lineWidth: 0.75
                )
                .frame(width: size + 4, height: size + 4)

            // Main Core Orb
            Circle()
                .fill(
                    LinearGradient(
                        colors: store.state == .loading
                            ? [Color(red: 139/255, green: 92/255, blue: 246/255), Color(red: 6/255, green: 182/255, blue: 212/255)]
                            : [Color(red: 16/255, green: 185/255, blue: 129/255), Color(red: 5/255, green: 150/255, blue: 105/255)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(
                    color: (store.state == .loading ? Color(red: 139/255, green: 92/255, blue: 246/255) : Color(red: 16/255, green: 185/255, blue: 129/255)).opacity(0.4),
                    radius: 8,
                    x: 0,
                    y: 3
                )

            // Sparkle Core Icon
            Image(systemName: store.state == .loading ? "rays" : "sparkles")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(store.state == .loading ? (avatarShimmer ? 360 : 0) : 0))
        }
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
                    .font(.system(size: 11, weight: .bold))
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
                    .font(.system(size: 23, weight: .bold, design: .rounded))
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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(accentGradient.first ?? AdminSurface.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((accentGradient.first ?? Color.gray).opacity(0.10), in: Capsule())
                }

                // Title and Subtitle
                VStack(alignment: isRTL ? .trailing : .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
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
                .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                .font(.system(size: 15, weight: .medium, design: .rounded))
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
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AdminSurface.primaryText)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 16/255, green: 185/255, blue: 129/255))
                        .frame(width: 5, height: 5)
                    Text(isRTL ? "بيانات حية" : "Live data")
                        .font(.system(size: 10, weight: .semibold))
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

            // High-Craft Studio Telemetry & Content Renderer
            if !message.text.isEmpty {
                puryParsedContentView(message.text)
            }

            // Studio Semantic Cards
            if let structured = message.metadata?.structuredData {
                if let cards = structured.cards, !cards.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(cards) { card in
                            semanticCardView(card)
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

            // Confirmation Proposal Action (Tier 3)
            if let action = message.metadata?.confirmationAction,
               message.metadata?.confirmationRequired == true,
               store.activeProposal?.token == action.token {
                tactileConfirmationCard(action)
            }
        }
    }

    // MARK: - Studio Content & Telemetry Renderer

    private func puryParsedContentView(_ rawText: String) -> some View {
        let parsed = PuryContentParser.parse(rawText, isRTL: isRTL)

        return VStack(alignment: isRTL ? .trailing : .leading, spacing: 12) {
            if !parsed.telemetryItems.isEmpty {
                // Intro narrative if any
                if let intro = parsed.introNarrative, !intro.isEmpty {
                    Text(intro)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineSpacing(4)
                        .multilineTextAlignment(isRTL ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                }

                // Studio Telemetry Grid
                telemetryGridView(parsed.telemetryItems)

                // Outro advisory callout if any
                if let outro = parsed.outroNotice, !outro.isEmpty {
                    editorialAdvisoryCallout(outro)
                }
            } else {
                // Standard Conversational Text Bubble
                Text(parsed.cleanFullText)
                    .font(.system(size: 15, weight: .regular))
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
                        .font(.system(size: 15, weight: .bold, design: .rounded))
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

                // High-Craft Metric Count Badge
                HStack(spacing: 4) {
                    Text(item.count)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(item.tint)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(item.tint.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(item.tint.opacity(0.28), lineWidth: 0.75))

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
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 59/255, green: 130/255, blue: 246/255))
                .padding(.top, 1)

            Text(noticeText)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AdminSurface.secondaryText)
                .lineSpacing(3)
                .multilineTextAlignment(isRTL ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
        .background(Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.2), lineWidth: 0.75)
        )
    }

    // MARK: - Studio Semantic Card View

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
                        .font(.system(size: 15, weight: .bold, design: .rounded))
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
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                    }
                }
            }

            // Interactive Navigation CTA
            if let entityType = card.entityType, let entityId = card.entityId, !entityId.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    handleDeepLink(entityType: entityType, entityId: entityId)
                } label: {
                    HStack(spacing: 6) {
                        Text(actionLabelForEntity(entityType))
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(AdminSurface.primary)

                        Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
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
        if card.isHotelCard { return "building.2.fill" }
        if card.isProductCard { return "shippingbox.fill" }
        if card.isOrderCard { return "bag.fill" }
        if card.entityType?.contains("branch") == true { return "mappin.and.ellipse" }
        return "doc.text.fill"
    }

    private func cardIconColor(_ card: PuryCard) -> Color {
        if card.isHotelCard { return Color(red: 16/255, green: 185/255, blue: 129/255) }
        if card.isProductCard { return Color(red: 245/255, green: 158/255, blue: 11/255) }
        if card.isOrderCard { return Color(red: 59/255, green: 130/255, blue: 246/255) }
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
        if lower.contains("product") || lower.contains("stock") {
            return isRTL ? "إدارة المنتج في المخزن" : "Manage Product Stock"
        }
        if lower.contains("branch") {
            return isRTL ? "عرض تفاصيل الفرع" : "View Branch Details"
        }
        return isRTL ? "فتح السجل في لوحة الإدارة" : "View Record in Admin"
    }

    private func dataBlockView(_ block: PuryDataBlock) -> some View {
        VStack(alignment: isRTL ? .trailing : .leading, spacing: 8) {
            ForEach(block.fields) { field in
                HStack {
                    Text(field.cleanLabel)
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text(field.cleanValue)
                        .font(AdminType.caption1Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusPill(_ status: String) -> some View {
        let cleanStatus = PuryModelsSanitizer.cleanText(status)
        return Text(cleanStatus)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.12), in: Capsule())
    }

    // MARK: - Tactile Confirmation Card (Tier 3)

    private func tactileConfirmationCard(_ action: PuryConfirmationAction) -> some View {
        VStack(alignment: isRTL ? .trailing : .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(red: 245/255, green: 158/255, blue: 11/255))
                }

                VStack(alignment: isRTL ? .trailing : .leading, spacing: 2) {
                    Text(isRTL ? "مطلوب تأكيد العملية" : "Confirmation Required")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(isRTL ? "تعديل حساس يتطلب اعتمادك الصريح" : "Sensitive operation requires authorization")
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()
            }

            if let warnings = action.warnings, !warnings.isEmpty {
                VStack(alignment: isRTL ? .trailing : .leading, spacing: 6) {
                    ForEach(warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 6) {
                            Text("⚠️")
                                .font(.system(size: 12))
                            Text(warning)
                                .font(AdminType.caption1)
                                .foregroundStyle(Color(red: 239/255, green: 68/255, blue: 68/255))
                                .multilineTextAlignment(isRTL ? .trailing : .leading)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                .background(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            if let updates = action.updates, !updates.isEmpty {
                VStack(alignment: isRTL ? .trailing : .leading, spacing: 6) {
                    Text(isRTL ? "التعديلات المقترحة:" : "Proposed Changes:")
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    ForEach(Array(updates.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Spacer()
                            Text(updates[key] ?? "")
                                .font(AdminType.caption1Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                    }
                }
                .padding(12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12))
            }

            // Confirmation Actions
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    Task {
                        await store.confirmAction(action, screenContext: screenContext)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(isRTL ? "تأكيد وتنفيذ" : "Confirm & Execute")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 16/255, green: 185/255, blue: 129/255), Color(red: 5/255, green: 150/255, blue: 105/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.cancelAction()
                } label: {
                    Text(isRTL ? "إلغاء" : "Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(maxWidth: 80)
                        .padding(.vertical, 13)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Thinking Bubble

    private var thinkingBubble: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color(red: 16/255, green: 185/255, blue: 129/255))
                .scaleEffect(0.9)

            Text(isRTL ? "بيوري يراجع البيانات المصرح بها ويجهز الإجابة..." : "Pury is analyzing authorized records...")
                .font(.system(size: 13, weight: .medium))
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
                .font(.system(size: 15, weight: .regular))
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
                .font(.system(size: 12, weight: .semibold))
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
    public let telemetryItems: [PuryTelemetryItem]
    public let outroNotice: String?
    public let cleanFullText: String

    public init(
        introNarrative: String?,
        telemetryItems: [PuryTelemetryItem],
        outroNotice: String?,
        cleanFullText: String
    ) {
        self.introNarrative = introNarrative
        self.telemetryItems = telemetryItems
        self.outroNotice = outroNotice
        self.cleanFullText = cleanFullText
    }
}

public enum PuryContentParser {
    public static func parse(_ rawText: String, isRTL: Bool) -> PuryParsedMessageContent {
        let lines = rawText.components(separatedBy: .newlines)
        var introLines: [String] = []
        var outroLines: [String] = []
        var items: [PuryTelemetryItem] = []
        var foundMetrics = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if let item = parseMetricLine(trimmed, isRTL: isRTL) {
                foundMetrics = true
                items.append(item)
            } else if foundMetrics {
                outroLines.append(cleanMarkdown(trimmed))
            } else {
                introLines.append(cleanMarkdown(trimmed))
            }
        }

        let intro = introLines.isEmpty ? nil : introLines.joined(separator: "\n")
        let outro = outroLines.isEmpty ? nil : outroLines.joined(separator: "\n")
        let full = cleanMarkdown(rawText)

        return PuryParsedMessageContent(
            introNarrative: intro,
            telemetryItems: items,
            outroNotice: outro,
            cleanFullText: full
        )
    }

    private static func parseMetricLine(_ line: String, isRTL: Bool) -> PuryTelemetryItem? {
        // Must start with markdown bullet
        guard line.hasPrefix("*") || line.hasPrefix("-") || line.hasPrefix("•") else {
            return nil
        }

        var text = line
        if text.hasPrefix("*") || text.hasPrefix("-") || text.hasPrefix("•") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Split by ":" or "："
        let parts = text.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }

        let rawKey = parts[0].trimmingCharacters(in: .whitespaces)
        let rawVal = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)

        let count = cleanMarkdown(rawVal).trimmingCharacters(in: .whitespaces)
        guard !count.isEmpty else { return nil }

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
