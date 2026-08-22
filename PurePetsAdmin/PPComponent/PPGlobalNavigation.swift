//
//  PPGlobalNavigation.swift
//  PurePetsAdmin
//
//  ONE global navigation owner for every screen, including Work / main / root.
//
//  NEXTGEN V6 REDESIGN
//  ─────────────────────────────────────────────────────────────────────────────
//  The operations masthead is one top-aligned row: Back / Close enters at the
//  logical leading edge, the identity stack follows it, and hosted actions stay
//  at the logical trailing edge. The title reflows in place instead of moving to
//  a second stage, and the expanded bar never exceeds 83pt.
//
//  The bar remains clear so operational content, not navigation decoration,
//  dominates the first screen. Liquid Glass is reserved for interactive controls
//  on iOS 26; semantic Pure Pets surfaces provide the iOS 15 fallback.
//
//  CONTRACT
//  ─────────────────────────────────────────────────────────────────────────────
//  • One navigation owner, one safe-area owner. Hosts keep routing + semantics.
//  • No business logic, no permission mutation, no routing decisions here.
//  • `PPGlobalNavigationStyle` is retained for source compatibility; all cases
//    now resolve to the single canonical composition. There are no per-screen
//    navigation designs.
//  • RTL mirrors through leading/trailing only. Dynamic Type, Reduce Motion,
//    VoiceOver and 44pt hit areas are honoured in both display modes.
//  • iOS 26 Liquid Glass when available, semantic Material fallback otherwise.
//  • Expanded reservation is capped at 83pt. Text remains VoiceOver-complete;
//    accessibility sizes use compact type metrics inside the same bounded row
//    so route chrome cannot displace operational content.
//

import SwiftUI
import UIKit

// MARK: - Public API

/// Retained for source compatibility with existing hosts.
///
/// The three historical styles now resolve to the single canonical Pure Pets Pro
/// navigation composition. `displayName` is preserved for debug pickers.
public enum PPGlobalNavigationStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case commandCrown
    case edgeLoom
    case contextDeck

    public var id: String { rawValue }

    /// Host-reserved height for `PPNavigationDisplayMode.expanded`.
    public var expandedBarHeight: CGFloat { PPNavSpec.expandedHeight }

    /// Host-reserved height for the rendered compact composition.
    public var compactBarHeight: CGFloat { PPNavSpec.compactHeight }

    public var displayName: String {
        switch self {
        case .commandCrown: return "Command Crown"
        case .edgeLoom: return "Edge Loom"
        case .contextDeck: return "Context Deck"
        }
    }
}

/// The two navigation compositions.
///
/// `expanded` is the standard iPhone / default presentation.
/// `compact` is selected automatically for narrow widths or once the host has
/// scrolled past the large-title threshold.
public enum PPNavigationDisplayMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case expanded
    case compact

    public var id: String { rawValue }
}

public enum PPGlobalNavigationActionKind: Hashable, Sendable {
    case back
    case close
    case refresh
    case more
    case profile
    case capabilityLens
    case command
    case notifications
    case confirm
    case custom(symbol: String)
}

public enum PPGlobalNavigationActionProminence: Hashable, Sendable {
    case standard
    case emphasized
    case quiet
}

public struct PPGlobalNavigationAction: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: PPGlobalNavigationActionKind
    public let accessibilityLabel: String
    public let accessibilityHint: String?
    public let prominence: PPGlobalNavigationActionProminence
    public let badge: String?
    public let isEnabled: Bool
    /// Visible label. Rendered only for `.emphasized` actions, as in
    /// `03_modal_create_navbar_3x.png`. `nil` keeps the action icon-only.
    public let title: String?
    /// Initials rendered inside a `.profile` action, as in the reference crown.
    public let monogram: String?

    public init(
        id: String,
        kind: PPGlobalNavigationActionKind,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        prominence: PPGlobalNavigationActionProminence = .standard,
        badge: String? = nil,
        isEnabled: Bool = true,
        title: String? = nil,
        monogram: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.prominence = prominence
        self.badge = badge
        self.isEnabled = isEnabled
        self.title = title
        self.monogram = monogram
    }

    public static let back = PPGlobalNavigationAction(
        id: "back",
        kind: .back,
        accessibilityLabel: Language.get("Back", alter: nil)
    )

    public static let close = PPGlobalNavigationAction(
        id: "close",
        kind: .close,
        accessibilityLabel: Language.get("Close", alter: nil)
    )

    public static let refresh = PPGlobalNavigationAction(
        id: "refresh",
        kind: .refresh,
        accessibilityLabel: Language.get("CommandCenter_Refresh", alter: nil),
        prominence: .emphasized
    )

    public static let more = PPGlobalNavigationAction(
        id: "more",
        kind: .more,
        accessibilityLabel: Language.get("CommandCenter_Tab_More", alter: nil)
    )
}

public struct PPGlobalNavigationStatus: Hashable, Sendable {
    public var label: String
    public var detail: String?
    public var isLive: Bool

    public init(label: String, detail: String? = nil, isLive: Bool = false) {
        self.label = label
        self.detail = detail
        self.isLive = isLive
    }
}

public struct PPGlobalNavigationConfiguration: Hashable, Sendable {
    public var style: PPGlobalNavigationStyle
    public var title: String
    public var eyebrow: String?
    public var subtitle: String?
    public var context: String?
    public var status: PPGlobalNavigationStatus?
    public var leadingAction: PPGlobalNavigationAction?
    public var trailingActions: [PPGlobalNavigationAction]
    public var showsContextFilament: Bool

    public init(
        style: PPGlobalNavigationStyle = .contextDeck,
        title: String,
        eyebrow: String? = nil,
        subtitle: String? = nil,
        context: String? = nil,
        status: PPGlobalNavigationStatus? = nil,
        leadingAction: PPGlobalNavigationAction? = nil,
        trailingActions: [PPGlobalNavigationAction] = [],
        showsContextFilament: Bool = true
    ) {
        self.style = style
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.context = context
        self.status = status
        self.leadingAction = leadingAction
        self.trailingActions = Array(trailingActions.prefix(3))
        self.showsContextFilament = showsContextFilament
    }

    /// The eyebrow line actually rendered. `context` is the documented fallback
    /// so hosts that only supply a context string keep their supporting line.
    fileprivate var resolvedEyebrow: String? {
        let candidate = eyebrow ?? context
        guard let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return candidate
    }

    fileprivate var hasTrailingChrome: Bool {
        !trailingActions.isEmpty || status != nil
    }
}

public typealias PPGlobalNavigationActionHandler = (PPGlobalNavigationAction) -> Void

// MARK: - Brand contract

private enum PPNavPalette {
    static var brand: Color { Color(uiColor: .ppPrimary) }
    static var brandPressed: Color { Color(uiColor: .ppPressedAction) }
    static var primaryText: Color { Color(uiColor: .ppTextPrimary) }
    static var secondaryText: Color { Color(uiColor: .ppTextSecondary) }
    static var surface: Color { Color(uiColor: .ppSurface) }
    static var hairline: Color { Color(uiColor: .ppSurfaceBorder) }
    static var canvas: Color { Color(uiColor: .ppBackground) }
    static var live: Color { Color(uiColor: .ppSuccess) }
    static var shadow: Color { Color(uiColor: .ppShadow) }
}

// MARK: - Navigation metrics

private enum PPNavSpec {
    // Host reservations -------------------------------------------------------
    static let expandedHeight: CGFloat = 72
    static let largeTextExpandedHeight: CGFloat = 72
    static let accessibilityExpandedHeight: CGFloat = 72
    static let compactHeight: CGFloat = 48

    // Navigation pearl --------------------------------------------------------
    static let expandedLeadingMargin: CGFloat = 20
    static let compactLeadingMargin: CGFloat = 16
    static let expandedPearl: CGFloat = 44
    static let compactPearl: CGFloat = 40
    static let pearlRadiusRatio: CGFloat = 0.456
    static let pearlGlyphRatio: CGFloat = 0.32
    static let chevronAspect: CGFloat = 0.57

    // Leading control craft ---------------------------------------------------
    /// HIG minimum touch target for the leading control, enforced through hit
    /// testing so the rendered 40pt compact pearl stays reference-true.
    static let pearlMinimumTarget: CGFloat = 44
    /// A chevron's base carries two round caps while its apex is a single
    /// point, so the ink reads off-centre at geometric centre. The ink is
    /// nudged toward the apex by this fraction of the control diameter.
    static let pearlGlyphOpticalShift: CGFloat = 0.022
    /// Directional press affordance: the chevron travels further toward the
    /// leading edge while the finger is down.
    static let pearlPressGlyphTravel: CGFloat = 1.5
    static let pearlPressScale: CGFloat = 0.93
    static let pearlRingWidth: CGFloat = 1.25
    static let pearlPressWellOpacity: Double = 0.14
    static let pearlDisabledOpacity: Double = 0.34
    static let pearlRestElevation: Double = 0.07
    static let pearlHoverElevation: Double = 0.10
    static let pearlPressElevation: Double = 0.02

