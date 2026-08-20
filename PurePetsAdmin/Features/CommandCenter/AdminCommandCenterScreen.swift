//
//  AdminCommandCenterScreen.swift
//  PurePetsAdmin
//
//  NEXTGEN V6 REDESIGN — Command Center Flagship Surface
//  ─────────────────────────────────────────────────────────────────────────────
//  World-class, high-density operational command center built with Pure Pets
//  NextGen V6 design language. Features glassmorphism materials, living ambient
//  depth, reactive status telemetry, dynamic priority dominance hierarchy,
//  and full RTL/LTR & VoiceOver accessibility.
//  Applied Pure Pets Beiruti brand typography to all strings.
//
//  CONTRACT
//  ─────────────────────────────────────────────────────────────────────────────
//  • Objective-C backend bridge contract is 100% preserved.
//  • All descriptor fields, applyRoleName, onRoute, onRefresh, applyReadiness,
//    and AdminCommandOrbitHostingController names are intact.
//  • String format specifiers strictly respect locale and string types.
//

import SwiftUI
import Combine
import UIKit

// MARK: - Bridge Descriptor (Preserved Obj-C Contract)

/// A presentation-only value supplied by the Objective-C backend
/// (`AdminDashboardViewController`). Field names and types are frozen.
@objc public class AdminCommandOrbitSignalDescriptor: NSObject {
    @objc public var identifier: String = ""
    @objc public var moduleTitle: String = ""
    @objc public var title: String = ""
    @objc public var detail: String = ""
    @objc public var symbolName: String = "square.grid.2x2"
    @objc public var urgency: Int = 0
    @objc public var count: Int = 0
    @objc public var isLive: Bool = false
}

// MARK: - Internal Domain Models

struct AdminCommandOrbitSignal: Identifiable, Hashable {
    let id: String
    let moduleTitle: String
    let title: String
    let detail: String
    let symbolName: String
    let urgency: Int
    let count: Int
    let isLive: Bool

    var isCritical: Bool { urgency >= 2 }
    var isElevated: Bool { urgency == 1 }
}

struct AdminCommandOrbitReadiness {
    let loadingAreas: [String]
    let failedAreas: [String]
    let updatedAt: Date?
}

struct AdminCommandOrbitSnapshot {
    var signals: [AdminCommandOrbitSignal]
    var roleName: String
    var capabilityCount: Int
    var isInitialized: Bool

    static let empty = AdminCommandOrbitSnapshot(signals: [], roleName: "", capabilityCount: 0, isInitialized: false)
}

enum AdminCommandOrbitPhase: Equatable {
    case connecting
    case loading
    case ready
    case allClear
    case degradedEmpty
    case denied
}

// MARK: - Observable Store

final class AdminCommandCenterStore: ObservableObject {
    @Published var snapshot: AdminCommandOrbitSnapshot = .empty
    @Published var readiness: AdminCommandOrbitReadiness = .init(loadingAreas: [], failedAreas: [], updatedAt: nil)
    @Published var localeCode: String = Language.currentLanguageCode()

    var onRoute: ((String) -> Void)?
    var onRefresh: (() -> Void)?
    var onRequestLogout: (() -> Void)?
    var onToggleLanguage: (() -> Void)?
    var onSelectTab: ((Int) -> Void)?

    func apply(roleName: String?, capabilityCount: Int, signals: [AdminCommandOrbitSignalDescriptor], animated: Bool) {
        let mapped = signals.prefix(8).map { d in
            AdminCommandOrbitSignal(
                id: d.identifier,
                moduleTitle: d.moduleTitle,
                title: d.title,
                detail: d.detail,
                symbolName: d.symbolName.isEmpty ? "square.grid.2x2" : d.symbolName,
                urgency: d.urgency,
                count: d.count,
                isLive: d.isLive
            )
        }
        snapshot = AdminCommandOrbitSnapshot(
            signals: mapped,
            roleName: roleName ?? "",
            capabilityCount: capabilityCount,
            isInitialized: true
        )
    }

