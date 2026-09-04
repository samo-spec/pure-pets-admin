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

            VStack(spacing: 0) {
                fixedNavBar(safeTop: safeTop, isRegular: isRegular)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: AdminCommandMetric.sectionSpacing) {
                        // ── Active Working Branch Horizon Capsule Pill ───
                        PPAdminBranchSwitcherBar(style: .compact)
                            .padding(.bottom, 2)

                        CommandEscalationHero(
                            model: heroModel,
                            isRegular: isRegular,
                            onPrimary: { signal in route(signal.id) }
                        )
                        .transition(reduceMotion ? .identity : .opacity)

                        phaseContent
                    }
                    .padding(.horizontal, AdminCommandMetric.pageMargin)
                    .padding(.top, 12)
                    .padding(.bottom, 112)
                    .frame(maxWidth: isRegular ? 980 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(AdminSurface.background.ignoresSafeArea())
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, direction)
        .environment(\.locale, locale)
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
        CommandCenterChrome(
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
            onLogout: { store.onRequestLogout?() }
        )
        .padding(.horizontal, AdminCommandMetric.pageMargin)
        .padding(.top, safeTop + 4)
        .padding(.bottom, 10)
        .frame(maxWidth: isRegular ? 980 : .infinity)
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
    private var phaseContent: some View {
        switch phase {
        case .connecting:
            EmptyView()
        case .loading:
            EmptyView()
        case .ready:
            readyContent
        case .allClear:
            EmptyView()
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

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: AdminCommandMetric.sectionSpacing) {
            // Temporarily hidden per user directive
            /*
            if !store.readiness.failedAreas.isEmpty {
                CommandRecoveryStrip(
                    title: L10n("AdminCommandCenter_SourceIssue_Title"),
                    detail: failedDetail,
                    actionTitle: L10n("AdminCommandCenter_Retry"),
                    action: refresh
                )
            }
            */

            CommandQuickActionsDeck(
                signals: store.snapshot.signals,
                onRoute: { route($0) }
            )

            CommandAccountingSovereignCard(
                onRoute: { route("accounting") }
            )

            if store.canAccessHotel {
                CommandHotelSovereignCard(
                    onRoute: { route("hotel") }
                )
            }

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

// MARK: - Chrome

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isMoreMenuPresented: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            identityAndControls
            CommandStatusLine(
                text: readinessText,
                tone: readinessTone,
                action: onReadinessTap
            )
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var identityAndControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                identityButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                quickControls
            }
        } else {
            HStack(alignment: .center, spacing: 14) {
                identityButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                quickControls
            }
        }
    }

    private var identityButton: some View {
        Button(action: onAccount) {
            HStack(spacing: 12) {
                identityAvatar

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Language.get("CommandCenter_Eyebrow", alter: "Pure Pets Operations"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminCommandInk.secondary)
                            .lineLimit(1)

                        Circle()
                            .fill(AdminSurface.primary)
                            .frame(width: 4, height: 4)

                        Text(capabilityText)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.primary)
                            .lineLimit(1)
                    }

                    Text(resolvedDisplayName)
                        .font(AdminType.title3)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(roleName)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(CommandPressStyle())
        .accessibilityLabel("\(resolvedDisplayName), \(roleName)")
        .accessibilityValue(capabilityText)
        .accessibilityHint(Language.get("AdminCommandCenter_AccountHint", alter: nil))
    }

    private var identityAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            AdminSurface.primary.opacity(0.18),
                            AdminSurface.primary.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            AdminRemoteImage(
                url: resolvedAvatarURL,
                contentMode: .fill,
                targetSize: CGSize(width: 44, height: 44)
            ) {
                Text(monogram)
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            Circle()
                .strokeBorder(AdminSurface.primary.opacity(0.35), lineWidth: 1.0)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
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

    private var quickControls: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onLanguage) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.control)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                        )

                    Label(languageTitle, systemImage: "globe")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }
            }
            .buttonStyle(CommandPressStyle())
            .accessibilityLabel(Language.get("Confirm_LanguageChange_Title", alter: nil))
            .accessibilityValue(languageTitle)

            moreActionsMenuTrigger
        }
    }

    private var moreActionsMenuTrigger: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isMoreMenuPresented.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isMoreMenuPresented ? AdminSurface.primary.opacity(0.12) : AdminSurface.control)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(isMoreMenuPresented ? AdminSurface.primary.opacity(0.4) : Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: isMoreMenuPresented ? 1 : 0.75)
                    )

                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isMoreMenuPresented ? AdminSurface.primary : AdminSurface.primaryText)
            }
        }
        .buttonStyle(CommandPressStyle())
        .accessibilityLabel(Language.get("CommandCenter_Tab_More", alter: nil))
        .background {
            if isMoreMenuPresented {
                Color.black.opacity(0.001)
                    .frame(width: 2500, height: 2500)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            isMoreMenuPresented = false
                        }
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isMoreMenuPresented {
                customHomeMoreActionsMenuCard
                    .offset(y: 52)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.88, anchor: .topTrailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(300)
            }
        }
    }

    private var customHomeMoreActionsMenuCard: some View {
        VStack(spacing: 0) {
            // 1. Refresh
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    isMoreMenuPresented = false
                }
                onRefresh()
            } label: {
                HStack(spacing: 12) {
                    Text(Language.get("AdminCommandCenter_Refresh", alter: "تحديث العمليات"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(CommandPressStyle())

            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.75)
                .padding(.horizontal, 12)

            // 2. Account
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    isMoreMenuPresented = false
                }
                onAccount()
            } label: {
                HStack(spacing: 12) {
                    Text(Language.get("EditMyAccount_Title", alter: "تعديل حسابي"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(CommandPressStyle())

            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.75)
                .padding(.horizontal, 12)

            // 3. Language
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    isMoreMenuPresented = false
                }
                onLanguage()
            } label: {
                HStack(spacing: 12) {
                    Text(Language.get("Confirm_LanguageChange_Title", alter: "تغيير اللغة"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(CommandPressStyle())

            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.75)
                .padding(.horizontal, 12)

            // 4. Logout (Destructive)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    isMoreMenuPresented = false
                }
                onLogout()
            } label: {
                HStack(spacing: 12) {
                    Text(Language.get("Logout", alter: "تسجيل الخروج"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundColor(Color(uiColor: .systemRed))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(uiColor: .systemRed))
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(CommandPressStyle())
        }
        .frame(width: 220)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 18, y: 8)
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
        } else {
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

// MARK: - Quick Actions Deck (Flagship Editorial Grid)

private struct CommandQuickActionItem: Identifiable, Hashable {
    let id: String
    let tag: String
    let title: String
    let subtitle: String
    let symbolName: String
    let accent: Color
    let badgeCount: Int?
    let isLive: Bool
}

private struct DeckWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct CommandQuickActionsDeck: View {
    let signals: [AdminCommandOrbitSignal]
    let onRoute: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var deckWidth: CGFloat = 0
    private let spacing: CGFloat = 11

    // Temporarily hide payments action per user directive
    private let showPaymentsAction = false

    private var items: [CommandQuickActionItem] {
        let fulfillmentSignal = signals.first { $0.id.contains("fulfillment") }
        let deliverySignal = signals.first { $0.id.contains("delivery") }
        let paymentSignal = signals.first { $0.id.contains("payment") }
        let stockSignal = signals.first { $0.id.contains("accessor") || $0.id.contains("stock") }

        var deckItems: [CommandQuickActionItem] = [
            // Index 0: POS (2 columns width)
            CommandQuickActionItem(
                id: "pos",
                tag: "pos",
                title: Language.get("AdminQuickActions_POS", alter: "Point of Sale"),
                subtitle: Language.get("AdminQuickActions_POS_Subtitle", alter: "Instant Sell"),
                symbolName: "cart.fill",
                accent: Color(red: 0.06, green: 0.72, blue: 0.51),
                badgeCount: nil,
                isLive: true
            ),
            // Index 1: Stock & Items (1 column width)
            CommandQuickActionItem(
                id: "accessories",
                tag: "accessories",
                title: Language.get("AdminQuickActions_Inventory", alter: "Stock & Items"),
                subtitle: Language.get("AdminQuickActions_Inventory_Subtitle", alter: "Catalog Levels"),
                symbolName: "archivebox.fill",
                accent: Color(red: 0.55, green: 0.36, blue: 0.96),
                badgeCount: (stockSignal?.count ?? 0) > 0 ? stockSignal?.count : nil,
                isLive: stockSignal?.isLive ?? false
            )
        ]

        if showPaymentsAction {
            deckItems.append(
                CommandQuickActionItem(
                    id: "payments",
                    tag: "payments",
                    title: Language.get("AdminQuickActions_Payments", alter: "Payments"),
                    subtitle: Language.get("AdminQuickActions_Payments_Subtitle", alter: "QIB & Ledger"),
                    symbolName: "creditcard.fill",
                    accent: Color(red: 0.85, green: 0.20, blue: 0.35),
                    badgeCount: (paymentSignal?.count ?? 0) > 0 ? paymentSignal?.count : nil,
                    isLive: paymentSignal?.isLive ?? false
                )
            )
        }

        deckItems.append(contentsOf: [
            // Delivery Fleet
            CommandQuickActionItem(
                id: "delivery",
                tag: "delivery",
                title: Language.get("AdminQuickActions_Delivery", alter: "Delivery Fleet"),
                subtitle: Language.get("AdminQuickActions_Delivery_Subtitle", alter: "Live Dispatch"),
                symbolName: "truck.box.fill",
                accent: Color(red: 0.14, green: 0.54, blue: 0.98),
                badgeCount: (deliverySignal?.count ?? 0) > 0 ? deliverySignal?.count : nil,
                isLive: deliverySignal?.isLive ?? false
            ),
            // Fulfillment
            CommandQuickActionItem(
                id: "fulfillment",
                tag: "fulfillment",
                title: Language.get("AdminQuickActions_Fulfillment", alter: "Fulfillment"),
                subtitle: Language.get("AdminQuickActions_Fulfillment_Subtitle", alter: "Pack & Prepare"),
                symbolName: "shippingbox.fill",
                accent: Color(red: 0.96, green: 0.55, blue: 0.12),
                badgeCount: (fulfillmentSignal?.count ?? 0) > 0 ? fulfillmentSignal?.count : nil,
                isLive: fulfillmentSignal?.isLive ?? false
            ),
            // Broadcast
            CommandQuickActionItem(
                id: "notificationsCompose",
                tag: "notificationsCompose",
                title: Language.get("AdminQuickActions_Broadcast", alter: "Broadcast"),
                subtitle: Language.get("AdminQuickActions_Broadcast_Subtitle", alter: "Push Alert"),
                symbolName: "bell.badge.fill",
                accent: Color(red: 0.96, green: 0.25, blue: 0.37),
                badgeCount: nil,
                isLive: false
            )
        ])

        return deckItems
    }

    private func computeWidths(in totalWidth: CGFloat) -> (oneCol: CGFloat, twoCol: CGFloat) {
        let heroInset = AdminCommandMetric.pageMargin
        let available = totalWidth > 0 ? totalWidth : (UIScreen.main.bounds.width - 2 * heroInset)
        let oneCol = max((available - 2 * spacing) / 3, 70)
        let twoCol = 2 * oneCol + spacing
        return (oneCol, twoCol)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            headerRow

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: spacing) {
                    ForEach(items) { item in
                        CommandQuickActionCard(item: item, isTwoColumn: false) {
                            onRoute(item.tag)
                        }
                    }
                }
            } else {
                let heroInset = AdminCommandMetric.pageMargin
                let availableWidth = deckWidth > 0 ? deckWidth : (UIScreen.main.bounds.width - 2 * heroInset)
                let widths = computeWidths(in: availableWidth)

                VStack(spacing: spacing) {
                    if showPaymentsAction && items.count >= 6 {
                        // Row 1: POS (2 columns) + Stock & Items (1 column)
                        HStack(spacing: spacing) {
                            CommandQuickActionCard(item: items[0], isTwoColumn: true) {
                                onRoute(items[0].tag)
                            }
                            .frame(width: widths.twoCol)

                            CommandQuickActionCard(item: items[1], isTwoColumn: false) {
                                onRoute(items[1].tag)
                            }
                            .frame(width: widths.oneCol)
                        }

                        // Row 2: Payments (2 columns) + Delivery Fleet (1 column)
                        HStack(spacing: spacing) {
                            CommandQuickActionCard(item: items[2], isTwoColumn: true) {
                                onRoute(items[2].tag)
                            }
                            .frame(width: widths.twoCol)

                            CommandQuickActionCard(item: items[3], isTwoColumn: false) {
                                onRoute(items[3].tag)
                            }
                            .frame(width: widths.oneCol)
                        }

                        // Row 3: Fulfillment (2 columns) + Broadcast (1 column)
                        HStack(spacing: spacing) {
                            CommandQuickActionCard(item: items[4], isTwoColumn: true) {
                                onRoute(items[4].tag)
                            }
                            .frame(width: widths.twoCol)

                            CommandQuickActionCard(item: items[5], isTwoColumn: false) {
                                onRoute(items[5].tag)
                            }
                            .frame(width: widths.oneCol)
                        }
                    } else if items.count >= 5 {
                        // Row 1: POS (2 columns) + Stock & Items (1 column)
                        HStack(spacing: spacing) {
                            CommandQuickActionCard(item: items[0], isTwoColumn: true) {
                                onRoute(items[0].tag)
                            }
                            .frame(width: widths.twoCol)

                            CommandQuickActionCard(item: items[1], isTwoColumn: false) {
                                onRoute(items[1].tag)
                            }
                            .frame(width: widths.oneCol)
                        }

                        // Row 2: Fulfillment + Delivery Fleet + Notifications in ONE unified 3-column row
                        if let fulfillment = items.first(where: { $0.id == "fulfillment" }),
                           let delivery = items.first(where: { $0.id == "delivery" }),
                           let broadcast = items.first(where: { $0.id == "notificationsCompose" }) {
                            HStack(spacing: spacing) {
                                CommandQuickActionCard(item: fulfillment, isTwoColumn: false) {
                                    onRoute(fulfillment.tag)
                                }
                                .frame(width: widths.oneCol)

                                CommandQuickActionCard(item: delivery, isTwoColumn: false) {
                                    onRoute(delivery.tag)
                                }
                                .frame(width: widths.oneCol)

                                CommandQuickActionCard(item: broadcast, isTwoColumn: false) {
                                    onRoute(broadcast.tag)
                                }
                                .frame(width: widths.oneCol)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: DeckWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(DeckWidthPreferenceKey.self) { newWidth in
            if newWidth > 0 && abs(deckWidth - newWidth) > 0.5 {
                deckWidth = newWidth
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Language.get("AdminQuickActions_SectionTitle", alter: "Quick Actions"))
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                Text(Language.get("AdminQuickActions_SectionDetail", alter: "High-velocity operational launchpad"))
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                Circle()
                    .fill(AdminSurface.primary)
                    .frame(width: 6, height: 6)
                Text(Language.get("AdminQuickActions_LivePill", alter: "Live Deck"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AdminSurface.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AdminSurface.primary.opacity(0.24), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
        }
    }
}

private struct CommandQuickActionCard: View {
    let item: CommandQuickActionItem
    var isTwoColumn: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    // Elevated icon glyph squircle with crisp optical highlight
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? item.accent.opacity(0.30)
                                    : Color.white.opacity(0.88)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(item.accent.opacity(colorScheme == .dark ? 0.50 : 0.32), lineWidth: 0.75)
                            )
                            .shadow(color: item.accent.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 3, x: 0, y: 1)

                        Image(systemName: item.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(item.accent)
                    }
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                    Spacer(minLength: 4)

                    if let count = item.badgeCount, count > 0 {
                        HStack(spacing: 3.5) {
                            Circle()
                                .fill(item.accent)
                                .frame(width: 5, height: 5)
                                .scaleEffect(isPulsing ? 1.25 : 0.85)
                            Text("\(count)")
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(item.accent)
                                .monospacedDigit()
                            if isTwoColumn {
                                Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(item.accent.opacity(0.70))
                            }
                        }
                        .padding(.horizontal, isTwoColumn ? 8 : 6)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(colorScheme == .dark ? item.accent.opacity(0.24) : Color.white.opacity(0.92))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(item.accent.opacity(0.32), lineWidth: 0.75)
                        )
                    } else if isTwoColumn && item.isLive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.accent)
                                .frame(width: 5, height: 5)
                                .scaleEffect(isPulsing ? 1.25 : 0.85)
                            Text(Language.get("AdminQuickActions_Live", alter: "Live"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(item.accent)
                            Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(item.accent.opacity(0.70))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(colorScheme == .dark ? item.accent.opacity(0.24) : Color.white.opacity(0.92))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(item.accent.opacity(0.32), lineWidth: 0.75)
                        )
                    } else {
                        Image(systemName: Language.isRTL() ? "chevron.backward" : "chevron.forward")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(item.accent.opacity(0.75))
                            .accessibilityHidden(true)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(item.subtitle)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 104)
            .background(
                ZStack {
                    // Base canvas to prevent transparency bleed
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)

                    // Subtle refined accent gradient wash
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    item.accent.opacity(colorScheme == .dark ? 0.10 : 0.05),
                                    item.accent.opacity(colorScheme == .dark ? 0.05 : 0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Optical radial glow from the leading corner
                    RadialGradient(
                        colors: [
                            item.accent.opacity(colorScheme == .dark ? 0.08 : 0.035),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: isTwoColumn ? 120 : 70
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(item.accent.opacity(colorScheme == .dark ? 0.45 : 0.28), lineWidth: 0.85)
            )
            .shadow(
                color: item.accent.opacity(colorScheme == .dark ? 0.22 : 0.10),
                radius: 6,
                x: 0,
                y: 2.5
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .accessibilityHint(Language.get("AdminCommandCenter_OpenHint", alter: "Opens section"))
    }
}

private struct CommandQuickActionCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
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
        listeners = [wsReg]
        sync()
    }

    private func sync() {
        guard let workspace = service.currentWorkspace,
              let dashboard = workspace.primaryDashboard else {
            grossRevenue = 0
            totalExpenses = 0
            paidOrderCount = 0
            expenseCount = 0
            isLoading = false
            return
        }
        grossRevenue = dashboard.income
        totalExpenses = dashboard.expenses
        paidOrderCount = workspace.incomeCount
        expenseCount = workspace.expenseCount
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
                    Text(Language.isRTL() ? "ر.ق" : "QAR")
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
