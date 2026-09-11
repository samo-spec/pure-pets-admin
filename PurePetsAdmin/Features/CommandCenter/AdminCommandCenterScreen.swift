//
//  AdminCommandCenterScreen.swift
//  PurePetsAdmin
//
//  SwiftyMax NextGen V6 redesign of the Admin command surface.
//  The Objective-C bridge, route identifiers, permissions, and live feed owners
//  remain unchanged; this file owns presentation only.
//

import SwiftUI
import Combine
import UIKit
import Firebase
@preconcurrency import FirebaseFirestore
import FirebaseAuth

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

    var isAttentionBearing: Bool {
        count > 0 || isLive || urgency >= 80
    }

    fileprivate var tier: AdminCommandPriorityTier {
        if urgency >= 90 || urgency == 2 { return .critical }
        if urgency >= 50 || urgency == 1 { return .elevated }
        return isAttentionBearing ? .watch : .ready
    }
}

struct AdminCommandOrbitReadiness: Equatable {
    let loadingAreas: [String]
    let failedAreas: [String]
    let updatedAt: Date?
}

struct AdminCommandOrbitSnapshot: Equatable {
    var signals: [AdminCommandOrbitSignal]
    var displayName: String
    var avatarURL: String
    var roleName: String
    var capabilityCount: Int
    var isInitialized: Bool

    static let empty = AdminCommandOrbitSnapshot(
        signals: [],
        displayName: "",
        avatarURL: "",
        roleName: "",
        capabilityCount: 0,
        isInitialized: false
    )
}

enum AdminCommandOrbitPhase: Equatable {
    case connecting
    case loading
    case ready
    case allClear
    case degradedEmpty
    case denied
}

fileprivate enum AdminCommandPriorityTier: Int, Comparable {
    case critical = 0
    case elevated = 1
    case watch = 2
    case ready = 3

    static func < (lhs: AdminCommandPriorityTier, rhs: AdminCommandPriorityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var tone: AdminCommandTone {
        switch self {
        case .critical: return .critical
        case .elevated: return .elevated
        case .watch: return .info
        case .ready: return .stable
        }
    }

    var localizedLabel: String {
        switch self {
        case .critical: return Language.get("AdminCommandCenter_Priority_Critical", alter: nil)
        case .elevated: return Language.get("AdminCommandCenter_Priority_Elevated", alter: nil)
        case .watch: return Language.get("AdminCommandCenter_Priority_Watch", alter: nil)
        case .ready: return Language.get("AdminCommandCenter_Priority_Normal", alter: nil)
        }
    }
}

// MARK: - Observable Store

@MainActor
final class AdminCommandCenterStore: ObservableObject {
    @Published var snapshot: AdminCommandOrbitSnapshot = .empty
    @Published var readiness: AdminCommandOrbitReadiness = .init(loadingAreas: [], failedAreas: [], updatedAt: nil)
    @Published var localeCode: String = Language.currentLanguageCode()
    @Published private(set) var canAccessHotel = false
    @Published private(set) var revision: Int = 0

    var onRoute: ((String) -> Void)?
    var onRefresh: (() -> Void)?
    var onRequestLogout: (() -> Void)?
    var onToggleLanguage: (() -> Void)?
    var onSelectTab: ((Int) -> Void)?

    func apply(
        displayName: String?,
        avatarURL: String?,
        roleName: String?,
        capabilityCount: Int,
        signals: [AdminCommandOrbitSignalDescriptor],
        animated: Bool
    ) {
        let mapped = signals.prefix(6).map { descriptor in
            AdminCommandOrbitSignal(
                id: descriptor.identifier,
                moduleTitle: descriptor.moduleTitle,
                title: descriptor.title,
                detail: descriptor.detail,
                symbolName: descriptor.symbolName.isEmpty ? "square.grid.2x2" : descriptor.symbolName,
                urgency: descriptor.urgency,
                count: descriptor.count,
                isLive: descriptor.isLive
            )
        }
        let nextSnapshot = AdminCommandOrbitSnapshot(
            signals: mapped,
            displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            avatarURL: avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            roleName: roleName ?? "",
            capabilityCount: capabilityCount,
            isInitialized: true
        )

        let change = {
            self.snapshot = nextSnapshot
            self.revision += 1
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            withAnimation(.easeOut(duration: 0.18)) {
                change()
            }
        } else {
            change()
        }
    }

    func applyReadiness(loadingAreas: [String], failedAreas: [String], updatedAt: Date?) {
        let nextReadiness = AdminCommandOrbitReadiness(
            loadingAreas: loadingAreas,
            failedAreas: failedAreas,
            updatedAt: updatedAt
        )
        let change = {
            self.readiness = nextReadiness
            self.revision += 1
        }
        if UIAccessibility.isReduceMotionEnabled {
            change()
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                change()
            }
        }
    }

    func applyHotelAccess(_ allowed: Bool) {
        guard canAccessHotel != allowed else { return }
        canAccessHotel = allowed
        revision += 1
    }
}

// MARK: - Hosting Controller (Preserved Obj-C Bridge)

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

    public init() {
        let store = AdminCommandCenterStore()
        store.localeCode = Language.currentLanguageCode()
        self.store = store
        super.init(nibName: nil, bundle: nil)
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

    public func applyIdentityDisplayName(
        _ displayName: String?,
        avatarURL: String?,
        roleName: String?,
        capabilityCount: Int,
        signals: [AdminCommandOrbitSignalDescriptor],
        animated: Bool
    ) {
        store.apply(
            displayName: displayName,
            avatarURL: avatarURL,
            roleName: roleName,
            capabilityCount: capabilityCount,
            signals: signals,
            animated: animated
        )
    }

    /// Compatibility seam for existing Objective-C callers that do not supply
    /// profile presentation data. It preserves the latest known identity.
    public func applyRoleName(_ roleName: String?, capabilityCount: Int, signals: [AdminCommandOrbitSignalDescriptor], animated: Bool) {
        applyIdentityDisplayName(
            store.snapshot.displayName,
            avatarURL: store.snapshot.avatarURL,
            roleName: roleName,
            capabilityCount: capabilityCount,
            signals: signals,
            animated: animated
        )
    }

    public func applyReadinessWithLoadingAreas(_ loadingAreas: [String], failedAreas: [String], updatedAt: Date?) {
        store.applyReadiness(loadingAreas: loadingAreas, failedAreas: failedAreas, updatedAt: updatedAt)
    }

    public func applyHotelAccess(_ allowed: Bool) {
        store.applyHotelAccess(allowed)
    }

}

// MARK: - Command Center Presentation

private enum AdminCommandMetric {
    static let pageMargin: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let surfaceRadius: CGFloat = 22
    static let heroRadius: CGFloat = 26
    static let tightRadius: CGFloat = 14
    static let minimumActionHeight: CGFloat = 52
    static let commandBarHeight: CGFloat = 58
    static let commandBarRadius: CGFloat = 18
    static let spineHeight: CGFloat = 12
    static let rowMinimumHeight: CGFloat = 76
    static let tabBarBottomInset: CGFloat = 124
}

private enum AdminCommandTypography {
    static let loadValue = Font.custom("Beiruti-Bold", size: 54, relativeTo: .largeTitle)
    static let decisionTitle = Font.custom("Beiruti-Bold", size: 26, relativeTo: .title)
}

enum AdminCommandInk {
    static let secondary = AdminSurface.primaryText.opacity(0.72)
    static let tertiary = AdminSurface.primaryText.opacity(0.58)
}

private enum AdminCommandTone: Equatable {
    case critical
    case elevated
    case stable
    case info
    case muted

    var color: Color {
        switch self {
        case .critical: return Color(uiColor: .ppPressedAction)
        case .elevated: return AdminSurface.primaryText
        case .stable: return AdminSurface.primaryText
        case .info: return AdminSurface.primaryPressed
        case .muted: return AdminCommandInk.secondary
        }
    }

    var accent: Color {
        switch self {
        case .critical: return Color(uiColor: .ppPressedAction)
        case .elevated: return Color(uiColor: .ppWarning)
        case .stable: return Color(uiColor: .ppSuccess)
        case .info: return AdminSurface.primary
        case .muted: return AdminCommandInk.tertiary
        }
    }

    var softFill: Color {
        switch self {
        case .critical: return Color(uiColor: .ppSoftRose)
        case .elevated: return Color(uiColor: .ppMineralBeige)
        case .stable: return Color(uiColor: .ppQuietLilac)
        case .info: return Color(uiColor: .ppSoftRose)
        case .muted: return AdminSurface.control
        }
    }

    var actionFill: Color {
        switch self {
        case .critical: return Color(uiColor: .ppPressedAction)
        default: return AdminSurface.primaryPressed
        }
    }

    var symbol: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .elevated: return "exclamationmark.circle.fill"
        case .stable: return "checkmark.shield.fill"
        case .info: return "arrow.triangle.2.circlepath"
        case .muted: return "shield"
        }
    }
}

private struct CommandSoftSurfaceModifier: ViewModifier {
    let radius: CGFloat
    let fill: Color
    let borderOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AdminSurface.hairline.opacity(borderOpacity), lineWidth: 1)
            }
    }
}

private extension View {
    func commandSoftSurface(
        radius: CGFloat = AdminCommandMetric.surfaceRadius,
        fill: Color = AdminSurface.surface,
        borderOpacity: Double = 0.72
    ) -> some View {
        modifier(CommandSoftSurfaceModifier(radius: radius, fill: fill, borderOpacity: borderOpacity))
    }
}

private struct AdminCommandSituation: Equatable {
    let tone: AdminCommandTone
    let title: String
    let detail: String
    let badge: String
    let symbol: String
    let showsProgress: Bool
}

struct AdminCommandCenterScreenView: View {
    @ObservedObject var store: AdminCommandCenterStore
    @ObservedObject private var branchContext = BranchContextStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingSourceIssueDetails = false
    @State private var isReplacingBranchData = false
    @State private var isShowingBranchSelection = false

    private var locale: Locale {
        Locale(identifier: store.localeCode == "ar" ? "ar_QA" : "en_QA")
    }

    private var direction: LayoutDirection {
        store.localeCode == "ar" ? .rightToLeft : .leftToRight
    }

    private var phase: AdminCommandOrbitPhase {
        let snapshot = store.snapshot
        if isReplacingBranchData { return .loading }
        if !snapshot.isInitialized { return .connecting }
        if snapshot.roleName.isEmpty { return .denied }
        if !store.readiness.loadingAreas.isEmpty,
           snapshot.signals.isEmpty,
           store.readiness.failedAreas.isEmpty {
            return .loading
        }
        if !store.readiness.failedAreas.isEmpty, snapshot.signals.isEmpty {
            return .degradedEmpty
        }
        if snapshot.signals.isEmpty { return .allClear }
        return .ready
    }

