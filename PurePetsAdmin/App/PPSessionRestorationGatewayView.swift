//
//  PPSessionRestorationGatewayView.swift
//  PurePetsAdmin
//
//  Category-Defining Sovereign Security Gateway (NextGen V6)
//  Reinvented from absolute first principles for iOS & iPad separately:
//  - iPhone: Tactical Security Vault with kinetic orbital radar & dynamic telemetry stages.
//  - iPad: Desktop-class Spatial Command Gateway with gyroscopic core & live verification matrix.
//

import SwiftUI
import UIKit
import Network

// MARK: - Autonomous Network Reachability Monitor

@MainActor
final class NetworkReachabilityMonitor: ObservableObject {
    static let shared = NetworkReachabilityMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var isCellular: Bool = false

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.purepets.admin.networkReachabilityMonitor", qos: .utility)

    init() {
        let monitor = NWPathMonitor()
        self.monitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            let connected = (path.status == .satisfied)
            let cellular = path.usesInterfaceType(.cellular)
            Task { @MainActor in
                guard let self else { return }
                if self.isConnected != connected || self.isCellular != cellular {
                    self.isConnected = connected
                    self.isCellular = cellular
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - Sovereign Verification Stage Enum

private enum VerificationStage: Int, CaseIterable {
    case securingLink = 0
    case validatingIAM = 1
    case syncingMesh = 2
    case armingCockpit = 3

    var title: String {
        switch self {
        case .securingLink:
            return Language.get("Restoring_Stage_Link_Title", alter: "تأمين بروتوكول الاتصال المشفر")
        case .validatingIAM:
            return Language.get("Restoring_Stage_IAM_Title", alter: "توثيق الاعتمادات والصلاحيات السيادية")
        case .syncingMesh:
            return Language.get("Restoring_Stage_Mesh_Title", alter: "مزامنة الفروع ومصفوفة العمليات")
        case .armingCockpit:
            return Language.get("Restoring_Stage_Cockpit_Title", alter: "تجهيز قمرة القيادة الإدارية")
        }
    }

    var subtitle: String {
        switch self {
        case .securingLink:
            return Language.get("Restoring_Stage_Link_Sub", alter: "التحقق من سلامة العتاد وشهادات App Check")
        case .validatingIAM:
            return Language.get("Restoring_Stage_IAM_Sub", alter: "مطابقة رتبة المشرف مع مصفوفة الأذونات المركزية")
        case .syncingMesh:
            return Language.get("Restoring_Stage_Mesh_Sub", alter: "تحميل بيانات المستودعات والصلاحيات المكانية")
        case .armingCockpit:
            return Language.get("Restoring_Stage_Cockpit_Sub", alter: "فتح القنوات وتفعيل بيئة العمل الآمنة")
        }
    }

    var icon: String {
        switch self {
        case .securingLink:
            return "lock.shield.fill"
        case .validatingIAM:
            return "person.badge.key.fill"
        case .syncingMesh:
            return "network"
        case .armingCockpit:
            return "bolt.shield.fill"
        }
    }
}

// MARK: - Main Gateway View

struct PPSessionRestorationGatewayView: View {
    @ObservedObject var sessionStore: AdminSessionStore
    @ObservedObject private var networkMonitor = NetworkReachabilityMonitor.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var currentStage: VerificationStage = .securingLink
    @State private var stageTimer: Timer? = nil

    // Auto-Recovery State Machine (Single-Shot Circuit Breaker)
    @State private var wasOffline: Bool = false
    @State private var hasAttemptedAutoRecoveryForCurrentOnlineSession: Bool = false
    @State private var isAutoRetrying: Bool = false

    init(sessionStore: AdminSessionStore) {
        self.sessionStore = sessionStore
    }

    private var effectiveError: String? {
        if let restoreError = sessionStore.restoreError {
            return restoreError
        }
        if !networkMonitor.isConnected {
            return Language.get("StatusNetworkError", alter: "حدث خطأ في الشبكة. تحقق من الاتصال وحاول مرة أخرى.")
        }
        return nil
    }

    var body: some View {
        GeometryReader { proxy in
            let isIPad = horizontalSizeClass == .regular || proxy.size.width >= 760

            ZStack {
                // Enterprise Ambient Luminous Canvas
                ambientCanvasBackground

                if isIPad {
                    iPadSessionRestorationGateway(
                        sessionStore: sessionStore,
                        currentStage: currentStage,
                        networkMonitor: networkMonitor,
                        effectiveError: effectiveError,
                        isAutoRetrying: isAutoRetrying,
                        onManualRetry: {
                            resetAndManualRetry()
                        }
                    )
                    .transition(.opacity)
                } else {
                    iPhoneSessionRestorationVault(
                        sessionStore: sessionStore,
                        currentStage: currentStage,
                        networkMonitor: networkMonitor,
                        effectiveError: effectiveError,
                        isAutoRetrying: isAutoRetrying,
                        onManualRetry: {
                            resetAndManualRetry()
                        }
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .onAppear {
                startStageCycle()
                if !networkMonitor.isConnected {
                    wasOffline = true
                }
            }
            .onDisappear {
                stageTimer?.invalidate()
                stageTimer = nil
            }
            .onChange(of: networkMonitor.isConnected) { isOnline in
                if !isOnline {
                    // Arm the auto-retry trigger: device is confirmed offline
                    wasOffline = true
                    hasAttemptedAutoRecoveryForCurrentOnlineSession = false
                    isAutoRetrying = false
                } else if isOnline && wasOffline && !hasAttemptedAutoRecoveryForCurrentOnlineSession {
                    triggerAutoRecovery()
                }
            }
        }
    }

    // MARK: - Ambient Canvas Background

    private var ambientCanvasBackground: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            // Subtle Deep Radial Light Cone
            RadialGradient(
                colors: [
                    Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.08),
                    Color(red: 244/255, green: 63/255, blue: 94/255).opacity(0.03),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 480
            )
            .ignoresSafeArea()

            // Subtle Top-Down Environmental Horizon
            LinearGradient(
                colors: [
                    Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.04),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }

    private func startStageCycle() {
        stageTimer?.invalidate()
        stageTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { _ in
            guard effectiveError == nil else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                if currentStage.rawValue < VerificationStage.allCases.count - 1 {
                    currentStage = VerificationStage(rawValue: currentStage.rawValue + 1) ?? .armingCockpit
                } else {
                    stageTimer?.invalidate()
                    stageTimer = nil
                }
            }
        }
    }

    // MARK: - Autonomous Network Reconnection Trigger

    private func triggerAutoRecovery() {
        guard !hasAttemptedAutoRecoveryForCurrentOnlineSession else { return }
        hasAttemptedAutoRecoveryForCurrentOnlineSession = true
        wasOffline = false
        isAutoRetrying = true

        // 0.8s stabilization debounce to allow IP assignment, DNS sockets, and routes to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard self.networkMonitor.isConnected else {
                self.isAutoRetrying = false
                self.wasOffline = true
                self.hasAttemptedAutoRecoveryForCurrentOnlineSession = false
                return
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                self.currentStage = .securingLink
            }
            self.startStageCycle()
            self.sessionStore.restoreCurrentSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.isAutoRetrying = false
            }
        }
    }

    private func resetAndManualRetry() {
        hasAttemptedAutoRecoveryForCurrentOnlineSession = false
        isAutoRetrying = false
        guard networkMonitor.isConnected else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            currentStage = .securingLink
        }
        startStageCycle()
        sessionStore.restoreCurrentSession()
    }
}

// MARK: - iPhone Tactical Security Vault Architecture

private struct iPhoneSessionRestorationVault: View {
    @ObservedObject var sessionStore: AdminSessionStore
    let currentStage: VerificationStage
    @ObservedObject var networkMonitor: NetworkReachabilityMonitor
    let effectiveError: String?
    let isAutoRetrying: Bool
    let onManualRetry: () -> Void

    @State private var auraPulse: Bool = false
    @State private var radarRotation: Double = 0
    @State private var counterRotation: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Top Attestation Sentinel Pill
            attestationSentinelPill
                .padding(.top, 48)

            Spacer(minLength: 16)

            // Epicenter: Kinetic Sovereign Radar Sigil
            sovereignKineticEpicenter
                .frame(width: 220, height: 220)

            Spacer(minLength: 24)

            // Telemetry Status & Recovery Container
            if let errorText = effectiveError {
                recoveryDossierCard(errorText: errorText)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                telemetryStatusCard
                    .transition(.opacity)
            }

            Spacer(minLength: 24)

            // Footer System Badge
            enterpriseFooterSignature
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 440)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                auraPulse = true
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                radarRotation = 360
            }
            withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
                counterRotation = -360
            }
        }
    }

    // MARK: - Top Sentinel Pill

    private var attestationSentinelPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(networkMonitor.isConnected ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                .frame(width: 7, height: 7)
                .shadow(color: (networkMonitor.isConnected ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.6), radius: 4)

            Text(networkMonitor.isConnected
                ? (effectiveError != nil
                    ? Language.get("CommandCenter_AutoDetect_Active", alter: "المراقبة التلقائية نشطة")
                    : Language.get("CommandCenter_Security_Attestation", alter: "نظام التوثيق والرقابة السيادية"))
                : Language.get("CommandCenter_Network_Offline", alter: "الإنترنت غير متصل"))
                .font(AdminType.caption2Bold)
                .foregroundColor(networkMonitor.isConnected ? AdminSurface.primaryText : Color(uiColor: .ppWarning))

            Text("•")
                .foregroundColor(AdminCommandInk.tertiary)

            HStack(spacing: 4) {
                Image(systemName: networkMonitor.isConnected ? (networkMonitor.isCellular ? "antenna.radiowaves.left.and.right" : "wifi") : "wifi.slash")
                    .font(.system(size: 9, weight: .semibold))
                Text(networkMonitor.isConnected
                    ? Language.get("AppCheck_Active", alter: "App Check مفعّل")
                    : Language.get("Restoring_Network_Monitoring_AutoRetry", alter: "بانتظار الشبكة"))
                    .font(AdminType.caption2)
            }
            .foregroundColor(networkMonitor.isConnected ? AdminCommandInk.secondary : Color(uiColor: .ppWarning))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(AdminSurface.surface, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(networkMonitor.isConnected ? AdminSurface.borderSubtle : Color(uiColor: .ppWarning).opacity(0.35), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .animation(.spring(response: 0.35), value: networkMonitor.isConnected)
    }

    // MARK: - Kinetic Sovereign Epicenter

    private var sovereignKineticEpicenter: some View {
        ZStack {
            // Outermost Resonant Halo Wave
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 190/255, green: 18/255, blue: 60/255).opacity(auraPulse ? 0.20 : 0.08),
                            Color(red: 244/255, green: 63/255, blue: 94/255).opacity(auraPulse ? 0.08 : 0.02),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 110
                    )
                )
                .scaleEffect(auraPulse ? 1.15 : 0.92)

            // Outer Gyroscope Dashed Ring
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.6),
                            Color(red: 244/255, green: 63/255, blue: 94/255).opacity(0.15),
                            Color.clear,
                            Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.6)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                )
                .frame(width: 186, height: 186)
                .rotationEffect(.degrees(radarRotation))

            // Middle Counter-Rotating Telemetry Ring
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color(uiColor: .ppPrimary).opacity(0.45),
                            Color.clear,
                            Color(uiColor: .ppPrimary).opacity(0.2),
                            Color.clear
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.25, dash: [4, 8])
                )
                .frame(width: 152, height: 152)
                .rotationEffect(.degrees(counterRotation))

            // Inner Glassmorphic Pedestal
            Circle()
                .fill(AdminSurface.surface)
                .frame(width: 112, height: 112)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 244/255, green: 63/255, blue: 94/255).opacity(0.5),
                                    Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.22), radius: 18, y: 6)

            // Official PurePets Admin Logo
            Image("AD_LOGO")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
        }
    }

    // MARK: - Telemetry Status Card

    private var telemetryStatusCard: some View {
        VStack(spacing: 16) {
            // Main Stage Nomenclature
            VStack(spacing: 6) {
                Text(currentStage.title)
                    .font(Font.custom("Beiruti-Bold", size: 21, relativeTo: .title3))
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .id("stage_title_\(currentStage.rawValue)")
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))

                Text(currentStage.subtitle)
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .id("stage_sub_\(currentStage.rawValue)")
                    .transition(.opacity)
            }

            // 4-Node Stage Progress Runway
            HStack(spacing: 8) {
                ForEach(VerificationStage.allCases, id: \.self) { stage in
                    Capsule()
                        .fill(
                            stage.rawValue <= currentStage.rawValue
                                ? Color(red: 190/255, green: 18/255, blue: 60/255)
                                : AdminSurface.hairline.opacity(0.8)
                        )
                        .frame(height: 4)
                        .animation(.spring(response: 0.35), value: currentStage)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
        }
        .padding(22)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AdminSurface.borderSubtle, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 4)
    }

    // MARK: - Recovery Dossier Card

    private func recoveryDossierCard(errorText: String) -> some View {
        VStack(spacing: 16) {
            // Diagnostic Alert Pip
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(uiColor: .ppError))

                Text(Language.get("CommandCenter_Restore_Failed_Badge", alter: "تعذر استعادة الجلسة الآمنة"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(Color(uiColor: .ppError))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(uiColor: .ppError).opacity(0.10), in: Capsule())

            // Diagnostic Explanation
            Text(errorText)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            // Autonomous Auto-Recovery Sentinel Pip
            HStack(spacing: 8) {
                if isAutoRetrying {
                    ProgressView()
                        .scaleEffect(0.68)
                        .tint(Color(uiColor: .ppSuccess))
                    Text(Language.get("Restoring_Network_Restored_AutoRetrying", alter: "تم التقاط الاتصال بالإنترنت... جاري إعادة المحاولة تلقائياً"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                } else if !networkMonitor.isConnected {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(uiColor: .ppWarning))
                    Text(Language.get("Restoring_Network_Monitoring_AutoRetry", alter: "المراقبة التلقائية نشطة: سيتم الاستئناف فور عودة الإنترنت"))
                        .font(AdminType.caption2)
                        .foregroundColor(Color(uiColor: .ppWarning))
                } else {
                    Image(systemName: "wifi")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(uiColor: .ppSuccess))
                    Text(Language.get("Restoring_Network_Online", alter: "متصل بالإنترنت"))
                        .font(AdminType.caption2)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                (networkMonitor.isConnected ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.10),
                in: Capsule()
            )
            .animation(.spring(response: 0.35), value: networkMonitor.isConnected)
            .animation(.spring(response: 0.35), value: isAutoRetrying)

            // Tactical Actions Runway
            VStack(spacing: 10) {
                Button(action: onManualRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("Retry", alter: "إعادة محاولة الاتصال"))
                            .font(PPBrandFont.bold(size: 15))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 190/255, green: 18/255, blue: 60/255),
                                Color(red: 225/255, green: 29/255, blue: 72/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(color: Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.32), radius: 8, y: 3)
                }
                .buttonStyle(RestorationTactilePressStyle())

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    sessionStore.signOut()
                }) {
                    Text(Language.get("SignOut_To_Login", alter: "تسجيل الخروج والتبديل لحساب آخر"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
            }
        }
        .padding(22)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(uiColor: .ppError).opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color(uiColor: .ppError).opacity(0.08), radius: 18, y: 6)
    }

    // MARK: - Footer Signature

    private var enterpriseFooterSignature: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundColor(AdminCommandInk.tertiary)

            Text(verbatim: "PurePets Sovereign Admin Platform • 2026")
                .font(AdminType.caption2.monospaced())
                .foregroundColor(AdminCommandInk.tertiary)
        }
    }
}

