//
//  PPGlobalNavigation.swift
//  PurePetsAdmin
//
//  ONE global navigation owner for every screen, including Work / main / root.
//
//  ─────────────────────────────────────────────────────────────────────────────
//  VISUAL SPECIFICATION
//  ─────────────────────────────────────────────────────────────────────────────
//  This file is a measured reconstruction of the supplied Pure Pets Pro
//  navigation reference renders:
//
//    01_large_title_expanded_navbar_3x.png   5940 x 786   → PPNavigationDisplayMode.expanded
//    02_compact_scrolled_navbar_3x.png       5934 x 363   → PPNavigationDisplayMode.compact
//    03_modal_create_navbar_3x.png           5934 x 426   → .compact + emphasized action
//
//  The references are drawn on a wide (~970pt) artboard, so horizontal *slack*
//  is not transferable to a phone. Two independent anchors fix the reference
//  scale at 6.1 reference-px per point:
//
//    • compact bar height 318px → 52.1pt  (the iOS compact navigation height)
//    • circular action        267px → 43.8pt  (the 44pt HIG touch target)
//
//  Every constant in `PPNavSpec` below is that measurement divided by 6.1.
//  Measured reference values are kept inline next to each constant so the
//  geometry stays auditable.
//
//  Reference px → pt (scale 6.1)
//  ┌────────────────────────────────┬──────────┬─────────┐
//  │ element                        │ ref px   │ pt      │
//  ├────────────────────────────────┼──────────┼─────────┤
//  │ surface corner radius          │ 183      │ 30      │
//  │ navigation pearl (expanded)    │ 351 sq   │ 57.5    │
//  │ pearl corner radius            │ 160      │ 26.2    │
//  │ navigation pearl (compact)     │ 255 sq   │ 41.8    │
//  │ command crown height (exp.)    │ 391      │ 64.1    │
//  │ command crown height (comp.)   │ 204      │ 33.4    │
//  │ circular action                │ 267      │ 43.8    │
//  │ action gap (expanded)          │ 53       │ 8.7     │
//  │ action gap (compact)           │ 103      │ 16.9    │
//  │ status chip height             │ 265      │ 43.4    │
//  │ status live dot                │ 42       │ 6.9     │
//  │ rail dot / pitch               │ 17 / 50  │ 2.8/8.2 │
//  │ eyebrow cap height             │ 46       │ 7.5     │
//  │ large title ascender           │ 203      │ 33.3    │
//  │ compact title ascender         │ 79       │ 13.0    │
//  │ filament thickness             │ 14       │ 2.3     │
//  └────────────────────────────────┴──────────┴─────────┘
//
//  Documented, deliberate deviations from the artboards (width-forced, platform
//  required, or requested after the first on-device review):
//
//  1. The bar surface is CLEAR. The artboard's floating white card, brand wash,
//     hairline and drop shadow are not drawn; the host's page background shows
//     through and only the floating controls carry material.
//  2. The artboard's 3x3 dot rail beside Back / Close is not drawn.
//  3. The artboard places pearl · title · crown on one row across ~970pt.
//     A 375-440pt phone cannot host that row, so the control row sits above the
//     title stage — which is also what "Large Title Expanded" means natively.
//  4. Type scale is reduced from the artboard ramp for phone legibility:
//     expanded title 30pt (artboard 46pt), subtitle 13pt, compact title 17pt.
//     Expanded bar height is 146pt, single-line title with tightening, so the
//     reservation never changes with content.
//  5. Reference eyebrow ink is #D9003C and reference body ink is neutral. Brand
//     source of truth (PPDesignTokens) wins: ppPrimary / ppTextPrimary /
//     ppTextSecondary / ppSuccess.
//
//  ─────────────────────────────────────────────────────────────────────────────
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
/// `compact` is selected automatically for narrow widths, accessibility text
/// sizes, or once the host has scrolled past the large-title threshold.
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

    fileprivate var hasChrome: Bool {
        leadingAction != nil || !trailingActions.isEmpty || status != nil
    }
}

public typealias PPGlobalNavigationActionHandler = (PPGlobalNavigationAction) -> Void

// MARK: - Brand contract

