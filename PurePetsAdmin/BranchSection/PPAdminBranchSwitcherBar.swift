//
//  PPAdminBranchSwitcherBar.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles for PurePets Flagship Admin.
//  Category-defining Active Branch Horizon Capsule & Command Center Banner.
//

import SwiftUI

public enum PPBranchSwitcherStyle {
    case compact
    case prominentHero
}

public struct PPAdminBranchSwitcherBar: View {
    @ObservedObject var contextStore = BranchContextStore.shared
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingSwitcherSheet = false
    @State private var isBeaconPulsing = false
    public let style: PPBranchSwitcherStyle

    public init(style: PPBranchSwitcherStyle = .compact) {
        self.style = style
    }

    public var body: some View {
        Button {
            triggerTap()
        } label: {
            switch style {
            case .compact:
                compactCapsule
            case .prominentHero:
                prominentHeroBanner
            }
        }
        .buttonStyle(BranchCapsulePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(branchSwitcherAccessibilityLabel))
        .accessibilityValue(Text(branchSwitcherAccessibilityValue))
        .accessibilityHint(Text(branchSwitcherAccessibilityHint))
        .accessibilityIdentifier("admin.branch.switcher")
        .sheet(isPresented: $showingSwitcherSheet) {
            PPBranchSelectionGateView()
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .onAppear {
            configureBeaconMotion()
        }
        .onChange(of: accessibilityReduceMotion) { _ in
            configureBeaconMotion()
        }
        .onDisappear {
            isBeaconPulsing = false
        }
    }

    private var hasResolvedContext: Bool {
        contextStore.activeBranch != nil || contextStore.isGlobal
    }

    private var branchCode: String? {
        guard let code = contextStore.activeBranch?.code
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else {
            return nil
        }
        return code
    }

    private var branchContextLabel: String {
        if contextStore.isGlobal {
            return Language.get("BranchContext_Global_Title", alter: "وصول شامل لكافة الفروع")
        }
        if contextStore.activeBranch != nil {
            return Language.get("BranchContext_Current_Active", alter: "الفرع النشط حالياً")
        }
        return Language.get("BranchContext_SelectBranch_Prompt", alter: "يرجى تحديد الفرع")
    }

    private var branchContextColor: Color {
        hasResolvedContext ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)
    }

    private var branchSymbolName: String {
        if contextStore.isGlobal {
            return "globe"
        }
        return contextStore.activeBranch == nil ? "building.2" : "building.2.fill"
    }

    private var branchSwitcherAccessibilityLabel: String {
        Language.get("BranchContext_Switcher_Title", alter: "تبديل فرع العمل")
    }

    private var branchSwitcherAccessibilityValue: String {
        guard let branchCode else {
            return contextStore.currentBranchDisplayName
        }
        return "\(contextStore.currentBranchDisplayName), \(branchCode)"
    }

    private var branchSwitcherAccessibilityHint: String {
        Language.get(
            "BranchContext_Switcher_Message",
            alter: "اختر الفرع لتفعيل سياق العمليات وعرض البيانات الخاصة به."
        )
    }

