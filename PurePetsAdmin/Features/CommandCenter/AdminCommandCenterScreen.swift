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
    @Published private(set) var revision: Int = 0

    var onRoute: ((String) -> Void)?
    var onRefresh: (() -> Void)?
    var onRequestLogout: (() -> Void)?
    var onToggleLanguage: (() -> Void)?
    var onSelectTab: ((Int) -> Void)?

    func apply(roleName: String?, capabilityCount: Int, signals: [AdminCommandOrbitSignalDescriptor], animated: Bool) {
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

    public func applyRoleName(_ roleName: String?, capabilityCount: Int, signals: [AdminCommandOrbitSignalDescriptor], animated: Bool) {
        store.apply(roleName: roleName, capabilityCount: capabilityCount, signals: signals, animated: animated)
    }

    public func applyReadinessWithLoadingAreas(_ loadingAreas: [String], failedAreas: [String], updatedAt: Date?) {
        store.applyReadiness(loadingAreas: loadingAreas, failedAreas: failedAreas, updatedAt: updatedAt)
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

private enum AdminCommandInk {
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var locale: Locale {
        Locale(identifier: store.localeCode == "ar" ? "ar_QA" : "en_QA")
    }

    private var direction: LayoutDirection {
        store.localeCode == "ar" ? .rightToLeft : .leftToRight
    }

    private var phase: AdminCommandOrbitPhase {
        let snapshot = store.snapshot
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

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: AdminCommandMetric.sectionSpacing) {
                    CommandCenterChrome(
                        roleName: roleDisplayName,
                        capabilityText: capabilityText,
                        readinessText: compactReadinessText,
                        readinessTone: readinessTone,
                        languageTitle: languageToggleTitle,
                        onAccount: { route("editMyAccount") },
                        onRefresh: { refresh() },
                        onLanguage: { store.onToggleLanguage?() },
                        onLogout: { store.onRequestLogout?() }
                    )

                    CommandEscalationHero(
                        model: heroModel,
                        isRegular: isRegular,
                        onPrimary: { signal in route(signal.id) }
                    )
                    .transition(reduceMotion ? .identity : .opacity)

                    phaseContent
                }
                .padding(.horizontal, AdminCommandMetric.pageMargin)
                .padding(.top, safeTop + 8)
                .padding(.bottom, 112)
                .frame(maxWidth: isRegular ? 980 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .background(AdminSurface.background.ignoresSafeArea())
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, direction)
        .environment(\.locale, locale)
        .onReceive(
            NotificationCenter.default
                .publisher(for: Notification.Name("LanguageDidChangeNotification"))
                .receive(on: RunLoop.main)
        ) { _ in
            store.localeCode = Language.currentLanguageCode()
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
            if !store.readiness.failedAreas.isEmpty {
                CommandRecoveryStrip(
                    title: L10n("AdminCommandCenter_SourceIssue_Title"),
                    detail: failedDetail,
                    actionTitle: L10n("AdminCommandCenter_Retry"),
                    action: refresh
                )
            }

            CommandQuickActionsDeck(
                signals: store.snapshot.signals,
                onRoute: { route($0) }
            )

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
    let roleName: String
    let capabilityText: String
    let readinessText: String
    let readinessTone: AdminCommandTone
    let languageTitle: String
    let onAccount: () -> Void
    let onRefresh: () -> Void
    let onLanguage: () -> Void
    let onLogout: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            identityAndControls
            CommandStatusLine(text: readinessText, tone: readinessTone)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var identityAndControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                identityButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                quickControls
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                identityButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                quickControls
            }
        }
    }

    private var identityButton: some View {
        Button(action: onAccount) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.control)
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 19, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AdminSurface.primary)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("CommandCenter_Eyebrow", alter: nil))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(roleName)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(capabilityText)
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(CommandPressStyle())
        .accessibilityLabel(roleName)
        .accessibilityValue(capabilityText)
        .accessibilityHint(Language.get("AdminCommandCenter_AccountHint", alter: nil))
    }

    private var quickControls: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onLanguage) {
                Label(languageTitle, systemImage: "globe")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 44, height: 44)
                    .background(AdminSurface.control, in: Circle())
            }
            .buttonStyle(CommandPressStyle())
            .accessibilityLabel(Language.get("Confirm_LanguageChange_Title", alter: nil))
            .accessibilityValue(languageTitle)

            Menu {
                Button(action: onRefresh) {
                    Label(Language.get("AdminCommandCenter_Refresh", alter: nil), systemImage: "arrow.clockwise")
                }
                Button(action: onAccount) {
                    Label(Language.get("EditMyAccount_Title", alter: nil), systemImage: "person.crop.circle")
                }
                Button(action: onLanguage) {
                    Label(Language.get("Confirm_LanguageChange_Title", alter: nil), systemImage: "globe")
                }
                Divider()
                Button(role: .destructive, action: onLogout) {
                    Label(Language.get("Logout", alter: nil), systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: 44, height: 44)
                    .background(AdminSurface.control, in: Circle())
            }
            .accessibilityLabel(Language.get("CommandCenter_Tab_More", alter: nil))
        }
    }
}