private enum PPNavPalette {
    static var brand: Color { Color(uiColor: .ppPrimary) }
    static var brandPressed: Color { Color(uiColor: .ppPressedAction) }
    static var brandShiner: Color { Color(uiColor: .ppPrimaryShiner) }
    static var primaryText: Color { Color(uiColor: .ppTextPrimary) }
    static var secondaryText: Color { Color(uiColor: .ppTextSecondary) }
    static var surface: Color { Color(uiColor: .ppSurface) }
    static var elevated: Color { Color(uiColor: .ppElevatedSurface) }
    static var recessed: Color { Color(uiColor: .ppSecondarySurface) }
    static var hairline: Color { Color(uiColor: .ppSurfaceBorder) }
    static var canvas: Color { Color(uiColor: .ppBackground) }
    static var live: Color { Color(uiColor: .ppSuccess) }
    static var shadow: Color { Color(uiColor: .ppShadow) }
}

// MARK: - Reference-derived metrics

private enum PPNavSpec {
    /// Reference pixels per point. Both independent anchors agree on 6.1.
    static let referenceScale: CGFloat = 6.1

    // Host reservations -------------------------------------------------------
    /// 56pt control row + eyebrow / title / subtitle stage.
    static let expandedHeight: CGFloat = 146
    /// Reference compact card 318px / 6.1.
    static let compactHeight: CGFloat = 52

    // Navigation pearl --------------------------------------------------------
    static let expandedLeadingMargin: CGFloat = 20
    static let compactLeadingMargin: CGFloat = 16    // 95px
    static let expandedPearl: CGFloat = 66
    static let compactPearl: CGFloat = 40
    static let pearlRadiusRatio: CGFloat = 0.456     // 160 / 351
    static let pearlGlyphRatio: CGFloat = 0.32
    static let expandedPearlGlyphRatio: CGFloat = 0.24
    static let expandedPearlTitleGap: CGFloat = 18
    static let chevronAspect: CGFloat = 0.57         // 56 / 98

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
    static let expandedCrownHeight: CGFloat = 56
    static let compactCrownHeight: CGFloat = 33.5    // 204px
    static let crownRadiusRatio: CGFloat = 0.27
    static let expandedCrownPadding: CGFloat = 6
    static let expandedAction: CGFloat = 44          // 267px
    static let compactAction: CGFloat = 33           // 200px
    static let expandedActionGap: CGFloat = 6
    static let compactActionGap: CGFloat = 14
    static let compactCrownPadding: CGFloat = 4
    static let expandedTrailingMargin: CGFloat = 16  // 99px
    static let compactTrailingMargin: CGFloat = 15   // 89px
    static let dividerLeadGap: CGFloat = 10
    static let dividerTrailGap: CGFloat = 10
    static let compactDividerLeadGap: CGFloat = 10
    static let compactDividerTrailGap: CGFloat = 12

    // Status chip -------------------------------------------------------------
    static let chipRadiusRatio: CGFloat = 0.245      // 65 / 265
    static let statusDot: CGFloat = 7                // 42px
    static let compactStatusDot: CGFloat = 6.9       // 42px
    static let chipLeadingPad: CGFloat = 12          // 72px
    static let chipTrailingPad: CGFloat = 14         // 97px
    static let chipDotGap: CGFloat = 9.5             // 58px

    // Title stage -------------------------------------------------------------
    static let stageTopGap: CGFloat = 2
    static let eyebrowToTitle: CGFloat = 2
    static let titleToSubtitle: CGFloat = 1
    static let stageBottomInset: CGFloat = 10
    static let filamentThickness: CGFloat = 2.5      // 14px
    static let filamentFraction: CGFloat = 0.13      // 284 / ~2200 visible track
    static let filamentMinimum: CGFloat = 40

    // Emphasized capsule (03_modal_create) ------------------------------------
    static let emphasizedHeight: CGFloat = 40        // 248px
    static let emphasizedPad: CGFloat = 16           // 98px
    static let emphasizedGlyphGap: CGFloat = 8       // 50px

    // Responsive thresholds ---------------------------------------------------
    /// Below this width the expanded title stage cannot hold a dominant title.
    static let compactWidthThreshold: CGFloat = 350
    /// Minimum readable width for the compact centred title cluster.
    static let compactTitleMinimum: CGFloat = 96
    /// Minimum leftover width before the status readout is dropped.
    static let statusDropMinimum: CGFloat = 84

    static func hostHeight(for mode: PPNavigationDisplayMode) -> CGFloat {
        mode == .expanded ? expandedHeight : compactHeight
    }
}

private enum PPNavGeometryID {
    static let pearl = "pp.nav.pearl"
    /// The expanded leading control is a distinct glass identity: both pearls
    /// can co-exist for one frame while the bar morphs between display modes,
    /// and two live effects may not share an ID inside one namespace.
    static let expandedPearl = "pp.nav.pearl.expanded"
    static let backCapsule = "pp.nav.back-capsule"
    static let expandedBackCapsule = "pp.nav.back-capsule.expanded"
    static let title = "pp.nav.title"
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
            size: mode == .expanded ? 30 : 17,
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
            size: mode == .expanded ? 13 : 11,
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
    public let onAction: PPGlobalNavigationActionHandler
    public let onDisplayModeChange: ((PPNavigationDisplayMode) -> Void)?

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var glassNamespace
    @State private var latchedMode: PPNavigationDisplayMode?