    // Back capsule ------------------------------------------------------------
    /// A normal 44pt navigation button. Its surface is intentionally simple:
    /// semantic glass, a quiet hairline, and the standard mirrored chevron.
    static let backControlDiameter: CGFloat = 44
    static let backCapsuleGlyphRatio: CGFloat = 0.34
    static let backCapsuleRingWidth: CGFloat = 0.75
    static let backCapsulePressWellOpacity: Double = 0.12
    static let backCapsuleRestElevation: Double = 0.04
    static let backCapsuleHoverElevation: Double = 0.07
    static let backCapsulePressElevation: Double = 0.01
    static let backCapsulePressScale: CGFloat = 0.96
    static let backCapsulePressGlyphTravel: CGFloat = 1.0

    // Command crown -----------------------------------------------------------
    static let expandedControlRowHeight: CGFloat = expandedHeight
    static let accessibilityControlRowHeight: CGFloat = expandedHeight
    static let expandedAction: CGFloat = 44
    static let compactAction: CGFloat = 40
    static let expandedActionGap: CGFloat = 8
    static let compactActionGap: CGFloat = 6
    static let titleControlGap: CGFloat = 10
    static let expandedTrailingMargin: CGFloat = 20
    static let compactTrailingMargin: CGFloat = 16
    static let dividerLeadGap: CGFloat = 10
    static let dividerTrailGap: CGFloat = 10
    static let compactDividerLeadGap: CGFloat = 10
    static let compactDividerTrailGap: CGFloat = 12

    // Status chip -------------------------------------------------------------
    static let statusDot: CGFloat = 7                // 42px
    static let compactStatusDot: CGFloat = 6.9       // 42px
    static let chipLeadingPad: CGFloat = 12          // 72px
    static let chipTrailingPad: CGFloat = 14         // 97px
    static let chipDotGap: CGFloat = 9.5             // 58px

    // Title row ---------------------------------------------------------------
    static let expandedRowTopInset: CGFloat = 2
    static let compactRowTopInset: CGFloat = 6
    static let eyebrowToTitle: CGFloat = 2
    static let titleToSubtitle: CGFloat = 1
    static let filamentBottomInset: CGFloat = 3
    static let filamentThickness: CGFloat = 2
    static let filamentFraction: CGFloat = 0.14
    static let filamentMinimum: CGFloat = 44

    // Emphasized capsule (03_modal_create) ------------------------------------
    static let emphasizedHeight: CGFloat = 40        // 248px
    static let emphasizedWidth: CGFloat = 96
    static let accessibilityEmphasizedWidth: CGFloat = 144
    static let emphasizedPad: CGFloat = 16           // 98px
    static let emphasizedGlyphGap: CGFloat = 8       // 50px

    // Responsive thresholds ---------------------------------------------------
    /// Below this width the full title row cannot hold every control safely.
    static let compactWidthThreshold: CGFloat = 350
    /// Minimum readable width for the compact leading title cluster.
    static let compactTitleMinimum: CGFloat = 96
    /// Minimum leftover width before the status readout is dropped.
    static let statusDropMinimum: CGFloat = 84

    static func hostHeight(
        for mode: PPNavigationDisplayMode,
        hasSubtitle: Bool = false,
        accessibilitySize: Bool = false,
        largeText: Bool = false
    ) -> CGFloat {
        guard mode == .expanded else { return compactHeight }
        if accessibilitySize { return 88 }
        if hasSubtitle {
            return largeText ? 82 : 72
        } else {
            return largeText ? 64 : 56
        }
    }

    static func usesTallExpandedHeight(_ size: DynamicTypeSize) -> Bool {
        size == .xxLarge || size == .xxxLarge
    }

    static func usesTallExpandedHeight(_ category: UIContentSizeCategory) -> Bool {
        category == .extraExtraLarge || category == .extraExtraExtraLarge
    }

    static func actionWidth(
        for action: PPGlobalNavigationAction,
        diameter: CGFloat,
        accessibilitySize: Bool,
        showsEmphasizedTitle: Bool
    ) -> CGFloat {
        guard action.prominence == .emphasized,
              showsEmphasizedTitle,
              action.title?.isEmpty == false else {
            return diameter
        }
        return accessibilitySize ? accessibilityEmphasizedWidth : emphasizedWidth
    }
}

private enum PPNavGeometryID {
    static let pearl = "pp.nav.pearl"
    static let backCapsule = "pp.nav.back-capsule"
    static let crown = "pp.nav.crown"
    static let statusChip = "pp.nav.status"
    static func action(_ id: String) -> String { "pp.nav.action.\(id)" }
}

// MARK: - Typography

private enum PPNavTypography {
    private static func beiruti(
        _ face: String,
        size: CGFloat,
        relativeTo style: Font.TextStyle,
        fallbackWeight: Font.Weight
    ) -> Font {
        if UIFont(name: face, size: size) != nil {
            return .custom(face, size: size, relativeTo: style)
        }
        return .system(size: size, weight: fallbackWeight, design: .rounded)
    }

    /// Expanded large title, compact inline title.
    static func title(_ mode: PPNavigationDisplayMode) -> Font {
        beiruti(
            "Beiruti-Bold",
            size: mode == .expanded ? 24 : 17,
            relativeTo: mode == .expanded ? .title : .headline,
            fallbackWeight: .bold
        )
    }

    /// Reference eyebrow cap height 46px → 10.5pt at cap ratio 0.72.
    static var eyebrow: Font {
        beiruti("Beiruti-Medium", size: 10.5, relativeTo: .caption2, fallbackWeight: .semibold)
    }

    static func subtitle(_ mode: PPNavigationDisplayMode) -> Font {
        beiruti(
            "Beiruti-Regular",
            size: mode == .expanded ? 12 : 11,
            relativeTo: .caption2,
            fallbackWeight: .regular
        )
    }

    /// Reference "Live" cap height 51px → 11.5pt.
    static var statusLabel: Font {
        beiruti("Beiruti-Bold", size: 11.5, relativeTo: .caption2, fallbackWeight: .bold)
    }

    /// Reference "Unified" → 10pt.
    static var statusDetail: Font {
        beiruti("Beiruti-Regular", size: 10, relativeTo: .caption2, fallbackWeight: .regular)
    }

    /// Reference "Save" cap height 55px → 12.5pt, rounded to 13pt.
    static var emphasizedLabel: Font {
        beiruti("Beiruti-Bold", size: 13, relativeTo: .footnote, fallbackWeight: .bold)
    }

    static func monogram(_ diameter: CGFloat) -> Font {
        beiruti("Beiruti-Bold", size: max(9, diameter * 0.42), relativeTo: .caption2, fallbackWeight: .bold)
    }
}

// MARK: - Public navigation bar

public struct PPGlobalNavigationBar: View {
    public let configuration: PPGlobalNavigationConfiguration
    public let collapseProgress: CGFloat
    public let safeAreaTop: CGFloat
    public let displayModeOverride: PPNavigationDisplayMode?
    public let layoutDirectionOverride: LayoutDirection?
    public let onAction: PPGlobalNavigationActionHandler
    public let onDisplayModeChange: ((PPNavigationDisplayMode) -> Void)?

    @Environment(\.layoutDirection) private var environmentLayoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var glassNamespace
    @State private var latchedMode: PPNavigationDisplayMode?

    public init(
        configuration: PPGlobalNavigationConfiguration,
        collapseProgress: CGFloat = 0,
        safeAreaTop: CGFloat = 0,
        displayMode: PPNavigationDisplayMode? = nil,
        layoutDirection: LayoutDirection? = nil,
        onAction: @escaping PPGlobalNavigationActionHandler,
        onDisplayModeChange: ((PPNavigationDisplayMode) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.collapseProgress = collapseProgress.ppClamped()
        self.safeAreaTop = max(0, safeAreaTop)
        self.displayModeOverride = displayMode
        self.layoutDirectionOverride = layoutDirection
        self.onAction = onAction
        self.onDisplayModeChange = onDisplayModeChange
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let mode = resolvedMode(width: width)
            let resolvedLayoutDirection = layoutDirectionOverride ?? environmentLayoutDirection

            ZStack(alignment: .top) {
                // The bar surface is intentionally clear: the host's page
                // background shows through and only the floating controls
                // (pearl, crown, status well) carry material.
                Color.clear

                PPNavStage(
                    configuration: configuration,
                    mode: mode,
                    width: width,
                    safeAreaTop: safeAreaTop,
                    namespace: glassNamespace,
                    onAction: onAction
                )
            }
            .environment(\.layoutDirection, resolvedLayoutDirection)
            .frame(width: width, alignment: .top)
            .animation(reduceMotion ? nil : motion, value: mode)
            .onChange(of: mode, perform: handleModeChange)
            .onAppear {
                latchedMode = mode
                onDisplayModeChange?(mode)
            }
        }
        .frame(height: intrinsicHeight, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.accessibility5)
        .accessibilityElement(children: .contain)
    }

