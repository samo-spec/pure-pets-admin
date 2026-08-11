//
//  PPGlobalNavigation.swift
//  PurePetsPro
//
//  Reusable global SwiftUI navigation system.
//  Minimum deployment target: iOS 15.
//  Native Liquid Glass path: iOS 26+ / Swift 6.2+.
//  Earlier systems: semantic Material fallback.
//
//  Public styles:
//  1) commandCrown  — large-title stage + edge-mounted command crown.
//  2) edgeLoom      — vertical semantic seam + woven navigation nodes.
//  3) contextDeck   — layered context planes that consolidate on scroll.
//
//  Design intent:
//  - One navigation owner.
//  - Large title on every screen, including root/main.
//  - One semantic action contract across all styles.
//  - RTL, Dynamic Type, VoiceOver, Reduce Motion.
//  - No business logic and no permission mutation.
//  - Pure Pets Pro colors + Beiruti typography with safe fallbacks.
//

import SwiftUI
import UIKit

// MARK: - Public API

public enum PPGlobalNavigationStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case commandCrown
    case edgeLoom
    case contextDeck

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .commandCrown: return "Command Crown"
        case .edgeLoom: return "Edge Loom"
        case .contextDeck: return "Context Deck"
        }
    }

    fileprivate var expandedHeight: CGFloat {
        switch self {
        case .commandCrown: return 186
        case .edgeLoom: return 206
        case .contextDeck: return 178
        }
    }

    fileprivate var compactHeight: CGFloat {
        switch self {
        case .commandCrown: return 72
        case .edgeLoom: return 78
        case .contextDeck: return 74
        }
    }
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

    public init(
        id: String,
        kind: PPGlobalNavigationActionKind,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        prominence: PPGlobalNavigationActionProminence = .standard,
        badge: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.prominence = prominence
        self.badge = badge
    }

    public static let back = PPGlobalNavigationAction(
        id: "back",
        kind: .back,
        accessibilityLabel: "Back",
        accessibilityHint: "Returns to the previous screen."
    )

    public static let close = PPGlobalNavigationAction(
        id: "close",
        kind: .close,
        accessibilityLabel: "Close",
        accessibilityHint: "Closes this screen."
    )

    public static let refresh = PPGlobalNavigationAction(
        id: "refresh",
        kind: .refresh,
        accessibilityLabel: "Refresh",
        accessibilityHint: "Reloads the current content.",
        prominence: .emphasized
    )

    public static let more = PPGlobalNavigationAction(
        id: "more",
        kind: .more,
        accessibilityLabel: "More actions"
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
        style: PPGlobalNavigationStyle = .commandCrown,
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
}

public typealias PPGlobalNavigationActionHandler = (PPGlobalNavigationAction) -> Void

// MARK: - Brand contract

private enum PPNavPalette {
    static var brand: Color {
        Color(uiColor: UIColor(named: "AppPrimaryClr") ?? UIColor(red: 0.698, green: 0.106, blue: 0.282, alpha: 1))
    }

    static var brandDarker: Color {
        Color(uiColor: UIColor(named: "AppPrimaryClrDarker") ?? UIColor(red: 0.604, green: 0.090, blue: 0.247, alpha: 1))
    }

    static var brandShiner: Color {
        Color(uiColor: UIColor(named: "AppPrimaryClrShiner") ?? UIColor(red: 0.839, green: 0.129, blue: 0.341, alpha: 1))
    }

    static var primaryText: Color {
        Color(uiColor: UIColor(named: "PrimaryTextClr") ?? .label)
    }

    static var secondaryText: Color {
        Color(uiColor: UIColor(named: "SeconderyTextClr") ?? .secondaryLabel)
    }

    static var surface: Color {
        Color(uiColor: UIColor(named: "AppSurfColor") ?? .secondarySystemBackground)
    }

    static var page: Color {
        Color(uiColor: UIColor(named: "PageColor") ?? .systemBackground)
    }

    static var canvas: Color {
        Color(
            uiColor: UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                }
                return UIColor(red: 0.969, green: 0.961, blue: 0.949, alpha: 1)
            }
        )
    }
}


private enum PPNavTypography {
    static func largeTitle(compact: Bool) -> Font {
        let size: CGFloat = compact ? 22 : 38
        if UIFont(name: "Beiruti-Bold", size: size) != nil {
            return .custom("Beiruti-Bold", size: size, relativeTo: compact ? .title2 : .largeTitle)
        }
        return compact
            ? .system(.title2, design: .rounded, weight: .bold)
            : .system(.largeTitle, design: .rounded, weight: .bold)
    }