    var body: some View {
        GeometryReader { geometry in
            let safeTop = max(geometry.safeAreaInsets.top, PPStatusBarHelper.statusBarHeight, 44)
            let isRegular = geometry.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize
            let ipadMaxWidth: CGFloat = 1160
            let heroInset = AdminCommandMetric.pageMargin
            let contentAvailableWidth = max(min(geometry.size.width - 2 * heroInset, isRegular ? ipadMaxWidth : geometry.size.width - 2 * heroInset), 320)

            // Large text and compact-height windows need the header to scroll
            // with the existing content, rather than consume its whole viewport.
            let scrollsHeader = dynamicTypeSize.isAccessibilitySize || geometry.size.height < 600

            VStack(spacing: 0) {
                if !scrollsHeader {
                    fixedNavBar(safeTop: safeTop, isRegular: isRegular)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if scrollsHeader {
                            fixedNavBar(safeTop: safeTop, isRegular: isRegular)
                        }

                        LazyVStack(alignment: .leading, spacing: AdminCommandMetric.sectionSpacing) {
                            phaseContent(isRegular: isRegular, containerWidth: contentAvailableWidth)
                        }
                        .padding(.horizontal, AdminCommandMetric.pageMargin)
                        .padding(.top, 14)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom + 88, AdminCommandMetric.tabBarBottomInset))
                        .frame(maxWidth: isRegular ? ipadMaxWidth : .infinity)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(AdminSurface.background.ignoresSafeArea())
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, direction)
        .environment(\.locale, locale)
        .sheet(isPresented: $isShowingBranchSelection) {
            PPBranchSelectionGateView()
                .environment(\.layoutDirection, direction)
                .environment(\.locale, locale)
        }
        .sheet(isPresented: $isShowingSourceIssueDetails) {
            sourceIssueSheet
                .environment(\.layoutDirection, direction)
                .environment(\.locale, locale)
        }
        .onAppear {
            refresh()
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: Notification.Name("LanguageDidChangeNotification"))
                .receive(on: RunLoop.main)
        ) { _ in
            store.localeCode = Language.currentLanguageCode()
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSNotification.Name.PPActiveBranchDidChange)
                .receive(on: RunLoop.main)
        ) { _ in
            refresh()
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: Notification.Name("PPAdminCommandAuthorizationDidChangeNotification"))
                .receive(on: RunLoop.main)
        ) { _ in
            refresh()
        }
    }

    private func fixedNavBar(safeTop: CGFloat, isRegular: Bool) -> some View {
        let ipadMaxWidth: CGFloat = 1160
        return CommandCenterChrome(
            displayName: store.snapshot.displayName,
            avatarURL: store.snapshot.avatarURL,
            roleName: roleDisplayName,
            capabilityText: capabilityText,
            readinessText: compactReadinessText,
            readinessTone: readinessTone,
            onReadinessTap: store.readiness.failedAreas.isEmpty ? nil : {
                isShowingSourceIssueDetails = true
            },
            languageTitle: languageToggleTitle,
            onAccount: { route("editMyAccount") },
            onRefresh: { refresh() },
            onLanguage: { store.onToggleLanguage?() },
            onLogout: { store.onRequestLogout?() },
            onSelectBranch: { isShowingBranchSelection = true },
            isRegular: isRegular
        )
        .padding(.horizontal, AdminCommandMetric.pageMargin)
        .padding(.top, safeTop + 4)
        .padding(.bottom, 6)
        .frame(maxWidth: isRegular ? ipadMaxWidth : .infinity)
        .frame(maxWidth: .infinity)
        .zIndex(100)
    }

    @ViewBuilder
    private var sourceIssueSheet: some View {
        let sheet = CommandSourceIssueSheet(
            sourceNames: localizedAreaNames(store.readiness.failedAreas),
            detail: failedDetail,
            updatedText: updatedText,
            onRetry: refresh
        )

        if #available(iOS 16.0, *) {
            sheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            sheet
        }
    }

    @ViewBuilder
    private func phaseContent(isRegular: Bool, containerWidth: CGFloat) -> some View {
        switch phase {
        case .connecting:
            EmptyView()
        case .loading:
            EmptyView()
        case .ready, .allClear:
            readyContent(isRegular: isRegular, containerWidth: containerWidth)
        case .degradedEmpty:
            CommandCenterSourcePanel(
                tone: .critical,
                title: L10n("AdminCommandCenter_Offline_Title"),
                detail: failedDetail,
                sourceNames: localizedAreaNames(store.readiness.failedAreas),
                showsProgress: false,
                actionTitle: L10n("AdminCommandCenter_Retry"),
                action: refresh
            )
        case .denied:
            EmptyView()
        }
    }

    private func readyContent(isRegular: Bool, containerWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AdminCommandMetric.sectionSpacing) {
            // Deck 1: Sovereign POS Console Station (Fast Sell & POS History)
            CommandPOSDeck(
                isRegular: isRegular,
                containerWidth: containerWidth,
                onRoute: { route($0) }
            )

            // Deck 2: Sovereign Stock & Catalog Horizon (Accessories, Food & Live Pets)
            CommandStockDeck(
                signals: store.snapshot.signals,
                isRegular: isRegular,
                containerWidth: containerWidth,
                onRoute: { route($0) }
            )

            // Deck 3: Operations Launchpad & Quick Actions Matrix
            CommandQuickActionsDeck(
                signals: store.snapshot.signals,
                isRegular: isRegular,
                containerWidth: containerWidth,
                onRoute: { route($0) }
            )

            if isRegular {
                // MARK: - iPad Multi-Horizon Flight Deck
                // Deck 2: Twin Telemetry Horizons (Accounting & Hotel side-by-side)
                if store.canAccessHotel {
                    HStack(alignment: .top, spacing: 14) {
                        CommandAccountingSovereignCard(
                            onRoute: { route("accounting") }
                        )
                        .frame(maxWidth: .infinity)

                        CommandHotelSovereignCard(
                            onRoute: { route("hotel") }
                        )
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    CommandAccountingSovereignCard(
                        onRoute: { route("accounting") }
                    )
                }

                // Deck 3: Panoramic Tactical Operational Beacon
                CommandEscalationHero(
                    model: heroModel,
                    isRegular: true,
                    onPrimary: { signal in route(signal.id) }
                )
                .transition(reduceMotion ? .identity : .opacity)

                // Deck 4: Dual-Wing Base Deck (Priority Runway + Source Ledger)
                HStack(alignment: .top, spacing: 14) {
                    CommandPriorityRunway(
                        title: runwayTitle,
                        detail: runwayDetail,
                        signals: store.snapshot.signals,
                        locale: locale,
                        action: { route($0.id) }
                    )
                    .frame(maxWidth: .infinity)

                    CommandSourceLedger(
                        title: L10n("AdminCommandCenter_SourceLedger"),
                        detail: L10n("AdminCommandCenter_SourceLedger_Detail"),
                        loadingSources: localizedAreaNames(store.readiness.loadingAreas),
                        failedSources: localizedAreaNames(store.readiness.failedAreas),
                        updatedText: updatedText
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                // MARK: - iPhone Single-Column High-Velocity Stack (Preserved 100%)
                // Index 2: Accounting Sovereign Card
                CommandAccountingSovereignCard(
                    onRoute: { route("accounting") }
                )

                // Index 3: Pets Hotel Sovereign Card
                if store.canAccessHotel {
                    CommandHotelSovereignCard(
                        onRoute: { route("hotel") }
                    )
                }

                // Index 4: Operational Health & Escalation Hero (Tactical Operational Beacon)
                CommandEscalationHero(
                    model: heroModel,
                    isRegular: false,
                    onPrimary: { signal in route(signal.id) }
                )
                .transition(reduceMotion ? .identity : .opacity)

                CommandPriorityRunway(
                    title: runwayTitle,
                    detail: runwayDetail,
                    signals: store.snapshot.signals,
                    locale: locale,
                    action: { route($0.id) }
                )

                CommandSourceLedger(
                    title: L10n("AdminCommandCenter_SourceLedger"),
                    detail: L10n("AdminCommandCenter_SourceLedger_Detail"),
                    loadingSources: localizedAreaNames(store.readiness.loadingAreas),
                    failedSources: localizedAreaNames(store.readiness.failedAreas),
                    updatedText: updatedText
                )
            }
        }
    }

    private var situation: AdminCommandSituation {
        switch phase {
        case .connecting:
            return AdminCommandSituation(
                tone: .info,
                title: L10n("AdminCommandCenter_Connecting"),
                detail: L10n("AdminCommandCenter_Connecting_Detail"),
                badge: L10n("AdminCommandOrbit_Connecting_Badge"),
                symbol: "antenna.radiowaves.left.and.right",
                showsProgress: true
            )
        case .loading:
            return AdminCommandSituation(
                tone: .info,
                title: L10n("AdminCommandCenter_Confirming"),
                detail: confirmingDetail,
                badge: L10n("AdminCommandCenter_LoadingSources"),
                symbol: "arrow.triangle.2.circlepath",
                showsProgress: true
            )
        case .ready:
            if totalAttentionCount > 0 {
                return AdminCommandSituation(
                    tone: highestTone,
                    title: L10n("CommandCenter_Health_Attention"),
                    detail: String(format: L10n("CommandCenter_Health_Attention_Format"), formattedCount(totalAttentionCount)),
                    badge: L10n("AdminCommandCenter_LiveSystem"),
                    symbol: highestTone.symbol,
                    showsProgress: false
                )
            }
            return AdminCommandSituation(
                tone: .stable,
                title: L10n("CommandCenter_Health_Stable"),
                detail: L10n("CommandCenter_Health_Stable_Detail"),
                badge: L10n("AdminCommandCenter_LiveSystem"),
                symbol: "checkmark.shield.fill",
                showsProgress: false
            )
        case .allClear:
            return AdminCommandSituation(
                tone: .stable,
                title: L10n("AdminCommandCenter_AllClear_Title"),
                detail: L10n("AdminCommandCenter_AllClear_Detail"),
                badge: L10n("AdminCommandCenter_NoAttention"),
                symbol: "checkmark.seal.fill",
                showsProgress: false
            )
        case .degradedEmpty:
            return AdminCommandSituation(
                tone: .critical,
                title: L10n("AdminCommandCenter_Offline_Title"),
                detail: failedDetail,
                badge: L10n("AdminCommandCenter_SourceIssue_Title"),
                symbol: "wifi.exclamationmark",
                showsProgress: false
            )
        case .denied:
            return AdminCommandSituation(
                tone: .muted,
                title: L10n("AdminCommandCenter_NoAccess_Title"),
                detail: L10n("AdminCommandCenter_NoAccess_Detail"),
                badge: L10n("AdminCommandCenter_AccessScope"),
                symbol: "lock.shield",
                showsProgress: false
            )
        }
    }

    private var primarySignal: AdminCommandOrbitSignal? {
        prioritizedSignals.first
    }

    /// Signals ordered by escalation priority: tier, then urgency, then load.
    /// The hero spine, the tier legend, and the primary command all read from
    /// this single ordering so the visual sequence matches the decision order.
    private var prioritizedSignals: [AdminCommandOrbitSignal] {
        store.snapshot.signals.sorted {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.urgency != $1.urgency { return $0.urgency > $1.urgency }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.id < $1.id
        }
    }

    private var heroModel: CommandHeroModel {
        let currentSituation = situation
        let primary = primarySignal
        return CommandHeroModel(
            situation: currentSituation,
            totalCountText: formattedCount(totalAttentionCount),
            usesNumericLoad: !store.snapshot.signals.isEmpty || currentSituation.tone == .stable,
            segments: loadSegments,
            tierGroups: tierGroups,
            stateClassLabel: stateClassLabel,
            capabilityText: capabilityText,
            updatedText: updatedText,
            primarySignal: primary,
            primaryActionTitle: primary.map(primaryActionTitle(for:)) ?? "",
            primaryCountText: primary.flatMap { $0.count > 0 ? formattedCount($0.count) : nil },
            hasLiveSignal: store.snapshot.signals.contains { $0.isLive },
            loadAccessibilityValue: loadAccessibilityValue,
            distributionAccessibilityValue: distributionAccessibilityValue
        )
    }

    /// One spine segment per authorized signal. Width weight is the real item
    /// count with a floor of one so a live area with no countable item stays
    /// legible instead of collapsing to nothing.
    private var loadSegments: [CommandLoadSegment] {
        prioritizedSignals.map { signal in
            CommandLoadSegment(
                id: signal.id,
                weight: Double(max(signal.count, 1)),
                accent: signal.tier.tone.accent
            )
        }
    }

    private var tierGroups: [CommandTierGroup] {
        var order: [AdminCommandPriorityTier] = []
        var totals: [AdminCommandPriorityTier: Int] = [:]
        for signal in prioritizedSignals {
            if totals[signal.tier] == nil {
                order.append(signal.tier)
                totals[signal.tier] = 0
            }
            totals[signal.tier, default: 0] += max(signal.count, 0)
        }
        return order.map { tier in
            let total = totals[tier] ?? 0
            return CommandTierGroup(
                id: tier.rawValue,
                label: tier.localizedLabel,
                countText: total > 0 ? formattedCount(total) : nil,
                accent: tier.tone.accent
            )
        }
    }

    /// Severity class for the operational-state ledger line. It reports the
    /// class of the highest-priority authorized signal instead of repeating the
    /// headline sentence, and stays absent while no class can be established.
    private var stateClassLabel: String? {
        switch phase {
        case .connecting, .loading, .denied:
            return nil
        case .ready:
            return (primarySignal?.tier ?? .ready).localizedLabel
        case .allClear:
            return AdminCommandPriorityTier.ready.localizedLabel
        case .degradedEmpty:
            return AdminCommandPriorityTier.elevated.localizedLabel
        }
    }

    private var loadAccessibilityValue: String {
        let currentSituation = situation
        if currentSituation.showsProgress || (store.snapshot.signals.isEmpty && currentSituation.tone != .stable) {
            return currentSituation.title
        }
        return String(format: L10n("AdminCommandCenter_Count_Format"), formattedCount(totalAttentionCount))
    }

    private var distributionAccessibilityValue: String {
        let groups = tierGroups
        guard !groups.isEmpty else { return situation.title }
        let template = L10n("AdminCommandCenter_TierCount_Format")
        let parts = groups.map { group -> String in
            guard let countText = group.countText else { return group.label }
            return String(format: template, group.label, countText)
        }
        return localizedList(parts)
    }

    private func primaryActionTitle(for signal: AdminCommandOrbitSignal) -> String {
        let module = signal.moduleTitle.isEmpty ? signal.title : signal.moduleTitle
        return String(format: L10n("AdminCommandCenter_PrimaryAction_Format"), module)
    }

    private var totalAttentionCount: Int {
        let attentionSignals = store.snapshot.signals.filter(\.isAttentionBearing)
        let count = attentionSignals.reduce(0) { $0 + max($1.count, 0) }
        return max(count, attentionSignals.isEmpty ? 0 : 1)
    }

    private var highestTone: AdminCommandTone {
        primarySignal?.tier.tone ?? .stable
    }

    private var readinessTone: AdminCommandTone {
        if !store.readiness.failedAreas.isEmpty { return .elevated }
        if !store.readiness.loadingAreas.isEmpty || !store.snapshot.isInitialized { return .info }
        return .stable
    }

    private var runwayTitle: String {
        totalAttentionCount > 0 ? L10n("CommandCenter_Needs_Attention") : L10n("CommandCenter_Command_Spine")
    }

    private var runwayDetail: String {
        totalAttentionCount > 0 ? L10n("CommandCenter_Needs_Attention_Detail") : L10n("CommandCenter_Command_Spine_Detail")
    }

    private var roleDisplayName: String {
        store.snapshot.roleName.isEmpty ? L10n("pp_role_admin") : store.snapshot.roleName
    }

    private var capabilityText: String {
        String(format: L10n("AdminCommand_ModuleCount_Format"), store.snapshot.capabilityCount)
    }

    private var languageToggleTitle: String {
        L10n(store.localeCode == "ar" ? "Language_English_Code" : "Language_Arabic_Code")
    }

    private var compactReadinessText: String {
        if !store.readiness.failedAreas.isEmpty { return L10n("AdminCommandCenter_SourceIssue_Title") }
        if !store.readiness.loadingAreas.isEmpty { return L10n("AdminCommandCenter_LoadingSources") }
        if !store.snapshot.isInitialized { return L10n("AdminCommandCenter_Connecting") }
        return L10n("AdminCommandCenter_Ready_Detail")
    }

    private var confirmingDetail: String {
        let areas = localizedAreaNames(store.readiness.loadingAreas)
        guard !areas.isEmpty else {
            return L10n("AdminCommandCenter_Confirming_Detail")
        }
        return String(format: L10n("AdminCommandCenter_Confirming_Format"), localizedList(areas))
    }

    private var failedDetail: String {
        let areas = localizedAreaNames(store.readiness.failedAreas)
        guard !areas.isEmpty else {
            return L10n("AdminCommandCenter_Offline_Detail")
        }
        return String(format: L10n("AdminCommandCenter_Degraded_Format"), localizedList(areas))
    }

    private var updatedText: String {
        guard let updatedAt = store.readiness.updatedAt else {
            return L10n("AdminCommandCenter_NotConfirmed")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: updatedAt, relativeTo: Date())
        return String(format: L10n("AdminCommandCenter_LastConfirmed_Format"), relative)
    }

    private func localizedAreaNames(_ areas: [String]) -> [String] {
        areas.map { area in
            let orbitKey = "AdminCommandOrbit_Area_\(area)"
            let commandKey = "CommandCenter_Area_\(area)"
            let orbitValue = Language.get(orbitKey, alter: nil)
            if orbitValue != orbitKey { return orbitValue }
            let commandValue = Language.get(commandKey, alter: nil)
            return commandValue == commandKey ? area : commandValue
        }
    }

    private func localizedList(_ values: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    private func L10n(_ key: String) -> String {
        Language.get(key, alter: nil)
    }

    private func route(_ tag: String) {
        guard !tag.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.onRoute?(tag)
    }

    private func refresh() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.onRefresh?()
    }

}

// MARK: - Workplace Header

/// Presentation only. Snapshot, staff scope, branch selection and routes stay
/// with their existing owners; every visible action is a sibling native control.
private struct CommandCenterChrome: View {
    let displayName: String
    let avatarURL: String
    let roleName: String
    let capabilityText: String
    let readinessText: String
    let readinessTone: AdminCommandTone
    let onReadinessTap: (() -> Void)?
    let languageTitle: String
    let onAccount: () -> Void
    let onRefresh: () -> Void
    let onLanguage: () -> Void
    let onLogout: () -> Void
    let onSelectBranch: () -> Void
    var isRegular: Bool = false

    @ObservedObject private var branchContextStore = BranchContextStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isShowingMoreMenu: Bool = false
    @State private var isSpinningRefresh: Bool = false
    @State private var pulseBeacon: Bool = false
    @ScaledMetric(relativeTo: .body) private var avatarSide: CGFloat = 36

    private var secondaryInk: Color {
        contrast == .increased ? AdminSurface.primaryText : AdminSurface.secondaryText
    }

    private var actionInk: Color {
        contrast == .increased ? AdminSurface.primaryText : Color(uiColor: .ppAccentText)
    }

    var body: some View {
        Group {
            if isRegular {
                ipadCommandBar
            } else {
                iphoneCommandCockpit
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("admin.command.header")
    }

    // MARK: - iPhone Sovereign Command Cockpit
    private var iphoneCommandCockpit: some View {
        VStack(spacing: 8) {
            // Tier 1: Flight Deck (Operator Identity & Precision Utility Cluster)
            HStack(alignment: .center, spacing: 10) {
                operatorIdentityPodiPhone

                Spacer(minLength: 4)

                flightUtilityClusteriPhone
            }

            // Tier 2: Active Working Branch Sovereign Chamber
            workingBranchChamberiPhone

            // Tier 3: Live Operations Telemetry Rail
            telemetryRailiPhone
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    AdminSurface.hairline,
                    lineWidth: contrast == .increased ? 1 : AdminStroke.hairline
                )
                .allowsHitTesting(false)
        }
        .shadow(
            color: AdminShadow.card.color,
            radius: AdminShadow.card.radius,
            y: AdminShadow.card.y
        )
        .zIndex(isShowingMoreMenu ? 10 : 1)
    }

    private var operatorIdentityPodiPhone: some View {
        Button(action: onAccount) {
            HStack(spacing: 9) {
                // Avatar with live authentication status indicator
                ZStack(alignment: .bottomTrailing) {
                    AdminRemoteImage(
                        url: resolvedAvatarURL,
                        contentMode: .fill,
                        targetSize: CGSize(width: 36, height: 36)
                    ) {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    Color(uiColor: .ppPrimary).opacity(0.16),
                                    Color(uiColor: .ppSoftRose).opacity(0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Text(monogram)
                                .font(PPBrandFont.bold(size: 14, relativeTo: .subheadline))
                                .foregroundStyle(actionInk)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                    )

                    // Authenticated live session indicator dot
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(AdminSurface.surface, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(resolvedDisplayName)
                        .font(PPBrandFont.bold(size: 15, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(roleName)
                            .font(PPBrandFont.medium(size: 11, relativeTo: .caption2))
                            .foregroundStyle(secondaryInk)
                            .lineLimit(1)

                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(secondaryInk.opacity(0.5))

                        Text("ADMIN")
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(actionInk)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandHeaderPressStyle())
        .accessibilityLabel(resolvedDisplayName)
        .accessibilityValue("\(roleName), \(capabilityText)")
        .accessibilityIdentifier("admin.command.header.account")
    }

    private var flightUtilityClusteriPhone: some View {
        HStack(spacing: 6) {
            // Language Matrix Switcher Pill
            Button(action: onLanguage) {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .semibold))
                    Text(languageTitle)
                        .font(PPBrandFont.bold(size: 12, relativeTo: .footnote))
                        .environment(\.layoutDirection, .leftToRight)
                }
                .foregroundStyle(AdminSurface.primaryText)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(
                    AdminSurface.control,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CommandHeaderPressStyle())
            .accessibilityLabel(Language.get("Confirm_LanguageChange_Title", alter: nil))
            .accessibilityValue(languageTitle)
            .accessibilityIdentifier("admin.command.header.language")

            // Live Sync Radar Refresh Button with rotation animation
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    isSpinningRefresh = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    isSpinningRefresh = false
                }
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSpinningRefresh ? AdminSurface.primary : AdminSurface.primaryText)
                    .rotationEffect(.degrees(isSpinningRefresh ? 360 : 0))
                    .frame(width: 32, height: 32)
                    .background(
                        isSpinningRefresh ? AdminSurface.primary.opacity(0.12) : AdminSurface.control,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSpinningRefresh ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline, lineWidth: 0.75)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(CommandHeaderPressStyle())
            .accessibilityLabel(Language.get("AdminCommandCenter_Refresh", alter: nil))
            .accessibilityIdentifier("admin.command.header.refresh")

            // Mission More Menu Button
            moreActionsMenu
        }
    }

    private var workingBranchChamberiPhone: some View {
        Button(action: triggerBranchSwitch) {
            HStack(alignment: .center, spacing: 10) {
                // Storefront Emblem with glowing Ruby-to-Coral Gradient Squircle
                ZStack {
                    LinearGradient(
                        colors: canSwitchBranch
                            ? [Color(uiColor: .ppPrimary), Color(uiColor: .ppPrimary).opacity(0.80)]
                            : [AdminSurface.control, AdminSurface.hairline],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "storefront.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canSwitchBranch ? Color.white : secondaryInk)
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .shadow(
                    color: canSwitchBranch ? Color(uiColor: .ppPrimary).opacity(0.24) : Color.clear,
                    radius: 5,
                    y: 2
                )

                // Branch Details
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(Language.get("AdminCommandCenter_Header_WorkingBranch", alter: "فرع العمل"))
                            .font(PPBrandFont.medium(size: 11, relativeTo: .caption2))
                            .foregroundStyle(secondaryInk)

                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 5, height: 5)
                    }

                    Text(currentBranchDisplayName)
                        .font(PPBrandFont.bold(size: 16.5, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Tactile Switch Affordance Pill
                if canSwitchBranch {
                    HStack(spacing: 4) {
                        Text(Language.get("AdminCommandCenter_Header_Switch", alter: "تبديل"))
                            .font(PPBrandFont.bold(size: 11.5, relativeTo: .caption))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .foregroundStyle(Color(uiColor: .ppPrimary))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Color(uiColor: .ppPrimary).opacity(0.10),
                        in: Capsule(style: .continuous)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(uiColor: .ppPrimary).opacity(0.22), lineWidth: 0.75)
                    )
                } else if !branchContextStore.availableBranches.isEmpty {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondaryInk)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                AdminSurface.control.opacity(0.65),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandHeaderPressStyle())
        .disabled(!canSwitchBranch)
        .accessibilityLabel(Language.get(
            canSwitchBranch ? "BranchContext_Switcher_Title" : "AdminCommandCenter_Header_WorkingBranch",
            alter: nil
        ))
        .accessibilityValue(currentBranchDisplayName)
        .accessibilityIdentifier("admin.command.header.branch")
    }

    private var telemetryRailiPhone: some View {
        Group {
            if let onReadinessTap {
                Button(action: onReadinessTap) {
                    telemetryRailContent
                        .contentShape(Rectangle())
                }
                .buttonStyle(CommandHeaderPressStyle())
                .accessibilityLabel(readinessText)
                .accessibilityHint(Language.get("AdminCommandCenter_SourceIssue_TapHint", alter: nil))
                .accessibilityIdentifier("admin.command.header.readiness")
            } else {
                telemetryRailContent
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(readinessText)
                    .accessibilityIdentifier("admin.command.header.readiness")
            }
        }
    }

    private var telemetryRailContent: some View {
        HStack(alignment: .center, spacing: 6) {
            // Live radar pulse dot with glowing halo
            ZStack {
                Circle()
                    .fill(readinessTone.accent.opacity(0.22))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulseBeacon ? 1.25 : 0.95)
                    .opacity(pulseBeacon ? 0.7 : 1.0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulseBeacon)

                Circle()
                    .fill(readinessTone.accent)
                    .frame(width: 6.5, height: 6.5)
            }
            .frame(width: 16, height: 16)

            Text(readinessText)
                .font(PPBrandFont.medium(size: 12, relativeTo: .caption))
                .foregroundStyle(onReadinessTap == nil ? secondaryInk : AdminSurface.primaryText)
                .lineLimit(1)

            Spacer(minLength: 4)

            if onReadinessTap != nil {
                HStack(spacing: 2) {
                    Text(Language.get("AdminCommandCenter_SourceIssue_SheetTitle", alter: "التفاصيل"))
                        .font(PPBrandFont.bold(size: 10.5, relativeTo: .caption2))
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                }
                .foregroundStyle(readinessTone.accent)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .onAppear {
            pulseBeacon = true
        }
    }

    // MARK: - iPad Aerospace Command Bar
    private var ipadCommandBar: some View {
        HStack(alignment: .center, spacing: 16) {
            // Wing 1: Working Branch Control Station
            workingBranchIPadStation

            Spacer(minLength: 12)

            // Wing 2: Real-Time Telemetry & Readiness Radar
            readinessControlIPad

            Spacer(minLength: 12)

            // Wing 3: Utility Flight Tools + Operator Identity Capsule
            HStack(spacing: 10) {
                utilityActionsIPad

                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(width: 1, height: 24)
                    .accessibilityHidden(true)

                accountSignatureIPad
                moreActionsMenu
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    AdminSurface.hairline,
                    lineWidth: contrast == .increased ? 1 : AdminStroke.hairline
                )
                .allowsHitTesting(false)
        }
        .shadow(
            color: AdminShadow.card.color,
            radius: AdminShadow.card.radius,
            y: AdminShadow.card.y
        )
        .zIndex(isShowingMoreMenu ? 10 : 1)
    }

    private var workingBranchIPadStation: some View {
        Button(action: triggerBranchSwitch) {
            HStack(alignment: .center, spacing: 12) {
                // Branch Storefront Glyphed Squircle with gradient
                ZStack {
                    LinearGradient(
                        colors: canSwitchBranch
                            ? [Color(uiColor: .ppPrimary), Color(uiColor: .ppPrimary).opacity(0.82)]
                            : [AdminSurface.control, AdminSurface.hairline],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "storefront.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSwitchBranch ? Color.white : secondaryInk)
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(
                    color: canSwitchBranch ? Color(uiColor: .ppPrimary).opacity(0.24) : Color.clear,
                    radius: 6,
                    y: 2
                )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(Language.get("AdminCommandCenter_Header_WorkingBranch", alter: "فرع العمل والتشغيل"))
                            .font(PPBrandFont.medium(size: 11.5, relativeTo: .caption2))
                            .foregroundStyle(secondaryInk)

                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 5.5, height: 5.5)
                    }

                    Text(currentBranchDisplayName)
                        .font(PPBrandFont.bold(size: 18, relativeTo: .title3))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                }

                if canSwitchBranch {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(Language.get("AdminCommandCenter_Header_Switch", alter: "تبديل"))
                            .font(PPBrandFont.bold(size: 11.5, relativeTo: .caption))
                    }
                    .foregroundStyle(Color(uiColor: .ppPrimary))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Color(uiColor: .ppPrimary).opacity(0.10),
                        in: Capsule(style: .continuous)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(uiColor: .ppPrimary).opacity(0.25), lineWidth: 0.75)
                    )
                } else if !branchContextStore.availableBranches.isEmpty {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondaryInk)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandHeaderPressStyle())
        .disabled(!canSwitchBranch)
        .accessibilityLabel(Language.get(
            canSwitchBranch ? "BranchContext_Switcher_Title" : "AdminCommandCenter_Header_WorkingBranch",
            alter: nil
        ))
        .accessibilityValue(currentBranchDisplayName)
        .accessibilityIdentifier("admin.command.header.branch.ipad")
    }

    private var readinessControlIPad: some View {
        Group {
            if let onReadinessTap {
                Button(action: onReadinessTap) {
                    readinessContentIPad
                        .contentShape(Rectangle())
                }
                .buttonStyle(CommandHeaderPressStyle())
                .accessibilityLabel(readinessText)
                .accessibilityHint(Language.get("AdminCommandCenter_SourceIssue_TapHint", alter: nil))
                .accessibilityIdentifier("admin.command.header.readiness.ipad")
            } else {
                readinessContentIPad
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(readinessText)
                    .accessibilityIdentifier("admin.command.header.readiness.ipad")
            }
        }
    }

    private var readinessContentIPad: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(readinessTone.accent.opacity(0.20))
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulseBeacon ? 1.25 : 0.95)
                    .opacity(pulseBeacon ? 0.7 : 1.0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulseBeacon)

                Circle()
                    .fill(readinessTone.accent)
                    .frame(width: 7.5, height: 7.5)
            }
            .frame(width: 18, height: 18)

            Text(readinessText)
                .font(PPBrandFont.bold(size: 13, relativeTo: .footnote))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)

            if onReadinessTap != nil {
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(readinessTone.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            AdminSurface.control,
            in: Capsule(style: .continuous)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(readinessTone.accent.opacity(0.25), lineWidth: 0.75)
        )
        .onAppear {
            pulseBeacon = true
        }
    }

    private var utilityActionsIPad: some View {
        HStack(spacing: 8) {
            // Language Matrix Switcher
            Button(action: onLanguage) {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .semibold))
                    Text(languageTitle)
                        .font(PPBrandFont.bold(size: 13, relativeTo: .footnote))
                        .environment(\.layoutDirection, .leftToRight)
                }
                .foregroundStyle(AdminSurface.primaryText)
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(
                    AdminSurface.control,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CommandHeaderPressStyle())
            .accessibilityLabel(Language.get("Confirm_LanguageChange_Title", alter: nil))
            .accessibilityValue(languageTitle)
            .accessibilityIdentifier("admin.command.header.language.ipad")

            // Live Sync Refresh with Haptics and Spin Animation
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    isSpinningRefresh = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    isSpinningRefresh = false
                }
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSpinningRefresh ? AdminSurface.primary : AdminSurface.primaryText)
                    .rotationEffect(.degrees(isSpinningRefresh ? 360 : 0))
                    .frame(width: 36, height: 36)
                    .background(
                        isSpinningRefresh ? AdminSurface.primary.opacity(0.12) : AdminSurface.control,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(isSpinningRefresh ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline, lineWidth: 0.75)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(CommandHeaderPressStyle())
            .accessibilityLabel(Language.get("AdminCommandCenter_Refresh", alter: nil))
            .accessibilityIdentifier("admin.command.header.refresh.ipad")
        }
    }

    private var accountSignatureIPad: some View {
        Button(action: onAccount) {
            HStack(spacing: 9) {
                AdminRemoteImage(
                    url: resolvedAvatarURL,
                    contentMode: .fill,
                    targetSize: CGSize(width: 36, height: 36)
                ) {
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(uiColor: .ppPrimary).opacity(0.16),
                                Color(uiColor: .ppSoftRose).opacity(0.40)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(monogram)
                            .font(PPBrandFont.bold(size: 14, relativeTo: .subheadline))
                            .foregroundStyle(actionInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(resolvedDisplayName)
                        .font(PPBrandFont.bold(size: 14, relativeTo: .footnote))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(roleName)
                            .font(PPBrandFont.medium(size: 11, relativeTo: .caption2))
                            .foregroundStyle(secondaryInk)
                            .lineLimit(1)

                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(secondaryInk.opacity(0.5))

                        Text("ADMIN")
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(actionInk)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandHeaderPressStyle())
        .accessibilityLabel(resolvedDisplayName)
        .accessibilityValue("\(roleName), \(capabilityText)")
        .accessibilityIdentifier("admin.command.header.account.ipad")
    }


    // MARK: - Actions Menu (Beiruti Brand Font)

    private var moreActionsMenu: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isShowingMoreMenu.toggle()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isShowingMoreMenu ? AdminSurface.primary : AdminSurface.primaryText)
                .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                .background(
                    isShowingMoreMenu ? AdminSurface.primary.opacity(0.12) : AdminSurface.control,
                    in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                        .strokeBorder(isShowingMoreMenu ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(CommandHeaderPressStyle())
        .accessibilityLabel(Language.get("CommandCenter_Tab_More", alter: nil))
        .accessibilityIdentifier("admin.command.header.more")
        .background {
            if isShowingMoreMenu {
                Color.black.opacity(0.001)
                    .frame(width: 3000, height: 3000)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            isShowingMoreMenu = false
                        }
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isShowingMoreMenu {
                customMoreActionsMenuCard
                    .offset(y: AdminTouchTarget.minimum + 8)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.88, anchor: .topTrailing).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing))
                    ))
                    .zIndex(500)
            }
        }
    }

    private var customMoreActionsMenuCard: some View {
        VStack(spacing: 0) {
            menuRow(
                title: Language.get("AdminCommandCenter_Refresh", alter: nil),
                systemImage: "arrow.clockwise",
                isDestructive: false
            ) {
                onRefresh()
            }

            menuDivider

            menuRow(
                title: Language.get("EditMyAccount_Title", alter: nil),
                systemImage: "person.crop.circle",
                isDestructive: false
            ) {
                onAccount()
            }

            menuDivider

            menuRow(
                title: String(format: Language.get("AdminCommandCenter_Header_Language_Format", alter: nil), languageTitle),
                systemImage: "globe",
                isDestructive: false
            ) {
                onLanguage()
            }

            menuDivider

            menuRow(
                title: Language.get("Logout", alter: nil),
                systemImage: "rectangle.portrait.and.arrow.right",
                isDestructive: true
            ) {
                onLogout()
            }
        }
        .frame(width: 230)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: 10)
        .environment(\.layoutDirection, layoutDirection)
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(AdminSurface.hairline)
            .frame(height: 0.75)
            .padding(.horizontal, 12)
    }

    private func menuRow(
        title: String,
        systemImage: String,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                isShowingMoreMenu = false
            }
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(isDestructive ? Color(uiColor: .ppPressedAction) : AdminSurface.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isDestructive ? Color(uiColor: .ppPressedAction) : AdminSurface.primary)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandMenuRowPressStyle())
    }

    // MARK: - Existing Context and Identity Resolution

    private var currentBranchDisplayName: String {
        let name = branchContextStore.currentBranchDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Language.get("BranchContext_SelectBranch_Prompt", alter: nil) : name
    }

    private var canSwitchBranch: Bool {
        branchContextStore.availableBranches.count > 1
    }

    private func triggerBranchSwitch() {
        guard canSwitchBranch else { return }
        let feedback = UIImpactFeedbackGenerator(style: .soft)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.82)
        onSelectBranch()
    }

    private var resolvedDisplayName: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? roleName : trimmedName
    }

    private var resolvedAvatarURL: URL? {
        let trimmedURL = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty, let url = URL(string: trimmedURL) {
            return url
        }
        if let user = UserManager.shared().currentUser {
            if let photo = user.photoURL, let url = URL(string: photo), !photo.isEmpty {
                return url
            }
            if let imgUrl = user.userImageUrl {
                return imgUrl
            }
            if let name = user.userImageName, let url = URL(string: name), !name.isEmpty {
                return url
            }
        }
        if let staffPhoto = PPStaffAuth.shared().cachedCurrentStaff?.photoURL, let url = URL(string: staffPhoto), !staffPhoto.isEmpty {
            return url
        }
        if let authPhoto = Auth.auth().currentUser?.photoURL {
            return authPhoto
        }
        return nil
    }

    private var monogram: String {
        let parts = resolvedDisplayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "PP" : letters.uppercased()
    }
}