private struct CommandStatusLine: View {
    let text: String
    let tone: AdminCommandTone

    var body: some View {
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
        .frame(minHeight: 24)
        .accessibilityElement(children: .combine)
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
///
/// Composition, in reading order: a trust line that states the live condition
/// together with the moment it was confirmed, a load column that quantifies the
/// authorized workload and splits it across a proportional escalation spine,
/// the decision statement, the single next command bound to the highest
/// priority signal, and an authority ledger. The spine replaces decorative
/// gauges: its widths and colors are the real per-area counts and priority
/// classes, so the graphic cannot disagree with the numbers beside it.
private struct CommandEscalationHero: View {
    let model: CommandHeroModel
    let isRegular: Bool
    let onPrimary: (AdminCommandOrbitSignal) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var livePulse = false

    private var stacksColumns: Bool {
        !isRegular || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            trustLine

            if stacksColumns {
                VStack(alignment: .leading, spacing: 20) {
                    loadColumn
                    decisionColumn
                }
            } else {
                HStack(alignment: .top, spacing: 26) {
                    loadColumn
                        .frame(width: 288, alignment: .leading)
                    decisionColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            authorityLedger
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .commandSoftSurface(radius: AdminCommandMetric.heroRadius, borderOpacity: 0.78)
        .accessibilityElement(children: .contain)
    }

    // MARK: Trust line

    @ViewBuilder
    private var trustLine: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                stateBadge
                freshnessStamp
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                stateBadge
                Spacer(minLength: 8)
                freshnessStamp
            }
        }
    }

    private var stateBadge: some View {
        HStack(spacing: 7) {
            liveIndicator
            Text(model.situation.badge)
                .font(AdminType.captionBold)
                .foregroundStyle(model.situation.tone.color)
                .lineLimit(2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(model.situation.tone.softFill, in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.situation.badge)
    }

    private var freshnessStamp: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AdminCommandInk.tertiary)
                .accessibilityHidden(true)
            Text(model.updatedText)
                .font(AdminType.caption1)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("CommandCenter_Last_Updated", alter: nil))
        .accessibilityValue(model.updatedText)
    }