    static func eyebrow() -> Font {
        if UIFont(name: "Beiruti-Medium", size: 12) != nil {
            return .custom("Beiruti-Medium", size: 12, relativeTo: .caption)
        }
        return .system(.caption, design: .rounded, weight: .semibold)
    }

    static func secondary() -> Font {
        if UIFont(name: "Beiruti-Regular", size: 14) != nil {
            return .custom("Beiruti-Regular", size: 14, relativeTo: .subheadline)
        }
        return .system(.subheadline, design: .rounded, weight: .regular)
    }

    static func action() -> Font {
        .system(size: 16, weight: .semibold, design: .rounded)
    }
}

// MARK: - Public navigation bar

public struct PPGlobalNavigationBar: View {
    public let configuration: PPGlobalNavigationConfiguration
    public let collapseProgress: CGFloat
    public let safeAreaTop: CGFloat
    public let onAction: PPGlobalNavigationActionHandler

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var glassNamespace

    public init(
        configuration: PPGlobalNavigationConfiguration,
        collapseProgress: CGFloat = 0,
        safeAreaTop: CGFloat = 0,
        onAction: @escaping PPGlobalNavigationActionHandler
    ) {
        self.configuration = configuration
        self.collapseProgress = collapseProgress.clamped(to: 0...1)
        self.safeAreaTop = max(0, safeAreaTop)
        self.onAction = onAction
    }

    public var body: some View {
        let progress = effectiveProgress

        Group {
            switch configuration.style {
            case .commandCrown:
                PPCommandCrownNavigation(
                    configuration: configuration,
                    progress: progress,
                    safeAreaTop: safeAreaTop,
                    layoutDirection: layoutDirection,
                    namespace: glassNamespace,
                    onAction: onAction
                )
            case .edgeLoom:
                PPEdgeLoomNavigation(
                    configuration: configuration,
                    progress: progress,
                    safeAreaTop: safeAreaTop,
                    layoutDirection: layoutDirection,
                    namespace: glassNamespace,
                    onAction: onAction
                )
            case .contextDeck:
                PPContextDeckNavigation(
                    configuration: configuration,
                    progress: progress,
                    safeAreaTop: safeAreaTop,
                    layoutDirection: layoutDirection,
                    namespace: glassNamespace,
                    onAction: onAction
                )
            }
        }
        .frame(height: barHeight(for: progress), alignment: .top)
        .animation(
            reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86, blendDuration: 0.08),
            value: configuration.style
        )
        .animation(
            reduceMotion ? nil : .interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.05),
            value: progress
        )
        .accessibilityElement(children: .contain)
    }

    private var effectiveProgress: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 1
        }
        return collapseProgress
    }

    private func barHeight(for progress: CGFloat) -> CGFloat {
        let expanded = configuration.style.expandedHeight + safeAreaTop
        let compact = configuration.style.compactHeight + safeAreaTop
        return expanded.interpolated(to: compact, progress: progress)
    }
}

// MARK: - Convenience scroll shell

public struct PPGlobalNavigationScrollShell<Content: View>: View {
    public let configuration: PPGlobalNavigationConfiguration
    public let collapseDistance: CGFloat
    public let onAction: PPGlobalNavigationActionHandler
    private let content: Content

    @State private var scrollOffset: CGFloat = 0
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
            let progress = min(max(-scrollOffset / collapseDistance, 0), 1)
            let reserveBase = dynamicTypeSize.isAccessibilitySize
                ? configuration.style.compactHeight
                : configuration.style.expandedHeight
            let reserve = reserveBase + safeTop

            ZStack(alignment: .top) {
                PPNavPalette.canvas
                    .ignoresSafeArea()

                ScrollView {
                    PPNavScrollOffsetProbe()
                    content
                        .padding(.top, reserve)
                        .padding(.bottom, 24)
                }
                .coordinateSpace(name: PPNavScrollCoordinateSpace.name)
                .onPreferenceChange(PPNavScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }

                PPGlobalNavigationBar(
                    configuration: configuration,
                    collapseProgress: progress,
                    safeAreaTop: safeTop,
                    onAction: onAction
                )
                .zIndex(10)
            }
            .ignoresSafeArea(edges: .top)
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Style 1: Command Crown

private struct PPCommandCrownNavigation: View {
    let configuration: PPGlobalNavigationConfiguration
    let progress: CGFloat
    let safeAreaTop: CGFloat
    let layoutDirection: LayoutDirection
    let namespace: Namespace.ID
    let onAction: PPGlobalNavigationActionHandler