    public init(
        configuration: PPGlobalNavigationConfiguration,
        collapseProgress: CGFloat = 0,
        safeAreaTop: CGFloat = 0,
        displayMode: PPNavigationDisplayMode? = nil,
        onAction: @escaping PPGlobalNavigationActionHandler,
        onDisplayModeChange: ((PPNavigationDisplayMode) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.collapseProgress = collapseProgress.ppClamped()
        self.safeAreaTop = max(0, safeAreaTop)
        self.displayModeOverride = displayMode
        self.onAction = onAction
        self.onDisplayModeChange = onDisplayModeChange
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let mode = resolvedMode(width: width)

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
                    layoutDirection: layoutDirection,
                    namespace: glassNamespace,
                    onAction: onAction
                )
            }
            .frame(width: width, alignment: .top)
            .animation(motion, value: mode)
            .onChange(of: mode) { newValue in
                latchedMode = newValue
                onDisplayModeChange?(newValue)
            }
            .onAppear { onDisplayModeChange?(mode) }
        }
        .frame(minHeight: intrinsicHeight, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.1)
    }

    /// Selection order: explicit override → accessibility text → scroll
    /// threshold (with hysteresis so the morph cannot flap) → available width.
    private func resolvedMode(width: CGFloat) -> PPNavigationDisplayMode {
        if let displayModeOverride { return displayModeOverride }
        if dynamicTypeSize.isAccessibilitySize { return .compact }
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
            ?? (dynamicTypeSize.isAccessibilitySize ? .compact : .expanded)
        return PPNavSpec.hostHeight(for: mode) + safeAreaTop
    }
}

// MARK: - Stage

private struct PPNavStage: View {
    let configuration: PPGlobalNavigationConfiguration
    let mode: PPNavigationDisplayMode
    let width: CGFloat
    let safeAreaTop: CGFloat
    let layoutDirection: LayoutDirection
    let namespace: Namespace.ID
    let onAction: PPGlobalNavigationActionHandler

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reservesExpandedLeadingSlot = false
    @State private var revealedLeadingAction: PPGlobalNavigationAction?
    @State private var expandedTitleOffset: CGFloat = 0