    private func triggerTap() {
        let feedback = UIImpactFeedbackGenerator(style: .soft)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.82)
        showingSwitcherSheet = true
    }

    private func configureBeaconMotion() {
        guard !accessibilityReduceMotion, hasResolvedContext else {
            isBeaconPulsing = false
            return
        }

        isBeaconPulsing = false
        DispatchQueue.main.async {
            withAnimation(
                .easeInOut(duration: 1.65)
                    .repeatForever(autoreverses: true)
            ) {
                isBeaconPulsing = true
            }
        }
    }

    // MARK: - Compact Branch Identity Island

    private var compactCapsule: some View {
        HStack(spacing: AdminSpacing.sm) {
            branchIdentityEmblem

            VStack(alignment: .leading, spacing: AdminSpacing.xxs) {
                HStack(spacing: 6) {
                    Text(branchContextLabel)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(branchContextColor)
                        .lineLimit(1)

                    if let branchCode {
                        branchCodeBadge(branchCode)
                    }
                }

                Text(contextStore.currentBranchDisplayName)
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.84)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: AdminSpacing.xs)

            branchSwitchAffordance
        }
        .padding(.leading, 7)
        .padding(.trailing, AdminSpacing.sm)
        .padding(.vertical, 7)
        .frame(
            minWidth: dynamicTypeSize.isAccessibilitySize ? 260 : 220,
            idealWidth: dynamicTypeSize.isAccessibilitySize ? 310 : 254,
            maxWidth: dynamicTypeSize.isAccessibilitySize ? 340 : 300,
            minHeight: AdminTouchTarget.expanded,
            alignment: .leading
        )
        .background(compactCapsuleSurface)
        .overlay(compactCapsuleBorder)
        .shadow(
            color: AdminSurface.primary.opacity(0.08),
            radius: 12,
            x: 0,
            y: 5
        )
        .shadow(
            color: Color.black.opacity(0.045),
            radius: 3,
            x: 0,
            y: 1
        )
        .contentShape(Capsule(style: .continuous))
    }

    private var branchIdentityEmblem: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AdminSurface.primary.opacity(0.18),
                            AdminSurface.primarySoft.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.72),
                            AdminSurface.primary.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: AdminStroke.hairline
                )

            Image(systemName: branchSymbolName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AdminSurface.primary)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 40, height: 40)
        .overlay(alignment: .bottomTrailing) {
            branchContextSignal
                .offset(x: 2, y: 2)
        }
        .accessibilityHidden(true)
    }

    private var branchContextSignal: some View {
        ZStack {
            Circle()
                .stroke(branchContextColor.opacity(0.24), lineWidth: 1.5)
                .frame(width: 15, height: 15)
                .scaleEffect(isBeaconPulsing && hasResolvedContext ? 1.32 : 0.94)
                .opacity(isBeaconPulsing && hasResolvedContext ? 0.18 : 0.72)

            Circle()
                .fill(branchContextColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(AdminSurface.surface, lineWidth: 2)
                )
        }
        .frame(width: 16, height: 16)
    }

    private func branchCodeBadge(_ code: String) -> some View {
        Text(code)
            .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
            .tracking(0.35)
            .foregroundColor(AdminSurface.primary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .background(
                Capsule(style: .continuous)
                    .fill(AdminSurface.primary.opacity(0.09))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(AdminSurface.primary.opacity(0.18), lineWidth: AdminStroke.hairline)
            )
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
    }

    private var branchSwitchAffordance: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AdminSurface.control.opacity(0.92))

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AdminSurface.hairline.opacity(0.86), lineWidth: AdminStroke.hairline)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AdminSurface.primary)
        }
        .frame(width: 34, height: 38)
        .accessibilityHidden(true)
    }

    private var compactCapsuleSurface: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(AdminSurface.surface)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AdminSurface.primary.opacity(0.075),
                            Color.clear,
                            AdminSurface.control.opacity(0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .padding(1)
        }
        .clipShape(Capsule(style: .continuous))
    }

    private var compactCapsuleBorder: some View {
        Capsule(style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        AdminSurface.primary.opacity(0.25),
                        AdminSurface.hairline.opacity(0.84),
                        Color.white.opacity(0.45)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: AdminStroke.thin
            )
    }

    // ── Prominent Hero Banner (Home Command Screen) ────────────────────────

    private var prominentHeroBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Eyebrow Telemetry & Switch CTA
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    // Live pulsing beacon
                    ZStack {
                        Circle()
                            .fill(Color.emerald600.opacity(isBeaconPulsing ? 0.4 : 0.15))
                            .frame(width: 14, height: 14)
                            .scaleEffect(isBeaconPulsing ? 1.3 : 0.85)

                        Circle()
                            .fill(Color.emerald600)
                            .frame(width: 6.5, height: 6.5)
                    }

                    Text(Language.isRTL() ? "نطاق العمليات النشط" : "Active Operational Scope")
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundColor(AdminCommandInk.secondary)

                    Circle()
                        .fill(Color(uiColor: .tertiaryLabel))
                        .frame(width: 3, height: 3)

                    Text(contextStore.activeBranch != nil
                         ? (Language.isRTL() ? "متصل" : "Live")
                         : (Language.isRTL() ? "غير محدد" : "Unset"))
                        .font(Font.custom("Beiruti-Bold", size: 11.5))
                        .foregroundColor(contextStore.activeBranch != nil ? .emerald600 : .orange)
                }

                Spacer()

                // Switch Pill Action
                HStack(spacing: 4) {
                    Text(Language.isRTL() ? "تبديل" : "Switch")
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundColor(AdminSurface.primary)

                    Image(systemName: Language.isRTL() ? "arrow.left.arrow.right" : "arrow.right.arrow.left")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(AdminSurface.primary.opacity(0.2), lineWidth: 0.5)
                )
            }

            // Main Branch Identification Row
            HStack(spacing: 12) {
                // Architectural Emblem Tile
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
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
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(AdminSurface.primary.opacity(0.3), lineWidth: 0.75)
                        )

                    Image(systemName: "building.2.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(contextStore.currentBranchDisplayName)
                            .font(Font.custom("Beiruti-Bold", size: 17))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let code = contextStore.activeBranch?.code, !code.isEmpty {
                            Text(code)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(AdminSurface.primary.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(AdminSurface.primary.opacity(0.25), lineWidth: 0.5)
                                )
                        }

                        Spacer()
                    }

                    // Metadata Micro-Badges
                    HStack(spacing: 6) {
                        if let branch = contextStore.activeBranch {
                            if branch.isDefault {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                    Text(Language.isRTL() ? "افتراضي" : "Default")
                                        .font(Font.custom("Beiruti-Bold", size: 10.5))
                                }
                                .foregroundColor(.amber600)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.amber600.opacity(0.12))
                                .cornerRadius(4)
                            }

                            HStack(spacing: 3) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 8))
                                Text(branch.localizedStockModeName())
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .cornerRadius(4)

                            if !branch.address.isEmpty {
                                Text(branch.address)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Color(uiColor: .secondaryLabel))
                                    .lineLimit(1)
                            }
                        } else {
                            Text(Language.isRTL() ? "المس لتحديد فرع العمل النشط" : "Tap to choose working branch")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            AdminSurface.primary.opacity(0.28),
                            Color(uiColor: .separator).opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        )
    }
}

// MARK: - Press Style for Smooth Physics

fileprivate struct BranchCapsulePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                configuration.isPressed && !accessibilityReduceMotion
                    ? AdminAnimation.pressScale
                    : 1.0
            )
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .brightness(configuration.isPressed ? -0.012 : 0.0)
            .animation(
                accessibilityReduceMotion ? nil : AdminAnimation.standard,
                value: configuration.isPressed
            )
    }
}
