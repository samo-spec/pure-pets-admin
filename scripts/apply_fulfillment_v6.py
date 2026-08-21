#!/usr/bin/env python3
from pathlib import Path
import re

path = Path("PurePetsAdmin/Fulfillment/PPFulfillmentOrdersViewController.swift")
text = path.read_text()


def sub(pattern: str, replacement: str, count: int = 1) -> None:
    global text
    updated, n = re.subn(pattern, replacement, text, count=count, flags=re.S)
    if n != count:
        raise RuntimeError(f"Expected {count} replacement(s), got {n}: {pattern[:100]}")
    text = updated

# Central-token adapter only: no private palette/spacing values.
sub(
    r"private enum PPFulfillmentTokens \{.*?\n\}\n\nprivate struct PPFulfillmentCardModifier",
    '''private enum PPFulfillmentTokens {
    static let spaceXS = CGFloat(PPSpaceXS)
    static let spaceSM = CGFloat(PPSpaceSM)
    static let spaceMD = CGFloat(PPSpaceMD)
    static let spaceBase = CGFloat(PPSpaceBase)
    static let spaceLG = CGFloat(PPSpaceLG)
    static let spaceXL = CGFloat(PPSpaceXL)
    static let screenMargin = CGFloat(PPScreenMargin)
    static let cornerSmall = CGFloat(PPCornerSmall)
    static let cornerMedium = CGFloat(PPCorner16)
    static let cornerCard = CGFloat(PPCornerCard)
    static let cornerHero = CGFloat(PPCornerCard)
    static let minimumTarget = CGFloat(PPTouchTargetMin)

    static let canvas = AdminSurface.background
    static let surface = AdminSurface.surface
    static let ink = AdminSurface.primaryText
    static let secondaryInk = AdminSurface.secondaryText
    static let tertiaryInk = Color(uiColor: .ppTextTertiary)
    static let gold = Color(uiColor: .ppPremiumAccent)
    static let success = Color(uiColor: .ppSuccess)
    static let warning = Color(uiColor: .ppWarning)
    static let danger = Color(uiColor: .ppError)
    static let info = Color(uiColor: .ppInfo)
    static let primary = AdminSurface.primary
    static let primarySoft = AdminSurface.primarySoft
    static let border = AdminSurface.hairline
    static let disabledFill = Color(uiColor: .ppSecondarySurface)

    /// Keeps existing call sites semantic while routing all typography through
    /// the app-wide AdminType scale instead of a Fulfillment-only font system.
    static func beiruti(_ weight: Font.Weight, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        let strong: Bool
        switch weight {
        case .medium, .semibold, .bold, .heavy, .black: strong = true
        default: strong = false
        }
        switch style {
        case .largeTitle: return strong ? AdminType.title : AdminType.title2
        case .title: return AdminType.title
        case .title2: return AdminType.title2
        case .title3: return AdminType.title3
        case .headline: return AdminType.headline
        case .subheadline: return strong ? AdminType.subheadlineBold : AdminType.subheadline
        case .body: return strong ? AdminType.headline : AdminType.body
        case .callout: return strong ? AdminType.calloutBold : AdminType.callout
        case .footnote: return strong ? AdminType.footnoteBold : AdminType.footnote
        case .caption: return strong ? AdminType.captionBold : AdminType.caption1
        case .caption2: return strong ? AdminType.caption2Bold : AdminType.caption2
        @unknown default: return strong ? AdminType.headline : AdminType.body
        }
    }
}

private struct PPFulfillmentCardModifier'''
)

# Remove broad decorative elevation from the shared Fulfillment card language.
text = text.replace(
    '''            .overlay(
                RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous)
                    .stroke(PPFulfillmentTokens.ink.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 8)''',
    '''            .overlay(
                RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous)
                    .stroke(PPFulfillmentTokens.border, lineWidth: 1)
            )''',
    1,
)

# Work queue: global navigation owns the page title. Replace the second in-page
# masthead with a compact live status/refresh row.
text = text.replace(
    '''                LazyVStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceXL) {
                    commandHeader
                    operationalPulse''',
    '''                LazyVStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceBase) {
                    operationalStatusBar
                    operationalPulse''',
    1,
)
text = text.replace(
    '''                .padding(.top, PPFulfillmentTokens.spaceBase)
                .padding(.bottom, 36)''',
    '''                .padding(.top, PPFulfillmentTokens.spaceXS)
                .padding(.bottom, PPFulfillmentTokens.spaceXL)''',
    1,
)

sub(
    r"\n    private var commandHeader: some View \{.*?\n    @ViewBuilder\n    private var liveStatus:",
    '''
    private var operationalStatusBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) {
                    liveStatus
                    refreshControl
                }
            } else {
                HStack(spacing: PPFulfillmentTokens.spaceSM) {
                    liveStatus
                    Spacer(minLength: PPFulfillmentTokens.spaceSM)
                    refreshControl
                }
            }
        }
        .font(AdminType.caption1)
        .foregroundStyle(PPFulfillmentTokens.secondaryInk)
        .accessibilityIdentifier("fulfillment.live.status")
    }

    private var refreshControl: some View {
        Button(action: viewModel.retry) {
            Image(systemName: viewModel.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PPFulfillmentTokens.primary)
                .frame(width: PPFulfillmentTokens.minimumTarget, height: PPFulfillmentTokens.minimumTarget)
                .background(PPFulfillmentTokens.primarySoft, in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRefreshing)
        .accessibilityLabel(PPFulfillmentL10n.text("Fulfillment_Retry"))
        .accessibilityIdentifier("fulfillment.refresh")
    }

    @ViewBuilder
    private var liveStatus:''',
)