/// Immediate press acknowledgement, with no extra motion or request state.
/// Native Menu/sheet presentations keep their system accessibility behavior.
private struct CommandHeaderPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .transaction { transaction in
                transaction.animation = nil
            }
    }
}

private struct CommandMenuRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? AdminSurface.primarySoft.opacity(0.6) : Color.clear)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

private struct CommandStatusLine: View {
    let text: String
    let tone: AdminCommandTone
    let action: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) {
                statusContent
                    .frame(minHeight: AdminTouchTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CommandPressStyle())
            .accessibilityHint(Language.get("AdminCommandCenter_SourceIssue_TapHint", alter: nil))
        } else {
            statusContent
                .frame(minHeight: 24)
        }
    }

    private var statusContent: some View {
        HStack(spacing: 8) {
            Image(systemName: tone.symbol)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tone.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(AdminType.captionBold)
                .foregroundStyle(tone.color)
                .lineLimit(2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CommandSourceIssueSheet: View {
    let sourceNames: [String]
    let detail: String
    let updatedText: String
    let onRetry: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                header

                Text(Language.get("AdminCommandCenter_SourceIssue_SheetDetail", alter: nil))
                    .font(AdminType.callout)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: AdminSpacing.md) {
                    Text(Language.get("AdminCommandCenter_SourceIssue_AffectedSources", alter: nil))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminCommandInk.secondary)

                    ForEach(sourceNames, id: \.self) { sourceName in
                        HStack(spacing: AdminSpacing.md) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AdminCommandTone.elevated.accent)
                                .accessibilityHidden(true)
                            Text(sourceName)
                                .font(AdminType.headline)
                                .foregroundStyle(AdminSurface.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: AdminTouchTarget.minimum)
                    }

                    Divider()

                    Text(detail)
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(updatedText)
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminCommandInk.tertiary)
                }
                .padding(AdminSpacing.base)
                .background(
                    RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                        .fill(AdminSurface.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                )

                Button {
                    dismiss()
                    onRetry()
                } label: {
                    Label(
                        Language.get("AdminCommandCenter_Retry", alter: nil),
                        systemImage: "arrow.clockwise"
                    )
                    .font(AdminType.headline)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable)
                    .background(
                        RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                            .fill(AdminSurface.primary)
                    )
                }
                .buttonStyle(CommandPressStyle())
                .accessibilityHint(Language.get("AdminCommandOrbit_Refresh_Hint", alter: nil))
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, AdminSpacing.lg)
            .padding(.bottom, AdminSpacing.xl)
        }
        .background(AdminSurface.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AdminSpacing.md) {
            ZStack {
                Circle()
                    .fill(AdminCommandTone.elevated.softFill)
                Image(systemName: AdminCommandTone.elevated.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AdminCommandTone.elevated.accent)
                    .accessibilityHidden(true)
            }
            .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)

            Text(Language.get("AdminCommandCenter_SourceIssue_SheetTitle", alter: nil))
                .font(AdminType.title3)
                .foregroundStyle(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    .background(AdminSurface.control, in: Circle())
            }
            .buttonStyle(CommandPressStyle())
            .accessibilityLabel(Language.get("Close", alter: nil))
        }
    }
}

// MARK: - Escalation Hero

/// One proportional slice of the escalation spine. `weight` is the real item
/// count reported for an authorized area, floored at one so an area that is
/// flagged without a countable item still occupies legible width.
private struct CommandLoadSegment: Identifiable, Equatable {
    let id: String
    let weight: Double
    let accent: Color
}

/// Aggregate load for one priority class, used by the spine legend.
/// `countText` is absent when the class carries no countable item.
private struct CommandTierGroup: Identifiable, Equatable {
    let id: Int
    let label: String
    let countText: String?
    let accent: Color
}

/// Every value the hero renders. All of it is derived by the owning screen from
/// the live store, so the hero never computes, invents, or caches operational
/// figures and never decides routing on its own.
private struct CommandHeroModel: Equatable {
    let situation: AdminCommandSituation
    let totalCountText: String
    let usesNumericLoad: Bool
    let segments: [CommandLoadSegment]
    let tierGroups: [CommandTierGroup]
    let stateClassLabel: String?
    let capabilityText: String
    let updatedText: String
    let primarySignal: AdminCommandOrbitSignal?
    let primaryActionTitle: String
    let primaryCountText: String?
    let hasLiveSignal: Bool
    let loadAccessibilityValue: String
    let distributionAccessibilityValue: String
}

/// The dominant operational anchor of the command surface.
/// Reimagined as the Sovereign Command Nucleus: high-density, low-vertical-footprint,
/// multi-spectrum telemetry cockpit with integrated escalation catalyst.
private struct CommandEscalationHero: View {
    let model: CommandHeroModel
    let isRegular: Bool
    let onPrimary: (AdminCommandOrbitSignal) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var livePulse = false

    private var isAccessibilityMode: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            telemetryHorizon

            if isRegular && !isAccessibilityMode {
                panoramicIntelligenceDeck
            } else {
                compactIntelligenceCluster
            }

