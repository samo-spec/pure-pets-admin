import SwiftUI

@MainActor
struct AdminAppShell: View {
    let session: AdminSession
    @ObservedObject var sessionStore: AdminSessionStore
    @ObservedObject var router: AdminRouter

    @State private var selectedTab: AdminTab = .command
    @State private var showsLogoutConfirmation = false
    @StateObject private var commandState: CommandCenterState

    init(session: AdminSession, sessionStore: AdminSessionStore, router: AdminRouter) {
        self.session = session
        self.sessionStore = sessionStore
        self.router = router
        _commandState = StateObject(wrappedValue: CommandCenterState(session: session))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CommandCenterView(session: session, router: router, state: commandState)
                .tabItem { tabLabel(.command) }
                .tag(AdminTab.command)

            AdminModuleListView(
                titleKey: "CommandCenter_Work_Title",
                detailKey: "CommandCenter_Work_Detail",
                routes: available([.payments, .fulfillment, .pointOfSale, .pointOfSaleHistory, .accessories, .food, .livePets]),
                session: session,
                router: router,
                commandState: commandState,
                onOpenCommand: { selectedTab = .command }
            )
            .tabItem { tabLabel(.work) }
            .tag(AdminTab.work)

            AdminModuleListView(
                titleKey: "CommandCenter_Operations_Title",
                detailKey: "CommandCenter_Operations_Detail",
                routes: available([.delivery, .providerApplications, .providerPlans, .providerFeatures, .providerAccounting, .branches, .agents, .homeControl, .services, .veterinarians, .moderation]),
                session: session,
                router: router,
                commandState: commandState,
                onOpenCommand: { selectedTab = .command }
            )
            .tabItem { tabLabel(.operations) }
            .tag(AdminTab.operations)

            AdminModuleListView(
                titleKey: "CommandCenter_People_Title",
                detailKey: "CommandCenter_People_Detail",
                routes: available([.users, .staff, .chats]),
                session: session,
                router: router,
                commandState: commandState,
                onOpenCommand: { selectedTab = .command }
            )
            .tabItem { tabLabel(.customers) }
            .tag(AdminTab.customers)

            AdminMoreView(
                session: session,
                routes: available([.account, .notifications, .notificationComposer, .notificationSettings, .accounting, .audit, .categories, .banners, .listings, .settings]),
                router: router,
                commandState: commandState,
                isSigningOut: sessionStore.isSigningOut,
                onLogout: { showsLogoutConfirmation = true },
                onOpenCommand: { selectedTab = .command }
            )
            .tabItem { tabLabel(.more) }
            .tag(AdminTab.more)
        }
        .tint(AdminSurface.primary)
        .fullScreenCover(item: $router.presentedRoute) { route in
            AdminLegacyRouteView(route: route) { router.presentedRoute = nil }
                .ignoresSafeArea()
        }
        .alert(Language.get("CommandCenter_Permission_Denied_Title", alter: nil), isPresented: $router.permissionDenied) {
            Button(Language.get("OK", alter: nil), role: .cancel) {}
        } message: {
            Text(Language.get("CommandCenter_Permission_Denied_Message", alter: nil))
        }
        .alert(Language.get("Logout_Confirm_Title", alter: nil), isPresented: $showsLogoutConfirmation) {
            Button(Language.get("Cancel", alter: nil), role: .cancel) {}
            Button(Language.get("Logout", alter: nil), role: .destructive, action: sessionStore.signOut)
        } message: {
            Text(Language.get("Logout_Confirm_Message", alter: nil))
        }
        .onAppear {
            commandState.loadIfNeeded()
            router.consumePendingRoute(session: session)
        }
        .onChange(of: session) { updatedSession in
            commandState.updateSession(updatedSession)
            guard let route = router.presentedRoute else { return }
            if !route.isAuthorized(for: updatedSession) {
                router.presentedRoute = nil
            }
        }
    }

    @ViewBuilder
    private func tabLabel(_ tab: AdminTab) -> some View {
        Label(Language.get(tab.titleKey, alter: nil), systemImage: tab.symbol)
    }

    private func available(_ routes: [AdminRoute]) -> [AdminRoute] {
        routes.filter { $0.isAuthorized(for: session) }
    }
}