    var body: some View {
        ZStack(alignment: .top) {
            PPAmbientField(progress: progress)

            PPTitleCluster(
                configuration: configuration,
                progress: progress,
                alignment: .leading,
                style: .commandCrown
            )
            .padding(.top, safeAreaTop + titleTop)
            .padding(.leading, titleLeading)
            .padding(.trailing, 92)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let leading = configuration.leadingAction {
                PPCommandPearl(
                    action: leading,
                    progress: progress,
                    layoutDirection: layoutDirection,
                    namespace: namespace,
                    onAction: onAction
                )
                .padding(.top, safeAreaTop + pearlTop)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: pearlOffsetX)
            }

            PPCommandCrown(
                configuration: configuration,
                progress: progress,
                layoutDirection: layoutDirection,
                namespace: namespace,
                onAction: onAction
            )
            .padding(.top, safeAreaTop + crownTop)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .offset(x: crownEdgeOffset)

            if configuration.showsContextFilament {
                PPContextFilament(progress: progress)
                    .padding(.horizontal, progress > 0.75 ? 0 : 22)
                    .padding(.top, safeAreaTop + filamentTop)
            }
        }
        .background(
            progress > 0.72
                ? PPNavPalette.canvas.opacity(0.88)
                : Color.clear
        )
    }

    private var titleTop: CGFloat { 48.interpolated(to: 24, progress: progress) }
    private var titleLeading: CGFloat { 22.interpolated(to: configuration.leadingAction == nil ? 18 : 70, progress: progress) }
    private var crownTop: CGFloat { 24.interpolated(to: 18, progress: progress) }
    private var pearlTop: CGFloat { 132.interpolated(to: 18, progress: progress) }
    private var filamentTop: CGFloat { 170.interpolated(to: 68, progress: progress) }
    private var crownEdgeOffset: CGFloat { layoutDirection == .leftToRight ? 9 : -9 }
    private var pearlOffsetX: CGFloat { layoutDirection == .leftToRight ? -8 : 8 }
}

private struct PPCommandCrown: View {
    let configuration: PPGlobalNavigationConfiguration
    let progress: CGFloat
    let layoutDirection: LayoutDirection
    let namespace: Namespace.ID
    let onAction: PPGlobalNavigationActionHandler