            if model.primarySignal != nil {
                actionCatalyst
            } else if model.situation.tone == .stable {
                stableStatusRibbon
            }
        }
        .padding(14)
        .background(heroAtmosphere)
        .overlay(heroGlassBorder)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Atmospheric Canvas

    private var heroAtmosphere: some View {
        ZStack {
            AdminSurface.control

            // Directional chromatic bloom matching tone
            RadialGradient(
                colors: [
                    model.situation.tone.accent.opacity(colorScheme == .dark ? 0.20 : 0.08),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 220
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.05), radius: 14, x: 0, y: 5)
    }

    private var heroGlassBorder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        model.situation.tone.accent.opacity(0.42),
                        Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.60 : 0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.0
            )
    }

    // MARK: - Telemetry Horizon (Top Filament)

    @ViewBuilder
    private var telemetryHorizon: some View {
        if isAccessibilityMode {
            telemetryHorizonVertical
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        liveStatusBadge
                        if let stateClass = model.stateClassLabel {
                            stateClassTag(stateClass)
                        }
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 6) {
                        freshnessTag
                        scopeTag
                    }
                }

                telemetryHorizonVertical
            }
        }
    }

    private var telemetryHorizonVertical: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                liveStatusBadge
                if let stateClass = model.stateClassLabel {
                    stateClassTag(stateClass)
                }
            }
            HStack(spacing: 6) {
                freshnessTag
                scopeTag
            }
        }
    }

    private var liveStatusBadge: some View {
        HStack(spacing: 5) {
            liveIndicator
            Text(model.situation.badge)
                .font(AdminType.captionBold)
                .foregroundStyle(model.situation.tone.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(model.situation.tone.softFill, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(model.situation.tone.accent.opacity(0.28), lineWidth: 0.75)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.situation.badge)
    }

    private func stateClassTag(_ stateClass: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.situation.tone.accent)
                .frame(width: 5, height: 5)
                .shadow(color: model.situation.tone.accent.opacity(0.6), radius: 2, x: 0, y: 0)
            Text(stateClass)
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.30 : 0.15), in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("CommandCenter_Operational_State", alter: "Operational state"))
        .accessibilityValue(stateClass)
    }

    private var freshnessTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AdminCommandInk.tertiary)
            Text(model.updatedText)
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.20 : 0.10), in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("CommandCenter_Last_Updated", alter: nil))
        .accessibilityValue(model.updatedText)
    }

    private var scopeTag: some View {
        HStack(spacing: 3) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AdminCommandInk.tertiary)
            Text(model.capabilityText)
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.20 : 0.10), in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("AdminCommandCenter_AccessScope", alter: nil))
        .accessibilityValue(model.capabilityText)
    }

    @ViewBuilder
    private var liveIndicator: some View {
        if model.hasLiveSignal {
            ZStack {
                Circle()
                    .stroke(model.situation.tone.accent.opacity(0.4), lineWidth: 1.2)
                    .frame(width: 12, height: 12)
                    .scaleEffect(livePulse ? 1.4 : 1.0)
                    .opacity(livePulse ? 0.0 : 1.0)

                Circle()
                    .fill(model.situation.tone.accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: model.situation.tone.accent.opacity(0.7), radius: 2.5, x: 0, y: 0)
            }
            .frame(width: 12, height: 12)
            .onAppear(perform: startLivePulse)
            .onChange(of: reduceMotion) { isReduced in
                if isReduced { stopLivePulse() } else { startLivePulse() }
            }
            .accessibilityHidden(true)
        } else {
            Image(systemName: model.situation.symbol)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.situation.tone.accent)
                .accessibilityHidden(true)
        }
    }

    private func startLivePulse() {
        guard !reduceMotion, !livePulse else { return }
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
            livePulse = true
        }
    }

    private func stopLivePulse() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            livePulse = false
        }
    }

    // MARK: - Compact Intelligence Cluster (iPhone)

    private var compactIntelligenceCluster: some View {
        HStack(alignment: .center, spacing: 12) {
            workloadPod
                .frame(width: 80)

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.situation.title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(model.situation.detail)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                CommandLoadSpine(
                    segments: model.segments,
                    trackAccent: model.situation.tone.accent,
                    showsPlaceholder: model.situation.showsProgress,
                    reduceMotion: reduceMotion
                )

                tierLegendRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Panoramic Intelligence Deck (iPad)

    private var panoramicIntelligenceDeck: some View {
        HStack(alignment: .center, spacing: 18) {
            workloadPod
                .frame(width: 100)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.situation.title)
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                Text(model.situation.detail)
                    .font(AdminType.caption)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(2)

                CommandLoadSpine(
                    segments: model.segments,
                    trackAccent: model.situation.tone.accent,
                    showsPlaceholder: model.situation.showsProgress,
                    reduceMotion: reduceMotion
                )

                tierLegendRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Workload Quantum Pod

    private var workloadPod: some View {
        VStack(spacing: 2) {
            Text(Language.get("AdminCommandCenter_ActiveLoad", alter: "Active Workload"))
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if model.situation.showsProgress {
                ProgressView()
                    .tint(model.situation.tone.color)
                    .scaleEffect(0.9)
                    .frame(height: 34)
            } else if model.usesNumericLoad {
                Text(model.totalCountText)
                    .font(Font.custom("Beiruti-Bold", size: 30, relativeTo: .title))
                    .foregroundStyle(AdminSurface.primaryText)
                    .monospacedDigit()
                    .commandNumericTransition()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: model.situation.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(model.situation.tone.accent)
                    .frame(height: 34)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            model.situation.tone.accent.opacity(colorScheme == .dark ? 0.16 : 0.07),
                            AdminSurface.control.opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(model.situation.tone.accent.opacity(0.24), lineWidth: 0.8)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("AdminCommandCenter_ActiveLoad", alter: nil))
        .accessibilityValue(model.loadAccessibilityValue)
    }

    // MARK: - Tier Legend Row

    @ViewBuilder
    private var tierLegendRow: some View {
        if !model.tierGroups.isEmpty {
            HStack(spacing: 8) {
                ForEach(model.tierGroups) { group in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(group.accent)
                            .frame(width: 5, height: 5)
                            .shadow(color: group.accent.opacity(0.5), radius: 1.5, x: 0, y: 0)
                        Text(group.label)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                            .lineLimit(1)
                        if let countText = group.countText {
                            Text(countText)
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(group.label)
                    .commandAccessibilityValue(group.countText.map {
                        String(format: Language.get("AdminCommandCenter_Count_Format", alter: nil), $0)
                    })
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Sovereign Action Catalyst

    private func actionCatalyst(for signal: AdminCommandOrbitSignal) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onPrimary(signal)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.20))
                    Image(systemName: signal.symbolName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(model.primaryActionTitle)
                        .font(AdminType.subheadlineBold)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Language.get("AdminCommandCenter_Act", alter: "Act now"))
                        .font(AdminType.caption2)
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                if let countText = model.primaryCountText {
                    Text(countText)
                        .font(AdminType.captionBold)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.22), in: Capsule(style: .continuous))
                        .accessibilityHidden(true)
                }

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 22, height: 22)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                signal.tier.tone.accent,
                                signal.tier.tone.accent.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: signal.tier.tone.accent.opacity(0.32), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.75)
            )
        }
        .buttonStyle(CommandPressStyle())
        .accessibilityLabel(model.primaryActionTitle)
        .commandAccessibilityValue(model.primaryCountText.map {
            String(format: Language.get("AdminCommandCenter_Count_Format", alter: nil), $0)
        })
        .accessibilityHint(Language.get("AdminCommandCenter_OpenHint", alter: nil))
    }

    @ViewBuilder
    private var actionCatalyst: some View {
        if let primary = model.primarySignal {
            actionCatalyst(for: primary)
        }
    }

    private var stableStatusRibbon: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(uiColor: .ppSuccess))

            Text(model.situation.detail)
                .font(AdminType.captionBold)
                .foregroundStyle(Color(uiColor: .ppSuccess))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .ppSuccess).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.25), lineWidth: 0.75)
        )
    }
}

// MARK: - Escalation Spine

private struct CommandLoadSpine: View {
    let segments: [CommandLoadSegment]
    let trackAccent: Color
    let showsPlaceholder: Bool
    let reduceMotion: Bool

    private let gap: CGFloat = 2.5
    private let minimumSegment: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(in: proxy.size.width)
            HStack(spacing: gap) {
                if showsPlaceholder || segments.isEmpty {
                    Capsule(style: .continuous)
                        .fill(trackAccent.opacity(0.24))
                } else {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        Capsule(style: .continuous)
                            .fill(segment.accent)
                            .frame(width: index < widths.count ? widths[index] : 0)
                            .shadow(color: segment.accent.opacity(0.35), radius: 1.5, x: 0, y: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.88), value: layoutSignature)
        }
        .frame(height: 5)
        .background(AdminSurface.control.opacity(0.5), in: Capsule(style: .continuous))
    }

    private var layoutSignature: String {
        let base = segments.map { "\($0.id):\(Int($0.weight))" }.joined(separator: "|")
        return showsPlaceholder ? base + "#pending" : base
    }

    /// Each segment receives a small fixed floor so no authorized area can
    /// disappear, and the remaining width is distributed by true weight.
    private func segmentWidths(in totalWidth: CGFloat) -> [CGFloat] {
        guard !segments.isEmpty, totalWidth > 0 else { return [] }
        let gaps = gap * CGFloat(max(segments.count - 1, 0))
        let available = max(totalWidth - gaps, 0)
        guard available > 0 else { return segments.map { _ in 0 } }
        let floorWidth = min(minimumSegment, available / CGFloat(segments.count))
        let proportional = max(available - floorWidth * CGFloat(segments.count), 0)
        let totalWeight = max(segments.reduce(0) { $0 + $1.weight }, 1)
        return segments.map { floorWidth + proportional * CGFloat($0.weight / totalWeight) }
    }
}

private extension View {
    @ViewBuilder
    func commandNumericTransition() -> some View {
        if #available(iOS 16.0, *) {
            contentTransition(.numericText())
        } else {
            self
        }
    }

    @ViewBuilder
    func commandAccessibilityValue(_ value: String?) -> some View {
        if let value = value {
            accessibilityValue(value)
        } else {
            self
        }
    }
}

// MARK: - POS Sovereign Command Console & Real-time Telemetry (Deck 1)

@MainActor
final class CommandPOSShiftTelemetryStore: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case zero
        case error(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var todayReceiptsCount: Int = 0
    @Published private(set) var todaySalesTotal: Double = 0.0
    @Published private(set) var cashSalesTotal: Double = 0.0
    @Published private(set) var cardSalesTotal: Double = 0.0
    @Published private(set) var refundsCount: Int = 0
    @Published private(set) var lastFetchDate: Date? = nil

    private var activeBranchID: String = ""
    private var isFetching: Bool = false

    func updateBranch(branchID: String) {
        let trimmed = branchID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != activeBranchID || state == .loading else { return }
        activeBranchID = trimmed
        fetchShiftTelemetry()
    }

    func fetchShiftTelemetry() {
        guard !activeBranchID.isEmpty else {
            self.state = .ready
            self.todayReceiptsCount = 0
            self.todaySalesTotal = 0.0
            return
        }

        guard !isFetching else { return }
        isFetching = true
        if state != .ready {
            state = .loading
        }

        PPPOSService.shared().fetchPOSHistory(branchID: activeBranchID) { [weak self] receipts, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isFetching = false
                self.lastFetchDate = Date()

                if let error = error {
                    if self.todayReceiptsCount == 0 {
                        self.state = .error(error.localizedDescription)
                    } else {
                        self.state = .ready
                    }
                    return
                }

                guard let receipts = receipts else {
                    self.state = .zero
                    self.todayReceiptsCount = 0
                    self.todaySalesTotal = 0.0
                    return
                }

                let calendar = Calendar.current
                var count = 0
                var total: Double = 0.0
                var cash: Double = 0.0
                var card: Double = 0.0
                var refunds = 0

                for receipt in receipts {
                    let isToday: Bool
                    if let created = receipt.createdAt {
                        isToday = calendar.isDateInToday(created)
                    } else {
                        isToday = false
                    }

                    if isToday {
                        count += 1
                        total += receipt.total
                        let method = receipt.paymentMethod.lowercased()
                        if method.contains("cash") {
                            cash += receipt.total
                        } else {
                            card += receipt.total
                        }
                        if receipt.refundedAmount > 0 {
                            refunds += 1
                        }
                    }
                }

                self.todayReceiptsCount = count
                self.todaySalesTotal = total
                self.cashSalesTotal = cash
                self.cardSalesTotal = card
                self.refundsCount = refunds

                if count == 0 {
                    self.state = .zero
                } else {
                    self.state = .ready
                }
            }
        }
    }
}

private struct CommandPOSShimmerMask: View {
    @State private var phase: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(
                colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .offset(x: phase * width * 1.5)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

private struct CommandPOSDeck: View {
    var isRegular: Bool = false
    var containerWidth: CGFloat = 0
    let onRoute: (String) -> Void

    @ObservedObject private var branchStore = BranchContextStore.shared
    @StateObject private var telemetryStore = CommandPOSShiftTelemetryStore()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isRadarPulsing = false
    @State private var arrowNudge: CGFloat = 0
    @State private var scannerSweep: CGFloat = 0

    private var currentBranchName: String {
        let name = branchStore.currentBranchDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty ? name : Language.get("Branch_Scope_Active", alter: "الفرع الحالي")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            if isRegular {
                CommandPOSiPadFlightDeck(
                    telemetryStore: telemetryStore,
                    currentBranchName: currentBranchName,
                    arrowNudge: arrowNudge,
                    scannerSweep: scannerSweep,
                    reduceMotion: reduceMotion,
                    onRoute: onRoute
                )
            } else {
                CommandPOSiPhoneCockpit(
                    telemetryStore: telemetryStore,
                    currentBranchName: currentBranchName,
                    arrowNudge: arrowNudge,
                    scannerSweep: scannerSweep,
                    reduceMotion: reduceMotion,
                    onRoute: onRoute
                )
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if let branchID = branchStore.activeBranch?.branchID {
                telemetryStore.updateBranch(branchID: branchID)
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isRadarPulsing = true
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                arrowNudge = 3.5
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                scannerSweep = 1.0
            }
        }
        .onReceive(branchStore.$activeBranch) { newBranch in
            if let branchID = newBranch?.branchID {
                telemetryStore.updateBranch(branchID: branchID)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(Language.get("AdminPOS_SectionTitle", alter: "منظومة نقاط البيع والكاشير"))
                        .font(AdminType.title3)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 3.5) {
                        Circle()
                            .fill(Color(red: 0.06, green: 0.78, blue: 0.56))
                            .frame(width: 5.5, height: 5.5)
                            .scaleEffect(isRadarPulsing && !reduceMotion ? 1.25 : 0.85)

                        Text("ONLINE")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))
                    }
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.06, green: 0.78, blue: 0.56).opacity(0.12), in: Capsule())
                }

                Text(Language.get("AdminPOS_SectionDetail", alter: "مساحة البيع الفوري السريع وإدارة سجل فواتير المبيعات"))
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Branch Beacon Pill with Pulsing Radar Halo
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .stroke(Color(red: 0.06, green: 0.78, blue: 0.56).opacity(isRadarPulsing && !reduceMotion ? 0.0 : 0.5), lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                        .scaleEffect(isRadarPulsing && !reduceMotion ? 1.8 : 0.8)

                    Circle()
                        .fill(Color(red: 0.06, green: 0.78, blue: 0.56))
                        .frame(width: 5, height: 5)
                }
                .frame(width: 10, height: 10)

                Image(systemName: "building.2.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))

                Text(currentBranchName)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(red: 0.06, green: 0.78, blue: 0.56).opacity(colorScheme == .dark ? 0.16 : 0.08), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color(red: 0.06, green: 0.78, blue: 0.56).opacity(0.18), lineWidth: 0.5)
            )
            .accessibilityLabel(Language.get("Branch_Scope_Active", alter: "الفرع الحالي") + ": \(currentBranchName)")
        }
    }
}

// MARK: - iPhone Handheld Tactical Cashier Cockpit (Dedicated Mobile Architecture)

private struct CommandPOSiPhoneCockpit: View {
    @ObservedObject var telemetryStore: CommandPOSShiftTelemetryStore
    let currentBranchName: String
    let arrowNudge: CGFloat
    let scannerSweep: CGFloat
    let reduceMotion: Bool
    let onRoute: (String) -> Void

    var body: some View {
        VStack(spacing: 11) {
            // Station 1: Commanding Express Checkout Hero Deck
            CommandPOSHeroExpressCardiPhone(
                telemetryStore: telemetryStore,
                currentBranchName: currentBranchName,
                arrowNudge: arrowNudge,
                scannerSweep: scannerSweep,
                reduceMotion: reduceMotion,
                action: { onRoute("pos") },
                quickScanAction: { onRoute("pos") }
            )

            // Station 2: Companion Shift Journal & Financial Ledger Ribbon
            CommandPOSShiftLedgerRibboniPhone(
                telemetryStore: telemetryStore,
                arrowNudge: arrowNudge,
                reduceMotion: reduceMotion,
                action: { onRoute("posHistory") }
            )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - iPhone Hero: Express Checkout Engine Card

private struct CommandPOSHeroExpressCardiPhone: View {
    @ObservedObject var telemetryStore: CommandPOSShiftTelemetryStore
    let currentBranchName: String
    let arrowNudge: CGFloat
    let scannerSweep: CGFloat
    let reduceMotion: Bool
    let action: () -> Void
    let quickScanAction: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let accent = Color(red: 0.05, green: 0.72, blue: 0.51)

    private var activeStaffName: String {
        let name = BranchContextStore.shared.currentStaff?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty ? name : Language.get("AdminPOS_ActiveCashier", alter: "الكاشير")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Telemetry Header
            HStack(spacing: 6) {
                // Live Radar Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                    Text(Language.get("AdminQuickActions_POS_Live", alter: "مباشر"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(accent.opacity(colorScheme == .dark ? 0.20 : 0.09), in: Capsule(style: .continuous))

                // Cashier Identity Pill
                HStack(spacing: 3) {
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(AdminCommandInk.secondary)
                    Text(activeStaffName)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04), in: Capsule(style: .continuous))

                Spacer(minLength: 4)

                // QIB Payment Ready Beacon
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.17))
                    Text(Language.get("AdminPOS_QIBReady", alter: "QIB جاهز للدفع"))
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AdminCommandInk.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color(red: 1.0, green: 0.78, blue: 0.17).opacity(colorScheme == .dark ? 0.15 : 0.08), in: Capsule(style: .continuous))
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)