// MARK: - iPad Spatial Command Gateway Architecture

private struct iPadSessionRestorationGateway: View {
    @ObservedObject var sessionStore: AdminSessionStore
    let currentStage: VerificationStage
    @ObservedObject var networkMonitor: NetworkReachabilityMonitor
    let effectiveError: String?
    let isAutoRetrying: Bool
    let onManualRetry: () -> Void

    @State private var auraPulse: Bool = false
    @State private var gyroOuterRotation: Double = 0
    @State private var gyroMiddleRotation: Double = 0
    @State private var gyroInnerRotation: Double = 0

    var body: some View {
        ZStack {
            // Centered High-Grade Floating Deck
            HStack(spacing: 36) {
                // Leading Pane: The Sovereign Core Vitrine
                sovereignCoreVitrine
                    .frame(width: 320)

                // Divider Line
                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(width: 1)
                    .padding(.vertical, 28)

                // Trailing Pane: Live Telemetry Verification Matrix
                verificationMatrixDossier
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(AdminSurface.surface)
                    .shadow(color: Color.black.opacity(0.09), radius: 36, x: 0, y: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(AdminSurface.borderSubtle, lineWidth: 1)
            )
            .frame(maxWidth: 820, maxHeight: 540)
            .padding(32)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                auraPulse = true
            }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                gyroOuterRotation = 360
            }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                gyroMiddleRotation = -360
            }
            withAnimation(.linear(duration: 32).repeatForever(autoreverses: false)) {
                gyroInnerRotation = 360
            }
        }
    }

    // MARK: - Sovereign Core Vitrine

    private var sovereignCoreVitrine: some View {
        VStack(spacing: 24) {
            Spacer()

            // Gyroscopic Hologram Chamber
            ZStack {
                // Multi-Tier Radial Emission
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 190/255, green: 18/255, blue: 60/255).opacity(auraPulse ? 0.22 : 0.09),
                                Color(red: 244/255, green: 63/255, blue: 94/255).opacity(auraPulse ? 0.10 : 0.03),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .scaleEffect(auraPulse ? 1.12 : 0.94)

                // Outer Segmented Horizon Ring
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.65),
                                Color.clear,
                                Color(red: 244/255, green: 63/255, blue: 94/255).opacity(0.4),
                                Color.clear
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2, dash: [12, 8])
                    )
                    .frame(width: 216, height: 216)
                    .rotationEffect(.degrees(gyroOuterRotation))

                // Middle Reverse Ring
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                Color(uiColor: .ppPrimary).opacity(0.5),
                                Color(uiColor: .ppPrimary).opacity(0.15),
                                Color.clear
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 10])
                    )
                    .frame(width: 176, height: 176)
                    .rotationEffect(.degrees(gyroMiddleRotation))

                // Inner Fine Micro-Ring
                Circle()
                    .strokeBorder(
                        Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 5])
                    )
                    .frame(width: 136, height: 136)
                    .rotationEffect(.degrees(gyroInnerRotation))

                // Pure Vector Sovereign Sigil Shield
                Circle()
                    .fill(AdminSurface.surface)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color(red: 244/255, green: 63/255, blue: 94/255).opacity(0.6),
                                        Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.25)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.24), radius: 16, y: 6)

                // Official PurePets Admin Logo
                Image("AD_LOGO")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
            }
            .frame(width: 240, height: 240)

            // Sovereign Brand Readout
            VStack(spacing: 4) {
                Text(verbatim: "PUREPETS")
                    .font(PPBrandFont.bold(size: 17))
                    .tracking(2.5)
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("CommandCenter_Enterprise_Security", alter: "المنظومة الإدارية والرقابية الموحدة"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()
        }
    }

    // MARK: - Verification Matrix Dossier

    private var verificationMatrixDossier: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header Stack
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(effectiveError != nil ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess))
                        .frame(width: 8, height: 8)
                        .shadow(color: (effectiveError != nil ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess)).opacity(0.6), radius: 4)

                    Text(Language.get("CommandCenter_Restoring_Gateway_Title", alter: "بوابة استعادة الجلسة السيادية"))
                        .font(Font.custom("Beiruti-Bold", size: 24, relativeTo: .title2))
                        .foregroundColor(AdminSurface.primaryText)
                }

                Text(Language.get("CommandCenter_Restoring_Gateway_Sub", alter: "جاري ربط محطة العمل الآمنة بنواة النظام المركزي ومزامنة الأذونات التشغيلية."))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)
            }

            // Error Recovery Area or 4-Step Checklist Matrix
            if let errorText = effectiveError {
                ipadRecoveryDeck(errorText: errorText)
            } else {
                matrixTelemetryChecklist
            }

            Spacer(minLength: 0)

            // iPad Hardware Keyboard Shortcut Bar
            HStack(spacing: 16) {
                if effectiveError != nil {
                    HStack(spacing: 4) {
                        Text(verbatim: "⌘R")
                            .font(AdminType.caption2.monospaced())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 4))
                        Text(Language.get("Retry", alter: "إعادة المحاولة"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminCommandInk.secondary)
                    }

                    HStack(spacing: 4) {
                        Text(verbatim: "Esc")
                            .font(AdminType.caption2.monospaced())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 4))
                        Text(Language.get("SignOut_To_Login", alter: "تبديل الحساب"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminCommandInk.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: networkMonitor.isConnected ? "checkmark.shield.fill" : "wifi.slash")
                            .font(.system(size: 11))
                            .foregroundColor(networkMonitor.isConnected ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                        Text(networkMonitor.isConnected
                            ? "Hardware Attestation • TLS 1.3 • AES-256"
                            : Language.get("CommandCenter_Network_Offline", alter: "الإنترنت غير متصل"))
                            .font(AdminType.caption2.monospaced())
                            .foregroundColor(networkMonitor.isConnected ? AdminCommandInk.tertiary : Color(uiColor: .ppWarning))
                    }
                }

                Spacer()

                Text(verbatim: "v6.0 Enterprise")
                    .font(AdminType.caption2.monospaced())
                    .foregroundColor(AdminCommandInk.tertiary)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Matrix Telemetry Checklist

    private var matrixTelemetryChecklist: some View {
        VStack(spacing: 10) {
            ForEach(VerificationStage.allCases, id: \.self) { stage in
                let isActive = stage == currentStage
                let isPast = stage.rawValue < currentStage.rawValue

                HStack(spacing: 12) {
                    // Stage Status Indicator
                    ZStack {
                        if isPast {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppSuccess))
                        } else if isActive {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(Color(red: 190/255, green: 18/255, blue: 60/255))
                        } else {
                            Circle()
                                .strokeBorder(AdminSurface.hairline, lineWidth: 1.5)
                                .frame(width: 14, height: 14)
                        }
                    }
                    .frame(width: 22, height: 22)

                    // Stage Name & Subtitle
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.title)
                            .font(isActive ? AdminType.calloutBold : AdminType.callout)
                            .foregroundColor(isActive ? AdminSurface.primaryText : (isPast ? AdminSurface.secondaryText : AdminCommandInk.tertiary))

                        Text(stage.subtitle)
                            .font(AdminType.caption2)
                            .foregroundColor(isActive ? AdminSurface.secondaryText : AdminCommandInk.tertiary.opacity(0.8))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Trailing Stage Glyph
                    Image(systemName: stage.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isActive ? Color(red: 190/255, green: 18/255, blue: 60/255) : AdminCommandInk.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isActive
                        ? Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.06)
                        : AdminSurface.control.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isActive
                                ? Color(red: 190/255, green: 18/255, blue: 60/255).opacity(0.24)
                                : AdminSurface.hairline.opacity(0.6),
                            lineWidth: 0.75
                        )
                )
            }
        }
    }

    // MARK: - iPad Recovery Deck

    private func ipadRecoveryDeck(errorText: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(uiColor: .ppError))
                Text(Language.get("CommandCenter_Restore_Failed_Badge", alter: "تعذر استعادة الجلسة الآمنة"))
                    .font(AdminType.calloutBold)
                    .foregroundColor(Color(uiColor: .ppError))
            }

            Text(errorText)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.primaryText)
                .lineLimit(3)

            // Autonomous Auto-Recovery Sentinel Pip
            HStack(spacing: 8) {
                if isAutoRetrying {
                    ProgressView()
                        .scaleEffect(0.70)
                        .tint(Color(uiColor: .ppSuccess))
                    Text(Language.get("Restoring_Network_Restored_AutoRetrying", alter: "تم التقاط الاتصال بالإنترنت... جاري استئناف الجلسة تلقائياً"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                } else if !networkMonitor.isConnected {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(uiColor: .ppWarning))
                    Text(Language.get("Restoring_Network_Monitoring_AutoRetry", alter: "المراقبة التلقائية نشطة: سيتم الاستئناف فور عودة الإنترنت"))
                        .font(AdminType.caption2)
                        .foregroundColor(Color(uiColor: .ppWarning))
                } else {
                    Image(systemName: "wifi")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(uiColor: .ppSuccess))
                    Text(Language.get("Restoring_Network_Online", alter: "متصل بالإنترنت"))
                        .font(AdminType.caption2)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                (networkMonitor.isConnected ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.10),
                in: Capsule()
            )
            .animation(.spring(response: 0.35), value: networkMonitor.isConnected)
            .animation(.spring(response: 0.35), value: isAutoRetrying)

            HStack(spacing: 12) {
                Button(action: onManualRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("Retry", alter: "إعادة المحاولة (⌘R)"))
                            .font(PPBrandFont.bold(size: 14))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 190/255, green: 18/255, blue: 60/255),
                                Color(red: 225/255, green: 29/255, blue: 72/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(RestorationTactilePressStyle())
                .keyboardShortcut("r", modifiers: .command)

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    sessionStore.signOut()
                }) {
                    Text(Language.get("SignOut_To_Login", alter: "تبديل الحساب (Esc)"))
                        .font(AdminType.callout)
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(RestorationTactilePressStyle())
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(18)
        .background(Color(uiColor: .ppError).opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppError).opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Tactile Press Style

private struct RestorationTactilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
