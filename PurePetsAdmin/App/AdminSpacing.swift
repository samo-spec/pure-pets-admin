//  AdminSpacing.swift — Core design system tokens for NextGen V6 SwiftUI rebuild.
//  Bridges PPDesignTokens.h UIKit constants into SwiftUI-native values.

import SwiftUI

// MARK: - Spacing (8pt Grid)

enum AdminSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let base: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let screenMargin: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 24
    static let groupSpacing: CGFloat = 20
    static let rowMinimumHeight: CGFloat = 52
    static let cornerRadiusSmall: CGFloat = AdminRadius.small
    static let cornerRadiusMedium: CGFloat = AdminRadius.medium
    static let cornerRadiusLarge: CGFloat = AdminRadius.large
    static let cornerRadiusCard: CGFloat = AdminRadius.card
}

// MARK: - Corner Radii

enum AdminRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let card: CGFloat = 16
    static let large: CGFloat = 20
    static let hero: CGFloat = 24
    static let pill: CGFloat = 999
    static let button: CGFloat = 14
}

// MARK: - Touch Targets

enum AdminTouchTarget {
    static let minimum: CGFloat = 44
    static let comfortable: CGFloat = 48
    static let inputField: CGFloat = 48
    static let expanded: CGFloat = 48
}

// MARK: - Animation

enum AdminAnimation {
    static let fast = Animation.easeOut(duration: 0.15)
    static let standard = Animation.spring(response: 0.3, dampingFraction: 0.75)
    static let slow = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let pressScale: CGFloat = 0.97

    // MARK: List & screen choreography
    //
    // One vocabulary for entrance, filtering, row reveal and disclosure, so a
    // screen does not accumulate a dozen unrelated magic springs. Before this,
    // `PPInventoryListView` alone held 77 animation call sites with 14 distinct
    // curves — including two *different* animations driving the same disclosure
    // gesture, which fought each other on every tap.

    /// Sections settling into place on first appearance. Slightly softer and
    /// longer than `standard`: this is the one moment the operator is reading
    /// rather than acting, so it can afford to be felt.
    static let screenEntrance = Animation.spring(response: 0.46, dampingFraction: 0.86)

    /// One row arriving. Quicker than `screenEntrance` because several play in
    /// sequence and the total must stay under roughly a third of a second.
    static let rowReveal = Animation.spring(response: 0.34, dampingFraction: 0.84)

    /// Swapping list content when a filter changes. Deliberately not a spring:
    /// a filter is a *replacement*, and overshoot reads as the old content
    /// bouncing back rather than new content arriving.
    static let filterSwap = Animation.easeOut(duration: 0.22)

    /// Disclosure — expanding or collapsing a group row. The single source of
    /// truth for that gesture; a caller must not wrap it in another animation.
    static let disclosure = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// Per-row delay when a group of rows reveals together.
    static let rowStagger: Double = 0.035

    /// Rows after this index appear without delay. Staggering an unbounded list
    /// makes the last row wait on arithmetic the operator never asked for; the
    /// effect is only legible for the first screenful anyway.
    static let maxStaggeredRows: Int = 6

    /// Distance a section or row travels while arriving. Small on purpose —
    /// large translations read as decoration on a dense operational screen.
    static let entranceOffset: CGFloat = 10

    /// Resolves an animation against Reduce Motion in one place, so honouring
    /// the setting is structural rather than something each call site has to
    /// remember. Only 8 of the 77 sites in the inventory screen did remember.
    static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Stagger delay for a row, collapsing to zero under Reduce Motion.
    static func staggerDelay(index: Int, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        return Double(min(index, maxStaggeredRows)) * rowStagger
    }
}

// MARK: - Shadow

enum AdminShadow {
    static let card: (color: Color, radius: CGFloat, y: CGFloat) = (.black.opacity(0.06), 8, 2)
    static let elevated: (color: Color, radius: CGFloat, y: CGFloat) = (.black.opacity(0.10), 16, 4)
    static let navigation: (color: Color, radius: CGFloat, y: CGFloat) = (.black.opacity(0.04), 4, 1)
}

// MARK: - Icon Sizes

enum AdminIconSize {
    static let small: CGFloat = 16
    static let medium: CGFloat = 20
    static let large: CGFloat = 24
    static let xl: CGFloat = 32
    static let hero: CGFloat = 44
}

// MARK: - Opacity

enum AdminOpacity {
    static let disabled: Double = 0.38
    static let secondary: Double = 0.60
    static let subtleBackground: Double = 0.07
    static let pressedOverlay: Double = 0.12
}

// MARK: - Stroke

enum AdminStroke {
    static let hairline: CGFloat = 0.5
    static let thin: CGFloat = 1.0
    static let medium: CGFloat = 1.5
}


// MARK: - List & Screen Entrance Modifiers