            // Center Hero Chamber: Laser Scanner Reticle + Dynamic Content
            HStack(alignment: .center, spacing: 14) {
                // Optical Viewfinder Reticle with Laser Beam
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(colorScheme == .dark ? 0.24 : 0.12),
                                    accent.opacity(colorScheme == .dark ? 0.08 : 0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                        .shadow(color: accent.opacity(colorScheme == .dark ? 0.45 : 0.25), radius: 5, y: 1.5)

                    // Animated Laser Scan Sweep
                    if !reduceMotion {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, accent.opacity(0.85), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 2.2)
                            .offset(y: (scannerSweep - 0.5) * 32)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(colorScheme == .dark ? 0.35 : 0.18), lineWidth: 0.9)
                )

                // Title & Subtitle Hierarchy
                VStack(alignment: .leading, spacing: 3.5) {
                    Text(Language.get("AdminPOS_TerminalTitle", alter: "نقطة بيع سريعة"))
                        .font(Font.custom("Beiruti-Bold", size: 17, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(Language.get("AdminPOS_TerminalSubtitle", alter: "مسح باركود • بيع فوري • دفع مباشر"))
                        .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .subheadline))
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)

                    // Tender Acceptance Pills
                    HStack(spacing: 5) {
                        HStack(spacing: 2.5) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.17))
                            Text("QIB TAP")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.04), in: Capsule())

                        HStack(spacing: 2.5) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color(red: 0.14, green: 0.54, blue: 0.98))
                            Text("MADA / VISA")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.04), in: Capsule())

                        HStack(spacing: 2.5) {
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))
                            Text("CASH")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.04), in: Capsule())
                    }
                    .foregroundStyle(AdminCommandInk.secondary)
                    .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 12)

            // Primary Tactile Action Launch Bar
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                action()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)

                    Text(Language.get("AdminPOS_StartFastCheckout", alter: "ابدأ عملية بيع سريعة"))
                        .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: (Language.isRTL() ? -1 : 1) * arrowNudge)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, Color(red: 0.03, green: 0.58, blue: 0.40)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
                )
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.35 : 0.20), radius: 6, y: 2.5)
            }
            .buttonStyle(CommandPOSCardPressStyle())
            .padding(.horizontal, 13)
            .padding(.bottom, 13)
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(colorScheme == .dark ? 0.06 : 0.025),
                                accent.opacity(colorScheme == .dark ? 0.015 : 0.005)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.28 : 0.15), lineWidth: 0.85)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: accent.opacity(colorScheme == .dark ? 0.22 : 0.07), radius: 9, y: 3.5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Language.get("AdminPOS_TerminalTitle", alter: "نقطة بيع سريعة") + ", " + currentBranchName)
        .accessibilityHint(Language.get("AdminPOS_StartFastCheckout", alter: "ابدأ عملية بيع سريعة"))
    }
}

// MARK: - iPhone Companion: Shift & Financial Ledger Ribbon

private struct CommandPOSShiftLedgerRibboniPhone: View {
    @ObservedObject var telemetryStore: CommandPOSShiftTelemetryStore
    let arrowNudge: CGFloat
    let reduceMotion: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let accent = Color(red: 0.18, green: 0.52, blue: 0.96)

    private var formattedTodaySales: String {
        let amount = telemetryStore.todaySalesTotal
        let currencySuffix = Language.isRTL() ? "ر.ق" : "QAR"
        return String(format: "%.2f %@", amount, currencySuffix)
    }

    private var headerBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3.5) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 7.5))
                    .foregroundStyle(accent)
                Text(Language.get("AdminPOS_HistorySection_Badge", alter: "سجل المبيعات والوردية"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(accent.opacity(colorScheme == .dark ? 0.20 : 0.08), in: Capsule(style: .continuous))

            Spacer()

            HStack(spacing: 3) {
                Image(systemName: "shield.checkerboard")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(accent)
                Text("AUDIT READY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AdminCommandInk.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04), in: Capsule(style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
    }

    private var salesVolumeMetric: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Language.get("AdminPOS_TodaySales", alter: "مبيعات اليوم"))
                .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)

            if telemetryStore.state == .loading {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 80, height: 18)
                    .overlay(CommandPOSShimmerMask())
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text(formattedTodaySales)
                    .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transactionsMetric: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(Language.get("AdminPOS_TransactionsCount", alter: "العمليات"))
                .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)

            if telemetryStore.state == .loading {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 40, height: 18)
                    .overlay(CommandPOSShimmerMask())
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                HStack(spacing: 2) {
                    Text("\(telemetryStore.todayReceiptsCount)")
                        .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline))
                        .foregroundStyle(accent)
                    Text(Language.get("AdminPOS_TransactionsCount", alter: "عملية"))
                        .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                        .foregroundStyle(AdminCommandInk.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var refundsMetric: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(Language.get("AdminPOS_Feature_Refunds", alter: "إدارة المرتجعات"))
                .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)

            if telemetryStore.state == .loading {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 50, height: 18)
                    .overlay(CommandPOSShimmerMask())
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else if telemetryStore.todayReceiptsCount == 0 {
                Text(Language.get("AdminPOS_NewShift", alter: "وردية جديدة"))
                    .font(Font.custom("Beiruti-Medium", size: 12, relativeTo: .caption))
                    .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))
                    .lineLimit(1)
            } else {
                HStack(spacing: 2) {
                    Text("\(telemetryStore.refundsCount)")
                        .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline))
                        .foregroundStyle(telemetryStore.refundsCount > 0 ? Color(red: 0.95, green: 0.40, blue: 0.40) : AdminSurface.primaryText)
                    Text(Language.isRTL() ? "مرتجع" : "refunds")
                        .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                        .foregroundStyle(AdminCommandInk.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var telemetryGrid: some View {
        HStack(spacing: 10) {
            salesVolumeMetric

            Rectangle()
                .fill(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.35 : 0.20))
                .frame(width: 1, height: 26)

            transactionsMetric

            Rectangle()
                .fill(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.35 : 0.20))
                .frame(width: 1, height: 26)

            refundsMetric
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var actionButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(accent)

                Text(Language.get("AdminPOS_OpenLedgerAndInvoices", alter: "عرض سجل الفواتير والإيصالات"))
                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : AdminSurface.primaryText)
                    .lineLimit(1)

                Spacer()

                Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(accent)
                    .offset(x: (Language.isRTL() ? -1 : 1) * arrowNudge)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(accent.opacity(colorScheme == .dark ? 0.28 : 0.16), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03), radius: 3, y: 1)
        }
        .buttonStyle(CommandPOSCardPressStyle())
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            telemetryGrid
            actionButton
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(colorScheme == .dark ? 0.05 : 0.02),
                                accent.opacity(colorScheme == .dark ? 0.01 : 0.003)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.26 : 0.14), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: accent.opacity(colorScheme == .dark ? 0.18 : 0.05), radius: 7, y: 2.5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Language.get("AdminPOS_HistoryTitle", alter: "سجل مبيعات الكاشير") + ", " + formattedTodaySales)
        .accessibilityHint(Language.get("AdminPOS_OpenLedgerAndInvoices", alter: "عرض سجل الفواتير والإيصالات"))
    }
}

// MARK: - iPad Countertop Register Command Deck (Dedicated Widescreen Architecture)

private struct CommandPOSiPadFlightDeck: View {
    @ObservedObject var telemetryStore: CommandPOSShiftTelemetryStore
    let currentBranchName: String
    let arrowNudge: CGFloat
    let scannerSweep: CGFloat
    let reduceMotion: Bool
    let onRoute: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Main Panoramic Countertop Horizon
            HStack(alignment: .top, spacing: 16) {
                // Wing A: Flagship Fast-Sell Terminal Console (~58% Horizon)
                CommandPOSFastSellConsoleiPad(
                    currentBranchName: currentBranchName,
                    arrowNudge: arrowNudge,
                    scannerSweep: scannerSweep,
                    reduceMotion: reduceMotion,
                    action: { onRoute("pos") },
                    quickScanAction: { onRoute("pos") }
                )
                .frame(maxWidth: .infinity)

                // Wing B: Real-time Sales Ledger & Shift Auditor Console (~42% Horizon)
                CommandPOSHistoryConsoleiPad(
                    telemetryStore: telemetryStore,
                    arrowNudge: arrowNudge,
                    reduceMotion: reduceMotion,
                    action: { onRoute("posHistory") }
                )
                .frame(maxWidth: .infinity)
            }

            // Bottom Diagnostics Filament Strip
            CommandPOSDiagnosticsFilamentiPad(
                currentBranchName: currentBranchName
            )
            .padding(.top, 12)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.11) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.45 : 0.22), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.06), radius: 14, y: 5)
    }
}

// MARK: - Station 1 (iPad): Countertop POS Terminal Console

private struct CommandPOSFastSellConsoleiPad: View {
    let currentBranchName: String
    let arrowNudge: CGFloat
    let scannerSweep: CGFloat
    let reduceMotion: Bool
    let action: () -> Void
    let quickScanAction: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let accent = Color(red: 0.05, green: 0.72, blue: 0.51)

    private var activeStaffName: String {
        let name = BranchContextStore.shared.currentStaff?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty ? name : Language.get("AdminPOS_ActiveCashier", alter: "الكاشير")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top Telemetry Horizon
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6.5, height: 6.5)
                    Text(Language.get("AdminPOS_ActiveTerminal_Badge", alter: "نظام نقطة البيع المباشر"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(accent.opacity(colorScheme == .dark ? 0.20 : 0.08), in: Capsule())

                HStack(spacing: 3.5) {
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(AdminCommandInk.secondary)
                    Text(activeStaffName)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04), in: Capsule())

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.17))
                    Text("FAST-SELL ENGINE")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AdminCommandInk.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04), in: Capsule())
            }

            // Center Body: Optical Reticle + Details
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(colorScheme == .dark ? 0.22 : 0.12),
                                    accent.opacity(colorScheme == .dark ? 0.08 : 0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 34, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                        .shadow(color: accent.opacity(colorScheme == .dark ? 0.45 : 0.20), radius: 6, y: 2)

                    if !reduceMotion {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, accent.opacity(0.75), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 2.5)
                            .offset(y: (scannerSweep - 0.5) * 36)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .frame(width: 72, height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(colorScheme == .dark ? 0.35 : 0.18), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("AdminPOS_TerminalTitle_iPad", alter: "نقطة البيع السريعة الفورية"))
                        .font(Font.custom("Beiruti-Bold", size: 19, relativeTo: .title3))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(Language.get("AdminPOS_TerminalSubtitle_iPad", alter: "مسح فوري للباركود • سلة مشتريات ذكية • إصدار فوري للفاتورة الضريبية"))
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .subheadline))
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(2)

                    // Tender Badges Horizon
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.17))
                            Text("QIB TAP")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.04), in: Capsule())

                        HStack(spacing: 3) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(red: 0.14, green: 0.54, blue: 0.98))
                            Text("MADA / VISA")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.04), in: Capsule())

                        HStack(spacing: 3) {
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))
                            Text("CASH")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.04), in: Capsule())

                        HStack(spacing: 3) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(red: 0.15, green: 0.83, blue: 0.40))
                            Text("WA RECEIPT")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.04), in: Capsule())
                    }
                    .foregroundStyle(AdminCommandInk.secondary)
                    .padding(.top, 2)
                }
            }

            // Primary & Quick Action Launchers
            HStack(spacing: 10) {
                // Primary Start Session Trigger with ⌘N Shortcut Badge
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    action()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)

                        Text(Language.get("AdminPOS_Launch_Session", alter: "بدء جلسة البيع الفوري السريع"))
                            .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .callout))
                            .foregroundStyle(.white)

                        Spacer()

                        // Keyboard Shortcut Pill
                        Text("⌘N")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))

                        Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: (Language.isRTL() ? -1 : 1) * arrowNudge)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent, Color(red: 0.03, green: 0.58, blue: 0.40)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
                    )
                    .shadow(color: accent.opacity(colorScheme == .dark ? 0.40 : 0.22), radius: 6, y: 2.5)
                }
                .buttonStyle(CommandPOSCardPressStyle())
                .keyboardShortcut("n", modifiers: .command)

                // Quick Scan Direct Action
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    quickScanAction()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent)

                        Text("⌘B")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(accent.opacity(colorScheme == .dark ? 0.16 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(accent.opacity(colorScheme == .dark ? 0.32 : 0.18), lineWidth: 0.75)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(CommandPOSCardPressStyle())
                .keyboardShortcut("b", modifiers: .command)
                .accessibilityLabel(Language.get("AdminPOS_QuickScan", alter: "مسح باركود مباشر"))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.32 : 0.16), lineWidth: 0.8)
        )
        .hoverEffect(.lift)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Language.get("AdminPOS_TerminalTitle_iPad", alter: "نقطة البيع السريعة الفورية"))
    }
}

// MARK: - Station 2 (iPad): Real-time Sales Ledger & Shift Auditor Console

private struct CommandPOSHistoryConsoleiPad: View {
    @ObservedObject var telemetryStore: CommandPOSShiftTelemetryStore
    let arrowNudge: CGFloat
    let reduceMotion: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let accent = Color(red: 0.18, green: 0.52, blue: 0.96)

    private var formattedTodaySales: String {
        let amount = telemetryStore.todaySalesTotal
        let currencySuffix = Language.isRTL() ? "ر.ق" : "QAR"
        return String(format: "%.2f %@", amount, currencySuffix)
    }

    private var headerBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(accent)
                Text(Language.get("AdminPOS_HistorySection_Badge", alter: "سجل المبيعات والوردية"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accent.opacity(colorScheme == .dark ? 0.20 : 0.08), in: Capsule())

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "shield.checkerboard")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(accent)
                Text("AUDIT READY")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AdminCommandInk.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04), in: Capsule())
        }
    }

    private var pulseChamber: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(colorScheme == .dark ? 0.22 : 0.12),
                            accent.opacity(colorScheme == .dark ? 0.08 : 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.45 : 0.20), radius: 6, y: 2)
        }
        .frame(width: 72, height: 72)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.35 : 0.18), lineWidth: 1)
        )
    }

    private var salesVolumeHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Language.get("AdminPOS_TodaySales", alter: "مبيعات اليوم"))
                .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .subheadline))
                .foregroundStyle(AdminCommandInk.secondary)

            Spacer()

            if telemetryStore.state == .loading {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 80, height: 20)
                    .overlay(CommandPOSShimmerMask())
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text(formattedTodaySales)
                    .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .title3))
                    .foregroundStyle(AdminSurface.primaryText)
                    .commandNumericTransition()
            }
        }
    }

    @ViewBuilder
    private var spectrumBar: some View {
        if telemetryStore.todaySalesTotal > 0 {
            GeometryReader { g in
                let total: CGFloat = CGFloat(telemetryStore.todaySalesTotal)
                let cash: CGFloat = CGFloat(telemetryStore.cashSalesTotal)
                let ratio: CGFloat = total > 0 ? (cash / total) : 0.0
                let cashPct: CGFloat = min(max(ratio, 0.0), 1.0)
                let cardPct: CGFloat = 1.0 - cashPct
                let cashWidth: CGFloat = max(g.size.width * cashPct - 1.0, 4.0)
                let cardWidth: CGFloat = max(g.size.width * cardPct - 1.0, 4.0)

                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.06, green: 0.78, blue: 0.56))
                        .frame(width: cashWidth)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: cardWidth)
                }
            }
            .frame(height: 4)
            .padding(.vertical, 2)
        }
    }

    private var shiftCapabilitiesRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text("\(telemetryStore.todayReceiptsCount)")
                    .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                    .foregroundStyle(accent)
                Text(Language.get("AdminPOS_TransactionsCount", alter: "عملية"))
                    .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
            }
            Text("•")
            HStack(spacing: 3) {
                Text("\(telemetryStore.refundsCount)")
                    .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                    .foregroundStyle(telemetryStore.refundsCount > 0 ? Color(red: 0.95, green: 0.40, blue: 0.40) : AdminSurface.primaryText)
                Text(Language.get("AdminPOS_Feature_Refunds", alter: "المرتجعات"))
                    .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
            }
            Text("•")
            Text(Language.get("AdminPOS_Feature_Audit", alter: "تدقيق الوردية"))
                .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
        }
        .foregroundStyle(AdminCommandInk.secondary)
        .padding(.top, 1)
    }

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            salesVolumeHeader
            spectrumBar
            shiftCapabilitiesRow
        }
    }

    private var actionButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : AdminSurface.primaryText)

                Text(Language.get("AdminPOS_Open_History", alter: "فتح سجل الفواتير والإيصالات"))
                    .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .callout))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : AdminSurface.primaryText)

                Spacer()

                // Keyboard Shortcut Pill
                Text("⌘H")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))

                Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .offset(x: (Language.isRTL() ? -1 : 1) * arrowNudge)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(colorScheme == .dark ? 0.32 : 0.20), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.04), radius: 4, y: 1.5)
        }
        .buttonStyle(CommandPOSCardPressStyle())
        .keyboardShortcut("h", modifiers: .command)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBar

            HStack(alignment: .center, spacing: 14) {
                pulseChamber
                statsColumn
            }

            actionButton
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.32 : 0.16), lineWidth: 0.8)
        )
        .hoverEffect(.lift)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Language.get("AdminPOS_HistoryTitle_iPad", alter: "سجل فواتير الكاشير واليومية") + ", " + formattedTodaySales)
    }
}

