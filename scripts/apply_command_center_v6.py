#!/usr/bin/env python3
from pathlib import Path

path = Path("PurePetsAdmin/Features/CommandCenter/AdminCommandCenterScreen.swift")
source = path.read_text(encoding="utf-8")
source = source.replace("signals.prefix(8)", "signals.prefix(6)")
source = source.replace("@available(iOS 16.0, *)\n@MainActor\n@objcMembers\npublic final class AdminCommandOrbitHostingController", "@MainActor\n@objcMembers\npublic final class AdminCommandOrbitHostingController")
marker = "// MARK: - Typography (Beiruti Brand Font)"
if marker not in source:
    raise SystemExit("Command Center presentation marker not found")
head = source.split(marker, 1)[0]

tail = r'''// MARK: - SwiftyMax V6 Priority Handoff Presentation

private enum AdminCommandMetric {
    static let pageMargin: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    static let cardRadius: CGFloat = 22
    static let compactRadius: CGFloat = 16
    static let iconSize: CGFloat = 44
    static let minimumActionHeight: CGFloat = 52
}

private enum AdminCommandTone {
    case critical
    case elevated
    case normal
    case info

    var color: Color {
        switch self {
        case .critical: return Color(uiColor: .ppError)
        case .elevated: return Color(uiColor: .ppWarning)
        case .normal: return Color(uiColor: .ppSuccess)
        case .info: return Color(uiColor: .ppInfo)
        }
    }

    var symbol: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .elevated: return "exclamationmark.circle.fill"
        case .normal: return "checkmark.circle.fill"
        case .info: return "arrow.triangle.2.circlepath"
        }
    }
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
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AdminCommandMetric.sectionSpacing) {
                operationalContext
                phaseContent
            }
            .padding(.horizontal, AdminCommandMetric.pageMargin)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .environment(\.layoutDirection, direction)
        .environment(\.locale, locale)
    }

    private var operationalContext: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n("AdminCommandCenter_Role"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(store.snapshot.roleName.isEmpty ? L10n("pp_role_admin") : store.snapshot.roleName)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(moduleCountText)
                    .font(AdminType.footnoteBold)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.trailing)
            }

            Divider()

            HStack(spacing: 10) {
                Image(systemName: readinessTone.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(readinessTone.color)
                    .frame(width: 28, height: 28)
                    .background(readinessTone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)

                Text(readinessText)
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminCommandMetric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminCommandMetric.cardRadius, style: .continuous)
                .stroke(AdminSurface.hairline)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .connecting:
            statePanel(
                tone: .info,
                title: L10n("AdminCommandCenter_Connecting"),
                detail: L10n("AdminCommandCenter_Connecting_Detail"),
                showsProgress: true,
                actionTitle: nil,
                action: nil
            )
        case .loading:
            statePanel(
                tone: .info,
                title: L10n("AdminCommandCenter_Confirming"),
                detail: confirmingDetail,
                showsProgress: true,
                actionTitle: nil,
                action: nil
            )
        case .ready:
            readyContent
        case .allClear:
            statePanel(
                tone: .normal,
                title: L10n("AdminCommandCenter_AllClear_Title"),
                detail: L10n("AdminCommandCenter_AllClear_Detail"),
                showsProgress: false,
                actionTitle: nil,
                action: nil
            )
        case .degradedEmpty:
            statePanel(
                tone: .critical,
                title: L10n("AdminCommandCenter_Failed_Title"),
                detail: failedDetail,
                showsProgress: false,
                actionTitle: L10n("AdminCommandCenter_Retry"),
                action: store.onRefresh
            )
        case .denied:
            statePanel(
                tone: .elevated,
                title: L10n("AdminCommandCenter_NoAccess_Title"),
                detail: L10n("AdminCommandCenter_NoAccess_Detail"),
                showsProgress: false,
                actionTitle: nil,
                action: nil
            )
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: AdminCommandMetric.sectionSpacing) {
            if !store.readiness.failedAreas.isEmpty {
                readinessWarning
            }

            if let primary = store.snapshot.signals.first {
                CommandPrimarySignalCard(
                    signal: primary,
                    locale: locale,
                    action: { store.onRoute?(primary.id) }
                )
            }

            let remaining = Array(store.snapshot.signals.dropFirst())
            if !remaining.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n("AdminCommandCenter_OtherPriorities"))
                        .font(AdminType.title3)
                        .foregroundColor(AdminSurface.primaryText)

                    VStack(spacing: 0) {
                        ForEach(Array(remaining.enumerated()), id: \.element.id) { index, signal in
                            Button {
                                store.onRoute?(signal.id)
                            } label: {
                                CommandSignalRow(
                                    signal: signal,
                                    locale: locale,
                                    showsDivider: index < remaining.count - 1
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminCommandMetric.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminCommandMetric.cardRadius, style: .continuous)
                            .stroke(AdminSurface.hairline)
                    )
                }
            }
        }
    }

    private var readinessWarning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(uiColor: .ppWarning))
                .frame(width: 36, height: 36)
                .background(Color(uiColor: .ppWarning).opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            Text(failedDetail)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .ppWarning).opacity(0.06), in: RoundedRectangle(cornerRadius: AdminCommandMetric.compactRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminCommandMetric.compactRadius, style: .continuous)
                .stroke(Color(uiColor: .ppWarning).opacity(0.20))
        )
        .accessibilityElement(children: .combine)
    }

    private func statePanel(
        tone: AdminCommandTone,
        title: String,
        detail: String,
        showsProgress: Bool,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tone.color.opacity(0.10))
                if showsProgress {
                    ProgressView().tint(tone.color)
                } else {
                    Image(systemName: tone.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(tone.color)
                }
            }
            .frame(width: 54, height: 54)
            .accessibilityHidden(true)

            Text(title)
                .font(AdminType.title3)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.center)

            Text(detail)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AdminType.calloutBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: AdminCommandMetric.minimumActionHeight)
                        .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminCommandMetric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminCommandMetric.cardRadius, style: .continuous)
                .stroke(AdminSurface.hairline)
        )
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }

    private var readinessTone: AdminCommandTone {
        if !store.readiness.failedAreas.isEmpty { return .elevated }
        if !store.readiness.loadingAreas.isEmpty || !store.snapshot.isInitialized { return .info }
        return .normal
    }

    private var readinessText: String {
        if !store.readiness.failedAreas.isEmpty { return failedDetail }
        if !store.readiness.loadingAreas.isEmpty { return confirmingDetail }
        if !store.snapshot.isInitialized { return L10n("AdminCommandCenter_Connecting_Detail") }
        return L10n("AdminCommandCenter_Ready_Detail")
    }

    private var confirmingDetail: String {
        guard !store.readiness.loadingAreas.isEmpty else {
            return L10n("AdminCommandCenter_Confirming_Detail")
        }
        return String(
            format: L10n("AdminCommandCenter_Confirming_Format"),
            store.readiness.loadingAreas.joined(separator: ", ")
        )
    }

    private var failedDetail: String {
        guard !store.readiness.failedAreas.isEmpty else {
            return L10n("AdminCommandCenter_Degraded_Generic")
        }
        return String(
            format: L10n("AdminCommandCenter_Degraded_Format"),
            store.readiness.failedAreas.joined(separator: ", ")
        )
    }

    private var moduleCountText: String {
        String(
            format: L10n("AdminCommand_ModuleCount_Format"),
            store.snapshot.capabilityCount
        )
    }

    private func L10n(_ key: String) -> String {
        Language.get(key, alter: nil)
    }
}

private struct CommandPrimarySignalCard: View {
    let signal: AdminCommandOrbitSignal
    let locale: Locale
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 16) { cardContent }
                } else {
                    cardContent
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminCommandMetric.cardRadius, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tone.color)
                    .frame(width: 4)
                    .padding(.vertical, 14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: AdminCommandMetric.cardRadius, style: .continuous)
                    .stroke(AdminSurface.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: AdminCommandMetric.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Language.get("AdminCommandCenter_OpenHint", alter: nil))
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                statusIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(signal.moduleTitle)
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(priorityTitle)
                        .font(AdminType.calloutBold)
                        .foregroundColor(tone.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(formattedCount(signal.count))
                    .font(AdminType.title2)
                    .foregroundColor(AdminSurface.primaryText)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(signal.title)
                    .font(AdminType.title3)
                    .foregroundColor(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !signal.detail.isEmpty {
                    Text(signal.detail)
                        .font(AdminType.callout)
                        .foregroundColor(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Text(Language.get("AdminCommandCenter_Act", alter: nil))
                    .font(AdminType.calloutBold)
                    .foregroundColor(tone.color)
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tone.color)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                if signal.isLive {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(uiColor: .ppInfo))
                        .accessibilityLabel(Language.get("CommandCenter_Live", alter: nil))
                }
            }
        }
    }

    private var statusIcon: some View {
        Image(systemName: signal.symbolName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(tone.color)
            .frame(width: AdminCommandMetric.iconSize, height: AdminCommandMetric.iconSize)
            .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }

    private var tone: AdminCommandTone {
        if signal.urgency >= 2 { return .critical }
        if signal.urgency == 1 { return .elevated }
        return .normal
    }

    private var priorityTitle: String {
        switch tone {
        case .critical: return Language.get("AdminCommandCenter_Priority_Critical", alter: nil)
        case .elevated: return Language.get("AdminCommandCenter_Priority_Elevated", alter: nil)
        default: return Language.get("AdminCommandCenter_Priority_Normal", alter: nil)
        }
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }
}

private struct CommandSignalRow: View {
    let signal: AdminCommandOrbitSignal
    let locale: Locale
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: signal.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tone.color)
                    .frame(width: 40, height: 40)
                    .background(tone.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(signal.moduleTitle)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                        Image(systemName: tone.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(tone.color)
                            .accessibilityHidden(true)
                    }
                    Text(signal.title)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !signal.detail.isEmpty {
                        Text(signal.detail)
                            .font(AdminType.footnote)
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(signal.count.formatted(.number.locale(locale)))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .monospacedDigit()
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 72)
            .contentShape(Rectangle())

            if showsDivider {
                Divider().padding(.leading, 70)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Language.get("AdminCommandCenter_OpenHint", alter: nil))
    }

    private var tone: AdminCommandTone {
        if signal.urgency >= 2 { return .critical }
        if signal.urgency == 1 { return .elevated }
        return .normal
    }
}
'''

path.write_text(head + tail, encoding="utf-8")
print("Applied Command Center SwiftyMax V6 Priority Handoff")
