//
//  PuryCommandCrown.swift
//  PurePetsAdmin
//
//  The Pury command crown: one authored header surface that replaces the previous
//  two stacked bars (identity bar + context strip).
//
//  Design intent
//  -------------
//  A staff operator opening Pury already knows who Pury is. What they cannot see, and
//  what actually governs the answer they are about to trust, is:
//
//    1. WHICH records Pury is bound to right now (the screen/branch/entity scope), and
//    2. WHAT Pury is doing with them (idle, reading, awaiting approval, denied, stale).
//
//  So the crown promotes the bound scope from a secondary strip into the header's
//  primary subtitle slot, makes it inspectable in place, and expresses the real
//  `PuryConversationStore.State` machine through a single 2pt signal spine on the
//  bottom edge instead of a decorative pulsing dot. One surface, one hairline,
//  no redundant liveness theater, ~34pt of chrome reclaimed.
//
//  Every string resolves through `PuryLocale` against Pury's own language, so the
//  crown stays coherent when Pury's language differs from the app language.
//

import SwiftUI
import UIKit

// MARK: - Header Signal (derived from the real state machine)

/// Operator-facing projection of `PuryConversationStore.State`.
/// Truthful by construction: every case maps to a state the store can actually be in,
/// and states the old header ignored (`pending`, `empty`) now have a voice.
@available(iOS 16.0, *)
struct PuryHeaderSignal: Equatable {
    enum Pulse: Equatable {
        /// Nothing in flight. Bottom edge is a plain hairline.
        case dormant
        /// Work in flight. Bottom edge runs a single travelling sweep.
        case sweeping
        /// A condition that persists until the operator acts. Bottom edge holds a solid tint.
        case steady
    }

    /// `nil` when there is nothing worth saying — silence is the reward for a clean state.
    let label: String?
    let symbol: String?
    let tint: Color
    let pulse: Pulse
    let voiceOverStatus: String

    static func resolve(state: PuryConversationStore.State, language: String) -> PuryHeaderSignal {
        func text(_ key: String, ar: String, en: String) -> String {
            PuryLocale.text(key, language: language, ar: ar, en: en)
        }

        let ready = text("Pury_State_Ready", ar: "جاهز", en: "Ready")

        switch state {
        case .idle, .ready:
            return PuryHeaderSignal(
                label: nil,
                symbol: nil,
                tint: AdminSurface.hairline,
                pulse: .dormant,
                voiceOverStatus: ready
            )

        case .loading:
            let label = text("Pury_State_Reading", ar: "يقرأ البيانات الحية", en: "Reading live records")
            return PuryHeaderSignal(
                label: label,
                symbol: nil,
                tint: PuryBrand.primary,
                pulse: .sweeping,
                voiceOverStatus: label
            )

        case .pending:
            let label = text("Pury_State_Executing", ar: "يتم التنفيذ بأمان", en: "Executing safely")
            return PuryHeaderSignal(
                label: label,
                symbol: "bolt.fill",
                tint: PuryBrand.primary,
                pulse: .sweeping,
                voiceOverStatus: label
            )

        case .confirmationRequired:
            let label = text("Pury_State_Awaiting_Approval", ar: "بانتظار موافقتك", en: "Awaiting your approval")
            return PuryHeaderSignal(
                label: label,
                symbol: "hand.raised.fill",
                tint: AdminSurface.amber,
                pulse: .steady,
                voiceOverStatus: label
            )

        case .conflictStale:
            let label = text("Pury_State_Stale", ar: "تغيّرت البيانات", en: "Records changed")
            return PuryHeaderSignal(
                label: label,
                symbol: "arrow.triangle.2.circlepath",
                tint: AdminSurface.amber,
                pulse: .steady,
                voiceOverStatus: label
            )

        case .denied:
            let label = text("Pury_State_Denied", ar: "صلاحية غير كافية", en: "Permission denied")
            return PuryHeaderSignal(
                label: label,
                symbol: "lock.fill",
                tint: AdminSurface.crimson,
                pulse: .steady,
                voiceOverStatus: label
            )

        case .error:
            let label = text("Pury_State_Alert", ar: "تنبيه تشغيلي", en: "Operational alert")
            return PuryHeaderSignal(
                label: label,
                symbol: "exclamationmark.triangle.fill",
                tint: AdminSurface.crimson,
                pulse: .steady,
                voiceOverStatus: label
            )

        case .empty:
            let label = text("Pury_State_NoResults", ar: "لا سجلات مطابقة", en: "No matching records")
            return PuryHeaderSignal(
                label: label,
                symbol: "magnifyingglass",
                tint: AdminSurface.secondaryText,
                pulse: .dormant,
                voiceOverStatus: label
            )
        }
    }
}