    private var motion: Animation? {
        guard !reduceMotion else { return nil }
        guard !UIAccessibility.isVoiceOverRunning, !UIAccessibility.isSwitchControlRunning else { return nil }
        return .timingCurve(0.2, 0, 0, 1, duration: 0.18)
    }

    private func handleModeChange(_ newValue: PPNavigationDisplayMode) {
        latchedMode = newValue
        onDisplayModeChange?(newValue)
    }

    /// Selection order: explicit override → accessibility text → scroll
    /// threshold (with hysteresis so the morph cannot flap) → available width.
    private func resolvedMode(width: CGFloat) -> PPNavigationDisplayMode {
        if let displayModeOverride { return displayModeOverride }
        if dynamicTypeSize.isAccessibilitySize { return .expanded }
        if width > 0, width < PPNavSpec.compactWidthThreshold { return .compact }

        let entering: CGFloat = 0.5
        let leaving: CGFloat = 0.34
        switch latchedMode {
        case .compact:
            return collapseProgress <= leaving ? .expanded : .compact
        default:
            return collapseProgress >= entering ? .compact : .expanded
        }
    }

    private var intrinsicHeight: CGFloat {
        let mode = latchedMode
            ?? displayModeOverride
            ?? .expanded
        let hasSubtitle = configuration.subtitle?.isEmpty == false
        return PPNavSpec.hostHeight(
            for: mode,
            hasSubtitle: hasSubtitle,
            accessibilitySize: dynamicTypeSize.isAccessibilitySize,
            largeText: PPNavSpec.usesTallExpandedHeight(dynamicTypeSize)
        ) + safeAreaTop
    }
}

// MARK: - Stage

private struct PPNavStage: View {
    let configuration: PPGlobalNavigationConfiguration
    let mode: PPNavigationDisplayMode
    let width: CGFloat
    let safeAreaTop: CGFloat
    let namespace: Namespace.ID
    let onAction: PPGlobalNavigationActionHandler

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let plan = PPNavPlan(
            configuration: configuration,
            mode: mode,
            width: width,
            accessibilitySize: dynamicTypeSize.isAccessibilitySize
        )

        VStack(alignment: .leading, spacing: 0) {
            controlRow(plan: plan)

            if configuration.showsContextFilament {
                PPNavContextFilament(width: plan.filamentWidth)
                    .padding(.horizontal, plan.leadingMargin)
                    .padding(.top, 12)
            }
        }
        .padding(.top, safeAreaTop)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : layoutMotion, value: configuration.leadingAction?.id)
        .animation(reduceMotion ? nil : layoutMotion, value: configuration.trailingActions.map(\.id))
        .animation(reduceMotion ? nil : layoutMotion, value: configuration.status)
    }

    // MARK: Control row

    @ViewBuilder
    private func controlRow(plan: PPNavPlan) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if configuration.leadingAction != nil {
                leadingCluster(plan: plan)
                    .padding(.trailing, PPNavSpec.titleControlGap)
            }

            titleCluster(plan: plan)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            if configuration.hasTrailingChrome {
                trailingCluster(plan: plan)
                    .padding(.leading, PPNavSpec.titleControlGap)
                    .transition(reduceMotion ? .identity : trailingTransition)
            }
        }
        .padding(.leading, plan.leadingMargin)
        .padding(.trailing, plan.trailingMargin)
        .padding(.top, plan.rowTopInset)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func leadingCluster(plan: PPNavPlan) -> some View {
        pearl(plan: plan)
    }

    @ViewBuilder
    private func pearl(plan: PPNavPlan) -> some View {
        if let leading = configuration.leadingAction {
            PPNavPearl(
                action: leading,
                diameter: plan.pearlDiameter,
                namespace: namespace,
                onAction: onAction
            )
            .id(leading.id)
            .transition(reduceMotion ? .identity : leadingTransition)
        }
    }

    @ViewBuilder
    private func trailingCluster(plan: PPNavPlan) -> some View {
        PPNavCommandCrown(
            configuration: configuration,
            plan: plan,
            onAction: onAction
        )
    }

    @ViewBuilder
    private func titleCluster(plan: PPNavPlan) -> some View {
        PPNavTitleCluster(
            configuration: configuration,
            mode: mode,
            showsSubtitle: plan.showsSubtitle
        )
    }

    private var layoutMotion: Animation? {
        guard !reduceMotion else { return nil }
        guard !UIAccessibility.isVoiceOverRunning, !UIAccessibility.isSwitchControlRunning else { return nil }
        return .timingCurve(0.2, 0, 0, 1, duration: 0.18)
    }

    private var leadingTransition: AnyTransition {
        usesStaticTransition
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private var trailingTransition: AnyTransition {
        usesStaticTransition
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
    }

    private var usesStaticTransition: Bool {
        reduceMotion || UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }
}

// MARK: - Responsive plan

/// Resolves every width-dependent decision once, so the compact and expanded
/// compositions never disagree and nothing collides on a 375pt phone.
private struct PPNavPlan {
    let mode: PPNavigationDisplayMode
    let width: CGFloat

    let leadingMargin: CGFloat
    let trailingMargin: CGFloat
    let controlRowHeight: CGFloat
    let pearlDiameter: CGFloat
    let actionDiameter: CGFloat
    let actionGap: CGFloat
    let dividerLeadGap: CGFloat
    let dividerTrailGap: CGFloat

    let showsStatus: Bool
    let showsStatusDetail: Bool
    let showsSubtitle: Bool
    let showsEmphasizedActionTitles: Bool
    let filamentWidth: CGFloat
    let rowTopInset: CGFloat

    init(
        configuration: PPGlobalNavigationConfiguration,
        mode: PPNavigationDisplayMode,
        width: CGFloat,
        accessibilitySize: Bool
    ) {
        self.mode = mode
        self.width = width

        let compact = mode == .compact
        let resolvedLeadingMargin = compact ? PPNavSpec.compactLeadingMargin : PPNavSpec.expandedLeadingMargin
        let resolvedTrailingMargin = compact ? PPNavSpec.compactTrailingMargin : PPNavSpec.expandedTrailingMargin
        let resolvedPearlDiameter = compact ? PPNavSpec.compactPearl : PPNavSpec.expandedPearl
        let resolvedActionDiameter: CGFloat = accessibilitySize && !compact
            ? 56
            : (compact ? PPNavSpec.compactAction : PPNavSpec.expandedAction)
        let resolvedActionGap = compact ? PPNavSpec.compactActionGap : PPNavSpec.expandedActionGap
        let resolvedDividerLeadGap = compact ? PPNavSpec.compactDividerLeadGap : PPNavSpec.dividerLeadGap
        let resolvedDividerTrailGap = compact ? PPNavSpec.compactDividerTrailGap : PPNavSpec.dividerTrailGap

        let resolvedControlRowHeight = compact
            ? PPNavSpec.compactHeight
            : (accessibilitySize
                ? PPNavSpec.accessibilityControlRowHeight
                : PPNavSpec.expandedControlRowHeight)

        let leadingWidth: CGFloat = resolvedLeadingMargin
            + (configuration.leadingAction != nil
                ? resolvedPearlDiameter + PPNavSpec.titleControlGap
                : 0)
        let actions = configuration.trailingActions
        let actionGapWidth = max(0, CGFloat(actions.count - 1)) * resolvedActionGap
        let requestedActionWidth = actions.reduce(CGFloat.zero) { partial, action in
            partial + PPNavSpec.actionWidth(
                for: action,
                diameter: resolvedActionDiameter,
                accessibilitySize: accessibilitySize,
                showsEmphasizedTitle: true
            )
        } + actionGapWidth
        let actionBudget = width > 0
            ? max(
                0,
                width
                    - leadingWidth
                    - resolvedTrailingMargin
                    - PPNavSpec.titleControlGap
                    - PPNavSpec.compactTitleMinimum
            )
            : .greatestFiniteMagnitude
        let showsEmphasized = requestedActionWidth <= actionBudget
        let resolvedShowsEmphasizedActionTitles = showsEmphasized
        let actionsWidth = actions.reduce(CGFloat.zero) { partial, action in
            partial + PPNavSpec.actionWidth(
                for: action,
                diameter: resolvedActionDiameter,
                accessibilitySize: accessibilitySize,
                showsEmphasizedTitle: showsEmphasized
            )
        } + actionGapWidth

        // 01/02 reference status readout: dot + label (+ detail when expanded).
        let statusWidth: CGFloat = accessibilitySize ? 120 : (compact ? 61 : 79)
        let dividerWidth = resolvedDividerLeadGap + resolvedDividerTrailGap + 1

        let trailingGap = configuration.hasTrailingChrome ? PPNavSpec.titleControlGap : 0
        let fixedTrailing = actionsWidth + trailingGap + resolvedTrailingMargin
        let centreBudget = width > 0 ? width - leadingWidth - fixedTrailing : .greatestFiniteMagnitude

        let resolvedShowsStatus: Bool
        if configuration.status == nil {
            resolvedShowsStatus = false
        } else if compact {
            resolvedShowsStatus = centreBudget - statusWidth - dividerWidth >= PPNavSpec.compactTitleMinimum
        } else {
            resolvedShowsStatus = centreBudget - statusWidth - dividerWidth >= PPNavSpec.statusDropMinimum
        }

        let resolvedShowsStatusDetail = !compact && !accessibilitySize && resolvedShowsStatus

        let statusCost = resolvedShowsStatus ? statusWidth + dividerWidth : 0
        let remaining = centreBudget - statusCost

        // At accessibility sizes preserve the requested title scale and remove
        // the supporting visual line; the combined accessibility label still
        // exposes the complete eyebrow, title, and subtitle.
        let resolvedShowsSubtitle = !accessibilitySize && (compact ? remaining >= 128 : true)

        let filamentTrack = max(0, width - 2 * PPNavSpec.expandedLeadingMargin)
        let resolvedFilamentWidth = width > 0
            ? max(PPNavSpec.filamentMinimum, filamentTrack * PPNavSpec.filamentFraction)
            : PPNavSpec.filamentMinimum

        leadingMargin = resolvedLeadingMargin
        trailingMargin = resolvedTrailingMargin
        controlRowHeight = resolvedControlRowHeight
        pearlDiameter = resolvedPearlDiameter
        actionDiameter = resolvedActionDiameter
        actionGap = resolvedActionGap
        dividerLeadGap = resolvedDividerLeadGap
        dividerTrailGap = resolvedDividerTrailGap

        showsStatus = resolvedShowsStatus
        showsStatusDetail = resolvedShowsStatusDetail
        showsSubtitle = resolvedShowsSubtitle
        showsEmphasizedActionTitles = resolvedShowsEmphasizedActionTitles
        filamentWidth = resolvedFilamentWidth
        rowTopInset = compact ? PPNavSpec.compactRowTopInset : PPNavSpec.expandedRowTopInset
    }
}