    var body: some View {
        PPGlassContainer(spacing: 7) {
            HStack(spacing: 7) {
                if let status = configuration.status, progress < 0.78 {
                    PPStatusReadout(status: status)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                ForEach(configuration.trailingActions) { action in
                    PPNavActionButton(
                        action: action,
                        diameter: 44.interpolated(to: 40, progress: progress),
                        shape: .softSquare,
                        namespace: namespace,
                        glassID: "crown.\(action.id)",
                        onAction: onAction
                    )
                }
            }
            .padding(.leading, progress < 0.78 ? 12 : 7)
            .padding(.trailing, 13)
            .padding(.vertical, 8)
            .ppGlassSurface(
                shape: PPCrownShape(flatEdge: layoutDirection == .leftToRight ? .right : .left),
                interactive: false,
                tint: nil,
                namespace: namespace,
                id: "command-crown"
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PPCommandPearl: View {
    let action: PPGlobalNavigationAction
    let progress: CGFloat
    let layoutDirection: LayoutDirection
    let namespace: Namespace.ID
    let onAction: PPGlobalNavigationActionHandler

    var body: some View {
        PPNavActionButton(
            action: action,
            diameter: 54.interpolated(to: 46, progress: progress),
            shape: .circle,
            namespace: namespace,
            glassID: "navigation-pearl",
            onAction: onAction
        )
    }
}

// MARK: - Style 2: Edge Loom

private struct PPEdgeLoomNavigation: View {
    let configuration: PPGlobalNavigationConfiguration
    let progress: CGFloat
    let safeAreaTop: CGFloat
    let layoutDirection: LayoutDirection
    let namespace: Namespace.ID
    let onAction: PPGlobalNavigationActionHandler

    var body: some View {
        ZStack(alignment: .top) {
            PPAmbientField(progress: progress * 0.6)

            PPEdgeLoomThread(
                progress: progress,
                safeAreaTop: safeAreaTop,
                layoutDirection: layoutDirection
            )

            VStack(alignment: .leading, spacing: 0) {
                if let leading = configuration.leadingAction {
                    PPNavActionButton(
                        action: leading,
                        diameter: 46,
                        shape: .circle,
                        namespace: namespace,
                        glassID: "loom.navigation",
                        onAction: onAction
                    )
                    .offset(x: layoutDirection == .leftToRight ? -16 : 16)
                    .padding(.bottom, 10)
                }

                if progress < 0.76 {
                    PPLoomContextKnot(status: configuration.status)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }

                if progress < 0.62 {
                    VStack(spacing: 9) {
                        ForEach(configuration.trailingActions) { action in
                            PPNavActionButton(
                                action: action,
                                diameter: 39,
                                shape: .softSquare,
                                namespace: namespace,
                                glassID: "loom.\(action.id)",
                                onAction: onAction
                            )
                        }
                    }
                    .padding(.top, 18)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                }
            }
            .padding(.top, safeAreaTop + 22.interpolated(to: 13, progress: progress))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 7)

            PPTitleCluster(
                configuration: configuration,
                progress: progress,
                alignment: .leading,
                style: .edgeLoom
            )
            .padding(.top, safeAreaTop + 28.interpolated(to: 20, progress: progress))
            .padding(.leading, 58.interpolated(to: 66, progress: progress))
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, alignment: .leading)

            if progress > 0.48 {
                HStack(spacing: 7) {
                    ForEach(configuration.trailingActions) { action in
                        PPNavActionButton(
                            action: action,
                            diameter: 39,
                            shape: .softSquare,
                            namespace: namespace,
                            glassID: "loom.compact.\(action.id)",
                            onAction: onAction
                        )
                    }
                }
                .padding(.top, safeAreaTop + 17)
                .padding(.trailing, 13)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity((progress - 0.48) / 0.52)
            }
        }
        .background(progress > 0.78 ? PPNavPalette.canvas.opacity(0.9) : Color.clear)
    }
}

private struct PPEdgeLoomThread: View {
    let progress: CGFloat
    let safeAreaTop: CGFloat
    let layoutDirection: LayoutDirection

    var body: some View {
        GeometryReader { proxy in
            let x: CGFloat = layoutDirection == .leftToRight ? 26 : proxy.size.width - 26
            let bottom = (176 - 98 * progress) + safeAreaTop

            Path { path in
                path.move(to: CGPoint(x: x, y: safeAreaTop + 6))
                path.addCurve(
                    to: CGPoint(x: x, y: bottom),
                    control1: CGPoint(x: x + directional(2), y: safeAreaTop + 44),
                    control2: CGPoint(x: x - directional(4), y: bottom - 48)
                )
            }
            .stroke(
                LinearGradient(
                    colors: [
                        PPNavPalette.brand,
                        PPNavPalette.brand.opacity(0.25),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
        }
        .allowsHitTesting(false)
    }

    private func directional(_ value: CGFloat) -> CGFloat {
        layoutDirection == .leftToRight ? value : -value
    }
}

private struct PPLoomContextKnot: View {
    let status: PPGlobalNavigationStatus?

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(PPNavPalette.brand.opacity(0.13))
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(PPNavPalette.brand)
                    .frame(width: 7, height: 7)
            }

            if let status {
                VStack(alignment: .leading, spacing: 0) {
                    Text(status.label)
                        .font(PPNavTypography.eyebrow())
                        .foregroundStyle(PPNavPalette.primaryText)
                    if let detail = status.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(PPNavPalette.secondaryText)
                    }
                }
            }
        }
        .offset(x: -2)
    }
}

// MARK: - Style 3: Context Deck

private struct PPContextDeckNavigation: View {
    let configuration: PPGlobalNavigationConfiguration
    let progress: CGFloat
    let safeAreaTop: CGFloat
    let layoutDirection: LayoutDirection
    let namespace: Namespace.ID
    let onAction: PPGlobalNavigationActionHandler

    var body: some View {
        ZStack(alignment: .top) {
            PPAmbientField(progress: progress * 0.45)

            PPContextDeckBackPlane(
                depth: 2,
                progress: progress,
                tint: PPNavPalette.brand.opacity(0.055)
            )
            .padding(.top, safeAreaTop + 24.interpolated(to: 13, progress: progress))
            .padding(.horizontal, 23.interpolated(to: 13, progress: progress))

            PPContextDeckBackPlane(
                depth: 1,
                progress: progress,
                tint: PPNavPalette.brand.opacity(0.085)
            )
            .padding(.top, safeAreaTop + 19.interpolated(to: 12, progress: progress))
            .padding(.horizontal, 18.interpolated(to: 12, progress: progress))

            PPGlassContainer(spacing: 8) {
                ZStack(alignment: .leading) {
                    PPTitleCluster(
                        configuration: configuration,
                        progress: progress,
                        alignment: .leading,
                        style: .contextDeck
                    )
                    .padding(.leading, configuration.leadingAction == nil ? 18 : 58)
                    .padding(.trailing, actionReserve)
                    .padding(.vertical, 15)

                    if let leading = configuration.leadingAction {
                        PPNavActionButton(
                            action: leading,
                            diameter: 44,
                            shape: .deckTab,
                            namespace: namespace,
                            glassID: "deck.navigation",
                            onAction: onAction
                        )
                        .offset(x: layoutDirection == .leftToRight ? -12 : 12)
                    }

                    HStack(spacing: 6) {
                        ForEach(configuration.trailingActions) { action in
                            PPNavActionButton(
                                action: action,
                                diameter: 41,
                                shape: .circle,
                                namespace: namespace,
                                glassID: "deck.\(action.id)",
                                onAction: onAction
                            )
                        }
                    }
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .ppGlassSurface(
                    shape: RoundedRectangle(cornerRadius: 29.interpolated(to: 24, progress: progress), style: .continuous),
                    interactive: false,
                    tint: nil,
                    namespace: namespace,
                    id: "context-deck-front"
                )
            }
            .padding(.top, safeAreaTop + 14.interpolated(to: 8, progress: progress))
            .padding(.horizontal, 13.interpolated(to: 9, progress: progress))

            if let status = configuration.status, progress < 0.7 {
                PPDeckStatusTab(status: status)
                    .padding(.top, safeAreaTop + 132)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 24)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .background(progress > 0.8 ? PPNavPalette.canvas.opacity(0.9) : Color.clear)
    }

    private var actionReserve: CGFloat {
        CGFloat(max(configuration.trailingActions.count, 1)) * 47 + 16
    }
}

private struct PPContextDeckBackPlane: View {
    let depth: Int
    let progress: CGFloat
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(tint)
            .frame(height: 124.interpolated(to: 57, progress: progress))
            .rotationEffect(
                .degrees(
                    (depth == 1 ? 1.1 : -1.5) * Double(1 - progress)
                )
            )
            .opacity(1 - 0.82 * progress)
            .allowsHitTesting(false)
    }
}

private struct PPDeckStatusTab: View {
    let status: PPGlobalNavigationStatus

    var body: some View {
        HStack(spacing: 7) {
            if status.isLive {
                Circle()
                    .fill(PPNavPalette.brand)
                    .frame(width: 7, height: 7)
            }

            Text(status.label)
                .font(PPNavTypography.eyebrow())

            if let detail = status.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(PPNavPalette.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(PPNavPalette.surface.opacity(0.88), in: Capsule())
        .overlay(Capsule().strokeBorder(PPNavPalette.primaryText.opacity(0.06)))
    }
}

// MARK: - Shared title + context

private enum PPTitleClusterStyle {
    case commandCrown
    case edgeLoom
    case contextDeck
}

private struct PPTitleCluster: View {
    let configuration: PPGlobalNavigationConfiguration
    let progress: CGFloat
    let alignment: HorizontalAlignment
    let style: PPTitleClusterStyle

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            if let eyebrow = configuration.eyebrow, progress < 0.72 {
                Text(eyebrow.uppercased())
                    .font(PPNavTypography.eyebrow())
                    .tracking(1.2)
                    .foregroundStyle(PPNavPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .transition(.opacity)
            }

            Text(configuration.title)
                .font(PPNavTypography.largeTitle(compact: progress > 0.55))
                .foregroundStyle(PPNavPalette.primaryText)
                .lineLimit(progress > 0.55 ? 1 : 2)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, progress < 0.72 && configuration.eyebrow != nil ? 4 : 0)

            if let subtitle = configuration.subtitle, progress < 0.66 {
                Text(subtitle)
                    .font(PPNavTypography.secondary())
                    .foregroundStyle(PPNavPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.top, 5)
                    .transition(.opacity)
            }

            if let context = configuration.context, style == .edgeLoom, progress < 0.5 {
                Text(context)
                    .font(.caption2)
                    .foregroundStyle(PPNavPalette.brand)
                    .lineLimit(1)
                    .padding(.top, 6)
            }
        }
    }
}

// MARK: - Shared actions

private enum PPNavActionShape {
    case circle
    case softSquare
    case deckTab
}

private struct PPNavActionContainerShape: InsettableShape {
    let kind: PPNavActionShape
    let cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .circle:
            return Circle()
                .inset(by: insetAmount)
                .path(in: rect)
        case .softSquare:
            return RoundedRectangle(
                cornerRadius: max(8, cornerRadius - insetAmount),
                style: .continuous
            )
            .inset(by: insetAmount)
            .path(in: rect)
        case .deckTab:
            return RoundedRectangle(
                cornerRadius: max(8, 15 - insetAmount),
                style: .continuous
            )
            .inset(by: insetAmount)
            .path(in: rect)
        }
    }

    func inset(by amount: CGFloat) -> PPNavActionContainerShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct PPNavActionButton: View {
    let action: PPGlobalNavigationAction
    let diameter: CGFloat
    let shape: PPNavActionShape
    let namespace: Namespace.ID
    let glassID: String
    let onAction: PPGlobalNavigationActionHandler

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            performHaptic()
            onAction(action)
        } label: {
            ZStack(alignment: .topTrailing) {
                PPNavigationGlyph(kind: action.kind, layoutDirection: layoutDirection)
                    .frame(width: 21, height: 21)
                    .foregroundStyle(foreground)

                if let badge = action.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(PPNavPalette.brandDarker, in: Capsule())
                        .offset(x: 8, y: -8)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ppInteractiveGlass(
            shape: buttonShape,
            tint: tint,
            namespace: namespace,
            id: glassID
        )
        .accessibilityLabel(Text(action.accessibilityLabel))
        .accessibilityHint(action.accessibilityHint.map(Text.init) ?? Text(""))
        .accessibilityValue(action.badge.map { Text($0) } ?? Text(""))
    }

    private var buttonShape: PPNavActionContainerShape {
        PPNavActionContainerShape(kind: shape, cornerRadius: max(14, diameter * 0.38))
    }

    private var tint: Color? {
        switch action.prominence {
        case .emphasized:
            return PPNavPalette.brand
        case .standard, .quiet:
            return nil
        }
    }

    private var foreground: Color {
        switch action.prominence {
        case .emphasized:
            return .white
        case .standard:
            return PPNavPalette.primaryText
        case .quiet:
            return PPNavPalette.secondaryText
        }
    }

    private func performHaptic() {
        guard !reduceMotion else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Custom navigation glyph layer
//
// Conventional controls keep conventional semantics.
// Proprietary concepts (Capability Lens / Command) get distinctive geometry.

private struct PPNavigationGlyph: View {
    let kind: PPGlobalNavigationActionKind
    let layoutDirection: LayoutDirection

    var body: some View {
        switch kind {
        case .back:
            PPChevronGlyph(pointsForward: false, layoutDirection: layoutDirection)
        case .close:
            PPCloseGlyph()
        case .refresh:
            PPRefreshGlyph()
        case .more:
            PPMoreGlyph()
        case .profile:
            PPProfileGlyph()
        case .capabilityLens:
            PPCapabilityLensGlyph()
        case .command:
            PPCommandGlyph()
        case .notifications:
            Image(systemName: "bell")
                .font(PPNavTypography.action())
        case .custom(let symbol):
            Image(systemName: symbol)
                .font(PPNavTypography.action())
        }
    }
}

private struct PPChevronGlyph: View {
    let pointsForward: Bool
    let layoutDirection: LayoutDirection

    var body: some View {
        GeometryReader { proxy in
            let shouldPointRight = pointsForward
                ? layoutDirection == .leftToRight
                : layoutDirection == .rightToLeft

            Path { path in
                let w = proxy.size.width
                let h = proxy.size.height
                let x1 = shouldPointRight ? w * 0.36 : w * 0.64
                let x2 = shouldPointRight ? w * 0.66 : w * 0.34

                path.move(to: CGPoint(x: x1, y: h * 0.2))
                path.addLine(to: CGPoint(x: x2, y: h * 0.5))
                path.addLine(to: CGPoint(x: x1, y: h * 0.8))
            }
            .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct PPCloseGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: proxy.size.width * 0.26, y: proxy.size.height * 0.26))
                path.addLine(to: CGPoint(x: proxy.size.width * 0.74, y: proxy.size.height * 0.74))
                path.move(to: CGPoint(x: proxy.size.width * 0.74, y: proxy.size.height * 0.26))
                path.addLine(to: CGPoint(x: proxy.size.width * 0.26, y: proxy.size.height * 0.74))
            }
            .stroke(style: StrokeStyle(lineWidth: 2.05, lineCap: .round))
        }
    }
}

private struct PPRefreshGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(
                x: proxy.size.width * 0.18,
                y: proxy.size.height * 0.18,
                width: proxy.size.width * 0.64,
                height: proxy.size.height * 0.64
            )