@MainActor
private struct AdminModuleListView: View {
    let titleKey: String
    let detailKey: String
    let routes: [AdminRoute]
    let session: AdminSession
    @ObservedObject var router: AdminRouter
    @ObservedObject var commandState: CommandCenterState
    let onOpenCommand: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    AdminConnectedSectionHeader(titleKey: titleKey, detailKey: detailKey)
                    AdminCommandPulseStrip(state: commandState, onOpenCommand: onOpenCommand)
                    if routes.isEmpty {
                        AdminEmptyRoutesView()
                    } else {
                        ForEach(routes) { route in
                            Button { router.present(route, session: session) } label: {
                                AdminRouteRow(route: route)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
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

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    AdminConnectedSectionHeader(
                        titleKey: "CommandCenter_Tab_More",
                        detailKey: "CommandCenter_Contextual_Actions_Detail"
                    )
                    AdminCommandPulseStrip(state: commandState, onOpenCommand: onOpenCommand)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.displayName)
                            .font(AdminType.title2)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(session.localizedRoleName)
                            .font(AdminType.callout)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(session.email)
                            .font(AdminType.footnote)
                            .foregroundColor(AdminSurface.secondaryText)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AdminSurface.hairline))
                    .accessibilityElement(children: .combine)

                    ForEach(routes) { route in
                        Button { router.present(route, session: session) } label: { AdminRouteRow(route: route) }
                            .buttonStyle(.plain)
                    }

                    Button {
                        let next = Language.currentLanguageCode() == "ar" ? "en" : "ar"
                        Language.userSelectedLanguage(next)
                    } label: {
                        Label(Language.get("Confirm_LanguageChange_Title", alter: nil), systemImage: "globe")
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(AdminSurface.control, in: Capsule())
                            .overlay(Capsule().stroke(AdminSurface.hairline))
                    }

                    Button(role: .destructive, action: onLogout) {
                        HStack(spacing: 10) {
                            if isSigningOut { ProgressView().tint(Color(uiColor: .ppError)) }
                            Label(Language.get(isSigningOut ? "CommandCenter_Signing_Out" : "Logout", alter: nil), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .font(AdminType.calloutBold)
                        .foregroundColor(Color(uiColor: .ppError))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(uiColor: .ppError).opacity(0.09), in: Capsule())
                        .overlay(Capsule().stroke(Color(uiColor: .ppError).opacity(0.20)))
                    }
                    .disabled(isSigningOut)
                }
                .padding(20)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}

private struct AdminConnectedSectionHeader: View {
    let titleKey: String
    let detailKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Language.get("CommandCenter_Eyebrow", alter: nil))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primary)
                .textCase(.uppercase)
            Text(Language.get(titleKey, alter: nil))
                .font(AdminType.title)
                .foregroundColor(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(Language.get(detailKey, alter: nil))
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
                Image(systemName: pulseSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(pulseColor)
                    .frame(width: 36, height: 36)
                    .background(pulseColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("CommandCenter_Title", alter: nil))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(pulseTitle)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .foregroundColor(AdminSurface.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(pulseColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(pulseColor.opacity(0.20)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

struct AdminRouteRow: View {
    let route: AdminRoute

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: route.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 44, height: 44)
                .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(Language.get(route.contextTitleKey, alter: nil))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)
                Text(Language.get(route.titleKey, alter: nil))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                .foregroundColor(AdminSurface.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(minHeight: 68)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline))
        .contentShape(Rectangle())
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
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(AdminSurface.secondaryText)
            Text(title).font(AdminType.headline).foregroundColor(AdminSurface.primaryText)
            Text(message)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