// MARK: - Title cluster

private struct PPNavTitleCluster: View {
    let configuration: PPGlobalNavigationConfiguration
    let mode: PPNavigationDisplayMode
    let showsSubtitle: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            if mode == .expanded,
               !dynamicTypeSize.isAccessibilitySize,
               let eyebrow = configuration.resolvedEyebrow {
                Text(eyebrow.uppercased())
                    .font(PPNavTypography.eyebrow)
                    .tracking(0.9)
                    .foregroundStyle(PPNavPalette.brand)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.bottom, PPNavSpec.eyebrowToTitle)
                    .accessibilityHidden(true)
            }

            Text(configuration.title)
                .font(PPNavTypography.title(typographyMode))
                .foregroundStyle(PPNavPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.78 : (mode == .expanded ? 0.82 : 0.88))
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(textAlignment)
                .accessibilityAddTraits(.isHeader)

            if showsSubtitle, let subtitle = configuration.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(PPNavTypography.subtitle(typographyMode))
                    .foregroundStyle(PPNavPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.76 : 0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PPNavSpec.titleToSubtitle)
                    .multilineTextAlignment(textAlignment)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilitySortPriority(3)
    }

    private var alignment: HorizontalAlignment { .leading }
    private var textAlignment: TextAlignment { .leading }
    private var typographyMode: PPNavigationDisplayMode {
        dynamicTypeSize.isAccessibilitySize ? .compact : mode
    }

    private var accessibilityLabel: Text {
        var parts: [String] = []
        if let eyebrow = configuration.resolvedEyebrow { parts.append(eyebrow) }
        parts.append(configuration.title)
        if let subtitle = configuration.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        return Text(parts.joined(separator: ", "))
    }
}

// MARK: - Navigation pearl

/// Leading Back / Close control.
///
/// This is the most-touched control in the entire product, so it is specified
/// to a higher standard than the rest of the bar:
///
///  • **One shape language.** Both display modes use the same semantic material
///    and optical treatment, changing only from 44pt to a 40pt compact glyph.
///  • **Optical centring.** A chevron's base carries two round caps while its
///    apex is a single point, so geometric centre reads off-centre. The ink is
///    nudged toward the apex (`pearlGlyphOpticalShift`). Symmetric glyphs such
///    as Close are left untouched.
///  • **Directional press.** Pressing does not grey the control out. The
///    surface sinks, a brand well fills it, the ink turns brand and travels
///    toward the leading edge — the direction the tap will take you.
///  • **Haptic on press-down**, not on action, so the control feels mechanical
///    rather than delayed. Haptics are not motion, so Reduce Motion does not
///    silence them; it only removes travel and scale.
///  • **44pt target in both modes**, enforced through hit testing so the
///    reference 40pt compact pearl stays reference-true.
///  • **Full mirroring.** Ink direction, optical shift, press travel and the
///    specular light source all derive from `layoutDirection`.
private struct PPNavPearl: View {
    let action: PPGlobalNavigationAction
    let diameter: CGFloat
    let namespace: Namespace.ID
    let onAction: PPGlobalNavigationActionHandler

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Button {
            onAction(action)
        } label: {
            PPNavGlyph(kind: action.kind, layoutDirection: layoutDirection)
                .frame(width: glyphSide, height: glyphSide)
        }
        .buttonStyle(
            PPNavPearlStyle(
                diameter: diameter,
                isDirectional: action.kind == .back,
                isBack: action.kind == .back,
                namespace: namespace
            )
        )
        .disabled(!action.isEnabled)
        .accessibilityLabel(Text(action.accessibilityLabel))
        .ppAccessibilityHint(action.accessibilityHint)
        .accessibilityShowsLargeContentViewer {
            Text(action.accessibilityLabel)
        }
        .accessibilityIdentifier("pp.nav.leading.\(action.id)")
        .accessibilitySortPriority(4)
    }

    private var glyphSide: CGFloat {
        action.kind == .back
            ? diameter * PPNavSpec.backCapsuleGlyphRatio
            : diameter * PPNavSpec.pearlGlyphRatio
    }
}

/// A back action uses the Return Beacon rather than the generic pearl: its
/// logical-leading rail and hooked mark create a single, unambiguous promise
/// that this control returns to the previous operational context.
private struct PPNavPearlStyle: ButtonStyle {
    let diameter: CGFloat
    let isDirectional: Bool
    let isBack: Bool
    let namespace: Namespace.ID

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if isBack {
            PPNavBackCapsuleSurface(
                diameter: diameter,
                namespace: namespace,
                isPressed: configuration.isPressed,
                label: configuration.label
            )
        } else {
            PPNavPearlSurface(
                diameter: diameter,
                isDirectional: isDirectional,
                namespace: namespace,
                isPressed: configuration.isPressed,
                label: configuration.label
            )
        }
    }
}

private struct PPNavPearlSurface: View {
    let diameter: CGFloat
    let isDirectional: Bool
    let namespace: Namespace.ID
    let isPressed: Bool
    let label: ButtonStyleConfiguration.Label

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isHovering = false

    var body: some View {
        let pressed = isPressed && isEnabled
        let shape = PPNavSquircle(cornerRadius: diameter * PPNavSpec.pearlRadiusRatio)

        ZStack {
            Color.clear
                .frame(width: diameter, height: diameter)
                .ppGlass(
                    shape: shape,
                    interactive: true,
                    tint: nil,
                    elevation: elevation(pressed: pressed),
                    namespace: namespace,
                    id: PPNavGeometryID.pearl
                )

            shape
                .fill(PPNavPalette.brand.opacity(pressed ? PPNavSpec.pearlPressWellOpacity : 0))

            shape
                .strokeBorder(ring(pressed: pressed), lineWidth: PPNavSpec.pearlRingWidth)

            label
                .foregroundStyle(pressed ? PPNavPalette.brandPressed : PPNavPalette.primaryText)
                .offset(x: inkOffset(pressed: pressed))
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(pressed && !reduceMotion ? PPNavSpec.pearlPressScale : 1, anchor: .center)
        .opacity(isEnabled ? 1 : PPNavSpec.pearlDisabledOpacity)
        .contentShape(PPNavHitArea(minimum: PPNavSpec.pearlMinimumTarget))
        .animation(pressMotion, value: pressed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: pressed, perform: handlePressedChange)
    }

    /// Reduce Motion keeps the state change — it only drops travel and scale,
    /// so the control still confirms the touch.
    private var pressMotion: Animation? {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.26, dampingFraction: 0.78, blendDuration: 0.08)
    }

    private func handlePressedChange(_ isDown: Bool) {
        if isDown { PPNavHaptics.leadingEngage() }
    }

    private func elevation(pressed: Bool) -> Double {
        if pressed { return PPNavSpec.pearlPressElevation }
        if isHovering { return PPNavSpec.pearlHoverElevation }
        return PPNavSpec.pearlRestElevation
    }