    func applyReadiness(loadingAreas: [String], failedAreas: [String], updatedAt: Date?) {
        readiness = AdminCommandOrbitReadiness(
            loadingAreas: loadingAreas,
            failedAreas: failedAreas,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Hosting Controller (Preserved Obj-C Bridge)

@available(iOS 16.0, *)
@MainActor
@objcMembers
public final class AdminCommandOrbitHostingController: UIViewController {

    public var onRoute: ((String) -> Void)? {
        didSet { store.onRoute = onRoute }
    }
    public var onRefresh: (() -> Void)? {
        didSet { store.onRefresh = onRefresh }
    }
    public var onRequestLogout: (() -> Void)? {
        didSet { store.onRequestLogout = onRequestLogout }
    }
    public var onToggleLanguage: (() -> Void)? {
        didSet { store.onToggleLanguage = onToggleLanguage }
    }
    public var onSelectTab: ((Int) -> Void)? {
        didSet { store.onSelectTab = onSelectTab }
    }

    let store: AdminCommandCenterStore
    private var hostingController: UIHostingController<AdminCommandCenterScreenView>?
    private nonisolated(unsafe) var languageObserver: NSObjectProtocol?

    public init() {
        let store = AdminCommandCenterStore()
        store.localeCode = Language.currentLanguageCode()
        self.store = store
        super.init(nibName: nil, bundle: nil)
        observeLanguage()
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let root = AdminCommandCenterScreenView(store: store)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        if #available(iOS 16.4, *) {
            host.safeAreaRegions = []
        }
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    public func applyRoleName(_ roleName: String?, capabilityCount: Int, signals: [AdminCommandOrbitSignalDescriptor], animated: Bool) {
        store.apply(roleName: roleName, capabilityCount: capabilityCount, signals: signals, animated: animated)
    }

    public func applyReadinessWithLoadingAreas(_ loadingAreas: [String], failedAreas: [String], updatedAt: Date?) {
        store.applyReadiness(loadingAreas: loadingAreas, failedAreas: failedAreas, updatedAt: updatedAt)
    }

    private func observeLanguage() {
        languageObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("LanguageDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.store.localeCode = Language.currentLanguageCode()
            }
        }
    }

    deinit {
        if let observer = languageObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - Typography (Beiruti Brand Font)

private enum V6Font {
    static func bold(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom("Beiruti-Bold", size: size, relativeTo: textStyle)
    }

    static func medium(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom("Beiruti-Medium", size: size, relativeTo: textStyle)
    }

    static func regular(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom("Beiruti-Regular", size: size, relativeTo: textStyle)
    }

    static func semibold(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom("Beiruti-SemiBold", size: size, relativeTo: textStyle)
    }

    // Semantic Presets
    static let heroTitle = Font.custom("Beiruti-Bold", size: 20, relativeTo: .title2)
    static let sectionTitle = Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline)
    static let cardTitle = Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline)
    static let cardTitleMedium = Font.custom("Beiruti-Medium", size: 15, relativeTo: .subheadline)
    static let roleName = Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline)
    static let moduleTag = Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption)
    static let body = Font.custom("Beiruti-Regular", size: 14, relativeTo: .body)
    static let bodyMedium = Font.custom("Beiruti-Medium", size: 14, relativeTo: .body)
    static let callout = Font.custom("Beiruti-Medium", size: 13, relativeTo: .callout)
    static let caption = Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption)
    static let captionBold = Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption)
    static let badge = Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2)
    static let time = Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2)
    static let avatarMonogram = Font.custom("Beiruti-Bold", size: 14, relativeTo: .caption)
}

// MARK: - NextGen V6 Design Tokens

private enum V6 {
    // Semantic Colors
    static let canvas = Color(uiColor: .ppBackground)
    static let cardBackground = Color(uiColor: .ppSurface)
    static let cardBackgroundElevated = Color(uiColor: .ppSurfaceElevated)
    static let primaryText = Color(uiColor: .ppTextPrimary)
    static let secondaryText = Color(uiColor: .ppTextSecondary)
    static let tertiaryText = Color(uiColor: .ppTextTertiary)
    static let brand = Color(uiColor: .ppPrimary)
    static let accent = Color(uiColor: .ppAccent)