// MARK: - iPad Diagnostics Filament Strip

private struct CommandPOSDiagnosticsFilamentiPad: View {
    let currentBranchName: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4.5) {
                Image(systemName: "cpu")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))
                Text("TERMINAL: POS-01")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            Circle()
                .fill(Color(uiColor: .ppSurfaceBorder))
                .frame(width: 3, height: 3)

            HStack(spacing: 4.5) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))
                Text(Language.isRTL() ? "المزامنة: متصل لحظياً (18ms)" : "Sync: Real-time Cloud (18ms)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            Circle()
                .fill(Color(uiColor: .ppSurfaceBorder))
                .frame(width: 3, height: 3)

            HStack(spacing: 4.5) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.17))
                Text("QIB CONTACTLESS: READY")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            Circle()
                .fill(Color(uiColor: .ppSurfaceBorder))
                .frame(width: 3, height: 3)

            HStack(spacing: 4.5) {
                Image(systemName: "printer.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(red: 0.14, green: 0.54, blue: 0.98))
                Text(Language.isRTL() ? "الطابعة الحرارية: جاهزة" : "Thermal: Ready")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            Spacer()

            HStack(spacing: 4.5) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AdminCommandInk.secondary)
                Text(currentBranchName)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8.5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.35 : 0.18), lineWidth: 0.5)
        )
    }
}

private struct CommandPOSCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Stock Sovereign Horizon Deck (Deck 2)

private struct CommandStockDeck: View {
    let signals: [AdminCommandOrbitSignal]
    var isRegular: Bool = false
    var containerWidth: CGFloat = 0
    let onRoute: (String) -> Void

    @ObservedObject private var branchStore = BranchContextStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var arrowNudge: CGFloat = 0

    private var accessoriesSignal: AdminCommandOrbitSignal? {
        signals.first { $0.id.contains("accessor") || $0.id.contains("stock") }
    }

    private var foodSignal: AdminCommandOrbitSignal? {
        signals.first { $0.id.contains("food") || $0.id.contains("nutrition") }
    }

    private var livePetsSignal: AdminCommandOrbitSignal? {
        signals.first { $0.id.contains("pet") || $0.id.contains("live") || $0.id.contains("animal") }
    }

    private var stockAlertCount: Int {
        let acc = accessoriesSignal?.count ?? 0
        let food = foodSignal?.count ?? 0
        let pets = livePetsSignal?.count ?? 0
        return acc + food + pets
    }

    private var currentBranchName: String {
        let name = branchStore.currentBranchDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty ? name : Language.get("Branch_Scope_Active", alter: "الفرع الحالي")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            headerRow

            if isRegular {
                ipadStockView
            } else {
                iphoneStockView
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                arrowNudge = 3.0
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Language.get("Stock_Section_Title", alter: "قطاع المخزون والمنتجات"))
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                Text(Language.get("Stock_Section_Subtitle", alter: "كتالوج المنتجات، الأغذية، والحيوانات الحية مع تتبع الكميات"))
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if stockAlertCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(uiColor: .ppWarning))
                        .frame(width: 5.5, height: 5.5)
                    Text(String(format: Language.get("Stock_Alerts_Count_Format", alter: "%d تنبيهات بالمخزون"), stockAlertCount))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(Color(uiColor: .ppWarning))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(Color(uiColor: .ppWarning).opacity(colorScheme == .dark ? 0.18 : 0.08), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color(uiColor: .ppWarning).opacity(0.18), lineWidth: 0.5)
                )
                .accessibilityHidden(true)
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.55, green: 0.36, blue: 0.96))
                        .frame(width: 5.5, height: 5.5)
                    Text(Language.get("Stock_Live_Sync_Active", alter: "مزامنة المخزون نشطة"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(Color(red: 0.55, green: 0.36, blue: 0.96))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(Color(red: 0.55, green: 0.36, blue: 0.96).opacity(colorScheme == .dark ? 0.16 : 0.08), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.18), lineWidth: 0.5)
                )
                .accessibilityHidden(true)
            }
        }
    }

    // iPhone: 3 Sculpted Vault Rows
    private var iphoneStockView: some View {
        VStack(spacing: 9) {
            CommandStockVaultCardiPhone(
                title: Language.get("Stock_Accessories_Title", alter: "المخزون والإكسسوارات"),
                subtitle: Language.get("Stock_Accessories_Subtitle", alter: "الأطواق، الألعاب، ومستلزمات العناية والرعاية"),
                iconName: "archivebox.fill",
                accent: Color(red: 0.55, green: 0.36, blue: 0.96),
                badgeCount: accessoriesSignal?.count ?? (stockAlertCount > 0 ? stockAlertCount : nil),
                arrowNudge: arrowNudge,
                action: { onRoute("stockSector:accessories") }
            )

            CommandStockVaultCardiPhone(
                title: Language.get("Stock_Food_Title", alter: "الأغذية والتغذية"),
                subtitle: Language.get("Stock_Food_Subtitle", alter: "الأغذية الجافة، الرطبة، المكملات والمكافآت"),
                iconName: "bag.fill",
                accent: Color(red: 0.96, green: 0.55, blue: 0.12),
                badgeCount: foodSignal?.count,
                arrowNudge: arrowNudge,
                action: { onRoute("stockSector:food") }
            )

            CommandStockVaultCardiPhone(
                title: Language.get("Stock_LivePets_Title", alter: "الحيوانات الحية"),
                subtitle: Language.get("Stock_LivePets_Subtitle", alter: "الطيور، القطط، الكلاب، السجلات والشرائح"),
                iconName: "pawprint.fill",
                accent: Color(red: 0.05, green: 0.65, blue: 0.52),
                badgeCount: livePetsSignal?.count,
                arrowNudge: arrowNudge,
                action: { onRoute("stockSector:livePets") }
            )
        }
        .frame(maxWidth: .infinity)
    }

    // iPad: Panoramic 3-Column Horizon Pavilion
    private var ipadStockView: some View {
        HStack(spacing: 14) {
            CommandStockVaultCardiPad(
                title: Language.get("Stock_Accessories_Title", alter: "المخزون والإكسسوارات"),
                subtitle: Language.get("Stock_Accessories_Subtitle", alter: "الأطواق، الألعاب، ومستلزمات العناية والرعاية"),
                categoryBadge: Language.get("Stock_Category_General", alter: "مستلزمات عامة"),
                iconName: "archivebox.fill",
                accent: Color(red: 0.55, green: 0.36, blue: 0.96),
                badgeCount: accessoriesSignal?.count ?? (stockAlertCount > 0 ? stockAlertCount : nil),
                arrowNudge: arrowNudge,
                action: { onRoute("stockSector:accessories") }
            )
            .frame(maxWidth: .infinity)

            CommandStockVaultCardiPad(
                title: Language.get("Stock_Food_Title", alter: "الأغذية والتغذية"),
                subtitle: Language.get("Stock_Food_Subtitle", alter: "الأغذية الجافة، الرطبة، المكملات والمكافآت"),
                categoryBadge: Language.get("Stock_Category_Nutrition", alter: "تغذية ومكملات"),
                iconName: "bag.fill",
                accent: Color(red: 0.96, green: 0.55, blue: 0.12),
                badgeCount: foodSignal?.count,
                arrowNudge: arrowNudge,
                action: { onRoute("stockSector:food") }
            )
            .frame(maxWidth: .infinity)

            CommandStockVaultCardiPad(
                title: Language.get("Stock_LivePets_Title", alter: "الحيوانات الحية"),
                subtitle: Language.get("Stock_LivePets_Subtitle", alter: "الطيور، القطط، الكلاب، السجلات والشرائح"),
                categoryBadge: Language.get("Stock_Category_LivePets", alter: "حيوانات حية"),
                iconName: "pawprint.fill",
                accent: Color(red: 0.05, green: 0.65, blue: 0.52),
                badgeCount: livePetsSignal?.count,
                arrowNudge: arrowNudge,
                action: { onRoute("stockSector:livePets") }
            )
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stock Vault Card (iPhone)

private struct CommandStockVaultCardiPhone: View {
    let title: String
    let subtitle: String
    let iconName: String
    let accent: Color
    let badgeCount: Int?
    let arrowNudge: CGFloat
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var iconGradient: LinearGradient {
        let topOpacity: Double = colorScheme == .dark ? 0.25 : 0.14
        let bottomOpacity: Double = colorScheme == .dark ? 0.08 : 0.04
        return LinearGradient(
            colors: [
                accent.opacity(topOpacity),
                accent.opacity(bottomOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconSquircle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(iconGradient)

            Image(systemName: iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
        }
        .frame(width: 44, height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.32 : 0.18), lineWidth: 0.75)
        )
    }

    private var titleAndDescription: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                if let count = badgeCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color(uiColor: .ppWarning), in: Capsule())
                }
            }

            Text(subtitle)
                .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chevronPill: some View {
        HStack(spacing: 3) {
            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)
                .offset(x: (Language.isRTL() ? -1 : 1) * arrowNudge * 0.6)
        }
        .frame(width: 28, height: 28)
        .background(accent.opacity(colorScheme == .dark ? 0.12 : 0.06), in: Circle())
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: 12) {
                iconSquircle
                titleAndDescription
                Spacer(minLength: 4)
                chevronPill
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accent.opacity(colorScheme == .dark ? 0.28 : 0.14), lineWidth: 0.75)
            )
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.14 : 0.04), radius: 5, y: 2)
        }
        .buttonStyle(CommandStockCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

// MARK: - Stock Vault Card (iPad)

private struct CommandStockVaultCardiPad: View {
    let title: String
    let subtitle: String
    let categoryBadge: String
    let iconName: String
    let accent: Color
    let badgeCount: Int?
    let arrowNudge: CGFloat
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var iconGradient: LinearGradient {
        let topOpacity: Double = colorScheme == .dark ? 0.24 : 0.14
        let bottomOpacity: Double = colorScheme == .dark ? 0.08 : 0.04
        return LinearGradient(
            colors: [
                accent.opacity(topOpacity),
                accent.opacity(bottomOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var topTagBar: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(categoryBadge)
                .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption2))
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(accent.opacity(colorScheme == .dark ? 0.20 : 0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(accent.opacity(colorScheme == .dark ? 0.28 : 0.16), lineWidth: 0.6)
                )

            Spacer(minLength: 4)

            if let count = badgeCount, count > 0 {
                HStack(spacing: 3.5) {
                    Circle()
                        .fill(Color(uiColor: .ppWarning))
                        .frame(width: 5, height: 5)
                    Text(count == 1 ? Language.get("Stock_Status_Alert_Singular", alter: "تنبيه نقص") : String(format: Language.get("Stock_Status_Alert_Plural", alter: "%d تنبيهات"), count))
                        .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
                        .foregroundStyle(Color(uiColor: .ppWarning))
                }
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .ppWarning).opacity(colorScheme == .dark ? 0.20 : 0.10))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color(uiColor: .ppWarning).opacity(0.24), lineWidth: 0.6)
                )
            } else {
                HStack(spacing: 3.5) {
                    Circle()
                        .fill(accent)
                        .frame(width: 4.5, height: 4.5)
                    Text(Language.get("Stock_Status_Active", alter: "متزامن"))
                        .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(accent.opacity(colorScheme == .dark ? 0.15 : 0.07))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(accent.opacity(colorScheme == .dark ? 0.22 : 0.12), lineWidth: 0.5)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var iconSquircle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(iconGradient)

            Image(systemName: iconName)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.40 : 0.18), radius: 4, y: 1.5)
        }
        .frame(width: 50, height: 50)
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.32 : 0.18), lineWidth: 0.8)
        )
    }

    private var titlesView: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(subtitle)
                .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(2)
                .lineSpacing(1.5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contentRow: some View {
        HStack(alignment: .center, spacing: 12) {
            iconSquircle
            titlesView
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionPill: some View {
        HStack(spacing: 5) {
            Text(Language.get("Stock_Open_Catalog", alter: "فتح الكتالوج"))
                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : AdminSurface.primaryText)

            Spacer()

            Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(accent)
                .offset(x: (Language.isRTL() ? -1 : 1) * arrowNudge * 0.7)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 33)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 0.7)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.03), radius: 2.5, y: 1)
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 11) {
                topTagBar
                contentRow
                Spacer(minLength: 2)
                actionPill
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 154)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(colorScheme == .dark ? Color(white: 0.13) : Color.white)

                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(colorScheme == .dark ? 0.06 : 0.025),
                                    accent.opacity(colorScheme == .dark ? 0.01 : 0.003)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(accent.opacity(colorScheme == .dark ? 0.26 : 0.14), lineWidth: 0.8)
            )
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.18 : 0.05), radius: 6, y: 2.5)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(CommandStockCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct CommandStockCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Operations Launchpad (Deck 3)

private struct CommandQuickActionItem: Identifiable, Hashable {
    let id: String
    let tag: String
    let title: String
    let subtitle: String
    let symbolName: String
    let accent: Color
    let badgeCount: Int?
    let isLive: Bool
    var isCustomAsset: Bool = false

    init(
        id: String,
        tag: String,
        title: String,
        subtitle: String,
        symbolName: String,
        accent: Color,
        badgeCount: Int?,
        isLive: Bool,
        isCustomAsset: Bool = false
    ) {
        self.id = id
        self.tag = tag
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.accent = accent
        self.badgeCount = badgeCount
        self.isLive = isLive
        self.isCustomAsset = isCustomAsset
    }
}

private struct CommandQuickActionIcon: View {
    let symbolName: String
    let accent: Color
    let size: CGFloat
    var isCustomAsset: Bool = false
    var weight: Font.Weight = .semibold

    init(symbolName: String, accent: Color, size: CGFloat, isCustomAsset: Bool = false, weight: Font.Weight = .semibold) {
        self.symbolName = symbolName
        self.accent = accent
        self.size = size
        self.isCustomAsset = isCustomAsset
        self.weight = weight
    }

    init(item: CommandQuickActionItem, size: CGFloat, weight: Font.Weight = .semibold) {
        self.symbolName = item.symbolName
        self.accent = item.accent
        self.size = size
        self.isCustomAsset = item.isCustomAsset
        self.weight = weight
    }

    var body: some View {
        let cleanName = symbolName.replacingOccurrences(of: ".png", with: "")
        if isCustomAsset || UIImage(named: cleanName) != nil || UIImage(named: symbolName) != nil {
            Image(cleanName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(accent)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: size, weight: weight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
        }
    }
}

private struct CommandQuickActionsDeck: View {
    let signals: [AdminCommandOrbitSignal]
    var isRegular: Bool = false
    var containerWidth: CGFloat = 0
    let onRoute: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded: Bool = false

    private let spacing: CGFloat = 11

    private var allDeckItems: [CommandQuickActionItem] {
        let fulfillmentSignal = signals.first { $0.id.contains("fulfillment") }
        let deliverySignal = signals.first { $0.id.contains("delivery") }
        let listingSignal = signals.first { $0.id.contains("listing") || $0.id.contains("moderat") }
        let userSignal = signals.first { $0.id.contains("user") }
        let staffSignal = signals.first { $0.id.contains("staff") }

        return [
            // 1. Fulfillment Orders
            CommandQuickActionItem(
                id: "fulfillment",
                tag: "fulfillment",
                title: Language.get("AdminQuickActions_Fulfillment", alter: "تجهيز الطلبات"),
                subtitle: Language.get("AdminQuickActions_Fulfillment_Subtitle", alter: "معالجة وتحضير الطلبات"),
                symbolName: "shippingbox.fill",
                accent: Color(red: 0.96, green: 0.55, blue: 0.12),
                badgeCount: (fulfillmentSignal?.count ?? 0) > 0 ? fulfillmentSignal?.count : nil,
                isLive: fulfillmentSignal?.isLive ?? false
            ),
            // 3. Delivery Fleet
            CommandQuickActionItem(
                id: "delivery",
                tag: "delivery",
                title: Language.get("AdminQuickActions_Delivery", alter: "أسطول التوصيل"),
                subtitle: Language.get("AdminQuickActions_Delivery_Subtitle", alter: "الشحنات الحية والمندوبين"),
                symbolName: "truck.box.fill",
                accent: Color(red: 0.14, green: 0.54, blue: 0.98),
                badgeCount: (deliverySignal?.count ?? 0) > 0 ? deliverySignal?.count : nil,
                isLive: deliverySignal?.isLive ?? false
            ),
            // 4. Staff & Roles
            CommandQuickActionItem(
                id: "staffManagement",
                tag: "staffManagement",
                title: Language.get("AdminQuickActions_Staff", alter: "فريق العمل"),
                subtitle: Language.get("AdminQuickActions_Staff_Subtitle", alter: "الأدوار والصلاحيات"),
                symbolName: "person.badge.shield.checkmark.fill",
                accent: Color(red: 0.36, green: 0.45, blue: 0.98),
                badgeCount: (staffSignal?.count ?? 0) > 0 ? staffSignal?.count : nil,
                isLive: false
            ),
            // 5. Provider Applications
            CommandQuickActionItem(
                id: "providerApplications",
                tag: "providerApplications",
                title: Language.get("AdminQuickActions_Providers", alter: "طلبات المزودين"),
                subtitle: Language.get("AdminQuickActions_Providers_Subtitle", alter: "مراجعة الانضمام"),
                symbolName: "storefront.fill",
                accent: Color(red: 0.05, green: 0.65, blue: 0.52),
                badgeCount: nil,
                isLive: true
            ),
            // 6. Broadcast Push Alert
            CommandQuickActionItem(
                id: "notificationsCompose",
                tag: "notificationsCompose",
                title: Language.get("AdminQuickActions_Broadcast", alter: "بث إشعار عام"),
                subtitle: Language.get("AdminQuickActions_Broadcast_Subtitle", alter: "إرسال تنبيه للجميع"),
                symbolName: "bell.badge.fill",
                accent: Color(red: 0.96, green: 0.25, blue: 0.37),
                badgeCount: nil,
                isLive: false
            ),
            // 7. Customers Directory
            CommandQuickActionItem(
                id: "usersList",
                tag: "usersList",
                title: Language.get("AdminQuickActions_Users", alter: "دليل العملاء"),
                subtitle: Language.get("AdminQuickActions_Users_Subtitle", alter: "الحسابات والسجلات"),
                symbolName: "person.2.fill",
                accent: Color(red: 0.05, green: 0.60, blue: 0.56),
                badgeCount: (userSignal?.count ?? 0) > 0 ? userSignal?.count : nil,
                isLive: userSignal?.isLive ?? false
            ),
            // 8. Listings & Moderation
            CommandQuickActionItem(
                id: "moderation",
                tag: "moderation",
                title: Language.get("AdminQuickActions_Moderation", alter: "إعلانات المنصة"),
                subtitle: Language.get("AdminQuickActions_Listings_Subtitle", alter: "تدقيق واعتماد الإعلانات"),
                symbolName: "checkmark.seal.fill",
                accent: Color(red: 0.45, green: 0.38, blue: 0.95),
                badgeCount: (listingSignal?.count ?? 0) > 0 ? listingSignal?.count : nil,
                isLive: listingSignal?.isLive ?? false
            ),
            // 9. Branch Network
            CommandQuickActionItem(
                id: "branches",
                tag: "branches",
                title: Language.get("AdminQuickActions_Branches", alter: "شبكة الفروع"),
                subtitle: Language.get("AdminQuickActions_Branches_Subtitle", alter: "المواقع والعمليات"),
                symbolName: "building.2.fill",
                accent: Color(red: 0.92, green: 0.50, blue: 0.15),
                badgeCount: nil,
                isLive: false
            ),
            // 10. Store Home Control
            CommandQuickActionItem(
                id: "homeControl",
                tag: "homeControl",
                title: Language.get("AdminQuickActions_HomeControl", alter: "واجهة التطبيق"),
                subtitle: Language.get("AdminQuickActions_HomeControl_Subtitle", alter: "أقسام وبانرات المتجر"),
                symbolName: "slider.horizontal.3",
                accent: Color(red: 0.20, green: 0.40, blue: 0.85),
                badgeCount: nil,
                isLive: false
            ),
            // 11. Security & Audit Trail
            CommandQuickActionItem(
                id: "audit",
                tag: "audit",
                title: Language.get("AdminQuickActions_Audit", alter: "سجل التدقيق"),
                subtitle: Language.get("AdminQuickActions_Audit_Subtitle", alter: "الرقابة وتتبع الأمان"),
                symbolName: "lock.shield.fill",
                accent: Color(red: 0.35, green: 0.40, blue: 0.52),
                badgeCount: nil,
                isLive: false
            )
        ]
    }

    private var visibleItems: [CommandQuickActionItem] {
        if isRegular || dynamicTypeSize.isAccessibilitySize || isExpanded {
            return allDeckItems
        }
        return Array(allDeckItems.prefix(6))
    }

    private var activeSignalsCount: Int {
        signals.reduce(0) { $0 + ($1.count > 0 ? 1 : 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            headerRow

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: spacing) {
                    ForEach(allDeckItems) { item in
                        CommandQuickActionCard(item: item) {
                            onRoute(item.tag)
                        }
                    }
                }
            } else if isRegular {
                ipadOperationsMatrixView
            } else {
                iphoneOperationsMatrixView
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Language.get("AdminQuickActions_SectionTitle", alter: "إجراءات سريعة"))
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                Text(Language.get("AdminQuickActions_SectionDetail", alter: "منصة إطلاق فورية للعمليات الميدانية"))
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if activeSignalsCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AdminSurface.primary)
                        .frame(width: 5.5, height: 5.5)
                    Text(String(format: Language.get("AdminQuickActions_SignalsCount_Format", alter: "%d إشارات نشطة"), activeSignalsCount))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(AdminSurface.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AdminSurface.primary.opacity(0.14), lineWidth: 0.5)
                )
                .accessibilityHidden(true)
            }
        }
    }

    // iPhone Operations Matrix (2 columns + expansion affordance)
    private var iphoneOperationsMatrixView: some View {
        VStack(spacing: spacing) {
            let columns = [
                GridItem(.flexible(), spacing: spacing),
                GridItem(.flexible(), spacing: spacing)
            ]

            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(visibleItems) { item in
                    CommandQuickActionCard(item: item) {
                        onRoute(item.tag)
                    }
                }
            }

            // Interactive Expansion Affordance (+5 More Tools)
            if !dynamicTypeSize.isAccessibilitySize {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))

                        Text(isExpanded ? Language.get("AdminQuickActions_ShowLess", alter: "عرض أقل") : (Language.get("AdminQuickActions_ShowMore", alter: "المزيد من الأدوات") + " (+\(max(allDeckItems.count - 6, 0)))"))
                            .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                    }
                    .foregroundStyle(AdminCommandInk.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.6)
                    )
                }
                .buttonStyle(CommandQuickActionCardStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // iPad Operations Matrix (Panoramic 3 to 4 columns)
    private var ipadOperationsMatrixView: some View {
        let effectiveWidth = containerWidth > 0 ? containerWidth : max(UIScreen.main.bounds.width - 2 * AdminCommandMetric.pageMargin, 740)
        let isWide = effectiveWidth >= 900
        let columnCount = isWide ? 4 : 3
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)

        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(allDeckItems) { item in
                CommandQuickActionCard(item: item) {
                    onRoute(item.tag)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sovereign Quick Action Card (Ergonomic 2-Tier Squircle)

private struct CommandQuickActionCard: View {
    let item: CommandQuickActionItem
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 7) {
                // Tier 1: Icon squircle + Telemetry Indicator
                HStack(alignment: .center, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? item.accent.opacity(0.28)
                                    : Color.white.opacity(0.92)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(item.accent.opacity(colorScheme == .dark ? 0.22 : 0.14), lineWidth: 0.75)
                            )
                            .shadow(color: item.accent.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 3, y: 1)

                        CommandQuickActionIcon(item: item, size: 17)
                    }
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                    Spacer(minLength: 4)

                    // Trailing Telemetry Pill / Arrow Affordance
                    if let count = item.badgeCount, count > 0 {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(item.accent)
                                .frame(width: 5, height: 5)
                                .scaleEffect(isPulsing ? 1.25 : 0.85)
                            Text("\(count)")
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(item.accent)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(colorScheme == .dark ? item.accent.opacity(0.22) : Color.white.opacity(0.92))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(item.accent.opacity(0.18), lineWidth: 0.75)
                        )
                    } else if item.isLive {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(item.accent)
                                .frame(width: 4.5, height: 4.5)
                                .scaleEffect(isPulsing ? 1.25 : 0.85)
                            Text(Language.get("AdminQuickActions_Live", alter: "مباشر"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(item.accent)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(item.accent.opacity(colorScheme == .dark ? 0.18 : 0.08), in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(item.accent.opacity(0.18), lineWidth: 0.75)
                        )
                    } else {
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(item.accent.opacity(0.55))
                            .accessibilityHidden(true)
                    }
                }

                Spacer(minLength: 2)

                // Tier 2: Arabic Typography Horizons
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(item.title)
                        .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(item.subtitle)
                        .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 94)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    item.accent.opacity(colorScheme == .dark ? 0.03 : 0.012),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(item.accent.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 0.75)
            )
            .shadow(
                color: item.accent.opacity(colorScheme == .dark ? 0.14 : 0.04),
                radius: 4,
                y: 1.5
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CommandQuickActionCardStyle())
        .onAppear {
            if item.badgeCount != nil || item.isLive {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.subtitle)")
        .accessibilityHint(Language.get("AdminCommandCenter_OpenHint", alter: "يفتح القسم"))
    }
}