    /// Optical shift plus press travel, mirrored. In LTR the back apex points
    /// leading (negative x); in RTL it points trailing (positive x).
    private func inkOffset(pressed: Bool) -> CGFloat {
        guard isDirectional else { return 0 }
        let optical = diameter * PPNavSpec.pearlGlyphOpticalShift
        let travel = (pressed && !reduceMotion) ? PPNavSpec.pearlPressGlyphTravel : 0
        let magnitude = optical + travel
        return layoutDirection == .rightToLeft ? magnitude : -magnitude
    }

    /// Specular ring. The light source always enters from the top outer edge,
    /// so the highlight mirrors with the layout instead of being pinned to a
    /// fixed corner.
    private func ring(pressed: Bool) -> LinearGradient {
        let lift = pressed ? 0.18 : (isHovering ? 0.10 : 0)

        return LinearGradient(
            colors: [
                PPNavPalette.hairline.opacity(min(1, 0.85 + lift)),
                PPNavPalette.hairline.opacity(min(1, 0.32 + lift)),
            ],
            startPoint: layoutDirection == .rightToLeft ? .topTrailing : .topLeading,
            endPoint: layoutDirection == .rightToLeft ? .bottomLeading : .bottomTrailing
        )
    }
}

/// Normal back treatment: a fixed 44pt capsule that uses the same semantic
/// glass configuration as the rest of the global navigation.
private struct PPNavBackCapsuleSurface: View {
    let diameter: CGFloat
    let namespace: Namespace.ID
    let isPressed: Bool
    let label: ButtonStyleConfiguration.Label

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isHovering = false

    var body: some View {
        let pressed = isPressed && isEnabled
        let shape = Capsule()

        ZStack {
            Color.clear
                .frame(width: diameter, height: diameter)
                .ppGlass(
                    shape: shape,
                    interactive: true,
                    tint: nil,
                    elevation: elevation(pressed: pressed),
                    namespace: namespace,
                    id: PPNavGeometryID.backCapsule
                )

            shape
                .fill(PPNavPalette.brand.opacity(pressed ? PPNavSpec.backCapsulePressWellOpacity : 0))

            shape
                .strokeBorder(ring(pressed: pressed), lineWidth: PPNavSpec.backCapsuleRingWidth)

            label
                .foregroundStyle(pressed ? PPNavPalette.brandPressed : PPNavPalette.primaryText)
                .offset(x: glyphOffset(pressed: pressed))
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(pressed && !reduceMotion ? PPNavSpec.backCapsulePressScale : 1, anchor: .center)
        .opacity(isEnabled ? 1 : PPNavSpec.pearlDisabledOpacity)
        .contentShape(PPNavHitArea(minimum: PPNavSpec.backControlDiameter))
        .animation(pressMotion, value: pressed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: pressed, perform: handlePressedChange)
    }

    private var leadingSign: CGFloat {
        layoutDirection == .rightToLeft ? 1 : -1
    }

    private func handlePressedChange(_ isDown: Bool) {
        if isDown { PPNavHaptics.leadingEngage() }
    }

    private var pressMotion: Animation? {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.24, dampingFraction: 0.8, blendDuration: 0.08)
    }

    private func elevation(pressed: Bool) -> Double {
        if pressed { return PPNavSpec.backCapsulePressElevation }
        if isHovering { return PPNavSpec.backCapsuleHoverElevation }
        return PPNavSpec.backCapsuleRestElevation
    }

    private func glyphOffset(pressed: Bool) -> CGFloat {
        let travel = pressed && !reduceMotion ? PPNavSpec.backCapsulePressGlyphTravel : 0
        return leadingSign * travel
    }

    private func ring(pressed: Bool) -> LinearGradient {
        let lift = pressed ? 0.12 : (isHovering ? 0.06 : 0)
        return LinearGradient(
            colors: [
                PPNavPalette.hairline.opacity(min(1, 0.72 + lift)),
                PPNavPalette.brand.opacity(min(1, 0.20 + lift)),
            ],
            startPoint: layoutDirection == .rightToLeft ? .topTrailing : .topLeading,
            endPoint: layoutDirection == .rightToLeft ? .bottomLeading : .bottomTrailing
        )
    }
}

// MARK: - Command crown

/// Logical-trailing status and commands. The rail itself has no decorative
/// surface; only controls receive interactive material.
private struct PPNavCommandCrown: View {
    let configuration: PPGlobalNavigationConfiguration
    let plan: PPNavPlan
    let onAction: PPGlobalNavigationActionHandler