/// Rises a section into place as part of a screen's one-shot entrance.
///
/// `step` orders the sections top to bottom so the screen assembles in reading
/// order — header, then context, then content — which is what makes the entrance
/// feel authored rather than like several independent things fading in.
private struct AdminEntranceModifier: ViewModifier {
    let step: Int
    let hasAppeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        // Under Reduce Motion the view is returned untouched. Applying a
        // zero-duration animation still costs a layout pass and can still flash
        // opacity on slower devices.
        if reduceMotion {
            content
        } else {
            content
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : AdminAnimation.entranceOffset)
                .animation(
                    AdminAnimation.screenEntrance.delay(
                        AdminAnimation.staggerDelay(index: step, reduceMotion: false)
                    ),
                    value: hasAppeared
                )
        }
    }
}

/// Registry that remembers cell identities that have completed their display animation
/// during a browsing session, preventing recycled cells from flickering or re-animating
/// when scrolling back up in a `LazyVStack` or `LazyVGrid`.
public final class AdminCellDisplayRegistry: @unchecked Sendable {
    public static let shared = AdminCellDisplayRegistry()
    private var displayedKeys = Set<String>()
    private let lock = NSLock()

    private init() {}

    public func hasDisplayed(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return displayedKeys.contains(key)
    }

    public func markDisplayed(key: String) {
        lock.lock()
        defer { lock.unlock() }
        displayedKeys.insert(key)
    }

    public func clear(prefix: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let prefix = prefix {
            displayedKeys = displayedKeys.filter { !$0.hasPrefix(prefix) }
        } else {
            displayedKeys.removeAll()
        }
    }
}

/// Animates a cell when it is displayed in an inventory list or grid.
///
/// Features:
/// - Staggers arrival for initial viewport items (smooth waterfall).
/// - Instantly animates scrolled-into-view items on appearance without trailing lag.
/// - Fluid Apple spring with subtle upward translation, gentle scale (0.985 -> 1.0), and opacity fade.
/// - Once displayed, remains stably settled at identity (no scroll jitter or flash).
/// - Immediately settles without animation under Reduce Motion.
public struct AdminCellDisplayModifier: ViewModifier {
    let id: String?
    let index: Int
    let baseDelay: Double
    let maxStaggeredIndex: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasDisplayed: Bool = false

    public init(
        id: String? = nil,
        index: Int = 0,
        baseDelay: Double = 0.0,
        maxStaggeredIndex: Int = 6
    ) {
        self.id = id
        self.index = index
        self.baseDelay = baseDelay
        self.maxStaggeredIndex = maxStaggeredIndex
    }

    public func body(content: Content) -> some View {
        let isAlreadyRecorded = id.map { AdminCellDisplayRegistry.shared.hasDisplayed(key: $0) } ?? false
        let isSettled = reduceMotion || hasDisplayed || isAlreadyRecorded

        if isSettled {
            content
        } else {
            content
                .opacity(hasDisplayed ? 1.0 : 0.0)
                .offset(y: hasDisplayed ? 0 : AdminAnimation.entranceOffset)
                .scaleEffect(hasDisplayed ? 1.0 : 0.985)
                .onAppear {
                    guard !hasDisplayed else { return }
                    if let id = id {
                        AdminCellDisplayRegistry.shared.markDisplayed(key: id)
                    }
                    let stagger: Double = {
                        if index < maxStaggeredIndex {
                            return baseDelay + Double(index) * AdminAnimation.rowStagger
                        } else {
                            return 0.0
                        }
                    }()
                    withAnimation(AdminAnimation.rowReveal.delay(stagger)) {
                        hasDisplayed = true
                    }
                }
        }
    }
}

/// Compatibility bridge for row-level reveal.
private struct AdminRowRevealModifier: ViewModifier {
    let index: Int
    let hasAppeared: Bool
    let revealComplete: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content.modifier(AdminCellDisplayModifier(index: index))
    }
}

extension View {
    /// Section-level entrance. `step` is the section's position in reading order.
    func inventoryEntrance(step: Int, hasAppeared: Bool, reduceMotion: Bool) -> some View {
        modifier(AdminEntranceModifier(step: step, hasAppeared: hasAppeared, reduceMotion: reduceMotion))
    }

    /// Row-level reveal, active during row appearance.
    func inventoryRowReveal(
        index: Int,
        hasAppeared: Bool = true,
        revealComplete: Bool = false,
        reduceMotion: Bool = false
    ) -> some View {
        modifier(AdminRowRevealModifier(
            index: index,
            hasAppeared: hasAppeared,
            revealComplete: revealComplete,
            reduceMotion: reduceMotion
        ))
    }

    /// Animates this cell when it displays on screen in an inventory list or grid.
    public func animateCellDisplay(
        id: String? = nil,
        index: Int = 0,
        baseDelay: Double = 0.0
    ) -> some View {
        modifier(AdminCellDisplayModifier(id: id, index: index, baseDelay: baseDelay))
    }
}