# Keep the pulse operational, not decorative.
text = text.replace(
    '''    private var operationalPulse: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceLG) {''',
    '''    private var operationalPulse: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceMD) {''',
    1,
)
text = text.replace(
    '''        .padding(PPFulfillmentTokens.spaceLG)
        .background(PPFulfillmentTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerHero, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(healthColor)
                .frame(width: 4)
                .padding(.vertical, PPFulfillmentTokens.spaceLG)
        }
        .overlay(
            RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerHero, style: .continuous)
                .stroke(healthColor.opacity(0.28), lineWidth: 1)
        )''',
    '''        .padding(PPFulfillmentTokens.spaceBase)
        .background(PPFulfillmentTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerCard, style: .continuous)
                .stroke(PPFulfillmentTokens.border, lineWidth: 1)
        )''',
    1,
)

# Stage progression becomes a compact filter rail rather than five dashboard cards.
sub(
    r"    private var workflowBoard: some View \{.*?\n    private var queueControls:",
    '''    private var workflowBoard: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) {
            Text(PPFulfillmentL10n.text("Fulfillment_Workflow_Title"))
                .font(AdminType.captionBold)
                .foregroundStyle(PPFulfillmentTokens.secondaryInk)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PPFulfillmentTokens.spaceSM) {
                    ForEach(PPFulfillmentStage.allCases) { stage in
                        PPFulfillmentStageNode(
                            stage: stage,
                            count: viewModel.count(for: stage),
                            isSelected: viewModel.stageFilter == stage
                        ) {
                            viewModel.stageFilter = viewModel.stageFilter == stage ? nil : stage
                            viewModel.exactStatus = ""
                            viewModel.statusGroup = .all
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var queueControls:''',
)

sub(
    r"private struct PPFulfillmentStageNode: View \{.*?\n\}\n\nprivate struct PPFulfillmentCommandRow:",
    '''private struct PPFulfillmentStageNode: View {
    let stage: PPFulfillmentStage
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PPFulfillmentTokens.spaceSM) {
                Image(systemName: stage.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(stageColor)
                    .accessibilityHidden(true)
                Text(PPFulfillmentL10n.text(stage.titleKey))
                    .font(AdminType.calloutBold)
                    .foregroundStyle(PPFulfillmentTokens.ink)
                    .lineLimit(1)
                Text("\\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? stageColor : PPFulfillmentTokens.secondaryInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((isSelected ? stageColor : PPFulfillmentTokens.secondaryInk).opacity(0.09), in: Capsule())
            }
            .padding(.horizontal, PPFulfillmentTokens.spaceMD)
            .frame(minHeight: PPFulfillmentTokens.minimumTarget)
            .background(
                isSelected ? stageColor.opacity(0.09) : PPFulfillmentTokens.surface,
                in: RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PPFulfillmentTokens.cornerSmall, style: .continuous)
                    .stroke(isSelected ? stageColor.opacity(0.55) : PPFulfillmentTokens.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? PPFulfillmentL10n.text("Fulfillment_Filter_Selected") : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("fulfillment.stage.\\(stage.rawValue)")
    }

    private var stageColor: Color {
        switch stage {
        case .intake: return PPFulfillmentTokens.primary
        case .preparation: return PPFulfillmentTokens.warning
        case .handoff: return PPFulfillmentTokens.info
        case .settlement: return PPFulfillmentTokens.gold
        case .outcome: return PPFulfillmentTokens.success
        }
    }
}

private struct PPFulfillmentCommandRow:''',
)

# Queue rows get denser while retaining accessibility reflow and semantic status.
text = text.replace(
    '''    var body: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceMD) {
            commandHeader''',
    '''    var body: some View {
        VStack(alignment: .leading, spacing: PPFulfillmentTokens.spaceSM) {
            commandHeader''',
    1,
)
text = text.replace('''        .padding(PPFulfillmentTokens.spaceBase)
        .background(hasChanged ? record.tone.color.opacity(0.045) : Color.clear)''', '''        .padding(.horizontal, PPFulfillmentTokens.spaceBase)
        .padding(.vertical, PPFulfillmentTokens.spaceMD)
        .background(hasChanged ? record.tone.color.opacity(0.045) : Color.clear)''', 1)

# Eliminate decorative timeline glow; state remains communicated by symbol/color/text.
text = text.replace('''                    .frame(width: 18, height: 18)
                    .shadow(color: tone.color.opacity(0.35), radius: 4)''', '''                    .frame(width: 18, height: 18)''', 1)

path.write_text(text)
print("Applied Fulfillment V6 presentation pass.")