    var body: some View {
        PPNavGlassContainer(spacing: plan.actionGap) {
            HStack(spacing: 0) {
                if plan.showsStatus, let status = configuration.status {
                    PPNavStatusWell(
                        status: status,
                        height: plan.actionDiameter,
                        showsDetail: plan.showsStatusDetail
                    )

                    Color.clear.frame(width: plan.dividerLeadGap, height: 1)
                    PPNavSeam(height: plan.actionDiameter * 0.95)
                    Color.clear.frame(width: plan.dividerTrailGap, height: 1)
                }

                if !configuration.trailingActions.isEmpty {
                    PPGlobalNavigationTrailingActionContainer(
                        actions: configuration.trailingActions,
                        mode: plan.mode,
                        showsEmphasizedTitles: plan.showsEmphasizedActionTitles,
                        onAction: onAction
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(1)
    }
}

/// Reusable logical-trailing action surface for the shared global navigation.
///
/// Screens pass their semantic icon/action pairs through
/// `PPGlobalNavigationConfiguration.trailingActions`; this container supplies
/// the common material, 44pt hit area, RTL ordering, and accessibility contract.
public struct PPGlobalNavigationTrailingActionContainer: View {
    private let actions: [PPGlobalNavigationAction]
    private let mode: PPNavigationDisplayMode
    private let showsEmphasizedTitles: Bool
    private let identifier: String
    private let onAction: PPGlobalNavigationActionHandler
    @Namespace private var glassNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        actions: [PPGlobalNavigationAction],
        mode: PPNavigationDisplayMode,
        showsEmphasizedTitles: Bool = true,
        id: String = "pp.nav.trailing-actions",
        onAction: @escaping PPGlobalNavigationActionHandler
    ) {
        self.actions = Array(actions.prefix(3))
        self.mode = mode
        self.showsEmphasizedTitles = showsEmphasizedTitles
        self.identifier = id
        self.onAction = onAction
    }

    public var body: some View {
        Group {
            if !actions.isEmpty {
                HStack(spacing: actionGap) {
                    ForEach(actions) { action in
                        PPNavActionButton(
                            action: action,
                            diameter: actionDiameter,
                            showsEmphasizedTitle: showsEmphasizedTitles,
                            surfacedIndividually: true,
                            namespace: glassNamespace,
                            onAction: onAction
                        )
                        .transition(reduceMotion ? .identity : actionTransition)
                    }
                }
                .animation(reduceMotion ? nil : actionMotion, value: actions.map(\.id))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .accessibilitySortPriority(1)
    }

    private var isExpanded: Bool { mode == .expanded }
    private var actionDiameter: CGFloat {
        if isExpanded && dynamicTypeSize.isAccessibilitySize { return 56 }
        return isExpanded ? PPNavSpec.expandedAction : PPNavSpec.compactAction
    }
    private var actionGap: CGFloat {
        isExpanded ? PPNavSpec.expandedActionGap : PPNavSpec.compactActionGap
    }

    private var actionMotion: Animation? {
        guard !reduceMotion else { return nil }
        guard !UIAccessibility.isVoiceOverRunning, !UIAccessibility.isSwitchControlRunning else { return nil }
        return .timingCurve(0.2, 0, 0, 1, duration: 0.18)
    }

    private var actionTransition: AnyTransition {
        usesStaticTransition
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
    }

    private var usesStaticTransition: Bool {
        reduceMotion || UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }
}

/// Inline operational status. Status remains text-and-shape legible without
/// introducing another pill into the command rail.
private struct PPNavStatusWell: View {
    let status: PPGlobalNavigationStatus
    let height: CGFloat
    let showsDetail: Bool

    var body: some View {
        HStack(spacing: PPNavSpec.chipDotGap) {
            if status.isLive {
                Circle()
                    .fill(PPNavPalette.live)
                    .frame(width: PPNavSpec.statusDot, height: PPNavSpec.statusDot)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(status.label)
                    .font(PPNavTypography.statusLabel)
                    .foregroundStyle(PPNavPalette.primaryText)
                    .lineLimit(1)

                if showsDetail, let detail = status.detail, !detail.isEmpty {
                    Text(detail)
                        .font(PPNavTypography.statusDetail)
                        .foregroundStyle(PPNavPalette.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, PPNavSpec.chipLeadingPad)
        .padding(.trailing, PPNavSpec.chipTrailingPad)
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text([status.label, status.detail]
                .compactMap { $0 }
                .joined(separator: ", "))
        )
        .accessibilitySortPriority(2)
    }
}

/// Vertical seam between the status readout and the action group.
private struct PPNavSeam: View {
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(PPNavPalette.primaryText.opacity(0.08))
            .frame(width: 1, height: height)
            .accessibilityHidden(true)
    }
}

// MARK: - Actions

private struct PPNavActionButton: View {
    let action: PPGlobalNavigationAction
    let diameter: CGFloat
    let showsEmphasizedTitle: Bool
    let surfacedIndividually: Bool
    let namespace: Namespace.ID
    let onAction: PPGlobalNavigationActionHandler

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            PPNavHaptics.select(reduceMotion: reduceMotion)
            onAction(action)
        } label: {
            content
                .contentShape(PPNavHitArea(minimum: 44))
        }
        .buttonStyle(PPNavPressStyle())
        .disabled(!action.isEnabled)
        .accessibilityLabel(Text(action.accessibilityLabel))
        .ppAccessibilityHint(action.accessibilityHint)
        .accessibilityValue(badgeAccessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch action.prominence {
        case .emphasized:
            emphasized
        case .standard, .quiet:
            standard
        }
    }

    // 03_modal_create: crimson capsule, checkmark + label, 248px tall.
    @ViewBuilder
    private var emphasized: some View {
        HStack(spacing: PPNavSpec.emphasizedGlyphGap) {
            PPNavGlyph(kind: action.kind, layoutDirection: layoutDirection)
                .frame(width: glyphSide, height: glyphSide)

            if let title = renderedTitle {
                Text(title)
                    .font(PPNavTypography.emphasizedLabel)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, renderedTitle == nil ? 0 : PPNavSpec.emphasizedPad)
        .frame(
            minWidth: controlWidth,
            maxWidth: controlWidth,
            minHeight: emphasizedControlHeight,
            maxHeight: emphasizedControlHeight
        )
        .ppGlass(
            shape: PPNavSquircle(cornerRadius: emphasizedControlHeight / 2),
            interactive: true,
            tint: PPNavPalette.brand,
            elevation: 0.09,
            namespace: namespace,
            id: PPNavGeometryID.action(action.id)
        )
    }

    private var emphasizedControlHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? max(diameter, 56)
            : min(diameter, PPNavSpec.emphasizedHeight)
    }

    private var controlWidth: CGFloat {
        PPNavSpec.actionWidth(
            for: action,
            diameter: diameter,
            accessibilitySize: dynamicTypeSize.isAccessibilitySize,
            showsEmphasizedTitle: renderedTitle != nil
        )
    }

    private var renderedTitle: String? {
        guard showsEmphasizedTitle,
              let title = action.title,
              !title.isEmpty else {
            return nil
        }
        return title
    }

    @ViewBuilder
    private var standard: some View {
        glyphStack
            .frame(width: diameter, height: diameter)
            .ppGlass(
                shape: PPNavSquircle(cornerRadius: diameter / 2),
                interactive: true,
                tint: nil,
                elevation: 0.06,
                namespace: namespace,
                id: PPNavGeometryID.action(action.id),
                enabled: surfacedIndividually
            )
    }

    @ViewBuilder
    private var glyphStack: some View {
        ZStack(alignment: .topTrailing) {
            if action.kind == .profile {
                PPNavMonogram(
                    diameter: diameter * (surfacedIndividually ? 0.69 : 0.67),
                    monogram: action.monogram
                )
            } else {
                PPNavGlyph(kind: action.kind, layoutDirection: layoutDirection)
                    .frame(width: glyphSide, height: glyphSide)
                    .foregroundStyle(foreground)
            }

            badge
        }
        .frame(width: diameter, height: diameter)
    }

    /// Reference bell ink 121px in a 267px button → 0.45 of the button.
    private var glyphSide: CGFloat { diameter * 0.45 }

    @ViewBuilder
    private var badge: some View {
        if let badge = action.badge {
            if badge.isEmpty {
                Circle()
                    .fill(PPNavPalette.brand)
                    .frame(width: diameter * 0.157, height: diameter * 0.157)
                    .offset(x: -diameter * 0.09, y: diameter * 0.13)
                    .accessibilityHidden(true)
            } else {
                Text(badge)
                    .font(.system(size: max(8, diameter * 0.2), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: diameter * 0.34, minHeight: diameter * 0.34)
                    .background(PPNavPalette.brandPressed, in: Capsule())
                    .offset(x: diameter * 0.02, y: -diameter * 0.02)
                    .accessibilityHidden(true)
            }
        }
    }

    private var foreground: Color {
        switch action.prominence {
        case .emphasized: return .white
        case .standard: return PPNavPalette.primaryText
        case .quiet: return PPNavPalette.secondaryText
        }
    }

    private var badgeAccessibilityValue: Text {
        guard let badge = action.badge, !badge.isEmpty else { return Text("") }
        return Text(badge)
    }
}

/// Crimson profile disc, 185px inside a 267px button in the reference crown.
private struct PPNavMonogram: View {
    let diameter: CGFloat
    let monogram: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [PPNavPalette.brand, PPNavPalette.brandPressed],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let monogram, !monogram.isEmpty {
                Text(monogram.uppercased())
                    .font(PPNavTypography.monogram(diameter))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 2)
            } else {
                PPNavProfileGlyph()
                    .stroke(style: StrokeStyle(lineWidth: max(1.2, diameter * 0.075), lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.white)
                    .frame(width: diameter * 0.56, height: diameter * 0.56)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - Context filament

/// Title-anchored context marker. It identifies the active route lane and never
/// represents progress.
private struct PPNavContextFilament: View {
    let width: CGFloat
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ZStack(alignment: layoutDirection == .rightToLeft ? .trailing : .leading) {
            Capsule()
                .fill(PPNavPalette.primaryText.opacity(0.06))
                .frame(height: PPNavSpec.filamentThickness)
                .frame(maxWidth: .infinity)

            Capsule()
                .fill(PPNavPalette.brand)
                .frame(width: width, height: PPNavSpec.filamentThickness)
        }
        .frame(height: PPNavSpec.filamentThickness)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: - Shapes

/// Continuous-corner squircle. `PPNavSpec.pearlRadiusRatio` reproduces the
/// measured reference outline of the pearl and the standalone action surfaces.
private struct PPNavSquircle: InsettableShape {
    let cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(max(0, cornerRadius - insetAmount), min(inset.width, inset.height) / 2)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: inset)
    }

    func inset(by amount: CGFloat) -> PPNavSquircle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Expands a control's hit region to the 44pt HIG minimum without changing its
/// layout size. The compact crown is 33.5pt tall in the reference, so the touch
/// target has to grow through hit testing rather than through layout.
private struct PPNavHitArea: Shape {
    let minimum: CGFloat

    func path(in rect: CGRect) -> Path {
        let width = max(rect.width, minimum)
        let height = max(rect.height, minimum)
        return Path(
            CGRect(
                x: rect.midX - width / 2,
                y: rect.midY - height / 2,
                width: width,
                height: height
            )
        )
    }
}

// MARK: - Glyph layer

private struct PPNavGlyph: View {
    let kind: PPGlobalNavigationActionKind
    let layoutDirection: LayoutDirection

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let stroke = StrokeStyle(
                lineWidth: max(1.4, side * 0.145),
                lineCap: .round,
                lineJoin: .round
            )

            switch kind {
            case .back:
                PPNavChevronGlyph(pointsTrailing: layoutDirection == .rightToLeft)
                    .stroke(style: stroke)
            case .close:
                PPNavCloseGlyph().stroke(style: stroke)
            case .confirm:
                PPNavCheckGlyph().stroke(style: stroke)
            case .refresh:
                PPNavRefreshGlyph().stroke(style: stroke)
            case .more:
                PPNavMoreGlyph()
            case .profile:
                PPNavProfileGlyph().stroke(style: stroke)
            case .capabilityLens:
                PPNavCapabilityLensGlyph(lineWidth: max(1.4, side * 0.115))
            case .command:
                PPNavCommandGlyph().stroke(style: StrokeStyle(lineWidth: max(1.2, side * 0.1), lineCap: .round, lineJoin: .round))
            case .notifications:
                PPNavBellGlyph(lineWidth: max(1.4, side * 0.13))
            case .custom(let symbol):
                Image(systemName: symbol)
                    .font(.system(size: side * 0.92, weight: .semibold))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Reference chevron: ink 56 x 98px → width 0.57 of height, round caps.
private struct PPNavChevronGlyph: Shape {
    let pointsTrailing: Bool

    func path(in rect: CGRect) -> Path {
        let inkHeight = rect.height
        let inkWidth = inkHeight * PPNavSpec.chevronAspect
        let midY = rect.midY
        let x0 = rect.midX - inkWidth / 2
        let x1 = rect.midX + inkWidth / 2
        let apexX = pointsTrailing ? x1 : x0
        let baseX = pointsTrailing ? x0 : x1

        var path = Path()
        path.move(to: CGPoint(x: baseX, y: midY - inkHeight / 2))
        path.addLine(to: CGPoint(x: apexX, y: midY))
        path.addLine(to: CGPoint(x: baseX, y: midY + inkHeight / 2))
        return path
    }
}

private struct PPNavCloseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.14)
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.move(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        return path
    }
}

/// Reference "Save" checkmark: 85px wide, shallow left arm, round joins.
private struct PPNavCheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY + rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.18))
        return path
    }
}

private struct PPNavRefreshGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) * 0.42
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(
            center: centre,
            radius: r,
            startAngle: .degrees(-64),
            endAngle: .degrees(214),
            clockwise: false
        )
        let tail = CGPoint(x: centre.x - r, y: centre.y)
        path.move(to: CGPoint(x: tail.x, y: tail.y - r * 0.05))
        path.addLine(to: CGPoint(x: tail.x, y: tail.y - r * 0.62))
        path.addLine(to: CGPoint(x: tail.x + r * 0.56, y: tail.y - r * 0.42))
        return path
    }
}

private struct PPNavMoreGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // Reference: three 28px dots on a 44px pitch inside a 260px button.
            let dot = side * 0.215
            HStack(spacing: dot * 0.58) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().frame(width: dot, height: dot)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct PPNavProfileGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + w * 0.32, y: rect.minY + h * 0.06, width: w * 0.36, height: w * 0.36))
        path.move(to: CGPoint(x: rect.minX + w * 0.14, y: rect.maxY - h * 0.02))
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.86, y: rect.maxY - h * 0.02),
            control1: CGPoint(x: rect.minX + w * 0.18, y: rect.minY + h * 0.58),
            control2: CGPoint(x: rect.minX + w * 0.82, y: rect.minY + h * 0.58)
        )
        return path
    }
}