    @ViewBuilder
    private var liveIndicator: some View {
        if model.hasLiveSignal {
            Circle()
                .fill(model.situation.tone.accent)
                .frame(width: 9, height: 9)
                .opacity(livePulse ? 0.34 : 1)
                .onAppear(perform: startLivePulse)
                .onChange(of: reduceMotion) { isReduced in
                    if isReduced {
                        stopLivePulse()
                    } else {
                        startLivePulse()
                    }
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: model.situation.symbol)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.situation.tone.accent)
                .accessibilityHidden(true)
        }
    }

    /// A single quiet breath on the live dot. It carries the only continuous
    /// motion on the surface and is removed entirely under Reduce Motion.
    private func startLivePulse() {
        guard !reduceMotion, !livePulse else { return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
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

    // MARK: Load column

    private var loadColumn: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("AdminCommandCenter_ActiveLoad", alter: nil))
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.tertiary)
                    .lineLimit(2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                loadValue
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Language.get("AdminCommandCenter_ActiveLoad", alter: nil))
            .accessibilityValue(model.loadAccessibilityValue)

            CommandLoadSpine(
                segments: model.segments,
                trackAccent: model.situation.tone.accent,
                showsPlaceholder: model.situation.showsProgress,
                reduceMotion: reduceMotion
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Language.get("AdminCommandCenter_Load_Distribution", alter: nil))
            .accessibilityValue(model.distributionAccessibilityValue)

            tierLegend
        }
    }

    @ViewBuilder
    private var loadValue: some View {
        if model.situation.showsProgress {
            ProgressView()
                .tint(model.situation.tone.color)
                .scaleEffect(1.1)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        } else if model.usesNumericLoad {
            Text(model.totalCountText)
                .font(dynamicTypeSize.isAccessibilitySize ? AdminType.title : AdminCommandTypography.loadValue)
                .foregroundStyle(AdminSurface.primaryText)
                .monospacedDigit()
                .commandNumericTransition()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Image(systemName: model.situation.symbol)
                .font(.system(size: 26, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.situation.tone.accent)
                .frame(width: 56, height: 56)
                .background(model.situation.tone.softFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private var tierLegend: some View {
        if !model.tierGroups.isEmpty {
            let rows = legendRows
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        ForEach(rows[index]) { group in
                            legendChip(group)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var legendRows: [[CommandTierGroup]] {
        let perRow = dynamicTypeSize.isAccessibilitySize ? 1 : 3
        return stride(from: 0, to: model.tierGroups.count, by: perRow).map { start in
            Array(model.tierGroups[start..<min(start + perRow, model.tierGroups.count)])
        }
    }

    private func legendChip(_ group: CommandTierGroup) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(group.accent)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(group.label)
                .font(AdminType.caption1)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let countText = group.countText {
                Text(countText)
                    .font(AdminType.captionBold)
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

    // MARK: Decision column

    private var decisionColumn: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 7) {
                Text(model.situation.title)
                    .font(dynamicTypeSize.isAccessibilitySize ? AdminType.title2 : AdminCommandTypography.decisionTitle)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(nil)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text(model.situation.detail)
                    .font(AdminType.callout)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(nil)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if let primary = model.primarySignal {
                commandBar(for: primary)
            }
        }
    }

    /// The next command. It is bound to the highest priority signal and carries
    /// that signal's own load, so the operator sees what the action resolves
    /// before opening it. Routing stays with the store-provided callback.
    private func commandBar(for signal: AdminCommandOrbitSignal) -> some View {
        Button {
            onPrimary(signal)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: signal.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.primaryActionTitle)
                        .font(AdminType.calloutBold)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Language.get("AdminCommandCenter_Act", alter: nil))
                        .font(AdminType.caption2)
                        .foregroundStyle(Color.white.opacity(0.76))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 6)

                if let countText = model.primaryCountText {
                    Text(countText)
                        .font(AdminType.captionBold)
                        .monospacedDigit()
                        .padding(.horizontal, 9)
                        .frame(minWidth: 30, minHeight: 26)
                        .background(Color.white.opacity(0.18), in: Capsule(style: .continuous))
                        .accessibilityHidden(true)
                }

                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: AdminCommandMetric.commandBarHeight)
            .background(
                signal.tier.tone.actionFill,
                in: RoundedRectangle(cornerRadius: AdminCommandMetric.commandBarRadius, style: .continuous)
            )
        }
        .buttonStyle(CommandPressStyle())
        .accessibilityLabel(model.primaryActionTitle)
        .commandAccessibilityValue(model.primaryCountText.map {
            String(format: Language.get("AdminCommandCenter_Count_Format", alter: nil), $0)
        })
        .accessibilityHint(Language.get("AdminCommandCenter_OpenHint", alter: nil))
    }

    // MARK: Authority ledger

    private var authorityLedger: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            if let stateClassLabel = model.stateClassLabel {
                ledgerRow(
                    title: Language.get("CommandCenter_Operational_State", alter: nil),
                    value: stateClassLabel,
                    accent: model.situation.tone.accent
                )
            }

            ledgerRow(
                title: Language.get("AdminCommandCenter_AccessScope", alter: nil),
                value: model.capabilityText,
                accent: nil
            )
        }
    }

    private func ledgerRow(title: String, value: String, accent: Color?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(AdminType.caption1)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if let accent = accent {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(value)
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(2)
                    .lineSpacing(2)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

// MARK: - Escalation Spine

/// A proportional load bar: one capsule per authorized area, ordered by
/// escalation priority from the leading edge, width proportional to the real
/// item count with a legibility floor, colored by priority class. It is a
/// single accessibility element because the priority list below the hero owns
/// the tappable per-area actions.
private struct CommandLoadSpine: View {
    let segments: [CommandLoadSegment]
    let trackAccent: Color
    let showsPlaceholder: Bool
    let reduceMotion: Bool

    private let gap: CGFloat = 3
    private let minimumSegment: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(in: proxy.size.width)
            HStack(spacing: gap) {
                if showsPlaceholder || segments.isEmpty {
                    Capsule(style: .continuous)
                        .fill(trackAccent.opacity(0.32))
                } else {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        Capsule(style: .continuous)
                            .fill(segment.accent)
                            .frame(width: index < widths.count ? widths[index] : 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.88), value: layoutSignature)
        }
        .frame(height: AdminCommandMetric.spineHeight)
        .background(AdminSurface.control, in: Capsule(style: .continuous))
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

// MARK: - Quick Actions Deck (Two-Row Flagship Grid)

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

private struct CommandQuickActionsDeck: View {
    let signals: [AdminCommandOrbitSignal]
    let onRoute: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    private var items: [CommandQuickActionItem] {
        let fulfillmentSignal = signals.first { $0.id.contains("fulfillment") }
        let deliverySignal = signals.first { $0.id.contains("delivery") }
        let paymentSignal = signals.first { $0.id.contains("payment") }
        let stockSignal = signals.first { $0.id.contains("accessor") || $0.id.contains("stock") }

        return [
            // Row 1: Core Operations & Rapid Commerce
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

            // Row 2: Management, Stock & Communications
            CommandQuickActionItem(
                id: "payments",
                tag: "payments",
                title: Language.get("AdminQuickActions_Payments", alter: "Payments"),
                subtitle: Language.get("AdminQuickActions_Payments_Subtitle", alter: "QIB & Ledger"),
                symbolName: "creditcard.fill",
                accent: Color(red: 0.85, green: 0.20, blue: 0.35),
                badgeCount: (paymentSignal?.count ?? 0) > 0 ? paymentSignal?.count : nil,
                isLive: paymentSignal?.isLive ?? false
            ),
            CommandQuickActionItem(
                id: "accessories",
                tag: "accessories",
                title: Language.get("AdminQuickActions_Inventory", alter: "Stock & Items"),
                subtitle: Language.get("AdminQuickActions_Inventory_Subtitle", alter: "Catalog Levels"),
                symbolName: "archivebox.fill",
                accent: Color(red: 0.55, green: 0.36, blue: 0.96),
                badgeCount: (stockSignal?.count ?? 0) > 0 ? stockSignal?.count : nil,
                isLive: stockSignal?.isLive ?? false
            ),
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
        ]
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 11)]
        }
        return [
            GridItem(.flexible(), spacing: 11),
            GridItem(.flexible(), spacing: 11),
            GridItem(.flexible(), spacing: 11)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            headerRow

            LazyVGrid(columns: columns, spacing: 11) {
                ForEach(items) { item in
                    CommandQuickActionCard(item: item) {
                        onRoute(item.tag)
                    }
                }
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
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center, spacing: 8) {
                    // Elevated icon glyph squircle with fine optical highlight
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        item.accent.opacity(colorScheme == .dark ? 0.32 : 0.20),
                                        item.accent.opacity(colorScheme == .dark ? 0.12 : 0.06)
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 22
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(item.accent.opacity(0.32), lineWidth: 0.75)
                            )

                        Image(systemName: item.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(item.accent)
                    }
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                    Spacer(minLength: 2)

                    if let count = item.badgeCount, count > 0 {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(item.accent)
                                .frame(width: 5, height: 5)
                                .scaleEffect(isPulsing ? 1.2 : 0.8)
                            Text("\(count)")
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(item.accent)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(item.accent.opacity(0.14), in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(item.accent.opacity(0.28), lineWidth: 0.5)
                        )
                    } else {
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AdminCommandInk.tertiary.opacity(0.60))
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
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AdminSurface.control)
                    .overlay(
                        RadialGradient(
                            colors: [
                                item.accent.opacity(colorScheme == .dark ? 0.08 : 0.04),
                                .clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 64
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.68 : 0.45), lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(CommandQuickActionCardStyle())
        .onAppear {
            if item.badgeCount != nil {
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
        VStack(alignment: .leading, spacing: 12) {
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
                VStack(spacing: 0) {
                    ForEach(Array(signals.enumerated()), id: \.element.id) { index, signal in
                        Button {
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
                .commandSoftSurface(radius: AdminCommandMetric.surfaceRadius, borderOpacity: 0.64)
            }
        }
    }
}

private struct CommandPriorityRow: View {
    let signal: AdminCommandOrbitSignal
    let locale: Locale
    let position: Int
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(signal.tier.tone.softFill)
                    Image(systemName: signal.symbolName)
                        .font(.system(size: 16, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(signal.tier.tone.accent)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

                if !isLast {
                    Rectangle()
                        .fill(AdminSurface.control)
                        .frame(width: 1, height: 32)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(priorityLabel)
                            .font(AdminType.captionBold)
                            .foregroundStyle(signal.tier.tone.color)
                            .lineLimit(2)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !signal.moduleTitle.isEmpty {
                            Text(signal.moduleTitle)
                                .font(AdminType.caption1)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .lineLimit(2)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 8)
                    if signal.count > 0 {
                        Text(signal.count.formatted(.number.locale(locale)))
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primaryText)
                            .monospacedDigit()
                            .accessibilityLabel(countAccessibilityText)
                    }
                }

                Text(signal.title)
                    .font(position == 1 ? AdminType.title3 : AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if !signal.detail.isEmpty {
                    Text(signal.detail)
                        .font(AdminType.callout)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(nil)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Text(Language.get("AdminCommandCenter_Act", alter: nil))
                        .font(AdminType.captionBold)
                        .foregroundStyle(signal.tier.tone.color)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(signal.tier.tone.accent)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(minHeight: AdminCommandMetric.rowMinimumHeight)
        .contentShape(Rectangle())
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

    private var rows: [CommandSourceRow] {
        var result: [CommandSourceRow] = []
        result.append(.init(title: Language.get("CommandCenter_Last_Updated", alter: nil), value: updatedText, tone: .stable, symbol: "clock"))
        if loadingSources.isEmpty && failedSources.isEmpty {
            result.append(.init(title: Language.get("AdminCommandCenter_SourceReady", alter: nil), value: Language.get("AdminCommandCenter_Ready_Detail", alter: nil), tone: .stable, symbol: "checkmark.circle"))
        }
        if !loadingSources.isEmpty {
            result.append(.init(title: Language.get("AdminCommandCenter_LoadingSources", alter: nil), value: localizedList(loadingSources), tone: .info, symbol: "arrow.triangle.2.circlepath"))
        }
        if !failedSources.isEmpty {
            result.append(.init(title: Language.get("AdminCommandCenter_SourceIssue_Title", alter: nil), value: localizedList(failedSources), tone: .elevated, symbol: "wifi.exclamationmark"))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, detail: detail)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 12) {
                        Image(systemName: row.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(row.tone.accent)
                            .frame(width: 36, height: 36)
                            .background(row.tone.softFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(AdminType.captionBold)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .lineLimit(2)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(row.value)
                                .font(AdminType.callout)
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(nil)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .accessibilityElement(children: .combine)

                    if index < rows.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .commandSoftSurface(radius: AdminCommandMetric.surfaceRadius, borderOpacity: 0.64)
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
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(uiColor: .ppWarning))
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .ppMineralBeige), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(nil)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(AdminType.callout)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(nil)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: action) {
                HStack(spacing: 8) {
                    Text(actionTitle)
                        .font(AdminType.calloutBold)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(AdminSurface.primaryPressed, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(CommandPressStyle())
        }
        .padding(16)
        .background(Color(uiColor: .ppMineralBeige), in: RoundedRectangle(cornerRadius: AdminCommandMetric.tightRadius, style: .continuous))
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
                .padding(12)
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
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tone.softFill)
                if showsProgress {
                    ProgressView().tint(tone.color)
                } else {
                    Image(systemName: tone.symbol)
                        .font(.system(size: 25, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tone.accent)
                }
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            VStack(spacing: 7) {
                Text(title)
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(AdminType.callout)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            extra

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: AdminCommandMetric.minimumActionHeight)
                        .background(tone.actionFill, in: RoundedRectangle(cornerRadius: AdminCommandMetric.tightRadius, style: .continuous))
                }
                .buttonStyle(CommandPressStyle())
                .accessibilityHint(Language.get("AdminCommandOrbit_Refresh_Hint", alter: nil))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .commandSoftSurface(radius: AdminCommandMetric.surfaceRadius, borderOpacity: 0.64)
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

private struct SectionHeader: View {
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

private struct CommandPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1.0)
    }
}
