#!/usr/bin/env python3
from pathlib import Path

path = Path("PurePetsAdmin/App/AdminAppShell.swift")
source = path.read_text(encoding="utf-8")
marker = "// MARK: - V6 Global Tab Bar"
if marker not in source:
    raise SystemExit("V6 tab bar marker not found")
head = source.split(marker, 1)[0]

tail = r'''// MARK: - V6 Global Tab Bar

private enum AdminShellMetric {
    static let pageMargin: CGFloat = 20
    static let groupRadius: CGFloat = 22
    static let compactRadius: CGFloat = 16
    static let rowMinimumHeight: CGFloat = 68
    static let tabBarTopInset: CGFloat = 8
    static let tabBarHorizontalInset: CGFloat = 10
    static let tabItemMinimumHeight: CGFloat = 58
}

struct V6GlobalTabBar: View {
    @Binding var selectedTab: AdminTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(AdminTab.allCases) { tab in
                tabItem(tab)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, AdminShellMetric.tabBarHorizontalInset)
        .padding(.top, AdminShellMetric.tabBarTopInset)
        .padding(.bottom, 6)
        .background(AdminSurface.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 1 / UIScreen.main.scale)
                .accessibilityHidden(true)
        }
    }

    private func tabItem(_ tab: AdminTab) -> some View {
        let isSelected = selectedTab == tab
        let title = Language.get(tab.titleKey, alter: nil)

        return Button {
            guard selectedTab != tab else { return }
            if reduceMotion {
                selectedTab = tab
            } else {
                withAnimation(.easeOut(duration: 0.16)) {
                    selectedTab = tab
                }
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AdminSurface.primary.opacity(0.11) : Color.clear)
                        .frame(width: 38, height: 30)
                    Image(systemName: tab.symbol)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)
                }
                .accessibilityHidden(true)

                Text(title)
                    .font(isSelected ? AdminType.captionBold : AdminType.caption1)
                    .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: AdminShellMetric.tabItemMinimumHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(V6CardButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared shell interaction style

struct V6CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
    }
}

@MainActor
private struct AdminModuleListView: View {
    let tab: AdminTab
    let routes: [AdminRoute]
    let session: AdminSession
    @ObservedObject var router: AdminRouter
    @ObservedObject var commandState: CommandCenterState
    let onOpenCommand: () -> Void

    private var navigationConfiguration: PPGlobalNavigationConfiguration {
        PPGlobalNavigationConfiguration(
            style: .contextDeck,
            title: Language.get(tab.titleKey, alter: nil),
            eyebrow: Language.get("CommandCenter_Eyebrow", alter: nil),
            subtitle: detailText,
            showsContextFilament: false
        )
    }

    private var detailText: String? {
        let key: String?
        switch tab {
        case .work: key = "CommandCenter_Work_Detail"
        case .operations: key = "CommandCenter_Operations_Detail"
        case .customers: key = "CommandCenter_People_Detail"
        default: key = nil
        }
        return key.map { Language.get($0, alter: nil) }
    }

    var body: some View {
        PPGlobalNavigationScrollShell(configuration: navigationConfiguration, onAction: { _ in }) {
            LazyVStack(alignment: .leading, spacing: 16) {
                AdminCommandPulseStrip(state: commandState, onOpenCommand: onOpenCommand)

                if routes.isEmpty {
                    AdminEmptyRoutesView()
                } else {
                    AdminRouteGroup(
                        routes: routes,
                        action: { router.present($0, session: session) }
                    )
                }
            }
            .padding(.horizontal, AdminShellMetric.pageMargin)
            .padding(.bottom, 8)
        }
    }
}

@MainActor
private struct AdminMoreView: View {
    let session: AdminSession
    let routes: [AdminRoute]
    @ObservedObject var router: AdminRouter
    @ObservedObject var commandState: CommandCenterState
    let isSigningOut: Bool
    let onLogout: () -> Void
    let onOpenCommand: () -> Void

    private var navigationConfiguration: PPGlobalNavigationConfiguration {
        PPGlobalNavigationConfiguration(
            style: .contextDeck,
            title: Language.get(AdminTab.more.titleKey, alter: nil),
            eyebrow: Language.get("CommandCenter_Eyebrow", alter: nil),
            subtitle: Language.get("CommandCenter_Contextual_Actions_Detail", alter: nil),
            showsContextFilament: false
        )
    }

    var body: some View {
        PPGlobalNavigationScrollShell(configuration: navigationConfiguration, onAction: { _ in }) {
            LazyVStack(alignment: .leading, spacing: 16) {
                AdminCommandPulseStrip(state: commandState, onOpenCommand: onOpenCommand)
                AdminProfileSummaryCard(session: session)

                if !routes.isEmpty {
                    AdminRouteGroup(
                        routes: routes,
                        action: { router.present($0, session: session) }
                    )
                }

                AdminUtilityActionGroup(
                    isSigningOut: isSigningOut,
                    onLanguage: {
                        let next = Language.currentLanguageCode() == "ar" ? "en" : "ar"
                        Language.userSelectedLanguage(next)
                    },
                    onLogout: onLogout
                )
            }
            .padding(.horizontal, AdminShellMetric.pageMargin)
            .padding(.bottom, 8)
        }
    }
}

private struct AdminProfileSummaryCard: View {
    let session: AdminSession

    var body: some View {
        HStack(spacing: 14) {
            Text(monogram)
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primary)
                .frame(width: 48, height: 48)
                .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayName)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(session.localizedRoleName)
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
                Text(session.email)
                    .font(AdminType.footnote)
                    .foregroundColor(AdminSurface.secondaryText)
                    .environment(\.layoutDirection, .leftToRight)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminShellMetric.groupRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminShellMetric.groupRadius, style: .continuous)
                .stroke(AdminSurface.hairline)
        )
        .accessibilityElement(children: .combine)
    }

    private var monogram: String {
        let parts = session.displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "PP" : letters.uppercased()
    }
}

private struct AdminUtilityActionGroup: View {
    let isSigningOut: Bool
    let onLanguage: () -> Void
    let onLogout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onLanguage) {
                AdminUtilityRow(
                    title: Language.get("Confirm_LanguageChange_Title", alter: nil),
                    symbol: "globe",
                    tint: AdminSurface.primary,
                    showsProgress: false
                )
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 58)

            Button(role: .destructive, action: onLogout) {
                AdminUtilityRow(
                    title: Language.get(isSigningOut ? "CommandCenter_Signing_Out" : "Logout", alter: nil),
                    symbol: "rectangle.portrait.and.arrow.right",
                    tint: Color(uiColor: .ppError),
                    showsProgress: isSigningOut
                )
            }
            .buttonStyle(.plain)
            .disabled(isSigningOut)
        }
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminShellMetric.groupRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminShellMetric.groupRadius, style: .continuous)
                .stroke(AdminSurface.hairline)
        )
    }
}

private struct AdminUtilityRow: View {
    let title: String
    let symbol: String
    let tint: Color
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.10))
                if showsProgress {
                    ProgressView().tint(tint)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(tint)
                }
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            Text(title)
                .font(AdminType.calloutBold)
                .foregroundColor(tint == AdminSurface.primary ? AdminSurface.primaryText : tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AdminSurface.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: AdminShellMetric.rowMinimumHeight)
        .contentShape(Rectangle())
    }
}

@MainActor
private struct AdminCommandPulseStrip: View {
    @ObservedObject var state: CommandCenterState
    let onOpenCommand: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onOpenCommand) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(pulseColor.opacity(0.10))
                    Image(systemName: pulseSymbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(pulseColor)
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("CommandCenter_Title", alter: nil))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(pulseTitle)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 64)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminShellMetric.compactRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminShellMetric.compactRadius, style: .continuous)
                    .stroke(AdminSurface.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(V6CardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Language.get("CommandCenter_Open_Detail", alter: nil))
    }

    private var pulseTitle: String {
        guard let snapshot = state.currentSnapshot else {
            return Language.get("CommandCenter_Loading", alter: nil)
        }
        switch snapshot.health {
        case .stable:
            return Language.get("CommandCenter_Health_Stable", alter: nil)
        case let .attention(count):
            return String(format: Language.get("CommandCenter_Health_Attention_Format", alter: nil), formattedCount(count))
        case let .partial(count):
            return String(format: Language.get("CommandCenter_Health_Partial_Format", alter: nil), formattedCount(count))
        }
    }

    private var pulseSymbol: String {
        guard let snapshot = state.currentSnapshot else { return "arrow.triangle.2.circlepath" }
        switch snapshot.health {
        case .stable: return "checkmark.shield.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .partial: return "arrow.triangle.2.circlepath"
        }
    }

    private var pulseColor: Color {
        guard let snapshot = state.currentSnapshot else { return AdminSurface.primary }
        switch snapshot.health {
        case .stable: return Color(uiColor: .ppSuccess)
        case .attention: return Color(uiColor: .ppWarning)
        case .partial: return AdminSurface.primary
        }
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }
}

private struct AdminRouteGroup: View {
    let routes: [AdminRoute]
    let action: (AdminRoute) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                Button { action(route) } label: {
                    AdminRouteRow(route: route, showsSeparator: index < routes.count - 1)
                }
                .buttonStyle(.plain)
            }
        }
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminShellMetric.groupRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminShellMetric.groupRadius, style: .continuous)
                .stroke(AdminSurface.hairline)
        )
    }
}

struct AdminRouteRow: View {
    let route: AdminRoute
    var showsSeparator = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: route.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 40, height: 40)
                    .background(AdminSurface.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                Text(Language.get(route.titleKey, alter: nil))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: AdminShellMetric.rowMinimumHeight)
            .contentShape(Rectangle())

            if showsSeparator {
                Divider().padding(.leading, 70)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Language.get("CommandCenter_Open_Detail", alter: nil))
    }
}

private struct AdminEmptyRoutesView: View {
    var body: some View {
        ContentUnavailableCompat(
            title: Language.get("CommandCenter_No_Routes_Title", alter: nil),
            message: Language.get("CommandCenter_No_Routes_Message", alter: nil),
            symbol: "lock.shield"
        )
    }
}

struct ContentUnavailableCompat: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(AdminSurface.secondaryText)
                .frame(width: 52, height: 52)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminShellMetric.groupRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminShellMetric.groupRadius, style: .continuous)
                .stroke(AdminSurface.hairline)
        )
        .accessibilityElement(children: .combine)
    }
}
'''

path.write_text(head + tail, encoding="utf-8")
print("Applied Admin shell V6 redesign")