/// Reference capability lens: two open concentric rings, a filled core and a
/// satellite node at the upper trailing edge.
private struct PPNavCapabilityLensGlyph: View {
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .trim(from: 0.10, to: 0.86)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-58))
                    .frame(width: side * 0.94, height: side * 0.94)

                Circle()
                    .trim(from: 0.10, to: 0.84)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-52))
                    .frame(width: side * 0.56, height: side * 0.56)

                Circle()
                    .frame(width: side * 0.17, height: side * 0.17)

                Circle()
                    .frame(width: side * 0.2, height: side * 0.2)
                    .offset(x: side * 0.3, y: -side * 0.28)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// Reference bell: rounded shoulder outline with a detached clapper arc.
private struct PPNavBellGlyph: View {
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: w * 0.08, y: h * 0.74))
                    path.addCurve(
                        to: CGPoint(x: w * 0.22, y: h * 0.46),
                        control1: CGPoint(x: w * 0.2, y: h * 0.7),
                        control2: CGPoint(x: w * 0.22, y: h * 0.6)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.5, y: h * 0.08),
                        control1: CGPoint(x: w * 0.22, y: h * 0.22),
                        control2: CGPoint(x: w * 0.33, y: h * 0.08)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.78, y: h * 0.46),
                        control1: CGPoint(x: w * 0.67, y: h * 0.08),
                        control2: CGPoint(x: w * 0.78, y: h * 0.22)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.92, y: h * 0.74),
                        control1: CGPoint(x: w * 0.78, y: h * 0.6),
                        control2: CGPoint(x: w * 0.8, y: h * 0.7)
                    )
                    path.closeSubpath()
                }
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.addArc(
                        center: CGPoint(x: w * 0.5, y: h * 0.78),
                        radius: w * 0.12,
                        startAngle: .degrees(10),
                        endAngle: .degrees(170),
                        clockwise: false
                    )
                }
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            .frame(width: w, height: h)
        }
    }
}

private struct PPNavCommandGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let r = min(w, h) * 0.18
        let left = rect.minX + w * 0.31
        let right = rect.minX + w * 0.69
        let top = rect.minY + h * 0.31
        let bottom = rect.minY + h * 0.69

        var path = Path()
        path.addArc(center: CGPoint(x: left, y: top), radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: right, y: top - r))
        path.addArc(center: CGPoint(x: right, y: top), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: right + r, y: bottom))
        path.addArc(center: CGPoint(x: right, y: bottom), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: left, y: bottom + r))
        path.addArc(center: CGPoint(x: left, y: bottom), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: left - r, y: top))
        path.closeSubpath()
        return path
    }
}

// MARK: - Interaction

private struct PPNavPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.96)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

private enum PPNavHaptics {
    @MainActor
    static func select(reduceMotion: Bool) {
        guard !reduceMotion else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Leading Back / Close press-down. Deliberately not gated on Reduce
    /// Motion: haptics are not motion, and this is the one control users
    /// operate without looking.
    @MainActor
    static func leadingEngage() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.85)
    }
}

// MARK: - Material system

private struct PPNavGlassContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
#else
        content
#endif
    }
}

private extension View {
    /// Applies a hint only when one exists. An empty hint string is still a
    /// hint to VoiceOver, so it must not be synthesised.
    @ViewBuilder
    func ppAccessibilityHint(_ hint: String?) -> some View {
        if let hint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            accessibilityHint(Text(hint))
        } else {
            self
        }
    }

    /// iOS 26 Liquid Glass when available; semantic Pure Pets material
    /// otherwise. `elevation` drives the fallback shadow that stands in for the
    /// glass specular edge.
    @ViewBuilder
    func ppGlass<S: InsettableShape>(
        shape: S,
        interactive: Bool,
        tint: Color?,
        elevation: Double,
        namespace: Namespace.ID,
        id: String,
        enabled: Bool = true
    ) -> some View {
        if enabled {
#if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                Group {
                    if let tint {
                        self.glassEffect(
                            interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                            in: shape
                        )
                    } else {
                        self.glassEffect(
                            interactive ? .regular.interactive() : .regular,
                            in: shape
                        )
                    }
                }
                .glassEffectID(id, in: namespace)
            } else {
                ppMaterialSurface(shape: shape, tint: tint, elevation: elevation)
            }
#else
            ppMaterialSurface(shape: shape, tint: tint, elevation: elevation)
#endif
        } else {
            self
        }
    }

    func ppMaterialSurface<S: InsettableShape>(
        shape: S,
        tint: Color?,
        elevation: Double
    ) -> some View {
        self
            .background {
                if let tint {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.92)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    shape
                        .fill(PPNavPalette.surface)
                        .background(shape.fill(.ultraThinMaterial))
                }
            }
            .overlay(
                shape.strokeBorder(
                    tint == nil
                        ? PPNavPalette.hairline.opacity(0.5)
                        : Color.white.opacity(0.16),
                    lineWidth: 0.5
                )
            )
            .shadow(color: PPNavPalette.shadow.opacity(elevation), radius: elevation > 0 ? 8 : 0, x: 0, y: elevation > 0 ? 3 : 0)
    }
}

// MARK: - Status bar helper

@MainActor
public enum PPStatusBarHelper {
    public static var statusBarHeight: CGFloat {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            let topInset = window.safeAreaInsets.top
            if topInset > 0 { return topInset }
        }
        if let statusBarManager = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.statusBarManager {
            let height = statusBarManager.statusBarFrame.height
            if height > 0 { return height }
        }
        return 47.0
    }
}

// MARK: - UIKit host

/// Hosts the Global bar in UIKit without introducing a second navigation stack.
/// The owning container remains responsible for routing and action semantics.
@MainActor
public final class PPGlobalNavigationHostingController: UIViewController {
    private let hostedController: UIHostingController<PPGlobalNavigationBar>
    public private(set) var configuration: PPGlobalNavigationConfiguration
    private var actionHandler: PPGlobalNavigationActionHandler
    private var appliedDisplayMode: PPNavigationDisplayMode?
    private var lastReportedBarHeight: CGFloat = 0
    public var onPreferredBarHeightChange: ((CGFloat) -> Void)?