// MARK: - Signal Spine

/// The crown's bottom edge. It is simultaneously the separator hairline and the
/// state indicator, which is why the crown needs only one hairline instead of two.
///
/// Direction-aware: the sweep always travels leading -> trailing, so it runs
/// right-to-left in Arabic and left-to-right in English.
@available(iOS 16.0, *)
private struct PurySignalSpine: View {
    let signal: PuryHeaderSignal
    let isRTL: Bool
    let allowsMotion: Bool

    @State private var sweepProgress: CGFloat = 0

    /// With Reduce Motion on, a sweeping state degrades to a solid tinted edge so the
    /// information survives without the animation carrying it.
    private var effectivePulse: PuryHeaderSignal.Pulse {
        if signal.pulse == .sweeping && !allowsMotion { return .steady }
        return signal.pulse
    }

    private var baseColor: Color {
        switch effectivePulse {
        case .dormant: return AdminSurface.hairline
        case .steady: return signal.tint.opacity(0.92)
        case .sweeping: return signal.tint.opacity(0.20)
        }
    }

    private var thickness: CGFloat {
        effectivePulse == .dormant ? 0.75 : 1.75
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let segment = max(72, width * 0.24)
            let travel = sweepProgress * (width + segment) - segment
            let direction: CGFloat = isRTL ? -1 : 1

            ZStack(alignment: .leading) {
                Rectangle().fill(baseColor)

                if effectivePulse == .sweeping {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, signal.tint, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: segment)
                        .offset(x: direction * travel)
                }
            }
        }
        .frame(height: thickness)
        .animation(.easeInOut(duration: 0.28), value: signal)
        .onAppear(perform: restartSweep)
        .onChange(of: effectivePulse) { _ in restartSweep() }
        .accessibilityHidden(true) // the state capsule already announces this in words
    }

    private func restartSweep() {
        guard effectivePulse == .sweeping else {
            sweepProgress = 0
            return
        }
        sweepProgress = 0
        withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
            sweepProgress = 1
        }
    }
}

// MARK: - Command Crown

@available(iOS 16.0, *)
struct PuryCommandCrown: View {
    let language: String
    let isRTL: Bool
    let state: PuryConversationStore.State
    let screenContext: PuryScreenContext?
    /// Driven by real product state (composing, or a conversation with depth) rather
    /// than scroll offset — deterministic, and it never jitters mid-scroll.
    let isCompact: Bool
    let canClearConversation: Bool
    let onSelectLanguage: (String) -> Void
    let onRequestClear: () -> Void
    let onClose: () -> Void

    @State private var isScopeExpanded = false
    @Namespace private var languagePillNamespace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Pury's navigation is an intentionally fixed system-chrome rhythm: circular actions
    /// are 36 × 36 and every non-circular navigation item is exactly 36 points high.
    /// Type scales inside those controls while their stable geometry preserves muscle memory.
    private static let navigationButtonSide: CGFloat = 36
    private static let navigationItemHeight: CGFloat = 36

    // MARK: Derived

    private var signal: PuryHeaderSignal {
        PuryHeaderSignal.resolve(state: state, language: language)
    }

    private var scopeFacets: [PuryScopeFacet] {
        screenContext?.scopeFacets(language: language) ?? []
    }

    private var scopeLabel: String {
        screenContext?.displayLabel(language: language)
            ?? PuryLocale.text("Pury_Context_Admin", language: language, ar: "لوحة الإدارة", en: "Admin Console")
    }

    private var hasScopeDetail: Bool { !scopeFacets.isEmpty }

