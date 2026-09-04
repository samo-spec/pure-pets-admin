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

    private let compactCornerRadius: CGFloat = 18

    public init(style: PPBranchSwitcherStyle = .compact) {
        self.style = style
    }

    public var body: some View {
        Button {
            triggerTap()
        } label: {
            switch style {
            case .compact, .prominentHero:
                compactCapsule
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(BranchCapsulePressStyle())
        .disabled(!canSwitchBranch)
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
        contextStore.activeBranch != nil
    }

    private var canSwitchBranch: Bool {
        contextStore.availableBranches.count > 1
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
        if contextStore.activeBranch != nil {
            return Language.get("BranchContext_Current_Active", alter: "الفرع النشط حالياً")
        }
        return Language.get("BranchContext_SelectBranch_Prompt", alter: "يرجى تحديد الفرع")
    }

    private var branchContextColor: Color {
        hasResolvedContext ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)
    }

    private var branchSymbolName: String {
        contextStore.activeBranch == nil ? "building.2" : "building.2.fill"
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
        if !canSwitchBranch {
            return Language.get(
                "BranchContext_SingleBranch_Locked",
                alter: "هذا هو فرع العمل الوحيد المعتمد لهذا الحساب."
            )
        }
        return Language.get(
            "BranchContext_Switcher_Message",
            alter: "اختر الفرع لتفعيل سياق العمليات وعرض البيانات الخاصة به."
        )
    }

    private func triggerTap() {
        guard canSwitchBranch else { return }
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

            Text(contextStore.currentBranchDisplayName)
                .font(PPBrandFont.bold(size: 15, relativeTo: .subheadline))
                .foregroundColor(AdminSurface.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.84)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer(minLength: AdminSpacing.xs)

            branchSwitchAffordance
        }
        .padding(.leading, 8)
        .padding(.trailing, AdminSpacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .contentShape(RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous))
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
        Group {
            if canSwitchBranch {
                HStack(spacing: 4) {
                    Text(Language.get("AdminCommandCenter_Switch_Action", alter: "تبديل"))
                        .font(PPBrandFont.bold(size: 12, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.primary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AdminSurface.control, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(AdminSurface.primary.opacity(0.22), lineWidth: 0.75)
                )
            } else {
                HStack(spacing: 3.5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(AdminCommandInk.secondary)

                    Text(Language.get("BranchContext_SingleBranch_Locked", alter: "فرع معتمد"))
                        .font(PPBrandFont.medium(size: 10.5, relativeTo: .caption2))
                        .foregroundStyle(AdminCommandInk.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(AdminSurface.control.opacity(0.5), in: Capsule())
            }
        }
        .accessibilityHidden(true)
    }

    private var compactCapsuleSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous)
                .fill(AdminSurface.surface)

            RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous)
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

            RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .padding(1)
        }
        .clipShape(RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous))
    }

    private var compactCapsuleBorder: some View {
        RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous)
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
        compactCapsule
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