    public init(
        configuration: PPGlobalNavigationConfiguration,
        onAction: @escaping PPGlobalNavigationActionHandler
    ) {
        self.configuration = configuration
        self.actionHandler = onAction
        self.hostedController = UIHostingController(
            rootView: PPGlobalNavigationBar(
                configuration: configuration,
                safeAreaTop: PPStatusBarHelper.statusBarHeight,
                layoutDirection: Language.isRTL() ? .rightToLeft : .leftToRight,
                onAction: onAction
            )
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Height the host must reserve so arbitrary child content stays below the
    /// single visible navigation owner, including full status bar clearance.
    public var preferredBarHeight: CGFloat {
        let hasSubtitle = configuration.subtitle?.isEmpty == false
        return PPNavSpec.hostHeight(
            for: preferredDisplayMode,
            hasSubtitle: hasSubtitle,
            accessibilitySize: traitCollection.preferredContentSizeCategory.isAccessibilityCategory,
            largeText: PPNavSpec.usesTallExpandedHeight(traitCollection.preferredContentSizeCategory)
        ) + currentStatusBarHeight
    }

    private var currentStatusBarHeight: CGFloat {
        if let window = view.window {
            let topInset = window.safeAreaInsets.top
            if topInset > 0 { return topInset }
        }
        return PPStatusBarHelper.statusBarHeight
    }

    public var preferredDisplayMode: PPNavigationDisplayMode {
        if !traitCollection.preferredContentSizeCategory.isAccessibilityCategory,
           view.bounds.width > 0,
           view.bounds.width < PPNavSpec.compactWidthThreshold {
            return .compact
        }
        return .expanded
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false

        hostedController.view.backgroundColor = .clear
        hostedController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hostedController)
        view.addSubview(hostedController.view)
        NSLayoutConstraint.activate([
            hostedController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostedController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostedController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostedController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostedController.didMove(toParent: self)
        refreshHostedBar()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshHostedBar()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        refreshHostedBar()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshHostedBar()
    }

    public func update(
        configuration: PPGlobalNavigationConfiguration,
        onAction: @escaping PPGlobalNavigationActionHandler
    ) {
        self.configuration = configuration
        actionHandler = onAction
        guard isViewLoaded else { return }
        refreshHostedBar()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }
        refreshHostedBar()
    }

    private func refreshHostedBar() {
        let displayMode = preferredDisplayMode
        appliedDisplayMode = displayMode
        let safeTop = currentStatusBarHeight
        hostedController.rootView = PPGlobalNavigationBar(
            configuration: configuration,
            collapseProgress: displayMode == .compact ? 1 : 0,
            safeAreaTop: safeTop,
            displayMode: displayMode,
            layoutDirection: Language.isRTL() ? .rightToLeft : .leftToRight,
            onAction: actionHandler
        )
        reportPreferredBarHeightIfNeeded()
    }

    private func reportPreferredBarHeightIfNeeded() {
        let height = preferredBarHeight
        guard abs(lastReportedBarHeight - height) > 0.5 else { return }
        lastReportedBarHeight = height
        preferredContentSize = CGSize(width: view.bounds.width, height: height)
        onPreferredBarHeightChange?(height)
    }
}

// MARK: - Convenience scroll shell

public struct PPGlobalNavigationScrollShell<Content: View>: View {
    public let configuration: PPGlobalNavigationConfiguration
    public let collapseDistance: CGFloat
    public let onAction: PPGlobalNavigationActionHandler
    private let content: Content

    @State private var scrollOffset: CGFloat = 0
    @State private var displayMode: PPNavigationDisplayMode?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        configuration: PPGlobalNavigationConfiguration,
        collapseDistance: CGFloat = 76,
        onAction: @escaping PPGlobalNavigationActionHandler,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.collapseDistance = max(44, collapseDistance)
        self.onAction = onAction
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geometry in
            let safeTop = max(geometry.safeAreaInsets.top, PPStatusBarHelper.statusBarHeight)
            let progress = (-scrollOffset / collapseDistance).ppClamped()
            let fallbackMode: PPNavigationDisplayMode = dynamicTypeSize.isAccessibilitySize
                ? .expanded
                : (geometry.size.width < PPNavSpec.compactWidthThreshold || progress >= 0.5
                    ? .compact
                    : .expanded)
            let resolvedMode = displayMode ?? fallbackMode
            let hasSubtitle = configuration.subtitle?.isEmpty == false
            let reserveBase = PPNavSpec.hostHeight(
                for: resolvedMode,
                hasSubtitle: hasSubtitle,
                accessibilitySize: dynamicTypeSize.isAccessibilitySize,
                largeText: PPNavSpec.usesTallExpandedHeight(dynamicTypeSize)
            )

            ZStack(alignment: .top) {
                PPNavPalette.canvas
                    .ignoresSafeArea()

                ScrollView {
                    PPNavScrollOffsetProbe()
                    content
                        .padding(.top, reserveBase + safeTop)
                }
                .coordinateSpace(name: PPNavScrollCoordinateSpace.name)
                .onPreferenceChange(PPNavScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }

                PPGlobalNavigationBar(
                    configuration: configuration,
                    collapseProgress: progress,
                    safeAreaTop: safeTop,
                    layoutDirection: Language.isRTL() ? .rightToLeft : .leftToRight,
                    onAction: onAction,
                    onDisplayModeChange: { newMode in
                        guard displayMode != newMode else { return }
                        displayMode = newMode
                    }
                )
                .zIndex(10)
            }
            .ignoresSafeArea()
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Scroll offset

private enum PPNavScrollCoordinateSpace {
    static let name = "PPGlobalNavigationScrollSpace"
}

private struct PPNavScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PPNavScrollOffsetProbe: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: PPNavScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(PPNavScrollCoordinateSpace.name)).minY
                )
        }
        .frame(height: 0)
    }
}

// MARK: - UIKit / Objective-C friendly descriptor

@objc public enum PPGlobalNavigationStyleObjC: Int {
    case commandCrown = 0
    case edgeLoom = 1
    case contextDeck = 2

    fileprivate var swiftStyle: PPGlobalNavigationStyle {
        switch self {
        case .commandCrown: return .commandCrown
        case .edgeLoom: return .edgeLoom
        case .contextDeck: return .contextDeck
        }
    }
}

@objcMembers
public final class PPGlobalNavigationDescriptor: NSObject {
    public var style: PPGlobalNavigationStyleObjC = .contextDeck
    public var title: String = ""
    public var eyebrow: String?
    public var subtitle: String?
    public var context: String?
    public var statusLabel: String?
    public var statusDetail: String?
    public var statusIsLive: Bool = false

    public override init() {
        super.init()
    }

    @nonobjc public func makeConfiguration(
        leadingAction: PPGlobalNavigationAction? = nil,
        trailingActions: [PPGlobalNavigationAction] = []
    ) -> PPGlobalNavigationConfiguration {
        let status: PPGlobalNavigationStatus? = statusLabel.map {
            PPGlobalNavigationStatus(
                label: $0,
                detail: statusDetail,
                isLive: statusIsLive
            )
        }

        return PPGlobalNavigationConfiguration(
            style: style.swiftStyle,
            title: title,
            eyebrow: eyebrow,
            subtitle: subtitle,
            context: context,
            status: status,
            leadingAction: leadingAction,
            trailingActions: trailingActions
        )
    }
}

// MARK: - Math helpers

private extension CGFloat {
    func ppClamped(to range: ClosedRange<CGFloat> = 0...1) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Previews

#if DEBUG
private struct PPGlobalNavigationReferenceHarness: View {
    @State private var mode: PPNavigationDisplayMode = .expanded

    var body: some View {
        VStack(spacing: 0) {
            Picker("Display mode", selection: $mode) {
                ForEach(PPNavigationDisplayMode.allCases) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // 01_large_title_expanded / 02_compact_scrolled
            PPGlobalNavigationBar(
                configuration: operationsConfiguration,
                collapseProgress: mode == .compact ? 1 : 0,
                displayMode: mode,
                onAction: { _ in }
            )

            // 03_modal_create
            PPGlobalNavigationBar(
                configuration: modalConfiguration,
                displayMode: .compact,
                onAction: { _ in }
            )
            .padding(.top, 24)

            Spacer()
        }
        .background(PPNavPalette.canvas)
    }

    private var operationsConfiguration: PPGlobalNavigationConfiguration {
        PPGlobalNavigationConfiguration(
            title: "Work",
            eyebrow: "Operations Center",
            subtitle: "All capabilities",
            status: .init(label: "Live", detail: "Unified", isLive: true),
            leadingAction: .back,
            trailingActions: [
                PPGlobalNavigationAction(id: "lens", kind: .capabilityLens, accessibilityLabel: "Capabilities"),
                PPGlobalNavigationAction(id: "alerts", kind: .notifications, accessibilityLabel: "Notifications", badge: ""),
                PPGlobalNavigationAction(id: "profile", kind: .profile, accessibilityLabel: "Account", monogram: "YN"),
            ],
            showsContextFilament: true
        )
    }

    private var modalConfiguration: PPGlobalNavigationConfiguration {
        PPGlobalNavigationConfiguration(
            title: "New Product",
            subtitle: "Create listing",
            leadingAction: .close,
            trailingActions: [
                .more,
                PPGlobalNavigationAction(
                    id: "save",
                    kind: .confirm,
                    accessibilityLabel: "Save",
                    prominence: .emphasized,
                    title: "Save"
                ),
            ],
            showsContextFilament: false
        )
    }
}

#Preview("Pure Pets Pro — Global Navigation") {
    PPGlobalNavigationReferenceHarness()
}

#Preview("RTL — Arabic") {
    PPGlobalNavigationReferenceHarness()
        .environment(\.layoutDirection, .rightToLeft)
}
#endif