    /// The AI provenance badge is real information (answers are model-generated), but it
    /// is the first thing to yield when the operator needs larger text.
    private var showsProvenanceBadge: Bool {
        !isCompact && dynamicTypeSize < .accessibility1
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86)
    }

    private var resolvedAvatarSize: CGFloat { Self.navigationButtonSide }
    private var resolvedControlSize: CGFloat { Self.navigationButtonSide }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Extends navbar background to fill the top safe area layout guide inset behind status bar
            Color.clear
                .frame(height: PPStatusBarHelper.statusBarHeight)
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 8) {
                PuryAvatar(
                    size: resolvedAvatarSize,
                    isLiving: true,
                    isThinking: state.isWaitingOrThinking,
                    motionState: state.puryMotionState,
                    showStatusRing: true,
                    showAmbientAura: false
                )
                .accessibilityHidden(true)

                identityColumn

                Spacer(minLength: 6)

                controlCluster
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, isCompact ? 7 : 10)
            .frame(maxWidth: 680)

            if isScopeExpanded && hasScopeDetail {
                scopeInspector
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .background(crownSurface)
        .overlay(alignment: .bottom) {
            PurySignalSpine(signal: signal, isRTL: isRTL, allowsMotion: !reduceMotion)
        }
        .animation(motion, value: isCompact)
        .animation(motion, value: isScopeExpanded)
        // A collapsed scope panel must never survive a context change it no longer describes.
        .onChange(of: scopeLabel) { _ in isScopeExpanded = false }
    }

    // MARK: Surface

    private var crownSurface: some View {
        ZStack {
            AdminSurface.surface.opacity(0.86)
                .background(.ultraThinMaterial)

            // Faint identity light so the crown reads as Pury's surface rather than
            // as a continuation of the host screen behind it.
            LinearGradient(
                colors: [PuryBrand.hotPink.opacity(0.055), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: Identity + Scope

    private var identityColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !isCompact {
                identityLockup
            }

            HStack(spacing: 6) {
                scopeChip
                    .layoutPriority(0)

                if let label = signal.label {
                    stateCapsule(label)
                        .layoutPriority(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identityLockup: some View {
        HStack(spacing: 6) {
            Text(PuryLocale.text("Pury_Name", language: language, ar: "بيوري", en: "Pury"))
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)

            if showsProvenanceBadge {
                Text(PuryLocale.text("Pury_Badge_AI", language: language, ar: "AI", en: "AI"))
                    .font(PPBrandFont.bold(size: 9.5, relativeTo: .caption2))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PuryBrand.identityGradient, in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            PuryLocale.text(
                "Pury_Identity_A11y",
                language: language,
                ar: "بيوري، مساعد تشغيلي بالذكاء الاصطناعي",
                en: "Pury, AI operations assistant"
            )
        )
        .accessibilityValue(signal.voiceOverStatus)
    }

    /// The single highest-value fact in the header: what Pury is bound to.
    /// Tapping it opens the binding in place — no modal, no navigation.
    private var scopeChip: some View {
        Button {
            guard hasScopeDetail else { return }
            withAnimation(motion) { isScopeExpanded.toggle() }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "scope")
                    .font(.system(size: 9, weight: .bold))

                Text(scopeLabel)
                    .font(AdminType.caption2Bold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.80)

                if hasScopeDetail {
                    // `chevron.down` is direction-neutral: rotating it 180 degrees reads
                    // identically in Arabic and English, unlike a mirrored forward chevron.
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .black))
                        .rotationEffect(.degrees(isScopeExpanded ? 180 : 0))
                }
            }
            .foregroundStyle(PuryBrand.primary)
            .padding(.horizontal, 7)
            .frame(height: Self.navigationItemHeight)
            .background(PuryBrand.primary.opacity(0.085), in: Capsule())
            .overlay(Capsule().strokeBorder(PuryBrand.primary.opacity(0.20), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .disabled(!hasScopeDetail)
        .accessibilityLabel(
            PuryLocale.text("Pury_Scope_A11y_Label", language: language, ar: "نطاق البيانات المرتبط", en: "Bound data scope")
        )
        .accessibilityValue(scopeLabel)
        .accessibilityHint(
            hasScopeDetail
                ? PuryLocale.text(
                    "Pury_Scope_A11y_Hint",
                    language: language,
                    ar: "انقر مرتين لعرض تفاصيل الارتباط",
                    en: "Double tap to show binding details"
                )
                : ""
        )
    }

    private func stateCapsule(_ label: String) -> some View {
        HStack(spacing: 4) {
            if let symbol = signal.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .bold))
            }

            Text(label)
                .font(AdminType.caption2Bold)
                .lineLimit(1)
        }
        .foregroundStyle(signal.tint)
        .padding(.horizontal, 7)
        .frame(height: Self.navigationItemHeight)
        .background(signal.tint.opacity(0.12), in: Capsule())
        .transition(
            .opacity.combined(
                with: .scale(scale: 0.92, anchor: isRTL ? .trailing : .leading)
            )
        )
        .accessibilityLabel(label)
    }

    // MARK: Scope Inspector

    /// In-place binding disclosure. Backend identifiers render monospaced and forced
    /// left-to-right so they stay readable and copy-accurate inside an Arabic layout.
    private var scopeInspector: some View {
        VStack(alignment: .leading, spacing: 9) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: 12, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(scopeFacets) { facet in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(facet.label)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)

                        if facet.isTechnical {
                            Text(facet.value)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .environment(\.layoutDirection, .leftToRight)
                        } else {
                            Text(facet.value)
                                .font(AdminType.caption1Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 9, weight: .bold))

                Text(
                    PuryLocale.text(
                        "Pury_Scope_Authority",
                        language: language,
                        ar: "يقرأ بيوري السجلات المصرح لك بها فقط، والتحقق يتم على الخادم.",
                        en: "Pury reads only records your staff permissions allow; authorization is enforced server-side."
                    )
                )
                .font(AdminType.caption2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(AdminSurface.secondaryText)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 3)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PuryBrand.primary.opacity(0.045))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.5)
        }
    }

    // MARK: Controls

    private var controlCluster: some View {
        HStack(spacing: 5) {
            languageDuoSwitch

            crownCircleButton(
                symbol: "trash",
                accessibilityLabel: PuryLocale.text(
                    "Pury_Clear_Chat",
                    language: language,
                    ar: "مسح المحادثة",
                    en: "Clear Conversation"
                ),
                isEnabled: canClearConversation,
                action: onRequestClear
            )

            crownCircleButton(
                symbol: "xmark",
                accessibilityLabel: PuryLocale.text("Pury_Close", language: language, ar: "إغلاق", en: "Close"),
                isEnabled: true,
                action: onClose
            )
        }
        .frame(height: Self.navigationItemHeight)
    }

    /// Always-present controls with fixed geometry. The previous header inserted and
    /// removed the clear button, which shifted the close button under the operator's
    /// thumb the moment a conversation started.
    private func crownCircleButton(
        symbol: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AdminSurface.control)

                Circle()
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)

                Image(systemName: symbol)
                    .font(.system(size: resolvedControlSize * 0.38, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
            }
            .frame(width: resolvedControlSize, height: resolvedControlSize)
            .opacity(isEnabled ? 1 : 0.34)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Both languages are shown with the active one filled, so the control states what
    /// Pury is speaking now instead of only naming the language you would switch to.
    private var languageDuoSwitch: some View {
        HStack(spacing: 0) {
            languageSegment(
                code: "ar",
                title: "ع",
                accessibleName: PuryLocale.text("Pury_Language_Arabic", language: language, ar: "العربية", en: "Arabic")
            )

            languageSegment(
                code: "en",
                title: "EN",
                accessibleName: PuryLocale.text("Pury_Language_English", language: language, ar: "الإنجليزية", en: "English")
            )
        }
        .padding(2)
        .background(AdminSurface.control, in: Capsule())
        .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        .frame(height: Self.navigationItemHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            PuryLocale.text("Pury_Language_A11y_Label", language: language, ar: "لغة بيوري", en: "Pury language")
        )
    }

    private func languageSegment(code: String, title: String, accessibleName: String) -> some View {
        let isActive = PuryLocale.normalized(language) == code

        return Button {
            guard !isActive else { return }
            onSelectLanguage(code)
        } label: {
            Text(title)
                .font(PPBrandFont.bold(size: 10.5, relativeTo: .caption2))
                .foregroundStyle(isActive ? Color.white : AdminSurface.secondaryText)
                .frame(minWidth: 22)
                .padding(.horizontal, 3.5)
                .frame(maxHeight: .infinity)
                .background {
                    if isActive {
                        Capsule()
                            .fill(PuryBrand.identityGradient)
                            .matchedGeometryEffect(id: "puryLanguagePill", in: languagePillNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibleName)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : [.isButton])
    }
}