            ZStack {
                Path { path in
                    path.addArc(
                        center: CGPoint(x: rect.midX, y: rect.midY),
                        radius: rect.width * 0.45,
                        startAngle: .degrees(-72),
                        endAngle: .degrees(212),
                        clockwise: false
                    )
                }
                .stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY - 2))
                    path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.minY + 4))
                    path.addLine(to: CGPoint(x: rect.minX + 10, y: rect.minY + 7))
                }
                .stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct PPMoreGlyph: View {
    var body: some View {
        HStack(spacing: 3.2) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().frame(width: 3.2, height: 3.2)
            }
        }
    }
}

private struct PPProfileGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let w = proxy.size.width
                let h = proxy.size.height
                path.addEllipse(in: CGRect(x: w * 0.35, y: h * 0.14, width: w * 0.3, height: w * 0.3))
                path.addArc(
                    center: CGPoint(x: w * 0.5, y: h * 0.82),
                    radius: w * 0.31,
                    startAngle: .degrees(205),
                    endAngle: .degrees(335),
                    clockwise: false
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct PPCapabilityLensGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Circle()
                    .stroke(lineWidth: 1.7)
                    .frame(width: w * 0.62, height: h * 0.62)
                    .offset(x: -w * 0.08)

                Circle()
                    .trim(from: 0.08, to: 0.82)
                    .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                    .frame(width: w * 0.42, height: h * 0.42)
                    .offset(x: w * 0.18, y: h * 0.12)

                Capsule()
                    .frame(width: w * 0.28, height: 1.8)
                    .rotationEffect(.degrees(42))
                    .offset(x: w * 0.28, y: h * 0.27)
            }
        }
    }
}