private struct CommandQuickActionCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Priority Runway

private struct CommandPriorityRunway: View {
    let title: String
    let detail: String
    let signals: [AdminCommandOrbitSignal]
    let locale: Locale
    let action: (AdminCommandOrbitSignal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, detail: detail)

            if signals.isEmpty {
                CommandCenterStatePanel(
                    tone: .stable,
                    title: Language.get("AdminCommandCenter_AllClear_Title", alter: nil),
                    detail: Language.get("AdminCommandCenter_AllClear_Detail", alter: nil),
                    showsProgress: false,
                    actionTitle: nil,
                    action: nil
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(signals.enumerated()), id: \.element.id) { index, signal in
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            action(signal)
                        } label: {
                            CommandPriorityRow(
                                signal: signal,
                                locale: locale,
                                position: index + 1,
                                isLast: index == signals.count - 1
                            )
                        }
                        .buttonStyle(CommandPressStyle())
                    }
                }
            }
        }
    }
}

private struct CommandPriorityRow: View {
    let signal: AdminCommandOrbitSignal
    let locale: Locale
    let position: Int
    let isLast: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Priority Leading Indicator Bar
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(signal.tier.tone.accent)
                .frame(width: 4, height: 44)
                .shadow(color: signal.tier.tone.accent.opacity(0.40), radius: 2, x: 0, y: 0)

            // Specimen Icon Container
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(signal.tier.tone.softFill)
                Image(systemName: signal.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(signal.tier.tone.accent)
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(signal.tier.tone.accent.opacity(0.25), lineWidth: 0.75)
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(priorityLabel)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(signal.tier.tone.color)
                            .lineLimit(1)

                        if !signal.moduleTitle.isEmpty {
                            Text("•")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(AdminCommandInk.tertiary)
                            Text(signal.moduleTitle)
                                .font(AdminType.caption2)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if signal.count > 0 {
                        Text(signal.count.formatted(.number.locale(locale)))
                            .font(AdminType.captionBold)
                            .foregroundStyle(signal.tier.tone.color)
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(signal.tier.tone.softFill, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(signal.tier.tone.accent.opacity(0.25), lineWidth: 0.5)
                            )
                            .accessibilityLabel(countAccessibilityText)
                    }
                }

                Text(signal.title)
                    .font(position == 1 ? AdminType.headline : AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !signal.detail.isEmpty {
                    Text(signal.detail)
                        .font(AdminType.callout)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(3)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text(Language.get("AdminCommandCenter_Act", alter: "Act now"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(signal.tier.tone.color)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(signal.tier.tone.accent)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.03), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.60 : 0.35), lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Language.get("AdminCommandCenter_OpenHint", alter: nil))
    }

    private var priorityLabel: String {
        signal.tier.localizedLabel
    }

    private var countAccessibilityText: String {
        String(format: Language.get("AdminCommandCenter_Count_Format", alter: nil), signal.count.formatted(.number.locale(locale)))
    }

    private var accessibilityLabel: String {
        String(
            format: Language.get("AdminCommandCenter_Priority_A11y_Format", alter: nil),
            priorityLabel,
            signal.title,
            signal.count.formatted(.number.locale(locale))
        )
    }
}

// MARK: - Source and Recovery

private struct CommandSourceLedger: View {
    let title: String
    let detail: String
    let loadingSources: [String]
    let failedSources: [String]
    let updatedText: String

    @Environment(\.colorScheme) private var colorScheme

    private var rows: [CommandSourceRow] {
        var result: [CommandSourceRow] = []
        result.append(.init(title: Language.get("CommandCenter_Last_Updated", alter: "Last confirmed"), value: updatedText, tone: .stable, symbol: "clock.badge.checkmark"))
        if loadingSources.isEmpty && failedSources.isEmpty {
            result.append(.init(title: Language.get("AdminCommandCenter_SourceReady", alter: "All sources verified"), value: Language.get("AdminCommandCenter_Ready_Detail", alter: "Real-time sync active"), tone: .stable, symbol: "checkmark.seal.fill"))
        }
        if !loadingSources.isEmpty {
            result.append(.init(title: Language.get("AdminCommandCenter_LoadingSources", alter: "Confirming sources"), value: localizedList(loadingSources), tone: .info, symbol: "arrow.triangle.2.circlepath"))
        }
        if !failedSources.isEmpty {
            result.append(.init(title: Language.get("AdminCommandCenter_SourceIssue_Title", alter: "Source issue"), value: localizedList(failedSources), tone: .elevated, symbol: "wifi.exclamationmark"))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, detail: detail)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(row.tone.softFill)
                            Image(systemName: row.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(row.tone.accent)
                        }
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(row.tone.accent.opacity(0.25), lineWidth: 0.75)
                        )
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .lineLimit(1)
                            Text(row.value)
                                .font(AdminType.callout)
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(2)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .accessibilityElement(children: .combine)

                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 70)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AdminSurface.control)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.03), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.60 : 0.35), lineWidth: 0.75)
            )
        }
    }

    private func localizedList(_ values: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = Locale(identifier: Language.currentLanguageCode())
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }
}

private struct CommandSourceRow: Identifiable {
    let title: String
    let value: String
    let tone: AdminCommandTone
    let symbol: String

    var id: String { "\(title)-\(value)" }
}

private struct CommandRecoveryStrip: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .ppWarning))
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .ppWarning).opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(AdminType.callout)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(3)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: action) {
                HStack(spacing: 8) {
                    Text(actionTitle)
                        .font(AdminType.calloutBold)
                        .lineLimit(1)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(CommandPressStyle())
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppWarning).opacity(0.35), lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct CommandCenterSourcePanel: View {
    let tone: AdminCommandTone
    let title: String
    let detail: String
    let sourceNames: [String]
    let showsProgress: Bool
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        CommandCenterStatePanel(
            tone: tone,
            title: title,
            detail: detail,
            showsProgress: showsProgress,
            actionTitle: actionTitle,
            action: action
        ) {
            if !sourceNames.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sourceNames, id: \.self) { source in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(tone.accent)
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                            Text(source)
                                .font(AdminType.callout)
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(nil)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

private struct CommandCenterStatePanel<Extra: View>: View {
    let tone: AdminCommandTone
    let title: String
    let detail: String
    let showsProgress: Bool
    let actionTitle: String?
    let action: (() -> Void)?
    let extra: Extra

    @Environment(\.colorScheme) private var colorScheme

    init(
        tone: AdminCommandTone,
        title: String,
        detail: String,
        showsProgress: Bool,
        actionTitle: String?,
        action: (() -> Void)?,
        @ViewBuilder extra: () -> Extra
    ) {
        self.tone = tone
        self.title = title
        self.detail = detail
        self.showsProgress = showsProgress
        self.actionTitle = actionTitle
        self.action = action
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(tone.softFill)
                    .frame(width: 64, height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(tone.accent.opacity(0.30), lineWidth: 1.0)
                    )

                if showsProgress {
                    ProgressView().tint(tone.color)
                } else {
                    Image(systemName: tone.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tone.accent)
                }
            }
            .frame(width: 64, height: 64)
            .shadow(color: tone.accent.opacity(0.25), radius: 8, x: 0, y: 3)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(AdminType.callout)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            extra

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AdminType.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(tone.actionFill)
                                .shadow(color: tone.accent.opacity(0.35), radius: 8, x: 0, y: 3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
                        )
                }
                .buttonStyle(CommandPressStyle())
                .accessibilityHint(Language.get("AdminCommandOrbit_Refresh_Hint", alter: nil))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.60 : 0.35), lineWidth: 0.75)
        )
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}

private extension CommandCenterStatePanel where Extra == EmptyView {
    init(
        tone: AdminCommandTone,
        title: String,
        detail: String,
        showsProgress: Bool,
        actionTitle: String?,
        action: (() -> Void)?
    ) {
        self.init(
            tone: tone,
            title: title,
            detail: detail,
            showsProgress: showsProgress,
            actionTitle: actionTitle,
            action: action
        ) {
            EmptyView()
        }
    }
}

// MARK: - Shared Components

struct SectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AdminType.title3)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(nil)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(AdminType.callout)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(nil)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct CommandPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1.0)
    }
}

// MARK: - Category-Defining Flagship Accounting Sovereign Entry Card

@MainActor
private final class CommandAccountingCardViewModel: ObservableObject {
    @Published private(set) var grossRevenue: Double = 0.0
    @Published private(set) var totalExpenses: Double = 0.0
    @Published private(set) var paidOrderCount: Int = 0
    @Published private(set) var expenseCount: Int = 0
    @Published private(set) var isLoading: Bool = true

    private nonisolated(unsafe) var notificationToken: (any NSObjectProtocol)? = nil
    private nonisolated(unsafe) var branchNotificationToken: (any NSObjectProtocol)? = nil

    private let service: PPAccountingService
    private nonisolated(unsafe) var listeners: [any ListenerRegistration] = []