    var body: some View {
        let plan = PPNavPlan(configuration: configuration, mode: mode, width: width)

        VStack(spacing: 0) {
            controlRow(plan: plan)

            if mode == .expanded {
                titleStage(plan: plan)
            }
        }
        .padding(.top, safeAreaTop)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: leadingSequenceKey) {
            await synchronizeExpandedLeadingAction()
        }
    }

    // MARK: Control row

    @ViewBuilder
    private func controlRow(plan: PPNavPlan) -> some View {
        HStack(spacing: 0) {
            leadingCluster(plan: plan)

            if mode == .compact {
                Spacer(minLength: 8)
            } else {
                Spacer(minLength: 12)
            }

            trailingCluster(plan: plan)
        }
        .padding(.leading, plan.leadingMargin)
        .padding(.trailing, plan.trailingMargin)
        .frame(height: plan.controlRowHeight)
        .overlay {
            // 02_compact_scrolled: the title cluster is centred on the bar,
            // not on the free space between the clusters.
            if mode == .compact {
                titleCluster(plan: plan)
                    .padding(.horizontal, plan.compactTitleSideInset)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func leadingCluster(plan: PPNavPlan) -> some View {
        // Expanded mode places the pearl beside the large-title stack. Compact
        // mode keeps the conventional inline navigation arrangement.
        if mode == .compact {
            pearl(plan: plan, outlined: false)
        }
    }

    @ViewBuilder
    private func pearl(plan: PPNavPlan, outlined: Bool) -> some View {
        if let leading = configuration.leadingAction {
            PPNavPearl(
                action: leading,
                diameter: leadingDiameter(for: leading, plan: plan),
                outlined: outlined,
                namespace: namespace,
                onAction: onAction
            )
        }
    }

    private func leadingDiameter(for action: PPGlobalNavigationAction, plan: PPNavPlan) -> CGFloat {
        action.kind == .back ? PPNavSpec.backControlDiameter : plan.pearlDiameter
    }

    private func expandedLeadingSlotWidth(plan: PPNavPlan) -> CGFloat {
        guard let action = configuration.leadingAction else { return 0 }
        return leadingDiameter(for: action, plan: plan) + PPNavSpec.expandedPearlTitleGap
    }

    @ViewBuilder
    private func trailingCluster(plan: PPNavPlan) -> some View {
        PPNavCommandCrown(
            configuration: configuration,
            plan: plan,
            namespace: namespace,
            onAction: onAction
        )
    }

    // MARK: Title

    @ViewBuilder
    private func titleStage(plan: PPNavPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                ZStack(alignment: .leading) {
                    if let leading = revealedLeadingAction {
                        PPNavPearl(
                            action: leading,
                            diameter: leadingDiameter(for: leading, plan: plan),
                            outlined: true,
                            namespace: namespace,
                            onAction: onAction
                        )
                        .transition(
                            .scale(scale: 0.82, anchor: .center)
                                .combined(with: .opacity)
                        )
                        .allowsHitTesting(configuration.leadingAction?.id == leading.id)
                    }
                }
                .frame(
                    width: reservesExpandedLeadingSlot
                        ? expandedLeadingSlotWidth(plan: plan)
                        : 0,
                    height: plan.pearlDiameter,
                    alignment: .leading
                )

                titleCluster(plan: plan)
                    .layoutPriority(1)
                    .offset(x: expandedTitleOffset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if configuration.showsContextFilament {
                PPNavContextFilament(width: plan.filamentWidth)
            }
        }
        .padding(.top, PPNavSpec.stageTopGap)
        .padding(.bottom, PPNavSpec.stageBottomInset)
        .padding(.horizontal, plan.leadingMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var leadingSequenceKey: PPNavLeadingSequenceKey {
        PPNavLeadingSequenceKey(
            action: configuration.leadingAction,
            mode: mode,
            reduceMotion: reduceMotion,
            isRightToLeft: layoutDirection == .rightToLeft
        )
    }

    @MainActor
    private func synchronizeExpandedLeadingAction() async {
        let requestedID = configuration.leadingAction?.id
        let shouldAnimate = mode == .expanded &&
            !reduceMotion &&
            !UIAccessibility.isVoiceOverRunning &&
            !UIAccessibility.isSwitchControlRunning

        guard mode == .expanded else {
            updateLeadingStateWithoutAnimation(
                reservesSlot: false,
                titleOffset: 0,
                action: nil
            )
            return
        }

        guard shouldAnimate else {
            updateLeadingStateWithoutAnimation(
                reservesSlot: requestedID != nil,
                titleOffset: 0,
                action: configuration.leadingAction
            )
            return
        }

        guard let requestedID else {
            if revealedLeadingAction != nil {
                withAnimation(PPNavMotion.leadingExit) {
                    revealedLeadingAction = nil
                }
                guard await waitForLeadingSequence(PPNavMotion.leadingExitDuration) else {
                    return
                }
            }

            if reservesExpandedLeadingSlot {
                updateLeadingStateWithoutAnimation(
                    reservesSlot: false,
                    titleOffset: expandedLeadingTravel,
                    action: nil
                )
            }
            withAnimation(PPNavMotion.leadingLayout) {
                expandedTitleOffset = 0
            }
            return
        }

        if let revealedLeadingAction,
           revealedLeadingAction.id != requestedID {
            withAnimation(PPNavMotion.leadingExit) {
                self.revealedLeadingAction = nil
            }
            guard await waitForLeadingSequence(PPNavMotion.leadingExitDuration) else {
                return
            }
        }

        if !reservesExpandedLeadingSlot {
            withAnimation(PPNavMotion.leadingLayout) {
                expandedTitleOffset = expandedLeadingTravel
            }
            guard await waitForLeadingSequence(PPNavMotion.leadingLayoutDuration) else {
                return
            }
            updateLeadingStateWithoutAnimation(
                reservesSlot: true,
                titleOffset: 0,
                action: nil
            )
        }

        guard !Task.isCancelled else { return }
        withAnimation(PPNavMotion.leadingReveal) {
            revealedLeadingAction = configuration.leadingAction
        }
    }

    @MainActor
    private func updateLeadingStateWithoutAnimation(
        reservesSlot: Bool,
        titleOffset: CGFloat,
        action: PPGlobalNavigationAction?
    ) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            reservesExpandedLeadingSlot = reservesSlot
            expandedTitleOffset = titleOffset
            revealedLeadingAction = action
        }
    }

    private var expandedLeadingTravel: CGFloat {
        let distance = PPNavSpec.expandedPearl +
            PPNavSpec.expandedPearlTitleGap
        return layoutDirection == .rightToLeft ? -distance : distance
    }

    private func waitForLeadingSequence(_ duration: TimeInterval) async -> Bool {
        do {
            try await Task<Never, Never>.sleep(
                nanoseconds: UInt64(duration * 1_000_000_000)
            )
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    @ViewBuilder
    private func titleCluster(plan: PPNavPlan) -> some View {
        PPNavTitleCluster(
            configuration: configuration,
            mode: mode,
            showsSubtitle: plan.showsSubtitle
        )
        .matchedGeometryEffect(id: PPNavGeometryID.title, in: namespace)
    }
}

private struct PPNavLeadingSequenceKey: Hashable {
    let action: PPGlobalNavigationAction?
    let mode: PPNavigationDisplayMode
    let reduceMotion: Bool
    let isRightToLeft: Bool
}

private enum PPNavMotion {
    static let leadingLayoutDuration: TimeInterval = 0.28
    static let leadingExitDuration: TimeInterval = 0.12
    static let leadingLayout = Animation.timingCurve(
        0.2,
        0,
        0,
        1,
        duration: leadingLayoutDuration
    )
    static let leadingReveal = Animation.easeOut(duration: 0.20)
    static let leadingExit = Animation.easeOut(duration: leadingExitDuration)
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
    let crownHeight: CGFloat
    let crownPadding: CGFloat
    let dividerLeadGap: CGFloat
    let dividerTrailGap: CGFloat

    let showsStatus: Bool
    let showsStatusDetail: Bool
    let showsSubtitle: Bool
    let compactTitleSideInset: CGFloat
    let filamentWidth: CGFloat

    init(configuration: PPGlobalNavigationConfiguration, mode: PPNavigationDisplayMode, width: CGFloat) {
        self.mode = mode
        self.width = width

        let compact = mode == .compact
        leadingMargin = compact ? PPNavSpec.compactLeadingMargin : PPNavSpec.expandedLeadingMargin
        trailingMargin = compact ? PPNavSpec.compactTrailingMargin : PPNavSpec.expandedTrailingMargin
        pearlDiameter = compact ? PPNavSpec.compactPearl : PPNavSpec.expandedPearl
        actionDiameter = compact ? PPNavSpec.compactAction : PPNavSpec.expandedAction
        actionGap = compact ? PPNavSpec.compactActionGap : PPNavSpec.expandedActionGap
        crownHeight = compact ? PPNavSpec.compactCrownHeight : PPNavSpec.expandedCrownHeight
        crownPadding = compact ? PPNavSpec.compactCrownPadding : PPNavSpec.expandedCrownPadding
        dividerLeadGap = compact ? PPNavSpec.compactDividerLeadGap : PPNavSpec.dividerLeadGap
        dividerTrailGap = compact ? PPNavSpec.compactDividerTrailGap : PPNavSpec.dividerTrailGap

        // Root / main screens carry no pearl and no crown. Collapsing the
        // control row keeps the title stage from floating in dead space while
        // every screen still uses this one component.
        if compact {
            controlRowHeight = PPNavSpec.compactHeight
        } else {
            let hasExpandedControlRow = configuration.status != nil ||
                !configuration.trailingActions.isEmpty
            controlRowHeight = hasExpandedControlRow
                ? PPNavSpec.expandedCrownHeight
                : 24
        }

        let actionCount = CGFloat(configuration.trailingActions.count)
        let actionsWidth = actionCount > 0
            ? actionCount * actionDiameter + max(0, actionCount - 1) * actionGap + 2 * crownPadding
            : 0

        // 01/02 reference status readout: dot + label (+ detail when expanded).
        let statusWidth: CGFloat = compact ? 61 : 79
        let dividerWidth = dividerLeadGap + dividerTrailGap + 1

        let leadingWidth: CGFloat = leadingMargin
            + (compact && configuration.leadingAction != nil ? pearlDiameter : 0)

        let fixedTrailing = actionsWidth + trailingMargin
        let centreBudget = width > 0 ? width - leadingWidth - fixedTrailing : .greatestFiniteMagnitude

        if configuration.status == nil {
            showsStatus = false
        } else if compact {
            showsStatus = centreBudget - statusWidth - dividerWidth >= PPNavSpec.compactTitleMinimum
        } else {
            showsStatus = centreBudget - statusWidth - dividerWidth >= PPNavSpec.statusDropMinimum
        }

        showsStatusDetail = !compact && showsStatus

        let statusCost = showsStatus ? statusWidth + dividerWidth : 0
        let remaining = centreBudget - statusCost

        showsSubtitle = compact ? remaining >= 128 : true

        compactTitleSideInset = compact
            ? max(leadingWidth, fixedTrailing + statusCost) + 8
            : 0

        let filamentTrack = max(0, width - 2 * PPNavSpec.expandedLeadingMargin)
        filamentWidth = width > 0
            ? max(PPNavSpec.filamentMinimum, filamentTrack * PPNavSpec.filamentFraction)
            : PPNavSpec.filamentMinimum
    }
}

// MARK: - Title cluster

private struct PPNavTitleCluster: View {
    let configuration: PPGlobalNavigationConfiguration
    let mode: PPNavigationDisplayMode
    let showsSubtitle: Bool

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            if mode == .expanded, let eyebrow = configuration.resolvedEyebrow {
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
                .font(PPNavTypography.title(mode))
                .foregroundStyle(PPNavPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(mode == .expanded ? 0.6 : 0.82)
                .allowsTightening(true)
                .multilineTextAlignment(textAlignment)
                .accessibilityAddTraits(.isHeader)

            if showsSubtitle, let subtitle = configuration.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(PPNavTypography.subtitle(mode))
                    .foregroundStyle(PPNavPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, PPNavSpec.titleToSubtitle)
                    .multilineTextAlignment(textAlignment)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var alignment: HorizontalAlignment { mode == .expanded ? .leading : .center }
    private var textAlignment: TextAlignment { mode == .expanded ? .leading : .center }

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
///  • **One shape language.** Both display modes render the measured
///    45.6%-radius continuous squircle. Expanded and compact differ only in
///    scale, ring treatment and elevation — which is what lets the glass morph
///    read as one object moving instead of two objects swapping.
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
    let outlined: Bool
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
                emphasized: outlined,
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
    }

    private var glyphSide: CGFloat {
        action.kind == .back
            ? diameter * PPNavSpec.backCapsuleGlyphRatio
            : diameter * (outlined ? PPNavSpec.expandedPearlGlyphRatio : PPNavSpec.pearlGlyphRatio)
    }
}

/// A back action uses the Return Beacon rather than the generic pearl: its
/// logical-leading rail and hooked mark create a single, unambiguous promise
/// that this control returns to the previous operational context.
private struct PPNavPearlStyle: ButtonStyle {
    let diameter: CGFloat
    let emphasized: Bool
    let isDirectional: Bool
    let isBack: Bool
    let namespace: Namespace.ID

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if isBack {
            PPNavBackCapsuleSurface(
                diameter: diameter,
                emphasized: emphasized,
                namespace: namespace,
                isPressed: configuration.isPressed,
                label: configuration.label
            )
        } else {
            PPNavPearlSurface(
                diameter: diameter,
                emphasized: emphasized,
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
    let emphasized: Bool
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
                    id: emphasized ? PPNavGeometryID.expandedPearl : PPNavGeometryID.pearl
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
        .onChange(of: pressed) { isDown in
            if isDown { PPNavHaptics.leadingEngage() }
        }
    }

    /// Reduce Motion keeps the state change — it only drops travel and scale,
    /// so the control still confirms the touch.
    private var pressMotion: Animation? {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.26, dampingFraction: 0.78, blendDuration: 0.08)
    }

    private func elevation(pressed: Bool) -> Double {
        if pressed { return PPNavSpec.pearlPressElevation }
        if isHovering { return PPNavSpec.pearlHoverElevation }
        return emphasized ? PPNavSpec.pearlRestElevation - 0.015 : PPNavSpec.pearlRestElevation
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
        let colors: [Color] = emphasized
            ? [
                PPNavPalette.brand.opacity(min(1, 0.92 + lift)),
                PPNavPalette.brandShiner.opacity(min(1, 0.52 + lift)),
                PPNavPalette.brand.opacity(min(1, 0.26 + lift)),
              ]
            : [
                PPNavPalette.hairline.opacity(min(1, 0.85 + lift)),
                PPNavPalette.hairline.opacity(min(1, 0.32 + lift)),
              ]

        return LinearGradient(
            colors: colors,
            startPoint: layoutDirection == .rightToLeft ? .topTrailing : .topLeading,
            endPoint: layoutDirection == .rightToLeft ? .bottomLeading : .bottomTrailing
        )
    }
}

/// Normal back treatment: a fixed 44pt capsule that uses the same semantic
/// glass configuration as the rest of the global navigation.
private struct PPNavBackCapsuleSurface: View {
    let diameter: CGFloat
    let emphasized: Bool
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
                    id: emphasized ? PPNavGeometryID.expandedBackCapsule : PPNavGeometryID.backCapsule
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
        .onChange(of: pressed) { isDown in
            if isDown { PPNavHaptics.leadingEngage() }
        }
    }

    private var leadingSign: CGFloat {
        layoutDirection == .rightToLeft ? 1 : -1
    }

    private var pressMotion: Animation? {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.24, dampingFraction: 0.8, blendDuration: 0.08)
    }

    private func elevation(pressed: Bool) -> Double {
        if pressed { return PPNavSpec.backCapsulePressElevation }
        if isHovering { return PPNavSpec.backCapsuleHoverElevation }
        return emphasized ? PPNavSpec.backCapsuleRestElevation + 0.01 : PPNavSpec.backCapsuleRestElevation
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

/// Trailing contextual cluster: status readout · seam · actions.
///
/// Expanded (01): one faint panel groups a recessed status well, the seam and
/// individually surfaced circular actions.
/// Compact (02): the panel dissolves, the status well and the action group
/// become the two raised surfaces, and the actions lose their own chrome.
private struct PPNavCommandCrown: View {
    let configuration: PPGlobalNavigationConfiguration
    let plan: PPNavPlan
    let namespace: Namespace.ID
    let onAction: PPGlobalNavigationActionHandler

    var body: some View {
        let isExpanded = plan.mode == .expanded

        PPNavGlassContainer(spacing: plan.actionGap) {
            HStack(spacing: 0) {
                if plan.showsStatus, let status = configuration.status {
                    PPNavStatusWell(
                        status: status,
                        height: plan.actionDiameter,
                        showsDetail: plan.showsStatusDetail,
                        raised: !isExpanded,
                        namespace: namespace
                    )

                    Color.clear.frame(width: plan.dividerLeadGap, height: 1)
                    PPNavSeam(height: plan.actionDiameter * 0.95)
                    Color.clear.frame(width: plan.dividerTrailGap, height: 1)
                }

                if !configuration.trailingActions.isEmpty {
                    PPGlobalNavigationTrailingActionContainer(
                        actions: configuration.trailingActions,
                        mode: plan.mode,
                        onAction: onAction
                    )
                }
            }
            .padding(isExpanded ? PPNavSpec.expandedCrownPadding : 0)
            .background {
                if isExpanded, configuration.hasChrome, !configuration.trailingActions.isEmpty {
                    PPNavSquircle(cornerRadius: plan.crownHeight * PPNavSpec.crownRadiusRatio)
                        .fill(PPNavPalette.surface.opacity(0.72))
                        .overlay(
                            PPNavSquircle(cornerRadius: plan.crownHeight * PPNavSpec.crownRadiusRatio)
                                .strokeBorder(PPNavPalette.hairline.opacity(0.42), lineWidth: 0.5)
                        )
                        .shadow(color: PPNavPalette.shadow.opacity(0.04), radius: 12, x: 0, y: 4)
                }
            }
        }
        .accessibilityElement(children: .contain)
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
    private let identifier: String
    private let onAction: PPGlobalNavigationActionHandler
    @Namespace private var glassNamespace

    public init(
        actions: [PPGlobalNavigationAction],
        mode: PPNavigationDisplayMode,
        id: String = "pp.nav.trailing-actions",
        onAction: @escaping PPGlobalNavigationActionHandler
    ) {
        self.actions = Array(actions.prefix(3))
        self.mode = mode
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
                            surfacedIndividually: isExpanded,
                            namespace: glassNamespace,
                            onAction: onAction
                        )
                    }
                }
                .padding(.horizontal, isExpanded ? 0 : PPNavSpec.compactCrownPadding)
                .ppGlass(
                    shape: PPNavSquircle(cornerRadius: crownHeight * PPNavSpec.crownRadiusRatio),
                    interactive: false,
                    tint: nil,
                    elevation: isExpanded ? 0 : 0.05,
                    namespace: glassNamespace,
                    id: identifier,
                    enabled: !isExpanded
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var isExpanded: Bool { mode == .expanded }
    private var actionDiameter: CGFloat {
        isExpanded ? PPNavSpec.expandedAction : PPNavSpec.compactAction
    }
    private var actionGap: CGFloat {
        isExpanded ? PPNavSpec.expandedActionGap : PPNavSpec.compactActionGap
    }
    private var crownHeight: CGFloat {
        isExpanded ? PPNavSpec.expandedCrownHeight : PPNavSpec.compactCrownHeight
    }
}

/// Recessed status readout. Measured 265px tall with a 0.245 radius ratio.
private struct PPNavStatusWell: View {
    let status: PPGlobalNavigationStatus
    let height: CGFloat
    let showsDetail: Bool
    let raised: Bool
    let namespace: Namespace.ID

    var body: some View {
        let shape = PPNavSquircle(cornerRadius: height * PPNavSpec.chipRadiusRatio)

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
        .background {
            if raised {
                shape
                    .fill(PPNavPalette.surface)
                    .shadow(color: PPNavPalette.shadow.opacity(0.05), radius: 8, x: 0, y: 3)
            } else {
                shape.fill(PPNavPalette.recessed.opacity(0.55))
            }
        }
        .overlay(shape.strokeBorder(PPNavPalette.hairline.opacity(0.45), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text([status.label, showsDetail ? status.detail : nil]
                .compactMap { $0 }
                .joined(separator: ", "))
        )
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
    let surfacedIndividually: Bool
    let namespace: Namespace.ID
    let onAction: PPGlobalNavigationActionHandler

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .accessibilityHint(action.accessibilityHint.map(Text.init) ?? Text(""))
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

            if let title = action.title, !title.isEmpty {
                Text(title)
                    .font(PPNavTypography.emphasizedLabel)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, action.title == nil ? 0 : PPNavSpec.emphasizedPad)
        .frame(
            minWidth: diameter,
            minHeight: min(diameter, PPNavSpec.emphasizedHeight),
            maxHeight: min(diameter, PPNavSpec.emphasizedHeight)
        )
        .ppGlass(
            shape: PPNavSquircle(cornerRadius: min(diameter, PPNavSpec.emphasizedHeight) / 2),
            interactive: true,
            tint: PPNavPalette.brand,
            elevation: 0.09,
            namespace: namespace,
            id: PPNavGeometryID.action(action.id)
        )
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

/// Progress filament at the foot of the expanded stage: 14px track, brand cap.
private struct PPNavContextFilament: View {
    let width: CGFloat
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(PPNavPalette.primaryText.opacity(0.06))
                .frame(height: PPNavSpec.filamentThickness)
                .frame(maxWidth: .infinity)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [PPNavPalette.brand, PPNavPalette.brand.opacity(0.55)],
                        startPoint: layoutDirection == .leftToRight ? .leading : .trailing,
                        endPoint: layoutDirection == .leftToRight ? .trailing : .leading
                    )
                )
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
                onAction: onAction
            )
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Height the host must reserve so arbitrary child content stays below the
    /// single visible navigation owner.
    public var preferredBarHeight: CGFloat {
        PPNavSpec.hostHeight(for: preferredDisplayMode)
    }

    public var preferredDisplayMode: PPNavigationDisplayMode {
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory ||
            (view.bounds.width > 0 && view.bounds.width < PPNavSpec.compactWidthThreshold) {
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

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if appliedDisplayMode != preferredDisplayMode {
            refreshHostedBar()
        }
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
        hostedController.rootView = PPGlobalNavigationBar(
            configuration: configuration,
            collapseProgress: displayMode == .compact ? 1 : 0,
            displayMode: displayMode,
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
            let safeTop = geometry.safeAreaInsets.top
            let progress = (-scrollOffset / collapseDistance).ppClamped()
            let fallbackMode: PPNavigationDisplayMode = dynamicTypeSize.isAccessibilitySize ||
                geometry.size.width < PPNavSpec.compactWidthThreshold ||
                progress >= 0.5 ? .compact : .expanded
            let reserveBase = (displayMode ?? fallbackMode) == .compact
                ? PPNavSpec.compactHeight
                : PPNavSpec.expandedHeight

            ZStack(alignment: .top) {
                PPNavPalette.canvas
                    .ignoresSafeArea()

                ScrollView {
                    PPNavScrollOffsetProbe()
                    content
                        .padding(.top, reserveBase + safeTop)
                }
                // Make the shared shell the single owner of trailing content
                // clearance.  A plain bottom padding ends at the scroll view's
                // frame and can leave the final row beneath the TabView dock or
                // the home indicator; safeAreaInset participates in scrolling
                // and adapts to both containers without a hard-coded tab-bar
                // height.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear
                        .frame(height: 24)
                        .accessibilityHidden(true)
                }
                .coordinateSpace(name: PPNavScrollCoordinateSpace.name)
                .onPreferenceChange(PPNavScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }

                PPGlobalNavigationBar(
                    configuration: configuration,
                    collapseProgress: progress,
                    safeAreaTop: safeTop,
                    onAction: onAction,
                    onDisplayModeChange: { newMode in
                        guard displayMode != newMode else { return }
                        displayMode = newMode
                    }
                )
                .zIndex(10)
            }
            .ignoresSafeArea(edges: .top)
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