private struct PPCommandGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { path in
                let r = min(w, h) * 0.18
                let left = w * 0.31
                let right = w * 0.69
                let top = h * 0.31
                let bottom = h * 0.69

                path.addArc(center: CGPoint(x: left, y: top), radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
                path.addLine(to: CGPoint(x: right, y: top - r))
                path.addArc(center: CGPoint(x: right, y: top), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
                path.addLine(to: CGPoint(x: right + r, y: bottom))
                path.addArc(center: CGPoint(x: right, y: bottom), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                path.addLine(to: CGPoint(x: left, y: bottom + r))
                path.addArc(center: CGPoint(x: left, y: bottom), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
                path.addLine(to: CGPoint(x: left - r, y: top))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Shared material system

private struct PPAmbientField: View {
    let progress: CGFloat

    var body: some View {
        LinearGradient(
            colors: [
                PPNavPalette.brand.opacity(0.09 * (1 - progress)),
                PPNavPalette.brandShiner.opacity(0.025 * (1 - progress)),
                .clear
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
        .allowsHitTesting(false)
    }
}

private struct PPStatusReadout: View {
    let status: PPGlobalNavigationStatus

    var body: some View {
        HStack(spacing: 7) {
            if status.isLive {
                ZStack {
                    Circle()
                        .fill(PPNavPalette.brand.opacity(0.13))
                        .frame(width: 18, height: 18)
                    Circle()
                        .fill(PPNavPalette.brand)
                        .frame(width: 6, height: 6)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(status.label)
                    .font(PPNavTypography.eyebrow())
                    .foregroundStyle(PPNavPalette.primaryText)
                    .lineLimit(1)

                if let detail = status.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(PPNavPalette.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PPContextFilament: View {
    let progress: CGFloat
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(PPNavPalette.primaryText.opacity(0.05))
                    .frame(height: 1)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [PPNavPalette.brand, PPNavPalette.brand.opacity(0)],
                            startPoint: layoutDirection == .leftToRight ? .leading : .trailing,
                            endPoint: layoutDirection == .leftToRight ? .trailing : .leading
                        )
                    )
                    .frame(width: max(38, proxy.size.width * (0.21 - 0.12 * progress)), height: 2.5)
            }
        }
        .frame(height: 3)
        .allowsHitTesting(false)
    }
}

private enum PPCrownFlatEdge {
    case left
    case right
}

private struct PPCrownShape: InsettableShape {
    let flatEdge: PPCrownFlatEdge
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let radius = max(14, min(27, rect.height * 0.43) - insetAmount)
        let minX = rect.minX + insetAmount
        let maxX = rect.maxX - insetAmount
        let minY = rect.minY + insetAmount
        let maxY = rect.maxY - insetAmount

        var path = Path()

        switch flatEdge {
        case .right:
            path.move(to: CGPoint(x: minX + radius, y: minY))
            path.addLine(to: CGPoint(x: maxX, y: minY))
            path.addLine(to: CGPoint(x: maxX, y: maxY))
            path.addLine(to: CGPoint(x: minX + radius, y: maxY))
            path.addQuadCurve(
                to: CGPoint(x: minX, y: maxY - radius),
                control: CGPoint(x: minX, y: maxY)
            )
            path.addLine(to: CGPoint(x: minX, y: minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: minX + radius, y: minY),
                control: CGPoint(x: minX, y: minY)
            )

        case .left:
            path.move(to: CGPoint(x: minX, y: minY))
            path.addLine(to: CGPoint(x: maxX - radius, y: minY))
            path.addQuadCurve(
                to: CGPoint(x: maxX, y: minY + radius),
                control: CGPoint(x: maxX, y: minY)
            )
            path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: maxX - radius, y: maxY),
                control: CGPoint(x: maxX, y: maxY)
            )
            path.addLine(to: CGPoint(x: minX, y: maxY))
        }

        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> PPCrownShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct PPGlassContainer<Content: View>: View {
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
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
#else
        content
#endif
    }
}

private extension View {
    @ViewBuilder
    func ppGlassSurface<S: InsettableShape>(
        shape: S,
        interactive: Bool,
        tint: Color?,
        namespace: Namespace.ID,
        id: String
    ) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if let tint {
                self
                    .glassEffect(
                        interactive
                            ? .regular.tint(tint).interactive()
                            : .regular.tint(tint),
                        in: shape
                    )
                    .glassEffectID(id, in: namespace)
            } else {
                self
                    .glassEffect(
                        interactive
                            ? .regular.interactive()
                            : .regular,
                        in: shape
                    )
                    .glassEffectID(id, in: namespace)
            }
        } else {
            fallbackGlass(shape: shape, tint: tint)
        }
#else
        fallbackGlass(shape: shape, tint: tint)
#endif
    }

    @ViewBuilder
    func ppInteractiveGlass<S: InsettableShape>(
        shape: S,
        tint: Color?,
        namespace: Namespace.ID,
        id: String
    ) -> some View {
        ppGlassSurface(
            shape: shape,
            interactive: true,
            tint: tint,
            namespace: namespace,
            id: id
        )
    }

    func fallbackGlass<S: InsettableShape>(
        shape: S,
        tint: Color?
    ) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .background((tint ?? Color.clear).opacity(tint == nil ? 0 : 0.84), in: shape)
            .overlay(
                shape.strokeBorder(
                    Color.primary.opacity(tint == nil ? 0.08 : 0.035),
                    lineWidth: 0.7
                )
            )
    }
}

// MARK: - Scroll offset

private enum PPNavScrollCoordinateSpace {
    static let name = "PPGlobalNavigationScrollSpace"
}

private struct PPNavScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

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
    public var style: PPGlobalNavigationStyleObjC = .commandCrown
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

// MARK: - Demo / Preview fixtures

#if DEBUG
private struct PPGlobalNavigationDemo: View {
    @State private var style: PPGlobalNavigationStyle = .commandCrown

    var body: some View {
        VStack(spacing: 0) {
            Picker("Navigation style", selection: $style) {
                ForEach(PPGlobalNavigationStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            PPGlobalNavigationScrollShell(
                configuration: configuration,
                onAction: { _ in }
            ) {
                VStack(spacing: 12) {
                    ForEach(0..<12, id: \.self) { index in
                        HStack {
                            Text(index == 0 ? "Overview" : "Operational row \(index)")
                                .font(.body)
                            Spacer()
                            Text(index == 0 ? "Processing" : "\(index * 3)")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 18)
                        .frame(minHeight: 62)
                        .background(
                            PPNavPalette.surface.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var configuration: PPGlobalNavigationConfiguration {
        PPGlobalNavigationConfiguration(
            style: style,
            title: "Payment Details",
            eyebrow: "Marketplace · Orders",
            subtitle: "PP-260801-RMMRU4",
            context: "Processing",
            status: .init(label: "Order", detail: "Processing", isLive: true),
            leadingAction: .back,
            trailingActions: [
                .refresh,
                .more
            ]
        )
    }
}

#Preview("Pure Pets Pro — Global Navigation") {
    PPGlobalNavigationDemo()
}
#endif

// MARK: - Math helpers

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(self, range.lowerBound), range.upperBound)
    }

    func interpolated(to target: CGFloat, progress: CGFloat) -> CGFloat {
        self + (target - self) * progress.clamped(to: 0...1)
    }
}