    init(service: PPAccountingService = .shared()) {
        self.service = service
        self.notificationToken = NotificationCenter.default.addObserver(
            forName: Notification.Name("PPAccountingDataDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sync()
            }
        }
        self.branchNotificationToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.PPActiveBranchDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.grossRevenue = 0
                self?.totalExpenses = 0
                self?.paidOrderCount = 0
                self?.expenseCount = 0
                self?.subscribe()
            }
        }
        subscribe()
    }

    deinit {
        listeners.forEach { $0.remove() }
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = branchNotificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func subscribe() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        isLoading = true

        let filter = "month"
        let wsReg = service.subscribeAccountingWorkspace(withFilter: filter) { [weak self] _ in
            Task { @MainActor in
                self?.sync()
            }
        }
        let orderReg = service.subscribeOrderRevenue(withFilter: filter) { [weak self] in
            Task { @MainActor in
                self?.sync()
            }
        }
        let expenseReg = service.subscribeExpenses(withFilter: filter) { [weak self] in
            Task { @MainActor in
                self?.sync()
            }
        }
        let txnReg = service.subscribeTransactions(withFilter: filter) { [weak self] in
            Task { @MainActor in
                self?.sync()
            }
        }
        listeners = [wsReg, orderReg, expenseReg, txnReg]
        sync()
    }

    private func sync() {
        let workspace = service.currentWorkspace
        let dashboard = workspace?.primaryDashboard

        // Multi-tier revenue derivation
        if let dashboard, dashboard.income > 0 {
            grossRevenue = dashboard.income
            paidOrderCount = workspace?.incomeCount ?? 0
        } else if let docs = workspace?.documents, !docs.isEmpty {
            let docIncome = docs.filter { $0.kind == "income" }.reduce(0.0) { $0 + $1.total }
            let docCount = docs.filter { $0.kind == "income" }.count
            if docIncome > 0 || docCount > 0 {
                grossRevenue = docIncome
                paidOrderCount = docCount
            } else if service.orderRevenue > 0 || service.orderCount > 0 {
                grossRevenue = service.orderRevenue
                paidOrderCount = service.orderCount
            } else if service.liveTransactionRevenue > 0 || service.liveTransactionCount > 0 {
                grossRevenue = service.liveTransactionRevenue
                paidOrderCount = service.liveTransactionCount
            } else {
                grossRevenue = 0
                paidOrderCount = 0
            }
        } else if service.orderRevenue > 0 || service.orderCount > 0 {
            grossRevenue = service.orderRevenue
            paidOrderCount = service.orderCount
        } else if service.liveTransactionRevenue > 0 || service.liveTransactionCount > 0 {
            grossRevenue = service.liveTransactionRevenue
            paidOrderCount = service.liveTransactionCount
        } else {
            grossRevenue = 0
            paidOrderCount = 0
        }

        // Multi-tier expense derivation
        if let dashboard, dashboard.expenses > 0 {
            totalExpenses = dashboard.expenses
            expenseCount = workspace?.expenseCount ?? 0
        } else if let docs = workspace?.documents, !docs.isEmpty {
            let docExpenses = docs.filter { $0.kind == "expense" }.reduce(0.0) { $0 + $1.total }
            let docCount = docs.filter { $0.kind == "expense" }.count
            if docExpenses > 0 || docCount > 0 {
                totalExpenses = docExpenses
                expenseCount = docCount
            } else if service.liveTotalExpenses > 0 || service.liveExpenseCount > 0 {
                totalExpenses = service.liveTotalExpenses
                expenseCount = service.liveExpenseCount
            } else {
                totalExpenses = 0
                expenseCount = 0
            }
        } else if service.liveTotalExpenses > 0 || service.liveExpenseCount > 0 {
            totalExpenses = service.liveTotalExpenses
            expenseCount = service.liveExpenseCount
        } else {
            totalExpenses = 0
            expenseCount = 0
        }

        isLoading = false
    }

    var netProfit: Double {
        grossRevenue - totalExpenses
    }

    var isProfitable: Bool {
        netProfit >= 0
    }

    var profitMarginPercent: Double {
        guard grossRevenue > 0 else { return 0.0 }
        return (netProfit / grossRevenue) * 100.0
    }

    var expenseRatio: Double {
        guard grossRevenue > 0 else { return totalExpenses > 0 ? 1.0 : 0.0 }
        return min(max(totalExpenses / grossRevenue, 0.0), 1.0)
    }
}

private struct CommandAccountingSovereignCard: View {
    let onRoute: () -> Void

    @StateObject private var viewModel = CommandAccountingCardViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onRoute()
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // Header Flight Deck: Live Beacon + Section Identity + Quick Route Pill
                headerDeck

                // Primary Hologram: Net Operating Profit
                netProfitHero

                // Secondary Telemetry Twin-Pillars: Inflow (Revenue) vs Outflow (Expenses)
                twinPillars

                // Micro Financial Efficiency Progress Gauge
                efficiencyGauge
            }
            .padding(18)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(cardBorder)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06),
                radius: 12,
                x: 0,
                y: 5
            )
            .scaleEffect(isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 50, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Language.isRTL() ? "اضغط لفتح الخزينة والتقارير المالية الكاملة" : "Tap to open complete financial command center")
    }

    private var headerDeck: some View {
        HStack(alignment: .center, spacing: 8) {
            // Glowing Symbol Squircle
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.72, blue: 0.44).opacity(colorScheme == .dark ? 0.30 : 0.16),
                                Color(red: 0.10, green: 0.55, blue: 0.85).opacity(colorScheme == .dark ? 0.22 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.40), lineWidth: 0.75)
                    )

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Language.get("Accounting_Title", alter: "الخزينة والمالية"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    // Live Telemetry Pulse Dot
                    HStack(spacing: 3.5) {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.78, blue: 0.48))
                            .frame(width: 5, height: 5)
                            .scaleEffect(isPulsing ? 1.3 : 0.8)
                        Text(Language.get("LiveSync", alter: "مباشر"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.12), in: Capsule())
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                }

                Text(Language.isRTL() ? "الأداء التشغيلي والخزينة • هذا الشهر" : "Operational Performance & Treasury • This Month")
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }

            Spacer(minLength: 4)

            // Tactile Entry Pill
            HStack(spacing: 4) {
                Text(Language.isRTL() ? "استعراض" : "Open")
                    .font(AdminType.caption2Bold)
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(AdminSurface.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AdminSurface.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), in: Capsule())
            .overlay(
                Capsule().strokeBorder(AdminSurface.primary.opacity(0.24), lineWidth: 0.5)
            )
        }
    }

    private var netProfitHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Language.isRTL() ? "صافي الربح التشغيلي" : "Net Operating Profit")
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)

                Spacer()

                // Margin Percentage Chip
                HStack(spacing: 3) {
                    Image(systemName: viewModel.isProfitable ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%@%.1f%%", viewModel.isProfitable ? "+" : "", viewModel.profitMarginPercent))
                        .font(AdminType.caption2Bold)
                        .monospacedDigit()
                }
                .foregroundStyle(viewModel.isProfitable ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.95, green: 0.35, blue: 0.40))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    (viewModel.isProfitable ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.95, green: 0.35, blue: 0.40))
                        .opacity(colorScheme == .dark ? 0.20 : 0.10),
                    in: Capsule()
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(formatCurrency(viewModel.netProfit))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(viewModel.isProfitable ? AdminSurface.primaryText : Color(red: 0.95, green: 0.35, blue: 0.40))
                    .monospacedDigit()

                Text(Language.isRTL() ? "ر.ق" : "QAR")
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminCommandInk.secondary)
            }
        }
    }

    private var twinPillars: some View {
        HStack(spacing: 10) {
            // Revenue Pillar
            pillarCell(
                title: Language.isRTL() ? "الإيرادات" : "Revenue",
                amount: viewModel.grossRevenue,
                subtitle: Language.isRTL() ? "\(viewModel.paidOrderCount) عملية دخل" : "\(viewModel.paidOrderCount) income entries",
                symbol: "arrow.up.forward.circle.fill",
                tint: Color(red: 0.16, green: 0.78, blue: 0.48)
            )

            // Expenses Pillar
            pillarCell(
                title: Language.isRTL() ? "المصروفات" : "Expenses",
                amount: viewModel.totalExpenses,
                subtitle: Language.isRTL() ? "\(viewModel.expenseCount) سند صرف" : "\(viewModel.expenseCount) vouchers",
                symbol: "arrow.down.forward.circle.fill",
                tint: Color(red: 0.95, green: 0.40, blue: 0.35)
            )
        }
    }

    private func pillarCell(title: String, amount: Double, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)

                HStack(spacing: 3) {
                    Text(formatCurrency(amount))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(Language.isRTL() ? "ر.ق" : "QAR")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AdminCommandInk.secondary)
                }

                Text(subtitle)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(tint.opacity(colorScheme == .dark ? 0.20 : 0.12), lineWidth: 0.5)
        )
    }

    private var efficiencyGauge: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let w = proxy.size.width
                let expenseRatio = CGFloat(viewModel.expenseRatio)
                let revenueRatio = max(1.0 - expenseRatio, 0.0)

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))

                    // Dynamic multi-segment
                    HStack(spacing: 2) {
                        if revenueRatio > 0 {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.16, green: 0.78, blue: 0.48), Color(red: 0.10, green: 0.65, blue: 0.70)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(w * revenueRatio - 1, 4))
                        }

                        if expenseRatio > 0 {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.95, green: 0.45, blue: 0.35), Color(red: 0.90, green: 0.25, blue: 0.35)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(w * expenseRatio - 1, 4))
                        }
                    }
                }
            }
            .frame(height: 6)

            HStack {
                Text(Language.isRTL() ? "كفاءة التشغيل المالي" : "Capital Efficiency")
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
                Spacer()
                Text(Language.isRTL() ? "انقر لفتح الخزينة والتحليلات ←" : "Tap for full ledger & analytics →")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)
            }
        }
        .padding(.top, 2)
    }

    private var cardBackground: some View {
        ZStack {
            AdminSurface.control

            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.78, blue: 0.48).opacity(colorScheme == .dark ? 0.08 : 0.04),
                    Color(red: 0.10, green: 0.55, blue: 0.85).opacity(colorScheme == .dark ? 0.06 : 0.02),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.78, blue: 0.48).opacity(colorScheme == .dark ? 0.40 : 0.25),
                        AdminSurface.primary.opacity(colorScheme == .dark ? 0.25 : 0.15),
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.85
            )
    }

    private var accessibilityLabel: String {
        let title = Language.isRTL() ? "الخزينة والمالية" : "Treasury and Finance"
        let profit = formatCurrency(viewModel.netProfit)
        let curr = Language.isRTL() ? "ريال قطري" : "QAR"
        return "\(title), \(profit) \(curr)"
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

// MARK: - Command Hotel Sovereign Card

private struct CommandHotelSovereignCard: View {
    let onRoute: () -> Void

    @ObservedObject private var viewModel = AdminPetsHotelViewModel.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onRoute()
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Header Flight Deck
                headerDeck

                // 2. Primary Hologram: Occupancy Radar & In-House Guests
                occupancyHero

                // 3. Operational Horizon Twin Pillars: Arrivals vs Departures
                operationalPillars

                // 4. Multi-Wing Capacity Horizon Bar
                wingHorizonBar
            }
            .padding(18)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(cardBorder)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06),
                radius: 12,
                x: 0,
                y: 5
            )
            .scaleEffect(isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 50, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Language.isRTL() ? "اضغط لفتح عمليات فندق ورعاية الحيوانات" : "Tap to open pets hotel operations hub")
    }

    // MARK: - Header Deck
    private var headerDeck: some View {
        HStack(alignment: .center, spacing: 8) {
            // Glowing Symbol Squircle
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.58, green: 0.35, blue: 0.95).opacity(colorScheme == .dark ? 0.30 : 0.16),
                                Color(red: 0.20, green: 0.65, blue: 0.95).opacity(colorScheme == .dark ? 0.22 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color(red: 0.58, green: 0.35, blue: 0.95).opacity(0.40), lineWidth: 0.75)
                    )

                Image(systemName: "bed.double.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.68, green: 0.45, blue: 1.0))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Language.get("Hotel_Title", alter: "فندق ورعاية الحيوانات"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)

                    // Live Telemetry Pulse Dot
                    HStack(spacing: 3.5) {
                        Circle()
                            .fill(Color(red: 0.35, green: 0.80, blue: 0.55))
                            .frame(width: 5, height: 5)
                            .scaleEffect(isPulsing ? 1.3 : 0.8)
                        Text(Language.get("LiveSync", alter: "مباشر"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(red: 0.35, green: 0.80, blue: 0.55))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.35, green: 0.80, blue: 0.55).opacity(0.12), in: Capsule())
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                }

                Text(Language.isRTL() ? "الإشغال والنزلاء • الغرف والرعاية الفندقية" : "Occupancy & In-House Guests • Boarding & Care")
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            Spacer(minLength: 4)

            // Tactile Entry Pill
            HStack(spacing: 4) {
                Text(Language.isRTL() ? "استعراض" : "Open")
                    .font(AdminType.caption2Bold)
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color(red: 0.58, green: 0.35, blue: 0.95))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(red: 0.58, green: 0.35, blue: 0.95).opacity(colorScheme == .dark ? 0.18 : 0.08), in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color(red: 0.58, green: 0.35, blue: 0.95).opacity(0.26), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Occupancy Hero
    private var occupancyHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Language.isRTL() ? "معدل إشغال الغرف والأجنحة" : "Room & Suite Occupancy Rate")
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)

                Spacer()

                // Active Capacity Chip
                HStack(spacing: 4) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(Language.isRTL() ? "\(viewModel.inHouseGuestsCount) نزيل مقيم" : "\(viewModel.inHouseGuestsCount) In-House")
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(Color(red: 0.58, green: 0.35, blue: 0.95))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Color(red: 0.58, green: 0.35, blue: 0.95).opacity(colorScheme == .dark ? 0.20 : 0.10),
                    in: Capsule()
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(viewModel.occupancyPercentageString)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(AdminSurface.primaryText)
                    .monospacedDigit()

                Text(Language.isRTL() ? "(\(viewModel.occupiedRoomsCount) من \(viewModel.totalRoomsCount) غرفة)" : "(\(viewModel.occupiedRoomsCount) of \(viewModel.totalRoomsCount) suites)")
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)

                if viewModel.attentionGuestsCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(Language.isRTL() ? "\(viewModel.attentionGuestsCount) عناية خاصة" : "\(viewModel.attentionGuestsCount) clinical")
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    // MARK: - Operational Twin Pillars
    private var operationalPillars: some View {
        HStack(spacing: 10) {
            // Arrivals Pillar
            pillarCell(
                title: Language.isRTL() ? "وصول اليوم" : "Arrivals Today",
                count: viewModel.arrivalsTodayCount,
                subtitle: Language.isRTL() ? "حجوزات مؤكدة" : "Confirmed bookings",
                symbol: "arrow.down.right.and.arrow.up.left",
                tint: Color(red: 0.20, green: 0.70, blue: 0.50)
            )

            // Departures Pillar
            pillarCell(
                title: Language.isRTL() ? "مغادرة اليوم" : "Departures Today",
                count: viewModel.departuresTodayCount,
                subtitle: Language.isRTL() ? "تسليم لأصحابها" : "Discharge & handover",
                symbol: "arrow.up.left.and.arrow.down.right",
                tint: Color(red: 0.30, green: 0.60, blue: 0.95)
            )
        }
    }

    private func pillarCell(title: String, count: Int, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)

                HStack(spacing: 4) {
                    Text("\(count)")
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .monospacedDigit()
                    Text(Language.isRTL() ? "حالات" : "items")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AdminCommandInk.secondary)
                }

                Text(subtitle)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(tint.opacity(colorScheme == .dark ? 0.20 : 0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Multi-Wing Horizon Bar
    private var wingHorizonBar: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let w = proxy.size.width
                let total = max(viewModel.totalRoomsCount, 1)
                let occupiedW = w * CGFloat(viewModel.occupiedRoomsCount) / CGFloat(total)
                let availableW = w * CGFloat(viewModel.availableRoomsCount) / CGFloat(total)
                let cleaningW = w * CGFloat(viewModel.cleaningRoomsCount) / CGFloat(total)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))

                    HStack(spacing: 2) {
                        if occupiedW > 3 {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.58, green: 0.35, blue: 0.95), Color(red: 0.45, green: 0.25, blue: 0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(occupiedW - 2, 4))
                        }
                        if availableW > 3 {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.20, green: 0.75, blue: 0.50), Color(red: 0.15, green: 0.65, blue: 0.45)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(availableW - 2, 4))
                        }
                        if cleaningW > 3 {
                            Capsule()
                                .fill(Color.orange.opacity(0.85))
                                .frame(width: max(cleaningW - 2, 4))
                        }
                    }
                }
            }
            .frame(height: 6)

            HStack {
                HStack(spacing: 12) {
                    legendDot(color: Color(red: 0.58, green: 0.35, blue: 0.95), label: Language.isRTL() ? "مشغول (\(viewModel.occupiedRoomsCount))" : "Occupied (\(viewModel.occupiedRoomsCount))")
                    legendDot(color: Color(red: 0.20, green: 0.75, blue: 0.50), label: Language.isRTL() ? "متاح (\(viewModel.availableRoomsCount))" : "Available (\(viewModel.availableRoomsCount))")
                    if viewModel.cleaningRoomsCount > 0 {
                        legendDot(color: Color.orange, label: Language.isRTL() ? "تعقيم (\(viewModel.cleaningRoomsCount))" : "Cleaning (\(viewModel.cleaningRoomsCount))")
                    }
                }
                Spacer()
                Text(Language.isRTL() ? "إدارة الفندق والنزلاء ←" : "Manage Hotel & Guests →")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color(red: 0.58, green: 0.35, blue: 0.95))
            }
        }
        .padding(.top, 2)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
        }
    }

    // MARK: - Visual Enclosure
    private var cardBackground: some View {
        ZStack {
            AdminSurface.control

            LinearGradient(
                colors: [
                    Color(red: 0.58, green: 0.35, blue: 0.95).opacity(colorScheme == .dark ? 0.08 : 0.04),
                    Color(red: 0.20, green: 0.65, blue: 0.95).opacity(colorScheme == .dark ? 0.06 : 0.02),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color(red: 0.58, green: 0.35, blue: 0.95).opacity(colorScheme == .dark ? 0.40 : 0.25),
                        Color(red: 0.20, green: 0.65, blue: 0.95).opacity(colorScheme == .dark ? 0.25 : 0.15),
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.85
            )
    }

    private var accessibilityLabel: String {
        let title = Language.isRTL() ? "فندق ورعاية الحيوانات" : "Pets Hotel and Boarding"
        let rate = viewModel.occupancyPercentageString
        let guests = "\(viewModel.inHouseGuestsCount)"
        return "\(title), \(rate), \(guests)"
    }
}