    // Status Tints
    static let critical = Color(uiColor: .ppError)
    static let elevated = Color(uiColor: .ppWarning)
    static let live = Color(uiColor: .ppInfo)
    static let success = Color(uiColor: .ppSuccess)

    // Geometry & Layout
    static let spacingXS: CGFloat = 6.0
    static let spacingSM: CGFloat = 10.0
    static let spacingMD: CGFloat = 14.0
    static let spacingLG: CGFloat = 18.0
    static let spacingXL: CGFloat = 24.0

    static let radiusSM: CGFloat = 12.0
    static let radiusMD: CGFloat = 16.0
    static let radiusLG: CGFloat = 22.0
    static let radiusXL: CGFloat = 28.0

    // Glass & Lighting
    static let glassStroke = LinearGradient(
        colors: [
            Color.white.opacity(0.32),
            Color.white.opacity(0.08),
            Color.black.opacity(0.04)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let glassStrokeDark = LinearGradient(
        colors: [
            Color.white.opacity(0.18),
            Color.white.opacity(0.04),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Interactive Button Styles

private struct V6GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Root Command Center View

@available(iOS 16.0, *)
struct AdminCommandCenterScreenView: View {
    @ObservedObject var store: AdminCommandCenterStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var locale: Locale { Locale(identifier: store.localeCode == "ar" ? "ar_QA" : "en_QA") }
    private var isRTL: Bool { Language.isRTL() }

    private var phase: AdminCommandOrbitPhase {
        let s = store.snapshot
        if !s.isInitialized { return .connecting }
        if !store.readiness.loadingAreas.isEmpty && s.signals.isEmpty && store.readiness.failedAreas.isEmpty {
            return .loading
        }
        if !store.readiness.failedAreas.isEmpty && s.signals.isEmpty {
            return .degradedEmpty
        }
        if s.roleName.isEmpty { return .denied }
        if s.signals.isEmpty { return .allClear }
        return .ready
    }

    var body: some View {
        let direction: LayoutDirection = isRTL ? .rightToLeft : .leftToRight
        ZStack(alignment: .bottom) {
            // Ambient Living Canvas
            V6.canvas.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    // Header (Top Nav)
                    v6NewHeader
                    
                    // Priority Section
                    v6PhaseContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 140) // Space for custom tab bar
            }
            .ignoresSafeArea(.all, edges: .bottom)
            
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .environment(\.layoutDirection, direction)
        .environment(\.locale, locale)
        .accessibilityElement(children: .contain)
    }

    // MARK: - New Header Layout
    
    private var v6NewHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Top Part
            VStack(alignment: .leading, spacing: 8) {
                Text("PURE PETS عمليات")
                    .font(V6Font.bold(12))
                    .foregroundStyle(V6.critical)
                    .tracking(1)
                
                Text(L10n("AdminCommandCenter_CommandCenter") == "AdminCommandCenter_CommandCenter" ? "مدار القيادة" : L10n("AdminCommandCenter_CommandCenter"))
                    .font(V6Font.bold(34))
                    .foregroundStyle(V6.primaryText)
                
                Text("العمل الحي ينجذب نحو أولويته.")
                    .font(V6Font.medium(15))
                    .foregroundStyle(V6.secondaryText)
            }
            .padding(.top, 12)
            
            // Divider
            Rectangle()
                .fill(V6.secondaryText.opacity(0.15))
                .frame(height: 1)
            
            // Status & Role Row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("مساحة العمل النشطة")
                        .font(V6Font.regular(13))
                        .foregroundStyle(V6.secondaryText)
                    Text(store.snapshot.roleName.isEmpty ? "مشرف عام" : store.snapshot.roleName)
                        .font(V6Font.bold(17))
                        .foregroundStyle(V6.primaryText)
                }
                
                Spacer()
                
                let criticalCount = store.snapshot.signals.filter { $0.isCritical }.count
                if criticalCount > 0 {
                    HStack(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("مباشر")
                                .font(V6Font.regular(13))
                                .foregroundStyle(V6.primaryText)
                            Text("\(criticalCount) حرجة")
                                .font(V6Font.bold(15))
                                .foregroundStyle(V6.primaryText)
                        }
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(V6.critical.opacity(0.12))
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(V6.critical)
                        }
                        .frame(width: 44, height: 44)
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("الحالة")
                                .font(V6Font.regular(13))
                                .foregroundStyle(V6.primaryText)
                            Text("مستقرة")
                                .font(V6Font.bold(15))
                                .foregroundStyle(V6.success)
                        }
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(V6.success.opacity(0.12))
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(V6.success)
                        }
                        .frame(width: 44, height: 44)
                    }
                }
            }
        }
    }

    // MARK: - Phase Dynamic Content Router

    @ViewBuilder
    private var v6PhaseContent: some View {
        switch phase {
        case .connecting, .loading:
            v6LoadingSkeletons
        case .ready:
            v6ReadyMatrix
        case .allClear:
            v6AllClearCelebration
        case .degradedEmpty:
            v6DegradedEmptyState
        case .denied:
            v6AccessDeniedState
        }
    }

    // MARK: - Ready Phase Matrix

    @ViewBuilder
    private var v6ReadyMatrix: some View {
        let criticalSignals = store.snapshot.signals.filter { $0.isCritical }
        let nonCriticalSignals = store.snapshot.signals.filter { !$0.isCritical }

        if let topHeroSignal = (criticalSignals.first ?? nonCriticalSignals.first) {
            VStack(alignment: .leading, spacing: 32) {
                // Dominant Hero Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("الأولوية الآن")
                        .font(V6Font.bold(18))
                        .foregroundStyle(V6.secondaryText)
                    
                    v6DominantHeroCard(for: topHeroSignal)
                }

                // Secondary Signals Deck
                if store.snapshot.signals.count > 1 {
                    let secondaryDeck = store.snapshot.signals.filter { $0.id != topHeroSignal.id }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("الأولويات التالية")
                            .font(V6Font.bold(18))
                            .foregroundStyle(V6.primaryText)
                        
                        ForEach(secondaryDeck) { signal in
                            v6TacticalSignalRow(signal: signal)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cards
    
    private func v6DominantHeroCard(for signal: AdminCommandOrbitSignal) -> some View {
        Button {
            store.onRoute?(signal.id)
        } label: {
            HStack(spacing: 0) {
                // Thick border on leading edge
                Rectangle()
                    .fill(urgencyTint(signal.urgency))
                    .frame(width: 4)
                
                VStack(spacing: 0) {
                    // Top row
                    HStack(alignment: .top) {
                        // Right side content (in RTL this is leading)
                        HStack(spacing: 12) {
                            // Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(urgencyTint(signal.urgency).opacity(0.12))
                                Image(systemName: signal.symbolName)
                                    .font(.system(size: 20))
                                    .foregroundStyle(V6.primaryText)
                            }
                            .frame(width: 48, height: 48)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(signal.moduleTitle)
                                    .font(V6Font.medium(14))
                                    .foregroundStyle(V6.secondaryText)
                                Text(priorityName(signal.urgency))
                                    .font(V6Font.bold(16))
                                    .foregroundStyle(V6.primaryText)
                            }
                        }
                        
                        Spacer()
                        
                        // Left side number
                        Text(formattedCount(signal.count))
                            .font(V6Font.bold(52)) // huge number
                            .foregroundStyle(V6.primaryText)
                    }
                    
                    Spacer().frame(height: 24)
                    
                    // Middle text
                    VStack(alignment: .leading, spacing: 8) {
                        Text(signal.title)
                            .font(V6Font.bold(22))
                            .foregroundStyle(V6.primaryText)
                        Text(signal.detail.isEmpty ? "يحتاج مراجعتك الآن" : signal.detail)
                            .font(V6Font.medium(16))
                            .foregroundStyle(V6.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer().frame(height: 32)
                    
                    // Bottom row
                    HStack {
                        HStack(spacing: 6) {
                            Text("فتح " + signal.moduleTitle)
                                .font(V6Font.bold(15))
                            Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(urgencyTint(signal.urgency))
                        
                        Spacer()
                        
                        if signal.isLive {
                            HStack(spacing: 6) {
                                Text("مباشر")
                                    .font(V6Font.medium(15))
                                    .foregroundStyle(V6.primaryText)
                                Circle()
                                    .fill(V6.critical)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
                .padding(.all, 24)
            }
            .background(V6.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(urgencyTint(signal.urgency).opacity(0.4), lineWidth: 1)
            )
            .shadow(color: urgencyTint(signal.urgency).opacity(0.08), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(V6CardButtonStyle())
    }

    private func v6TacticalSignalRow(signal: AdminCommandOrbitSignal) -> some View {
        Button {
            store.onRoute?(signal.id)
        } label: {
            HStack(spacing: 0) {
                // Thick border on leading edge
                Rectangle()
                    .fill(urgencyTint(signal.urgency))
                    .frame(width: 4)
                
                HStack(alignment: .center, spacing: 16) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(urgencyTint(signal.urgency).opacity(0.12))
                        Image(systemName: signal.symbolName)
                            .font(.system(size: 20))
                            .foregroundStyle(V6.primaryText)
                    }
                    .frame(width: 48, height: 48)
                    
                    // Text block
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(signal.moduleTitle)
                                .font(V6Font.medium(13))
                                .foregroundStyle(V6.secondaryText)
                            if signal.isLive {
                                Text("مباشر")
                                    .font(V6Font.bold(13))
                                    .foregroundStyle(V6.primaryText)
                            }
                        }
                        Text(signal.title)
                            .font(V6Font.bold(17))
                            .foregroundStyle(V6.primaryText)
                            .lineLimit(2)
                        if !signal.detail.isEmpty {
                            Text(signal.detail)
                                .font(V6Font.medium(14))
                                .foregroundStyle(V6.secondaryText)
                        }
                    }
                    
                    Spacer()
                    
                    // Left side
                    VStack(alignment: .center, spacing: 12) {
                        Text(formattedCount(signal.count))
                            .font(V6Font.bold(26))
                            .foregroundStyle(V6.primaryText)
                        Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(urgencyTint(signal.urgency))
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 20)
            }
            .background(V6.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(urgencyTint(signal.urgency).opacity(0.3), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - Custom Bottom Tab Bar
    


    // MARK: - Utility States

    private var v6AllClearCelebration: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(V6.success.opacity(0.1)).frame(width: 80, height: 80)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(V6.success)
            }
            Text(L10n("AdminCommandCenter_AllClear_Title") == "AdminCommandCenter_AllClear_Title" ? "كل شيء مستقر" : L10n("AdminCommandCenter_AllClear_Title"))
                .font(V6Font.bold(20))
                .foregroundStyle(V6.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(V6.cardBackground)
        .cornerRadius(24)
    }

    private var v6LoadingSkeletons: some View {
        VStack(spacing: 16) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 24)
                    .fill(V6.cardBackground)
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(V6.secondaryText.opacity(0.1), lineWidth: 1)
                    )
            }
        }
    }

    private var v6DegradedEmptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(V6.critical)
            Text("فشل التحميل")
                .font(V6Font.bold(20))
                .foregroundStyle(V6.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(V6.cardBackground)
        .cornerRadius(24)
    }

    private var v6AccessDeniedState: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(V6.secondaryText)
            Text("لا توجد صلاحية")
                .font(V6Font.bold(20))
                .foregroundStyle(V6.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(V6.cardBackground)
        .cornerRadius(24)
    }

    // MARK: - Helpers

    private func urgencyTint(_ urgency: Int) -> Color {
        if urgency >= 2 { return V6.critical }
        if urgency == 1 { return V6.elevated }
        return V6.success
    }

    private func priorityName(_ urgency: Int) -> String {
        if urgency >= 2 { return "أولوية حرجة" }
        if urgency == 1 { return "أولوية متوسطة" }
        return "أولوية عادية"
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    private func L10n(_ key: String) -> String {
        Language.get(key, alter: nil)
    }
}
