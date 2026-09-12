import SwiftUI

@MainActor
struct AdminAppShell: View {
    let session: AdminSession
    @ObservedObject var sessionStore: AdminSessionStore
    @ObservedObject var router: AdminRouter

    @State private var selectedTab: AdminTab = .command
    @State private var commandShowsNestedWorkflow = false
    @State private var showsLogoutConfirmation = false
    @StateObject private var commandState: CommandCenterState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var availableTabs: [AdminTab] {
        let tabs = AdminTab.allCases.filter { $0.isAuthorized(for: session) }
        return tabs.isEmpty ? [.more] : tabs
    }

    init(session: AdminSession, sessionStore: AdminSessionStore, router: AdminRouter) {
        self.session = session
        self.sessionStore = sessionStore
        self.router = router
        _commandState = StateObject(wrappedValue: CommandCenterState(session: session))
        UITabBar.appearance().isHidden = true

        let authorized = AdminTab.allCases.filter { $0.isAuthorized(for: session) }
        _selectedTab = State(initialValue: authorized.first ?? .more)
    }

    var body: some View {
        NavigationView {
            shellContent
                .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var shellContent: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .command:
                    AdminCommandOrbitDashboard(
                        session: session,
                        languageCode: sessionStore.languageCode,
                        onNavigationDepthChanged: { commandShowsNestedWorkflow = $0 }
                    )
                    .ignoresSafeArea()

                case .work:
                    AdminWorkDeckView(
                        session: session,
                        router: router,
                        commandState: commandState,
                        onOpenCommand: { selectedTab = .command }
                    )
                    .ignoresSafeArea()

                case .operations:
                    AdminOperationsDeckView(
                        session: session,
                        router: router,
                        commandState: commandState,
                        onOpenCommand: { selectedTab = .command }
                    )
                    .ignoresSafeArea()

                case .customers:
                    AdminPeopleDeckView(
                        session: session,
                        router: router,
                        commandState: commandState,
                        onOpenCommand: { selectedTab = .command }
                    )
                    .ignoresSafeArea()

                case .more:
                    AdminMoreView(
                        session: session,
                        routes: available([.account, .notifications, .notificationComposer, .notificationSettings, .accounting, .audit, .categories, .banners, .listings]),
                        router: router,
                        commandState: commandState,
                        isSigningOut: sessionStore.isSigningOut,
                        onLogout: { showsLogoutConfirmation = true },
                        onOpenCommand: { selectedTab = .command }
                    )
                    .ignoresSafeArea()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !(selectedTab == .command && commandShowsNestedWorkflow) {
                V6GlobalTabBar(selectedTab: $selectedTab, tabs: availableTabs, session: session)
            }
        }
        .ignoresSafeArea()
        .tint(AdminSurface.primary)
        .background(routePushLink)
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
            if !availableTabs.contains(selectedTab) {
                selectedTab = availableTabs.first ?? .more
            }
            router.consumePendingRoute(session: session)
        }
        .onChange(of: selectedTab) { tab in
            if tab != .command {
                commandState.loadIfNeeded()
            }
        }
        .onChange(of: session) { updatedSession in
            commandState.updateSession(updatedSession)
            let updatedTabs = AdminTab.allCases.filter { $0.isAuthorized(for: updatedSession) }
            if !updatedTabs.contains(selectedTab) {
                selectedTab = updatedTabs.first ?? .more
            }
            guard let route = router.presentedRoute else { return }
            if !route.isAuthorized(for: updatedSession) {
                router.presentedRoute = nil
            }
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSNotification.Name.PPActiveBranchDidChange)
                .receive(on: RunLoop.main)
        ) { _ in
            commandState.refresh()
        }
    }

    /// Module routes are full screens, so the shell pushes them instead of
    /// presenting another modal layer. Dedicated sheets and transient system
    /// presenters remain owned by their existing call sites.
    private var routePushLink: some View {
        NavigationLink(
            destination: routeDestination,
            isActive: Binding(
                get: { router.presentedRoute != nil },
                set: { isActive in
                    if !isActive {
                        router.presentedRoute = nil
                    }
                }
            )
        ) {
            EmptyView()
        }
        .hidden()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var routeDestination: some View {
        if let route = router.presentedRoute {
            AdminRouteDestinationView(route: route, session: session, router: router)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .navigationBarHidden(true)
                .toolbar(.hidden, for: .navigationBar)
                // UIKit continues to own both safe-area edges for legacy route
                // containers; the push only replaces the former modal handoff.
                .ignoresSafeArea()
        } else {
            EmptyView()
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
private struct AdminCommandOrbitDashboard: UIViewControllerRepresentable {
    let session: AdminSession
    let languageCode: String
    let onNavigationDepthChanged: (Bool) -> Void

    func makeUIViewController(context: Context) -> AdminCommandOrbitContainerController {
        let controller = AdminCommandOrbitContainerController()
        controller.onNavigationDepthChanged = onNavigationDepthChanged
        return controller
    }

    func updateUIViewController(_ controller: AdminCommandOrbitContainerController, context: Context) {
        controller.onNavigationDepthChanged = onNavigationDepthChanged
        controller.refresh(session: session, languageCode: languageCode)
    }
}

private final class AdminCommandOrbitContainerController: UIViewController, UINavigationControllerDelegate {
    var onNavigationDepthChanged: ((Bool) -> Void)?
    private let dashboard = PPAdminCreateCommandSpineDashboardController()
    private var workflowNavigationController: AdminCommandOrbitNavigationController?
    private var appliedLanguageCode: String?
    private var appliedSession: AdminSession?
    private var authorizationRefreshGeneration = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage()

        let navigationController = AdminCommandOrbitNavigationController(rootViewController: dashboard)
        workflowNavigationController = navigationController
        PPSetCommandCenterNavigationManaged(navigationController, true)
        navigationController.delegate = self
        applyGlobalNavigationPresentation(to: dashboard, in: navigationController)

        addChild(navigationController)
        view.addSubview(navigationController.view)
        navigationController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navigationController.view.topAnchor.constraint(equalTo: view.topAnchor),
            navigationController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        navigationController.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        workflowNavigationController?.viewWillAppear(animated)
        PPAdminRefreshCommandSpineDashboard(dashboard)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshBottomDockLanguage()
        applyBottomDockPolish()
        PPAdminRefreshCommandSpineDashboard(dashboard)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyBottomDockPolish()
    }

    /// Refines only the system-owned TabView appearance. The five stable tab
    /// identifiers, selection state, symbols, labels, and routing stay owned by
    /// `AdminAppShell` and `AdminTab`.
    private func applyBottomDockPolish() {
        guard let tabBarController else { return }
        let tabBar = tabBarController.tabBar

        tabBarController.view.backgroundColor = .ppBackground
        tabBar.backgroundColor = .ppBackground
        tabBar.isTranslucent = false
        tabBar.tintColor = .ppPrimary
        tabBar.unselectedItemTintColor = .ppTextSecondary

        let appearance = (tabBar.standardAppearance.copy() as? UITabBarAppearance)
            ?? UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .ppBackground
        appearance.backgroundEffect = nil
        appearance.shadowColor = UIColor.ppSurfaceBorder.withAlphaComponent(0.72)

        let normalBaseFont = UIFont(name: "Beiruti-Medium", size: 11)
            ?? UIFont.systemFont(ofSize: 11, weight: .medium)
        let selectedBaseFont = UIFont(name: "Beiruti-Bold", size: 11)
            ?? UIFont.systemFont(ofSize: 11, weight: .semibold)
        let fontMetrics = UIFontMetrics(forTextStyle: .caption2)
        let normalFont = fontMetrics.scaledFont(for: normalBaseFont, maximumPointSize: 13)
        let selectedFont = fontMetrics.scaledFont(for: selectedBaseFont, maximumPointSize: 13)

        for itemAppearance in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            itemAppearance.normal.iconColor = .ppTextSecondary
            itemAppearance.normal.titleTextAttributes = [
                .font: normalFont,
                .foregroundColor: UIColor.ppTextSecondary,
            ]
            itemAppearance.selected.iconColor = .ppPrimary
            itemAppearance.selected.titleTextAttributes = [
                .font: selectedFont,
                .foregroundColor: UIColor.ppPrimary,
            ]
        }

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    /// Updates presentation metadata in place so a language switch never
    /// rebuilds the tab controller or its stateful child workflows.
    private func refreshBottomDockLanguage() {
        guard let tabBarController, let items = tabBarController.tabBar.items else { return }

        let direction = Language.semanticAttributeForCurrentLanguage()
        tabBarController.view.semanticContentAttribute = direction
        tabBarController.tabBar.semanticContentAttribute = direction

        for (item, tab) in zip(items, AdminTab.allCases) {
            let title = Language.get(tab.titleKey, alter: nil)
            item.title = title
            item.accessibilityLabel = title
        }

        tabBarController.tabBar.setNeedsLayout()
        tabBarController.tabBar.layoutIfNeeded()
    }

    func refresh(session: AdminSession, languageCode: String) {
        let authorizationChanged = appliedSession != session
        appliedSession = session
        let languageChanged = appliedLanguageCode != languageCode
        appliedLanguageCode = languageCode

        let direction = Language.semanticAttributeForCurrentLanguage()
        view.semanticContentAttribute = direction
        view.backgroundColor = .ppBackground
        workflowNavigationController?.view.semanticContentAttribute = direction
        workflowNavigationController?.view.backgroundColor = .ppBackground
        workflowNavigationController?.topViewController?.view.semanticContentAttribute = direction
        workflowNavigationController?.topViewController?.view.backgroundColor = .ppBackground
        refreshBottomDockLanguage()
        applyBottomDockPolish()

        if authorizationChanged, dashboard.isViewLoaded {
            authorizationRefreshGeneration &+= 1
            let generation = authorizationRefreshGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.authorizationRefreshGeneration == generation,
                      self.appliedSession == session else {
                    return
                }
                PPAdminRefreshCommandSpineDashboard(self.dashboard)
                NotificationCenter.default.post(
                    name: Notification.Name("PPAdminCommandAuthorizationDidChangeNotification"),
                    object: self.dashboard
                )
            }
        }

        guard languageChanged else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.appliedLanguageCode == languageCode else { return }
            self.refreshBottomDockLanguage()
            self.applyBottomDockPolish()
        }
    }

    private func applyGlobalNavigationPresentation(to viewController: UIViewController,
                                                   in navigationController: UINavigationController) {
        let direction = Language.semanticAttributeForCurrentLanguage()
        viewController.view.semanticContentAttribute = direction
        viewController.view.backgroundColor = .ppBackground
        navigationController.view.semanticContentAttribute = direction
        navigationController.view.backgroundColor = .ppBackground
        navigationController.setNavigationBarHidden(true, animated: false)
        viewController.extendedLayoutIncludesOpaqueBars = true
        viewController.edgesForExtendedLayout = .all
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        onNavigationDepthChanged?(navigationController.viewControllers.first !== viewController)
        applyGlobalNavigationPresentation(to: viewController, in: navigationController)
    }

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
        onNavigationDepthChanged?(navigationController.viewControllers.first !== viewController)
    }
}

private final class AdminCommandOrbitNavigationController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        super.setNavigationBarHidden(true, animated: false)
        pp_enableSwipeToPop()
    }

    override func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        super.setNavigationBarHidden(true, animated: false)
    }
}

// MARK: - NextGen V6 Floating Morphic Command Dock

private enum AdminShellMetric {
    static let pageMargin: CGFloat = 20
    static let groupRadius: CGFloat = 22
    static let compactRadius: CGFloat = 16
    static let rowMinimumHeight: CGFloat = 68
    static let dockCornerRadius: CGFloat = 28
    static let dockItemRadius: CGFloat = 20
}

struct V6GlobalTabBar: View {
    @Binding var selectedTab: AdminTab
    var tabs: [AdminTab] = AdminTab.allCases
    var session: AdminSession? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    private var isPadWidescreen: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    private var bottomSafeAreaInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow }) ?? scenes.flatMap { $0.windows }.first
        let bottom = window?.safeAreaInsets.bottom ?? 0
        return max(bottom, 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Specular Top Hairline
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            AdminSurface.hairline.opacity(colorScheme == .dark ? 0.35 : 0.65),
                            AdminSurface.primary.opacity(colorScheme == .dark ? 0.25 : 0.15),
                            AdminSurface.hairline.opacity(colorScheme == .dark ? 0.20 : 0.40)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.75)

            // Dedicated Form-Factor Ergonomics
            if isPadWidescreen {
                AdminPadCountertopTabBar(
                    selectedTab: $selectedTab,
                    tabs: tabs,
                    session: session
                )
            } else {
                AdminPhoneDockedTabBar(
                    selectedTab: $selectedTab,
                    tabs: tabs
                )
            }

            // Safe Area Bottom Inset Floor Spacer
            Color.clear
                .frame(height: bottomSafeAreaInset)
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                AdminSurface.surface.opacity(colorScheme == .dark ? 0.92 : 0.96)
            }
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06), radius: 12, x: 0, y: -4)
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

// MARK: - iPhone Handheld Tactical Command Deck

private struct AdminPhoneDockedTabBar: View {
    @Binding var selectedTab: AdminTab
    let tabs: [AdminTab]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var phoneTabAnimationNamespace
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(tabs) { tab in
                phoneTabItem(tab)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .frame(height: 52)
    }

    private func phoneTabItem(_ tab: AdminTab) -> some View {
        let isSelected = selectedTab == tab
        let title = Language.get(tab.titleKey, alter: nil)
        let symbol = isSelected ? tab.selectedSymbol : tab.symbol

        return Button {
            guard selectedTab != tab else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if reduceMotion {
                selectedTab = tab
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                    selectedTab = tab
                }
            }
        } label: {
            ZStack {
                if isSelected {
                    // Fluid Matched-Geometry Active Capsule
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AdminSurface.primary.opacity(colorScheme == .dark ? 0.24 : 0.12),
                                    AdminSurface.primary.opacity(colorScheme == .dark ? 0.14 : 0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AdminSurface.primary.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 0.75)
                        )
                        .matchedGeometryEffect(id: "ActivePhoneTabIndicator", in: phoneTabAnimationNamespace)
                }

                VStack(spacing: 2) {
                    // Micro-Beacon Active Dot
                    Circle()
                        .fill(isSelected ? AdminSurface.primary : Color.clear)
                        .frame(width: 4, height: 4)
                        .opacity(isSelected ? 1.0 : 0.0)
                        .scaleEffect(isSelected ? 1.0 : 0.2)
                        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
                        .accessibilityHidden(true)

                    Image(systemName: symbol)
                        .font(.system(size: isSelected ? 17 : 16, weight: isSelected ? .semibold : .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.78))
                        .frame(height: 18)
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(isSelected ? Font.custom("Beiruti-Bold", size: 11.5) : Font.custom("Beiruti-Medium", size: 11))
                        .foregroundColor(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.80))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(V6TabButtonStyle())
        .keyboardShortcut(tab.keyEquivalent, modifiers: .command)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - iPad Countertop Flight Deck (3-Zone Mission Architecture)

private struct AdminPadCountertopTabBar: View {
    @Binding var selectedTab: AdminTab
    let tabs: [AdminTab]
    let session: AdminSession?
    @ObservedObject private var branchStore = BranchContextStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var padTabAnimationNamespace
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Zone 1: Leading Branch Context & Radar Beacon
            leadingBranchRadarZone
                .frame(minWidth: 180, maxWidth: 260, alignment: .leading)

            Spacer(minLength: 8)

            // Zone 2: Centered Anchored Segmented Command Rail
            centerCommandRailZone
                .frame(maxWidth: 640)

            Spacer(minLength: 8)

            // Zone 3: Trailing Operator Identity & Session Badge
            trailingOperatorZone
                .frame(minWidth: 180, maxWidth: 260, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(height: 58)
    }

    private var leadingBranchRadarZone: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.15, green: 0.78, blue: 0.45).opacity(0.25))
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(Color(red: 0.15, green: 0.78, blue: 0.45))
                    .frame(width: 7, height: 7)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "building.2.crop.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)

                    Text(branchDisplayName)
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                }

                Text(branchStore.isSyncingBackend ? Language.get("Syncing...", alter: nil) : Language.get("Live Radar Online", alter: nil))
                    .font(Font.custom("Beiruti-Regular", size: 10))
                    .foregroundColor(branchStore.isSyncingBackend ? AdminSurface.primary : Color(red: 0.15, green: 0.78, blue: 0.45))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AdminSurface.surface.opacity(colorScheme == .dark ? 0.45 : 0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.hairline.opacity(0.35), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(branchDisplayName), \(Language.get("Live Radar Online", alter: nil))")
    }

    private var branchDisplayName: String {
        if !branchStore.currentBranchDisplayName.isEmpty {
            return branchStore.currentBranchDisplayName
        } else if let branch = branchStore.activeBranch {
            return Language.isRTL() ? branch.nameAr : branch.nameEn
        } else if branchStore.isGlobal {
            return Language.get("Global Network", alter: nil)
        } else {
            return "PurePets Central"
        }
    }

    private var centerCommandRailZone: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                padTabItem(tab)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AdminSurface.surface.opacity(colorScheme == .dark ? 0.50 : 0.70))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AdminSurface.hairline.opacity(0.4), lineWidth: 0.75)
                )
        )
    }

    private func padTabItem(_ tab: AdminTab) -> some View {
        let isSelected = selectedTab == tab
        let title = Language.get(tab.titleKey, alter: nil)
        let symbol = isSelected ? tab.selectedSymbol : tab.symbol

        return Button {
            guard selectedTab != tab else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if reduceMotion {
                selectedTab = tab
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                    selectedTab = tab
                }
            }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AdminSurface.primary.opacity(colorScheme == .dark ? 0.26 : 0.14),
                                    AdminSurface.primary.opacity(colorScheme == .dark ? 0.16 : 0.07)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AdminSurface.primary.opacity(colorScheme == .dark ? 0.35 : 0.22), lineWidth: 0.75)
                        )
                        .matchedGeometryEffect(id: "ActivePadTabIndicator", in: padTabAnimationNamespace)
                }

                HStack(spacing: 6) {
                    if isSelected {
                        Circle()
                            .fill(AdminSurface.primary)
                            .frame(width: 4, height: 4)
                            .transition(.scale)
                    }

                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.85))

                    Text(title)
                        .font(isSelected ? Font.custom("Beiruti-Bold", size: 13) : Font.custom("Beiruti-Medium", size: 12.5))
                        .foregroundColor(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .lineLimit(1)

                    Text(tab.shortcutBadge)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? AdminSurface.primary.opacity(0.85) : AdminSurface.secondaryText.opacity(0.45))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isSelected ? AdminSurface.primary.opacity(0.12) : AdminSurface.hairline.opacity(0.2))
                        )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(V6TabButtonStyle())
        .keyboardShortcut(tab.keyEquivalent, modifiers: .command)
        .hoverEffect(.lift)
        .accessibilityLabel(title)
        .accessibilityValue(tab.shortcutBadge)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var trailingOperatorZone: some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(operatorName)
                    .font(Font.custom("Beiruti-Bold", size: 12))
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                Text(operatorRole)
                    .font(Font.custom("Beiruti-Regular", size: 10))
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
            }

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AdminSurface.primary.opacity(0.25),
                                AdminSurface.primary.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(AdminSurface.primary.opacity(0.35), lineWidth: 0.75)
                    )

                Text(operatorInitials)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(AdminSurface.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AdminSurface.surface.opacity(colorScheme == .dark ? 0.45 : 0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.hairline.opacity(0.35), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Language.get("Operator", alter: nil)): \(operatorName), \(operatorRole)")
    }

    private var operatorName: String {
        if let session = session, !session.displayName.isEmpty {
            return session.displayName
        } else if let staff = branchStore.currentStaff, let name = staff.displayName, !name.isEmpty {
            return name
        } else {
            return "Command Staff"
        }
    }

    private var operatorRole: String {
        if let session = session {
            return session.roleIdentifier.replacingOccurrences(of: "_", with: " ").capitalized
        } else if let staff = branchStore.currentStaff {
            return staff.localizedRoleName() ?? staff.roleIdentifier ?? "Operator"
        } else {
            return "Operator"
        }
    }

    private var operatorInitials: String {
        let name = operatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = name.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first, let second = parts.last?.first {
            return "\(first)\(second)".uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        } else {
            return "OP"
        }
    }
}

// MARK: - Shared shell interaction style

struct V6TabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct V6CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
    }
}

// MARK: - Work Deck (Category-Defining Operations Cockpit)

@MainActor
private struct AdminWorkDeckView: View {
    let session: AdminSession
    @ObservedObject var router: AdminRouter
    @ObservedObject var commandState: CommandCenterState
    let onOpenCommand: () -> Void

    @ObservedObject private var branchStore = BranchContextStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingBranchSwitcher = false

    private var isPadWide: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    private var navigationConfiguration: PPGlobalNavigationConfiguration {
        PPGlobalNavigationConfiguration(
            style: .contextDeck,
            title: Language.get(AdminTab.work.titleKey, alter: "العمل"),
            eyebrow: Language.get("CommandCenter_Eyebrow", alter: "عمليات PURE PETS"),
            subtitle: Language.get("CommandCenter_Work_Detail", alter: "مسارات المدفوعات والتنفيذ ونقطة البيع المتاحة لدورك."),
            showsContextFilament: false
        )
    }

    private var canPOS: Bool { AdminRoute.pointOfSale.isAuthorized(for: session) }
    private var canPOSHistory: Bool { AdminRoute.pointOfSaleHistory.isAuthorized(for: session) }
    private var canFulfillment: Bool { AdminRoute.fulfillment.isAuthorized(for: session) }
    private var canPayments: Bool { AdminRoute.payments.isAuthorized(for: session) }
    private var canPaymentSettings: Bool { AdminRoute.paymentSettings.isAuthorized(for: session) }
    private var canAccessories: Bool { AdminRoute.accessories.isAuthorized(for: session) }
    private var canFood: Bool { AdminRoute.food.isAuthorized(for: session) }
    private var canLivePets: Bool { AdminRoute.livePets.isAuthorized(for: session) }

    private var hasAnyAuthorizedRoute: Bool {
        canPOS || canPOSHistory || canFulfillment || canPayments || canPaymentSettings || canAccessories || canFood || canLivePets
    }

    var body: some View {
        PPGlobalNavigationScrollShell(configuration: navigationConfiguration, onAction: { _ in }) {
            Group {
                if !hasAnyAuthorizedRoute {
                    AdminEmptyRoutesView()
                        .padding(.horizontal, AdminShellMetric.pageMargin)
                } else if isPadWide {
                    iPadDeckLayout
                } else {
                    iPhoneDeckLayout
                }
            }
            .padding(.bottom, 104)
        }
        .sheet(isPresented: $showingBranchSwitcher) {
            PPBranchSelectionGateView()
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: - iPhone Tactile Layout

    private var iPhoneDeckLayout: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            // 1. Branch Horizon Capsule
            branchHorizonPill

            // 2. Command Health Pulse Strip
            if AdminTab.command.isAuthorized(for: session) {
                AdminCommandPulseStrip(state: commandState, onOpenCommand: onOpenCommand)
            }

            // 3. Hero POS Terminal Tile (Flagship Frontline)
            if canPOS {
                heroPOSTile
            }

            // 4. Twin Operational Radar (Fulfillment + Sales History)
            if canFulfillment || canPOSHistory {
                twinOperationalRadar
            }

            // 5. Financial Sentinel Card
            if canPayments || canPaymentSettings {
                financialSentinelCard
            }

            // 6. Tri-Vault Inventory Horizon
            if canAccessories || canFood || canLivePets {
                triVaultInventorySection
            }
        }
        .padding(.horizontal, AdminShellMetric.pageMargin)
    }

    // MARK: - iPad Countertop Command Deck Layout

    private var iPadDeckLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Unified Operations Command Horizon Bar (Spans full width)
            iPadOperationsHorizonBar

            // 2. Primary Operations Dual Wings
            HStack(alignment: .top, spacing: 20) {
                // Wing A: Flagship POS Terminal Console + Financial Governance Desk
                VStack(spacing: 18) {
                    if canPOS {
                        iPadPOSTerminalConsole
                    }

                    if canPayments || canPaymentSettings {
                        iPadFinancialControlCard
                    }
                }
                .frame(maxWidth: .infinity)

                // Wing B: Live Operational Radar (Fulfillment Dispatch + Sales History + System Health)
                VStack(spacing: 18) {
                    if canFulfillment {
                        iPadFulfillmentCard
                    }

                    if canPOSHistory {
                        iPadPOSHistoryCard
                    }

                    if AdminTab.command.isAuthorized(for: session) {
                        iPadSystemHealthCard
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // 3. Tri-Vault Inventory Command Bay (Full width, 3 generous columns, ZERO truncation)
            if canAccessories || canFood || canLivePets {
                iPadInventoryVaultBay
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Shared / iPhone Components

    private var branchHorizonPill: some View {
        Button {
            triggerHaptic(.light)
            showingBranchSwitcher = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(branchStore.currentBranchDisplayName.isEmpty
                             ? Language.get("BranchContext_SelectBranch_Prompt", alter: "تحديد الفرع")
                             : branchStore.currentBranchDisplayName)
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)

                        if let code = branchStore.activeBranch?.code, !code.isEmpty {
                            Text(verbatim: "#" + code.normalizedEnglishDigits)
                                .font(PPBrandFont.bold(size: 10))
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(Language.get("BranchContext_TapToSwitch", alter: "المس لتبديل الفرع النشط"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(Language.get("BranchContext_Switch_Action", alter: "تبديل"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primary)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    private var heroPOSTile: some View {
        Button {
            triggerHaptic(.medium)
            router.present(.pointOfSale, session: session)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.10, blue: 0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [AdminSurface.primary.opacity(0.35), Color.clear],
                                    center: Language.isRTL() ? .topLeading : .topTrailing,
                                    startRadius: 0,
                                    endRadius: 180
                                )
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.20), radius: 14, x: 0, y: 6)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(AdminSurface.primary.opacity(0.20))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "cart.fill.badge.plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AdminSurface.primary)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(Language.get("POS_Title", alter: "نقطة البيع السريع"))
                                    .font(AdminType.headline)
                                    .foregroundColor(.white)

                                if let code = branchStore.activeBranch?.code, !code.isEmpty {
                                    Text(verbatim: "#" + code.normalizedEnglishDigits)
                                        .font(PPBrandFont.bold(size: 11))
                                        .foregroundColor(Color.white.opacity(0.60))
                                }
                            }
                        }

                        Spacer()

                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(uiColor: .ppSuccess))
                                .frame(width: 7, height: 7)
                            Text(Language.get("POS_Live_Ready_Badge", alter: "جاهز للفوترة"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(Color(uiColor: .ppSuccess))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("POS_Terminal_Action_Header", alter: "إصدار فاتورة جديدة ومسح الباركود"))
                            .font(AdminType.title3)
                            .foregroundColor(.white)

                        Text(Language.get("POS_Hero_Subtitle", alter: "فواتير مباشرة، قراءة الباركود، واحتساب الخصومات والدفع الفوري"))
                            .font(AdminType.footnote)
                            .foregroundColor(Color.white.opacity(0.78))
                            .lineLimit(2)
                    }

                    HStack {
                        HStack(spacing: 7) {
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 14, weight: .bold))
                            Text(Language.get("POS_Launch_Terminal", alter: "بدء عملية البيع الآن"))
                                .font(AdminType.calloutBold)
                            Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.white, in: Capsule())
                        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)

                        Spacer()
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(V6CardButtonStyle())
    }

    private var twinOperationalRadar: some View {
        HStack(spacing: 12) {
            if canFulfillment {
                Button {
                    triggerHaptic(.light)
                    router.present(.fulfillment, session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .ppWarning).opacity(0.14))
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(Color(uiColor: .ppWarning))
                            }
                            .frame(width: 38, height: 38)

                            Spacer()

                            if let awaiting = commandState.snapshot?.operations.awaitingFulfillment, awaiting > 0 {
                                Text(verbatim: "\(awaiting)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(uiColor: .ppWarning), in: Capsule())
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Fulfillment_Title", alter: "طلبات التنفيذ"))
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)

                            Text(fulfillmentStatusText)
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 0.8)
                    )
                }
                .buttonStyle(V6CardButtonStyle())
            }

            if canPOSHistory {
                Button {
                    triggerHaptic(.light)
                    router.present(.pointOfSaleHistory, session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AdminSurface.primary.opacity(0.12))
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AdminSurface.primary)
                            }
                            .frame(width: 38, height: 38)

                            Spacer()

                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AdminSurface.secondaryText)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("POS_History_Title", alter: "سجل المبيعات"))
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)

                            Text(Language.get("POS_History_Subtitle_Short", alter: "الإيصالات، الاسترجاع، والإلغاء"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 0.8)
                    )
                }
                .buttonStyle(V6CardButtonStyle())
            }
        }
    }

    private var fulfillmentStatusText: String {
        if let count = commandState.snapshot?.operations.awaitingFulfillment, count > 0 {
            return String(format: Language.get("Fulfillment_Pending_Count_Format", alter: "%d بانتظار التجهيز"), count)
        }
        return Language.get("Fulfillment_All_Clear", alter: "جميع الطلبات مكتملة")
    }

    private var financialSentinelCard: some View {
        VStack(spacing: 0) {
            if canPayments {
                Button {
                    triggerHaptic(.light)
                    router.present(.payments, session: session)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .ppSuccess).opacity(0.12))
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppSuccess))
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("PaymentMgmt_Dashboard_Title", alter: "إدارة المدفوعات"))
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)

                            Text(Language.get("PaymentMgmt_Subtitle_Short", alter: "عمليات QIB، التحصيل، وتدقيق العمليات"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }

                        Spacer()

                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if canPayments && canPaymentSettings {
                Divider()
                    .padding(.leading, 64)
                    .background(AdminSurface.hairline)
            }

            if canPaymentSettings {
                Button {
                    triggerHaptic(.light)
                    router.present(.paymentSettings, session: session)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AdminSurface.secondaryText.opacity(0.10))
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .frame(width: 34, height: 34)

                        Text(Language.get("PaymentMgmt_Dashboard_Settings_Title", alter: "أساسيات وتكوين الدفع"))
                            .font(AdminType.callout)
                            .foregroundColor(AdminSurface.primaryText)

                        Spacer()

                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private var triVaultInventorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Language.get("Inventory_Vault_Section_Title", alter: "خزائن المخزون والمنتجات"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)
                    .textCase(.uppercase)

                Spacer()

                Text(Language.get("Inventory_Vault_Badge", alter: "مزامنة فورية بالفرع"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(spacing: 10) {
                if canAccessories {
                    inventoryVaultRow(
                        title: Language.get("Manage Accessories", alter: "إدارة الإكسسوارات"),
                        subtitle: Language.get("Accessories_Vault_Desc", alter: "أطواق، ألعاب، ومستلزمات العناية والرعاية"),
                        icon: "cube.box.fill",
                        tintColor: Color(uiColor: .systemTeal),
                        route: .accessories
                    )
                }

                if canFood {
                    inventoryVaultRow(
                        title: Language.get("manageFood", alter: "إدارة الطعام والتغذية"),
                        subtitle: Language.get("Food_Vault_Desc", alter: "أغذية جافة ورطبة، مكملات ومكافآت غذائية"),
                        icon: "bag.fill",
                        tintColor: Color(uiColor: .systemOrange),
                        route: .food
                    )
                }

                if canLivePets {
                    inventoryVaultRow(
                        title: Language.get("Manage Live Pets", alter: "إدارة الحيوانات الحية"),
                        subtitle: Language.get("LivePets_Vault_Desc", alter: "الطيور، القطط، الكلاب، السجلات والشرائح"),
                        icon: "pawprint.fill",
                        tintColor: Color(uiColor: .ppPrimary),
                        route: .livePets
                    )
                }
            }
        }
    }

    private func inventoryVaultRow(
        title: String,
        subtitle: String,
        icon: String,
        tintColor: Color,
        route: AdminRoute
    ) -> some View {
        Button {
            triggerHaptic(.light)
            router.present(route, session: session)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tintColor.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(tintColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)

                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - iPad Subviews

    // MARK: - iPad Operations Horizon Bar

    private var iPadOperationsHorizonBar: some View {
        HStack(spacing: 16) {
            // Leading: Branch Context & Switch Trigger
            Button {
                triggerHaptic(.light)
                showingBranchSwitcher = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AdminSurface.primary.opacity(0.12))
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(branchStore.currentBranchDisplayName.isEmpty
                                 ? Language.get("BranchContext_SelectBranch_Prompt", alter: "تحديد الفرع")
                                 : branchStore.currentBranchDisplayName)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)

                            if let code = branchStore.activeBranch?.code, !code.isEmpty {
                                Text(verbatim: "#" + code.normalizedEnglishDigits)
                                    .font(PPBrandFont.bold(size: 11))
                                    .foregroundColor(AdminSurface.primary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                            }
                        }

                        Text(Language.get("BranchContext_TapToSwitch", alter: "المس لتبديل الفرع الميداني النشط"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                        .padding(8)
                        .background(AdminSurface.primary.opacity(0.10), in: Circle())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Trailing: Cashier Profile & Live Shift Status
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Text(session.displayName.prefix(1))
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.displayName)
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(session.localizedRoleName)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                Divider()
                    .frame(height: 24)
                    .background(AdminSurface.hairline)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 8, height: 8)
                        .shadow(color: Color(uiColor: .ppSuccess).opacity(0.5), radius: 4)

                    Text(Language.get("Shift_Active_Label", alter: "الوردية نشطة"))
                        .font(AdminType.captionBold)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Flagship Obsidian POS Terminal Console

    private var iPadPOSTerminalConsole: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [AdminSurface.primary.opacity(0.32), Color.clear],
                                center: Language.isRTL() ? .topLeading : .topTrailing,
                                startRadius: 0,
                                endRadius: 260
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color.blue.opacity(0.12), Color.clear],
                                center: Language.isRTL() ? .bottomTrailing : .bottomLeading,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.24), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)

            VStack(alignment: .leading, spacing: 18) {
                // Console Header: Hardware Badge + Live Status Beacon
                HStack(alignment: .center) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.primary.opacity(0.22))
                                .frame(width: 44, height: 44)
                            Image(systemName: "cart.fill.badge.plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(AdminSurface.primary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(Language.get("POS_Hardware_Console_Title", alter: "وحدة البيع المباشر (POS)"))
                                    .font(AdminType.title3)
                                    .foregroundColor(.white)

                                if let code = branchStore.activeBranch?.code, !code.isEmpty {
                                    Text(verbatim: "#" + code.normalizedEnglishDigits)
                                        .font(PPBrandFont.bold(size: 11))
                                        .foregroundColor(Color.white.opacity(0.65))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.10), in: Capsule())
                                }
                            }

                            Text(Language.get("POS_Hardware_Sub_Eyebrow", alter: "محطة الفوترة السريعة بالفرع"))
                                .font(AdminType.caption2)
                                .foregroundColor(Color.white.opacity(0.60))
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 8, height: 8)
                            .shadow(color: Color(uiColor: .ppSuccess).opacity(0.6), radius: 4)

                        Text(Language.get("POS_Ready_Short", alter: "جاهز للتحصيل الفوري"))
                            .font(AdminType.captionBold)
                            .foregroundColor(Color(uiColor: .ppSuccess))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .ppSuccess).opacity(0.14), in: Capsule())
                }

                // Central Headline & Workflow Explanation
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("POS_Main_Invoice_Action", alter: "إصدار فواتير ومسح الباركود"))
                        .font(AdminType.title2)
                        .foregroundColor(.white)

                    Text(Language.get("POS_Hero_Subtitle_Extended", alter: "قراءة الباركود، حساب فوري للخصومات، تحصيل كاش أو عبر البطاقة البنكية، وطباعة إيصالات QIB المعتمدة."))
                        .font(AdminType.callout)
                        .foregroundColor(Color.white.opacity(0.80))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Dominant Primary Action Button
                Button {
                    triggerHaptic(.medium)
                    router.present(.pointOfSale, session: session)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 18, weight: .bold))

                        Text(Language.get("POS_Launch_Terminal_Primary", alter: "فتح نقطة البيع وبدء الفاتورة"))
                            .font(AdminType.headline)

                        Spacer()

                        Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(V6CardButtonStyle())

                // Tactical Speed-Dial Dock
                HStack(spacing: 10) {
                    // Shortcut 1: Fast Barcode Scan
                    Button {
                        triggerHaptic(.light)
                        router.present(.pointOfSale, session: session)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 13, weight: .semibold))
                            Text(Language.get("POS_Quick_Scan_Action", alter: "مسح باركود"))
                                .font(AdminType.captionBold)
                        }
                        .foregroundColor(.white.opacity(0.90))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // Shortcut 2: Today's Ledger
                    if canPOSHistory {
                        Button {
                            triggerHaptic(.light)
                            router.present(.pointOfSaleHistory, session: session)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(Language.get("POS_Today_Receipts", alter: "فواتير اليوم"))
                                    .font(AdminType.captionBold)
                            }
                            .foregroundColor(.white.opacity(0.90))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(22)
        }
    }

    // MARK: - Financial Governance Module

    private var iPadFinancialControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .ppSuccess).opacity(0.14))
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("PaymentMgmt_Dashboard_Title", alter: "المالية وبوابات الدفع والتسويات"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)

                    Text(Language.get("PaymentMgmt_Section_Subtitle", alter: "عمليات التحصيل الإلكتروني، نقاط البيع، وإعدادات QIB"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()
            }

            VStack(spacing: 8) {
                if canPayments {
                    Button {
                        triggerHaptic(.light)
                        router.present(.payments, session: session)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppSuccess))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(Language.get("PaymentMgmt_Records_Title", alter: "إدارة وسجلات المدفوعات"))
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                Text(Language.get("PaymentMgmt_Records_Sub", alter: "مراجعة العمليات، تدقيق التحصيلات، والتسويات اليومية"))
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.secondaryText)
                            }

                            Spacer()

                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .padding(12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(V6CardButtonStyle())
                }

                if canPaymentSettings {
                    Button {
                        triggerHaptic(.light)
                        router.present(.paymentSettings, session: session)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(AdminSurface.primary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(Language.get("PaymentMgmt_Dashboard_Settings_Title", alter: "إعدادات أجهزة وبوابات الدفع"))
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                Text(Language.get("PaymentMgmt_Settings_Sub", alter: "تكوين ماكينات QIB، نقاط الدفع، وعمولات العمليات"))
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.secondaryText)
                            }

                            Spacer()

                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .padding(12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(V6CardButtonStyle())
                }
            }
        }
        .padding(18)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Operational Radar Modules

    private var iPadFulfillmentCard: some View {
        Button {
            triggerHaptic(.light)
            router.present(.fulfillment, session: session)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .ppWarning).opacity(0.14))
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Color(uiColor: .ppWarning))
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Fulfillment_Title", alter: "طلبات التنفيذ والتوصيل"))
                            .font(AdminType.title3)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("Fulfillment_Live_Queue", alter: "طلبات المتجر الإلكتروني بانتظار التحضير"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    if let count = commandState.snapshot?.operations.awaitingFulfillment, count > 0 {
                        HStack(spacing: 4) {
                            Text(verbatim: "\(count)")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                            Text(Language.get("Fulfillment_Pending_Unit", alter: "طلب"))
                                .font(AdminType.caption2Bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color(uiColor: .ppWarning), in: Capsule())
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text(Language.get("Fulfillment_All_Clear", alter: "مكتمل"))
                                .font(AdminType.caption2Bold)
                        }
                        .foregroundColor(Color(uiColor: .ppSuccess))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                    }
                }

                Text(Language.get("Fulfillment_Hub_Desc", alter: "متابعة تجهيز وتعبئة طلبيات العملاء، مراجعة الفواتير المحجوزة، وتوجيه الشحنات لمناديب التوصيل أو الاستلام من الفرع."))
                    .font(AdminType.footnote)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    HStack(spacing: 6) {
                        Text(Language.get("Fulfillment_Open_Action", alter: "فتح منصة تجهيز الطلبات"))
                            .font(AdminType.calloutBold)
                        Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(Color(uiColor: .ppWarning))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .ppWarning).opacity(0.12), in: Capsule())

                    Spacer()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    private var iPadPOSHistoryCard: some View {
        Button {
            triggerHaptic(.light)
            router.present(.pointOfSaleHistory, session: session)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AdminSurface.primary.opacity(0.12))
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("POS_History_Title", alter: "سجل العمليات والمبيعات"))
                            .font(AdminType.title3)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("POS_History_Archive_Eyebrow", alter: "أرشيف فواتير الكاشير والتحصيل"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Text(Language.get("POS_History_Subtitle_Long", alter: "استعراض كافة الفواتير المصدرة اليوم، إعادة طباعة الإيصالات للعملاء، وتوثيق المرتجعات أو إلغاء العمليات."))
                    .font(AdminType.footnote)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    HStack(spacing: 6) {
                        Text(Language.get("POS_History_Review_Action", alter: "استعراض سجل الفواتير"))
                            .font(AdminType.calloutBold)
                        Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())

                    Spacer()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    private var iPadSystemHealthCard: some View {
        Button(action: onOpenCommand) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(pulseColor.opacity(0.12))
                    Image(systemName: pulseSymbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(pulseColor)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("CommandCenter_Title", alter: "مركز العمليات المركزي"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)

                    Text(pulseTitle)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                }

                Spacer()

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    private var pulseTitle: String {
        guard let snapshot = commandState.currentSnapshot else {
            return Language.get("CommandCenter_Loading", alter: "جارٍ تحديث النبض...")
        }
        switch snapshot.health {
        case .stable:
            return Language.get("CommandCenter_Health_Stable", alter: "كافة المؤشرات التشغيلية منتظمة")
        case let .attention(count):
            return String(format: Language.get("CommandCenter_Health_Attention_Format", alter: "%d إجراءات تتطلب المتابعة"), count)
        case let .partial(count):
            return String(format: Language.get("CommandCenter_Health_Partial_Format", alter: "%d عمليات تحت الملاحظة"), count)
        }
    }

    private var pulseSymbol: String {
        guard let snapshot = commandState.currentSnapshot else { return "arrow.triangle.2.circlepath" }
        switch snapshot.health {
        case .stable: return "checkmark.shield.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .partial: return "arrow.triangle.2.circlepath"
        }
    }

    private var pulseColor: Color {
        guard let snapshot = commandState.currentSnapshot else { return AdminSurface.primary }
        switch snapshot.health {
        case .stable: return Color(uiColor: .ppSuccess)
        case .attention: return Color(uiColor: .ppWarning)
        case .partial: return AdminSurface.primary
        }
    }

    // MARK: - Tri-Vault Inventory Command Bay (Full Width, Zero Truncation)

    private var iPadInventoryVaultBay: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("Inventory_Vault_Section_Title", alter: "خزائن المخزون والمنتجات بالفرع"))
                        .font(AdminType.title3)
                        .foregroundColor(AdminSurface.primaryText)

                    Text(Language.get("Inventory_Live_Sync_Full", alter: "مزامنة لحظية حية مع المستودع المركزي وقواعد بيانات الكتالوج"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()
            }

            HStack(spacing: 16) {
                if canAccessories {
                    iPadVaultColumnCard(
                        title: Language.get("Manage Accessories", alter: "إدارة المستلزمات والأطواق"),
                        subtitle: Language.get("Accessories_Vault_Desc_Full", alter: "أطواق، ألعاب، مستلزمات العناية والرعاية، وإكسسوارات الحيوانات"),
                        badge: Language.get("Accessories_Badge", alter: "مستلزمات"),
                        icon: "cube.box.fill",
                        tint: Color(uiColor: .systemTeal),
                        route: .accessories
                    )
                }

                if canFood {
                    iPadVaultColumnCard(
                        title: Language.get("manageFood", alter: "إدارة الطعام والتغذية"),
                        subtitle: Language.get("Food_Vault_Desc_Full", alter: "دراي فود، معلبات، مكملات صحية ومكافآت غذائية لكافة الفصائل"),
                        badge: Language.get("Food_Badge", alter: "أغذية ومكملات"),
                        icon: "bag.fill",
                        tint: Color(uiColor: .systemOrange),
                        route: .food
                    )
                }

                if canLivePets {
                    iPadVaultColumnCard(
                        title: Language.get("Manage Live Pets", alter: "إدارة الحيوانات الأليفة"),
                        subtitle: Language.get("LivePets_Vault_Desc_Full", alter: "الطيور، القطط، الكلاب، السجلات البيطرية، التطعيمات والشرائح"),
                        badge: Language.get("LivePets_Badge", alter: "سجلات حية"),
                        icon: "pawprint.fill",
                        tint: Color(uiColor: .ppPrimary),
                        route: .livePets
                    )
                }
            }
        }
        .padding(22)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private func iPadVaultColumnCard(
        title: String,
        subtitle: String,
        badge: String,
        icon: String,
        tint: Color,
        route: AdminRoute
    ) -> some View {
        Button {
            triggerHaptic(.light)
            router.present(route, session: session)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint.opacity(0.14))
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(tint)
                    }
                    .frame(width: 44, height: 44)

                    Spacer()

                    Text(badge)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.12), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                HStack {
                    Text(Language.get("Inventory_Manage_Action", alter: "فتح الخزينة وإدارة المخزون"))
                        .font(AdminType.captionBold)
                        .foregroundColor(tint)
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(tint)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - Tactile Haptic Trigger

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

// MARK: - People & Human Capital Command Horizon (NextGen V6 Studio Architecture)

@MainActor
private struct AdminPeopleDeckView: View {
    let session: AdminSession
    @ObservedObject var router: AdminRouter
    @ObservedObject var commandState: CommandCenterState
    let onOpenCommand: () -> Void

    @ObservedObject private var branchStore = BranchContextStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingBranchSwitcher = false

    private var isPadWide: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    private var navigationConfiguration: PPGlobalNavigationConfiguration {
        PPGlobalNavigationConfiguration(
            style: .contextDeck,
            title: Language.get(AdminTab.customers.titleKey, alter: "الأشخاص"),
            eyebrow: Language.get("CommandCenter_Eyebrow", alter: "عمليات PURE PETS"),
            subtitle: Language.get("CommandCenter_People_Detail", alter: "سجلات العملاء ووصول الفريق والمحادثات المتاحة لصلاحياتك."),
            showsContextFilament: false
        )
    }

    private var canUsers: Bool { AdminRoute.users.isAuthorized(for: session) }
    private var canStaff: Bool { AdminRoute.staff.isAuthorized(for: session) }
    private var canChats: Bool { AdminRoute.chats.isAuthorized(for: session) }

    private var hasAnyAuthorizedRoute: Bool {
        canUsers || canStaff || canChats
    }

    var body: some View {
        PPGlobalNavigationScrollShell(configuration: navigationConfiguration, onAction: { _ in }) {
            Group {
                if !hasAnyAuthorizedRoute {
                    AdminEmptyRoutesView()
                        .padding(.horizontal, AdminShellMetric.pageMargin)
                } else if isPadWide {
                    iPadPeopleDeckLayout
                } else {
                    iPhonePeopleDeckLayout
                }
            }
            .padding(.bottom, 104)
        }
        .sheet(isPresented: $showingBranchSwitcher) {
            PPBranchSelectionGateView()
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: - iPhone Tactile Layout

    private var iPhonePeopleDeckLayout: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            // 1. Branch Horizon Capsule
            branchHorizonPill

            // 2. Command Health Pulse Strip
            if AdminTab.command.isAuthorized(for: session) {
                AdminCommandPulseStrip(state: commandState, onOpenCommand: onOpenCommand)
            }

            // 3. Hero Customer Intelligence Tile (Flagship Frontline)
            if canUsers {
                heroCustomerIntelligenceTile
            }

            // 4. Twin Human Capital Pillars (Staff Access + Support Chats)
            if canStaff || canChats {
                twinHumanCapitalRadar
            }

            // 5. Security Governance & Role Sentinel Card
            if canStaff || canUsers {
                securityGovernanceSentinelCard
            }
        }
        .padding(.horizontal, AdminShellMetric.pageMargin)
    }

    // MARK: - iPad Countertop Command Deck Layout

    private var iPadPeopleDeckLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Panoramic People Command Horizon Bar (Spans full width)
            iPadPeopleHorizonBar

            // 2. Dual Tactical Command Wings
            HStack(alignment: .top, spacing: 20) {
                // Wing A: Customer Intelligence Console + Live Support Dispatch
                VStack(spacing: 18) {
                    if canUsers {
                        iPadCustomerIntelligenceConsole
                    }

                    if canChats {
                        iPadSupportDispatchCard
                    }
                }
                .frame(maxWidth: .infinity)

                // Wing B: Staff Governance Console + Identity Security Sentinel
                VStack(spacing: 18) {
                    if canStaff {
                        iPadStaffAccessConsole
                    }

                    if canStaff || canUsers {
                        iPadSecuritySentinelCard
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Shared / iPhone Components

    private var branchHorizonPill: some View {
        Button {
            triggerHaptic(.light)
            showingBranchSwitcher = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(branchStore.currentBranchDisplayName.isEmpty
                             ? Language.get("BranchContext_SelectBranch_Prompt", alter: "تحديد الفرع")
                             : branchStore.currentBranchDisplayName)
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)

                        if let code = branchStore.activeBranch?.code, !code.isEmpty {
                            Text(verbatim: "#" + code.normalizedEnglishDigits)
                                .font(PPBrandFont.bold(size: 10))
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(Language.get("BranchContext_TapToSwitch", alter: "المس لتبديل الفرع النشط"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(Language.get("BranchContext_Switch_Action", alter: "تبديل"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primary)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - iPhone Flagship Customer Intelligence Hero Tile

    private var heroCustomerIntelligenceTile: some View {
        Button {
            triggerHaptic(.medium)
            router.present(.users, session: session)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.10, blue: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [AdminSurface.primary.opacity(0.35), Color.clear],
                                    center: Language.isRTL() ? .topLeading : .topTrailing,
                                    startRadius: 0,
                                    endRadius: 190
                                )
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.20), radius: 14, x: 0, y: 6)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(AdminSurface.primary.opacity(0.20))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AdminSurface.primary)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(Language.get("People_Hero_Title", alter: "منظومة وسجلات العملاء"))
                                    .font(AdminType.headline)
                                    .foregroundColor(.white)

                                if let count = commandState.snapshot?.business.users, count > 0 {
                                    Text(verbatim: "#PP • \(count.formatted()) " + Language.get("People_Registered_Accounts", alter: "حساب مسجل"))
                                        .font(PPBrandFont.bold(size: 11))
                                        .foregroundColor(Color.white.opacity(0.65))
                                } else {
                                    Text(Language.get("People_Verified_Directory", alter: "دليل العملاء المركزي المعتمد"))
                                        .font(PPBrandFont.bold(size: 11))
                                        .foregroundColor(Color.white.opacity(0.65))
                                }
                            }
                        }

                        Spacer()

                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(uiColor: .ppSuccess))
                                .frame(width: 7, height: 7)
                            Text(Language.get("People_Directory_Active", alter: "الدليل متصل"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(Color(uiColor: .ppSuccess))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("People_Hero_Action_Header", alter: "فحص الحسابات والملفات الشخصية"))
                            .font(AdminType.title3)
                            .foregroundColor(.white)

                        Text(Language.get("People_Hero_Subtitle", alter: "سجلات العملاء، ملفات الحيوانات، توثيق الحسابات، وضبط قيود الوصول الفورية."))
                            .font(AdminType.footnote)
                            .foregroundColor(Color.white.opacity(0.78))
                            .lineLimit(2)
                    }

                    // Micro-Telemetry Feature Strip
                    HStack(spacing: 12) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppSuccess))
                            Text(Language.get("People_Verified_Accounts_Pill", alter: "حسابات موثقة"))
                                .font(AdminType.caption2)
                                .foregroundColor(Color.white.opacity(0.85))
                        }

                        Circle()
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 3, height: 3)

                        HStack(spacing: 5) {
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AdminSurface.primary)
                            Text(Language.get("People_Pet_Dossiers_Pill", alter: "ملفات الحيوانات"))
                                .font(AdminType.caption2)
                                .foregroundColor(Color.white.opacity(0.85))
                        }

                        Circle()
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 3, height: 3)

                        HStack(spacing: 5) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppWarning))
                            Text(Language.get("People_Identity_Security_Pill", alter: "حماية الهوية"))
                                .font(AdminType.caption2)
                                .foregroundColor(Color.white.opacity(0.85))
                        }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .bold))
                            Text(Language.get("People_Browse_Customers", alter: "استعراض دليل العملاء"))
                                .font(AdminType.calloutBold)
                            Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.white, in: Capsule())
                        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)

                        Spacer()
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - iPhone Twin Human Capital Radar (Staff Access + Live Chats)

    private var twinHumanCapitalRadar: some View {
        HStack(spacing: 12) {
            if canStaff {
                Button {
                    triggerHaptic(.light)
                    router.present(.staff, session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(red: 0.38, green: 0.38, blue: 0.95).opacity(0.14))
                                Image(systemName: "person.badge.shield.checkmark.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.95))
                            }
                            .frame(width: 38, height: 38)

                            Spacer()

                            Text(verbatim: "Tier 1-3")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.95))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.38, green: 0.38, blue: 0.95).opacity(0.12), in: Capsule())
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Staff_Management", alter: "إدارة وصول الفريق"))
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)

                            Text(Language.get("People_Staff_Subtitle", alter: "الرتب والمستويات والصلاحيات"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }

                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: 0.38, green: 0.38, blue: 0.95))
                                .frame(width: 5, height: 5)
                            Text(Language.get("People_Active_Staff_Pill", alter: "فريق العمل النشط"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.95))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 0.8)
                    )
                }
                .buttonStyle(V6CardButtonStyle())
            }

            if canChats {
                Button {
                    triggerHaptic(.light)
                    router.present(.chats, session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(red: 0.15, green: 0.68, blue: 0.75).opacity(0.14))
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(Color(red: 0.15, green: 0.68, blue: 0.75))
                            }
                            .frame(width: 38, height: 38)

                            Spacer()

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(uiColor: .ppSuccess))
                                    .frame(width: 6, height: 6)
                                Text(Language.get("People_Chats_Live_Desk", alter: "مباشر"))
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(uiColor: .ppSuccess))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Chats", alter: "المحادثات"))
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)

                            Text(Language.get("People_Chats_Subtitle", alter: "خدمة العملاء والدعم الفوري"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }

                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: 0.15, green: 0.68, blue: 0.75))
                                .frame(width: 5, height: 5)
                            Text(Language.get("People_Support_Desk_Ready", alter: "جاهز للمحادثات المباشرة"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(Color(red: 0.15, green: 0.68, blue: 0.75))
                                .lineLimit(1)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 0.8)
                    )
                }
                .buttonStyle(V6CardButtonStyle())
            }
        }
    }

    // MARK: - iPhone Security Governance Sentinel Card

    private var securityGovernanceSentinelCard: some View {
        Button {
            triggerHaptic(.light)
            if canStaff {
                router.present(.staff, session: session)
            } else if canUsers {
                router.present(.users, session: session)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.62, blue: 0.18).opacity(0.12))
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: 0.95, green: 0.62, blue: 0.18))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(Language.get("People_Security_Policy_Eyebrow", alter: "سياسات الأمان والحوكمة"))
                            .font(AdminType.captionBold)
                            .foregroundColor(Color(red: 0.95, green: 0.62, blue: 0.18))

                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 5, height: 5)
                    }

                    Text(Language.get("People_Security_Policy_Title", alter: "هيكلية الرتب والامتيازات ومستويات الوصول"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(Language.get("People_Security_Policy_Detail", alter: "عزل الصلاحيات الحساسة، حماية بيانات العملاء، وسجلات التدقيق المعتمدة."))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - iPad Panoramic People Horizon Bar

    private var iPadPeopleHorizonBar: some View {
        HStack(spacing: 16) {
            // Leading: Interactive Field Branch Context Button
            Button {
                triggerHaptic(.light)
                showingBranchSwitcher = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "building.2.crop.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(branchStore.currentBranchDisplayName.isEmpty
                                 ? Language.get("BranchContext_SelectBranch_Prompt", alter: "تحديد الفرع الميداني")
                                 : branchStore.currentBranchDisplayName)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)

                            if let code = branchStore.activeBranch?.code, !code.isEmpty {
                                Text(verbatim: "#" + code.normalizedEnglishDigits)
                                    .font(PPBrandFont.bold(size: 11))
                                    .foregroundColor(AdminSurface.primary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                            }
                        }

                        Text(Language.get("BranchContext_TapToSwitch", alter: "المس لتبديل الفرع الميداني النشط"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                        .padding(8)
                        .background(AdminSurface.primary.opacity(0.10), in: Circle())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Center: Live Registered Users Metric Counter
            if let count = commandState.snapshot?.business.users, count > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AdminSurface.primary)

                    Text(verbatim: "\(count.formatted())")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(AdminSurface.primaryText)

                    Text(Language.get("People_Registered_Accounts", alter: "حساب مسجل"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 0.8)
                )
            }

            // Trailing: Officer Profile & Live Shift Indicator
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Text(session.displayName.prefix(1))
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.displayName)
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(session.localizedRoleName)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                Divider()
                    .frame(height: 24)
                    .background(AdminSurface.hairline)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 8, height: 8)
                        .shadow(color: Color(uiColor: .ppSuccess).opacity(0.5), radius: 4)

                    Text(Language.get("People_Directory_Active", alter: "الدليل متصل"))
                        .font(AdminType.captionBold)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - iPad Customer Intelligence Console (Wing A Flagship)

    private var iPadCustomerIntelligenceConsole: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [AdminSurface.primary.opacity(0.32), Color.clear],
                                center: Language.isRTL() ? .topLeading : .topTrailing,
                                startRadius: 0,
                                endRadius: 260
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.38, green: 0.38, blue: 0.95).opacity(0.14), Color.clear],
                                center: Language.isRTL() ? .bottomTrailing : .bottomLeading,
                                startRadius: 0,
                                endRadius: 220
                            )
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.24), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 8)

            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(alignment: .center) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.primary.opacity(0.22))
                                .frame(width: 44, height: 44)
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(AdminSurface.primary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(Language.get("People_Console_Title", alter: "منصة العملاء والفريق"))
                                    .font(AdminType.title3)
                                    .foregroundColor(.white)

                                Text(Language.get("People_Live_Sync", alter: "مزامنة فورية"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundColor(AdminSurface.primary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(AdminSurface.primary.opacity(0.18), in: Capsule())
                            }

                            Text(Language.get("People_Console_Eyebrow", alter: "وحدة استخبارات وحوكمة الأشخاص"))
                                .font(AdminType.caption2)
                                .foregroundColor(Color.white.opacity(0.65))
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 8, height: 8)
                            .shadow(color: Color(uiColor: .ppSuccess).opacity(0.6), radius: 5)
                        Text(Language.get("People_Directory_Active", alter: "الدليل متصل"))
                            .font(AdminType.captionBold)
                            .foregroundColor(Color(uiColor: .ppSuccess))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Color(uiColor: .ppSuccess).opacity(0.14), in: Capsule())
                }

                // Main Action Callout
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("People_Hero_Action_Header", alter: "فحص الحسابات والملفات الشخصية"))
                        .font(AdminType.title2)
                        .foregroundColor(.white)

                    Text(Language.get("People_Hero_Subtitle", alter: "سجلات العملاء، ملفات الحيوانات، توثيق الحسابات، وضبط قيود الوصول الفورية."))
                        .font(AdminType.callout)
                        .foregroundColor(Color.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 3 Capability Badges
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(uiColor: .ppSuccess))
                        Text(Language.get("People_Verified_Accounts_Pill", alter: "حسابات موثقة"))
                            .font(AdminType.footnote)
                            .foregroundColor(Color.white.opacity(0.90))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())

                    HStack(spacing: 6) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                        Text(Language.get("People_Pet_Dossiers_Pill", alter: "ملفات الحيوانات"))
                            .font(AdminType.footnote)
                            .foregroundColor(Color.white.opacity(0.90))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())

                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(uiColor: .ppWarning))
                        Text(Language.get("People_Identity_Security_Pill", alter: "حماية الهوية"))
                            .font(AdminType.footnote)
                            .foregroundColor(Color.white.opacity(0.90))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }

                // Primary Launch Bar
                Button {
                    triggerHaptic(.medium)
                    router.present(.users, session: session)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.rectangle.stack.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text(Language.get("People_Browse_Customers", alter: "استعراض دليل العملاء"))
                            .font(AdminType.headline)
                        Spacer()
                        Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.20), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(V6CardButtonStyle())
            }
            .padding(22)
        }
    }

    // MARK: - iPad Support Dispatch Card (Wing A Secondary)

    private var iPadSupportDispatchCard: some View {
        Button {
            triggerHaptic(.light)
            router.present(.chats, session: session)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 0.15, green: 0.68, blue: 0.75).opacity(0.14))
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color(red: 0.15, green: 0.68, blue: 0.75))
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Chats", alter: "المحادثات"))
                            .font(AdminType.title3)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("People_Chats_Subtitle", alter: "خدمة العملاء والدعم الفوري"))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 7, height: 7)
                        Text(Language.get("People_Support_Desk_Ready", alter: "جاهز للمحادثات المباشرة"))
                            .font(AdminType.captionBold)
                            .foregroundColor(Color(uiColor: .ppSuccess))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                }

                Text(Language.get("People_Hero_Subtitle", alter: "قنوات التواصل الفوري، دعم الطلبات والاستفسارات، وإدارة شكاوى ورعاية العملاء."))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)

                HStack {
                    Text(Language.get("People_iPad_Open_Chats", alter: "دخول مركز محادثات الدعم"))
                        .font(AdminType.headline)
                        .foregroundColor(Color(red: 0.15, green: 0.68, blue: 0.75))

                    Spacer()

                    Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.15, green: 0.68, blue: 0.75))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(red: 0.15, green: 0.68, blue: 0.75).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(18)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - iPad Staff Access Console (Wing B Primary)

    private var iPadStaffAccessConsole: some View {
        Button {
            triggerHaptic(.light)
            router.present(.staff, session: session)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 0.38, green: 0.38, blue: 0.95).opacity(0.14))
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.95))
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Staff_Management", alter: "إدارة وصول الفريق"))
                            .font(AdminType.title3)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("People_Staff_Subtitle", alter: "الرتب والمستويات والصلاحيات"))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    Text(verbatim: "RBAC Matrix")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.95))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.38, green: 0.38, blue: 0.95).opacity(0.12), in: Capsule())
                }

                // 3 Tier Hierarchy Summary Cards
                VStack(spacing: 8) {
                    HStack {
                        Text(verbatim: "Tier 1")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.primary.opacity(0.12), in: Capsule())

                        Text(Language.get("People_Role_Tier_1", alter: "السيادة وإدارة النظام (مالك، مدير نظام)"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Spacer()
                    }
                    .padding(8)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack {
                        Text(verbatim: "Tier 2")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.95))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.38, green: 0.38, blue: 0.95).opacity(0.12), in: Capsule())

                        Text(Language.get("People_Role_Tier_2", alter: "مدراء العمليات والتحصيل والمخزون"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Spacer()
                    }
                    .padding(8)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack {
                        Text(verbatim: "Tier 3")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Color(uiColor: .ppSuccess))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())

                        Text(Language.get("People_Role_Tier_3", alter: "الدعم الفني والخدمة الميدانية"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Spacer()
                    }
                    .padding(8)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack {
                    Text(Language.get("People_iPad_Manage_Team", alter: "إدارة طاقم العمل والصلاحيات"))
                        .font(AdminType.headline)
                        .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.95))

                    Spacer()

                    Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.95))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(red: 0.38, green: 0.38, blue: 0.95).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(18)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - iPad Security Sentinel Card (Wing B Secondary)

    private var iPadSecuritySentinelCard: some View {
        Button {
            triggerHaptic(.light)
            onOpenCommand()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(pulseColor.opacity(0.14))
                    Image(systemName: pulseSymbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(pulseColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("People_Security_Policy_Eyebrow", alter: "سياسات الأمان والحوكمة"))
                        .font(AdminType.captionBold)
                        .foregroundColor(pulseColor)

                    Text(pulseTitle)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(Language.get("People_Security_Health_Check", alter: "فحص سلامة الصلاحيات والتسويات الأمنية"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(Language.get("CommandCenter_Open_Detail", alter: "عرض"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primary)
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
            }
            .padding(16)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - Pulse State Helpers

    private var pulseTitle: String {
        guard let snapshot = commandState.currentSnapshot else {
            return Language.get("CommandCenter_Loading", alter: "جارٍ تحديث النبض...")
        }
        switch snapshot.health {
        case .stable:
            return Language.get("People_Security_Pulse_Stable", alter: "مستويات الأمان والحوكمة منضبطة")
        case let .attention(count):
            return String(format: Language.get("CommandCenter_Health_Attention_Format", alter: "%d إجراءات تتطلب المتابعة"), count)
        case let .partial(count):
            return String(format: Language.get("CommandCenter_Health_Partial_Format", alter: "%d عمليات تحت الملاحظة"), count)
        }
    }

    private var pulseSymbol: String {
        guard let snapshot = commandState.currentSnapshot else { return "arrow.triangle.2.circlepath" }
        switch snapshot.health {
        case .stable: return "checkmark.shield.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .partial: return "arrow.triangle.2.circlepath"
        }
    }

    private var pulseColor: Color {
        guard let snapshot = commandState.currentSnapshot else { return AdminSurface.primary }
        switch snapshot.health {
        case .stable: return Color(uiColor: .ppSuccess)
        case .attention: return Color(uiColor: .ppWarning)
        case .partial: return AdminSurface.primary
        }
    }

    // MARK: - Tactile Haptic Trigger

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

@MainActor
private struct AdminOperationsDeckView: View {
    let session: AdminSession
    @ObservedObject var router: AdminRouter
    @ObservedObject var commandState: CommandCenterState
    let onOpenCommand: () -> Void

    @ObservedObject private var branchStore = BranchContextStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @State private var showingBranchSwitcher = false

    private var isPadWide: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    private var navigationConfiguration: PPGlobalNavigationConfiguration {
        PPGlobalNavigationConfiguration(
            style: .contextDeck,
            title: Language.get(AdminTab.operations.titleKey, alter: "العمليات"),
            eyebrow: Language.get("CommandCenter_Eyebrow", alter: "عمليات PURE PETS"),
            subtitle: Language.get("Operations_Horizon_Subtitle", alter: "منظومة اللوجستيات، شبكة المزودين، الرعاية البيطرية، وحوكمة المنصة"),
            showsContextFilament: false
        )
    }

    // Authorizations
    private var canDelivery: Bool { AdminRoute.delivery.isAuthorized(for: session) }
    private var canProviderApplications: Bool { AdminRoute.providerApplications.isAuthorized(for: session) }
    private var canProviderPlans: Bool { AdminRoute.providerPlans.isAuthorized(for: session) }
    private var canProviderFeatures: Bool { AdminRoute.providerFeatures.isAuthorized(for: session) }
    private var canProviderAccounting: Bool { AdminRoute.providerAccounting.isAuthorized(for: session) }
    private var canBranches: Bool { AdminRoute.branches.isAuthorized(for: session) }
    private var canAgents: Bool { AdminRoute.agents.isAuthorized(for: session) }
    private var canHomeControl: Bool { AdminRoute.homeControl.isAuthorized(for: session) }
    private var canServices: Bool { AdminRoute.services.isAuthorized(for: session) }
    private var canVeterinarians: Bool { AdminRoute.veterinarians.isAuthorized(for: session) }
    private var canModeration: Bool { AdminRoute.moderation.isAuthorized(for: session) }
    private var canHotel: Bool { AdminRoute.hotel.isAuthorized(for: session) }

    private var hasAnyAuthorizedRoute: Bool {
        canDelivery || canProviderApplications || canProviderPlans || canProviderFeatures || canProviderAccounting || canBranches || canAgents || canHomeControl || canServices || canVeterinarians || canModeration || canHotel
    }

    private var hasProvidersSection: Bool {
        canProviderApplications || canProviderPlans || canProviderFeatures || canProviderAccounting
    }

    private var hasCareSection: Bool {
        canVeterinarians || canHotel || canServices
    }

    private var hasTerritorialSection: Bool {
        canBranches || canAgents
    }

    private var hasPlatformSection: Bool {
        canHomeControl || canModeration
    }

    var body: some View {
        PPGlobalNavigationScrollShell(configuration: navigationConfiguration, onAction: { _ in }) {
            Group {
                if !hasAnyAuthorizedRoute {
                    AdminEmptyRoutesView()
                        .padding(.horizontal, AdminShellMetric.pageMargin)
                } else if isPadWide {
                    iPadOperationsDeckLayout
                } else {
                    iPhoneOperationsDeckLayout
                }
            }
            .padding(.bottom, 104)
        }
        .sheet(isPresented: $showingBranchSwitcher) {
            PPBranchSelectionGateView()
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: - iPhone Tactile Layout

    private var iPhoneOperationsDeckLayout: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            // 1. Branch Horizon Capsule
            branchHorizonPill

            // 2. Command Health Pulse Strip
            if AdminTab.command.isAuthorized(for: session) {
                AdminCommandPulseStrip(state: commandState, onOpenCommand: onOpenCommand)
            }

            // 3. Hero Delivery Fleet Logistics Command Console
            if canDelivery {
                heroDeliveryFleetConsole(isPad: false)
            }

            // 4. Merchant & Provider Ecosystem Station
            if hasProvidersSection {
                providerEcosystemDeck(isPad: false)
            }

            // 5. Specialized Care, Veterinary & Hospitality Desk
            if hasCareSection {
                careAndHospitalityDesk(isPad: false)
            }

            // 6. Territorial Infrastructure & Field Force Desk
            if hasTerritorialSection {
                territorialInfrastructureDesk(isPad: false)
            }

            // 7. Platform Experience & Discovery Control Bay
            if hasPlatformSection {
                platformExperienceDeck(isPad: false)
            }
        }
        .padding(.horizontal, AdminShellMetric.pageMargin)
    }

    // MARK: - iPad Widescreen Operations Deck Layout

    private var iPadOperationsDeckLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Panoramic Horizon Operations Ribbon
            iPadOperationsHorizonRibbon

            // 2. Dual Tactical Command Wings
            HStack(alignment: .top, spacing: 20) {
                // Wing A: Fleet Logistics Command + Provider Ecosystem Hub
                VStack(spacing: 18) {
                    if canDelivery {
                        heroDeliveryFleetConsole(isPad: true)
                    }

                    if hasProvidersSection {
                        providerEcosystemDeck(isPad: true)
                    }

                    if hasPlatformSection {
                        platformExperienceDeck(isPad: true)
                    }
                }
                .frame(maxWidth: .infinity)

                // Wing B: Specialized Care Network & Territorial Infrastructure
                VStack(spacing: 18) {
                    if hasCareSection {
                        careAndHospitalityDesk(isPad: true)
                    }

                    if hasTerritorialSection {
                        territorialInfrastructureDesk(isPad: true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - iPad Panoramic Horizon Bar

    private var iPadOperationsHorizonRibbon: some View {
        HStack(spacing: 16) {
            // Leading: Store Branch Switcher
            Button {
                triggerHaptic(.light)
                showingBranchSwitcher = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AdminSurface.primary.opacity(0.12))
                        Image(systemName: "building.2.crop.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(branchStore.currentBranchDisplayName.isEmpty
                                 ? Language.get("BranchContext_SelectBranch_Prompt", alter: "تحديد الفرع")
                                 : branchStore.currentBranchDisplayName)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)

                            if let code = branchStore.activeBranch?.code, !code.isEmpty {
                                Text(verbatim: "#" + code.normalizedEnglishDigits)
                                    .font(PPBrandFont.bold(size: 11))
                                    .foregroundColor(AdminSurface.primary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                            }
                        }

                        Text(Language.get("BranchContext_TapToSwitch", alter: "المس لتبديل الفرع الميداني النشط"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                        .padding(8)
                        .background(AdminSurface.primary.opacity(0.10), in: Circle())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Center: Command Center Telemetry Health Beacon
            if AdminTab.command.isAuthorized(for: session) {
                Button {
                    triggerHaptic(.light)
                    onOpenCommand()
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(pulseHealthColor.opacity(0.15))
                                .frame(width: 34, height: 34)
                            Image(systemName: pulseHealthSymbol)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(pulseHealthColor)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(Language.get("CommandCenter_Title", alter: "مركز العمليات"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.secondaryText)
                            Text(pulseHealthTitle)
                                .font(AdminType.subheadlineBold)
                                .foregroundColor(AdminSurface.primaryText)
                        }

                        Circle()
                            .fill(pulseHealthColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: pulseHealthColor.opacity(0.6), radius: 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 0.8)
                    )
                }
                .buttonStyle(V6CardButtonStyle())
            }

            Spacer()

            // Trailing: Operations Duty Desk Presence
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(Language.get("Operations_Horizon_Title", alter: "العمليات المركزية"))
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(session.localizedRoleName)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                Divider()
                    .frame(height: 24)
                    .background(AdminSurface.hairline)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 8, height: 8)
                        .shadow(color: Color(uiColor: .ppSuccess).opacity(0.5), radius: 4)

                    Text(Language.get("Shift_Active_Label", alter: "الوردية نشطة"))
                        .font(AdminType.captionBold)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - iPhone Branch Horizon Capsule

    private var branchHorizonPill: some View {
        Button {
            triggerHaptic(.light)
            showingBranchSwitcher = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(branchStore.currentBranchDisplayName.isEmpty
                             ? Language.get("BranchContext_SelectBranch_Prompt", alter: "تحديد الفرع")
                             : branchStore.currentBranchDisplayName)
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)

                        if let code = branchStore.activeBranch?.code, !code.isEmpty {
                            Text(verbatim: "#" + code.normalizedEnglishDigits)
                                .font(PPBrandFont.bold(size: 10))
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(Language.get("BranchContext_TapToSwitch", alter: "المس لتبديل الفرع النشط"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(Language.get("More_Switch_Branch", alter: "تبديل"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primary)
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - Flagship Obsidian Fleet Logistics Console

    private func heroDeliveryFleetConsole(isPad: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: isPad ? 24 : 22, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: isPad ? 24 : 22, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color.cyan.opacity(0.30), Color.clear],
                                center: Language.isRTL() ? .topLeading : .topTrailing,
                                startRadius: 0,
                                endRadius: isPad ? 280 : 200
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isPad ? 24 : 22, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [AdminSurface.primary.opacity(0.20), Color.clear],
                                center: Language.isRTL() ? .bottomTrailing : .bottomLeading,
                                startRadius: 0,
                                endRadius: isPad ? 240 : 160
                            )
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: isPad ? 24 : 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: isPad ? 24 : 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.24), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.24), radius: 16, x: 0, y: 8)

            VStack(alignment: .leading, spacing: 16) {
                // Header: Fleet Badge + Live Status Beacon
                HStack(alignment: .center) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.cyan, Color.blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: isPad ? 48 : 44, height: isPad ? 48 : 44)
                                .shadow(color: Color.cyan.opacity(0.4), radius: 8, x: 0, y: 3)

                            Image(systemName: "truck.box.fill")
                                .font(.system(size: isPad ? 20 : 18, weight: .bold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Operations_Delivery_Hero_Title", alter: "إدارة أسطول التوصيل واللوجستيات"))
                                .font(AdminType.headline)
                                .foregroundColor(.white)

                            Text(Language.get("Operations_Delivery_Tag_Live", alter: "المسارات نشطة"))
                                .font(AdminType.caption2)
                                .foregroundColor(Color.cyan.opacity(0.90))
                        }
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 7, height: 7)
                            .shadow(color: Color(uiColor: .ppSuccess).opacity(0.8), radius: 3)
                        Text(Language.get("Operations_Delivery_Tag_Live", alter: "نشط ميدانياً"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(Color(uiColor: .ppSuccess))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                }

                // Subtitle
                Text(Language.get("Operations_Delivery_Hero_Subtitle", alter: "مراقبة مسارات الشحن، إدارة المناديب، ومتابعة تسليم الطلبات"))
                    .font(AdminType.footnote)
                    .foregroundColor(Color.white.opacity(0.78))
                    .lineLimit(2)

                // Dispatch Telemetry Tags
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "point.filled.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.cyan)
                        Text(Language.get("Operations_Delivery_Tag_Couriers", alter: "مزامنة المناديب"))
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(Color.cyan)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.12), in: Capsule())

                    HStack(spacing: 4) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.7))
                        Text("Live GPS")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.85))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())

                    Spacer()
                }

                // Primary Trigger Button
                Button {
                    triggerHaptic(.medium)
                    router.present(.delivery, session: session)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "truck.box")
                            .font(.system(size: 15, weight: .bold))
                        Text(Language.get("Operations_Delivery_Hero_Action", alter: "دخول مركز التوصيل الميداني"))
                            .font(AdminType.calloutBold)
                        Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(Color(red: 0.08, green: 0.09, blue: 0.12))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                    .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(V6CardButtonStyle())
            }
            .padding(isPad ? 20 : 16)
        }
    }

    // MARK: - Merchant & Provider Ecosystem Desk

    private func providerEcosystemDeck(isPad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.purple.opacity(0.12))
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.purple)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("Operations_Providers_Station_Title", alter: "منظومة الشركاء والمزودين"))
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Operations_Providers_Station_Subtitle", alter: "طلبات الانضمام، باقات الاشتراكات، مصفوفة الميزات، والعمولات"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                if canProviderApplications {
                    Button {
                        triggerHaptic(.light)
                        router.present(.providerApplications, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Providers_Applications_Title", alter: "طلبات انضمام المزودين"),
                            subtitle: Language.get("Operations_Provider_Apps_Desc", alter: "مراجعة واعتماد طلبات المتاجر والعيادات الجديدة"),
                            symbol: "person.badge.plus.fill",
                            symbolColor: .purple,
                            showsDivider: canProviderPlans || canProviderFeatures || canProviderAccounting
                        )
                    }
                    .buttonStyle(.plain)
                }

                if canProviderPlans {
                    Button {
                        triggerHaptic(.light)
                        router.present(.providerPlans, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Providers_Plans_Title", alter: "باقات واشتراكات الشركاء"),
                            subtitle: Language.get("Operations_Provider_Plans_Desc", alter: "هيكلة باقات الاشتراكات السنوية والشهرية"),
                            symbol: "list.clipboard.fill",
                            symbolColor: .blue,
                            showsDivider: canProviderFeatures || canProviderAccounting
                        )
                    }
                    .buttonStyle(.plain)
                }

                if canProviderFeatures {
                    Button {
                        triggerHaptic(.light)
                        router.present(.providerFeatures, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Providers_Features_Title", alter: "مصفوفة الصلاحيات والميزات"),
                            subtitle: Language.get("Operations_Provider_Features_Desc", alter: "تخصيص مصفوفة الصلاحيات والميزات لكل شريك"),
                            symbol: "gearshape.2.fill",
                            symbolColor: .indigo,
                            showsDivider: canProviderAccounting
                        )
                    }
                    .buttonStyle(.plain)
                }

                if canProviderAccounting {
                    Button {
                        triggerHaptic(.light)
                        router.present(.providerAccounting, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Providers_Accounting_Title", alter: "محاسبة وعمولات المزودين"),
                            subtitle: Language.get("Operations_Provider_Accounting_Desc", alter: "التسويات المالية، حساب العمولات، ومستحقات المزودين"),
                            symbol: "chart.pie.fill",
                            symbolColor: Color(uiColor: .ppSuccess),
                            showsDivider: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Care, Veterinary & Pet Hospitality Desk

    private func careAndHospitalityDesk(isPad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.pink.opacity(0.12))
                    Image(systemName: "stethoscope")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.pink)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("Operations_Care_Station_Title", alter: "الخدمات البيطرية والفندقة والعناية"))
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Operations_Care_Station_Subtitle", alter: "العيادات الطبية، فندقة الحيوانات، وباقات العناية المتخصصة"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                if canVeterinarians {
                    Button {
                        triggerHaptic(.light)
                        router.present(.veterinarians, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Vet_Section_Title", alter: "شبكة الأطباء والعيادات البيطرية"),
                            subtitle: Language.get("Operations_Vets_Desc", alter: "إدارة شبكة الأطباء والعيادات وسجلات الكشوفات"),
                            symbol: "stethoscope",
                            symbolColor: .pink,
                            showsDivider: canHotel || canServices
                        )
                    }
                    .buttonStyle(.plain)
                }

                if canHotel {
                    Button {
                        triggerHaptic(.light)
                        router.present(.hotel, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Hotel_Title", alter: "فندق ورعاية الحيوانات الأليفة"),
                            subtitle: Language.get("Operations_Hotel_Desc", alter: "حجوزات الإقامة، متابعة النزلاء، وإشغال الغرف"),
                            symbol: "bed.double.fill",
                            symbolColor: .orange,
                            showsDivider: canServices
                        )
                    }
                    .buttonStyle(.plain)
                }

                if canServices {
                    Button {
                        triggerHaptic(.light)
                        router.present(.services, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Service_Manage_Title", alter: "باقات الخدمات والعناية الميدانية"),
                            subtitle: Language.get("Operations_Services_Desc", alter: "خدمات الغرومينغ، التدريب، وباقات العناية الميدانية"),
                            symbol: "cross.case.fill",
                            symbolColor: .teal,
                            showsDivider: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Territorial Infrastructure & Field Force Desk

    private func territorialInfrastructureDesk(isPad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("Operations_Field_Station_Title", alter: "الفروع والتمثيل الميداني"))
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Operations_Field_Station_Subtitle", alter: "مراكز التوزيع، الفروع الجغرافية، وشبكة الوكلاء المعتمدين"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                if canBranches {
                    Button {
                        triggerHaptic(.light)
                        router.present(.branches, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Branches_Title", alter: "الفروع ومراكز التوزيع الميدانية"),
                            subtitle: Language.get("Operations_Branches_Desc", alter: "إدارة مراكز الفروع، النطاقات الجغرافية، وساعات العمل"),
                            symbol: "building.2.fill",
                            symbolColor: AdminSurface.primary,
                            showsDivider: canAgents
                        )
                    }
                    .buttonStyle(.plain)
                }

                if canAgents {
                    Button {
                        triggerHaptic(.light)
                        router.present(.agents, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Agents_Title", alter: "شبكة الوكلاء والممثلين الميدانيين"),
                            subtitle: Language.get("Operations_Agents_Desc", alter: "شبكة الوكلاء المعتمدين والممثلين الإقليميين"),
                            symbol: "person.text.rectangle.fill",
                            symbolColor: .cyan,
                            showsDivider: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Platform Discovery & Trust Bay

    private func platformExperienceDeck(isPad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.indigo.opacity(0.12))
                    Image(systemName: "switch.2")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.indigo)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("Operations_Platform_Station_Title", alter: "تجربة المنصة وحوكمة المحتوى"))
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Operations_Platform_Station_Subtitle", alter: "التحكم في الواجهة الرئيسية ومكافحة الانتهاكات والرقابة"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                if canHomeControl {
                    Button {
                        triggerHaptic(.light)
                        router.present(.homeControl, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("HomeControl_Title", alter: "التحكم في الصفحة الرئيسية"),
                            subtitle: Language.get("Operations_HomeControl_Desc", alter: "تخصيص أرفف الشاشة الرئيسية وسلايدر الاستكشاف"),
                            symbol: "switch.2",
                            symbolColor: .indigo,
                            showsDivider: canModeration
                        )
                    }
                    .buttonStyle(.plain)
                }

                if canModeration {
                    Button {
                        triggerHaptic(.light)
                        router.present(.moderation, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Moderation_Title", alter: "مركز الرقابة ومكافحة الانتهاكات"),
                            subtitle: Language.get("Operations_Moderation_Desc", alter: "مراجعة المحتوى المبلغ عنه ومكافحة الانتهاكات"),
                            symbol: "shield.lefthalf.filled",
                            symbolColor: .purple,
                            showsDivider: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Reusable High-Fidelity Desk Row

    private func deskActionRow(
        title: String,
        subtitle: String,
        symbol: String,
        symbolColor: Color,
        showsDivider: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(symbolColor.opacity(0.12))
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(symbolColor)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .contentShape(Rectangle())

            if showsDivider {
                Divider()
                    .padding(.leading, 64)
                    .background(AdminSurface.hairline)
            }
        }
    }

    // MARK: - Telemetry & Status Helpers

    private var pulseHealthTitle: String {
        guard let snapshot = commandState.currentSnapshot else {
            return Language.get("CommandCenter_Loading", alter: "جاري الفحص...")
        }
        switch snapshot.health {
        case .stable:
            return Language.get("CommandCenter_Health_Stable", alter: "العمليات واضحة")
        case let .attention(count):
            return String(format: Language.get("CommandCenter_Health_Attention_Format", alter: "%@ إجراء بحاجة انتباه"), formattedCount(count))
        case let .partial(count):
            return String(format: Language.get("CommandCenter_Health_Partial_Format", alter: "%@ تدقيق مطلوب"), formattedCount(count))
        }
    }

    private var pulseHealthColor: Color {
        guard let snapshot = commandState.currentSnapshot else { return AdminSurface.primary }
        switch snapshot.health {
        case .stable: return Color(uiColor: .ppSuccess)
        case .attention: return Color(uiColor: .ppWarning)
        case .partial: return AdminSurface.primary
        }
    }

    private var pulseHealthSymbol: String {
        guard let snapshot = commandState.currentSnapshot else { return "shield" }
        switch snapshot.health {
        case .stable: return "checkmark.shield.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .partial: return "arrow.triangle.2.circlepath"
        }
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
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

    @ObservedObject private var branchStore = BranchContextStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @State private var showingBranchSwitcher = false

    private var isPadWide: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    private var navigationConfiguration: PPGlobalNavigationConfiguration {
        PPGlobalNavigationConfiguration(
            style: .contextDeck,
            title: Language.get(AdminTab.more.titleKey, alter: "المزيد"),
            eyebrow: Language.get("CommandCenter_Eyebrow", alter: "عمليات PURE PETS"),
            subtitle: Language.get("More_Horizon_Subtitle", alter: "لوحة التحكم السيادية، الاتصالات، والحوكمة المركزية"),
            showsContextFilament: false
        )
    }

    private var canAccount: Bool { AdminRoute.account.isAuthorized(for: session) }
    private var canSettings: Bool { AdminRoute.settings.isAuthorized(for: session) }
    private var canNotifications: Bool { AdminRoute.notifications.isAuthorized(for: session) }
    private var canNotificationComposer: Bool { AdminRoute.notificationComposer.isAuthorized(for: session) }
    private var canNotificationSettings: Bool { AdminRoute.notificationSettings.isAuthorized(for: session) }
    private var canAccounting: Bool { AdminRoute.accounting.isAuthorized(for: session) }
    private var canAudit: Bool { AdminRoute.audit.isAuthorized(for: session) }
    private var canCategories: Bool { AdminRoute.categories.isAuthorized(for: session) }
    private var canBanners: Bool { AdminRoute.banners.isAuthorized(for: session) }
    private var canListings: Bool { AdminRoute.listings.isAuthorized(for: session) }

    private var hasAnyAuthorizedRoute: Bool {
        canAccount || canSettings || canNotifications || canNotificationComposer || canNotificationSettings || canAccounting || canAudit || canCategories || canBanners || canListings
    }

    private var hasBroadcastSection: Bool {
        canNotificationComposer || canNotifications || canNotificationSettings
    }

    private var hasGovernanceSection: Bool {
        canAccounting || canAudit
    }

    private var hasCommercialSection: Bool {
        canCategories || canBanners || canListings
    }

    var body: some View {
        PPGlobalNavigationScrollShell(configuration: navigationConfiguration, onAction: { _ in }) {
            Group {
                if !hasAnyAuthorizedRoute {
                    AdminEmptyRoutesView()
                        .padding(.horizontal, AdminShellMetric.pageMargin)
                } else if isPadWide {
                    iPadMoreDeckLayout
                } else {
                    iPhoneMoreDeckLayout
                }
            }
            .padding(.bottom, 104)
        }
        .sheet(isPresented: $showingBranchSwitcher) {
            PPBranchSelectionGateView()
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: - iPhone Tactile Layout

    private var iPhoneMoreDeckLayout: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            // 1. Branch Horizon Capsule
            branchHorizonPill

            // 2. Flagship Sovereign Executive Master Console
            sovereignConsoleCard(isPad: false)

            // 3. Communications & Broadcast Studio
            if hasBroadcastSection {
                broadcastStudioDesk(isPad: false)
            }

            // 4. Financial Governance & Security Desk
            if hasGovernanceSection {
                financialAndSecurityDesk(isPad: false)
            }

            // 5. Commercial Catalog & Content Bay
            if hasCommercialSection {
                commercialCatalogDesk(isPad: false)
            }

            // 6. Platform Environment & Session Dock
            environmentAndSessionDock
        }
        .padding(.horizontal, AdminShellMetric.pageMargin)
    }

    // MARK: - iPad Widescreen Command Deck Layout

    private var iPadMoreDeckLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Panoramic Horizon Operations Ribbon
            iPadMoreHorizonBar

            // 2. Dual Tactical Command Wings
            HStack(alignment: .top, spacing: 20) {
                // Wing A: Sovereign Console & Governance Desk
                VStack(spacing: 18) {
                    sovereignConsoleCard(isPad: true)

                    if hasGovernanceSection {
                        financialAndSecurityDesk(isPad: true)
                    }

                    environmentAndSessionDock
                }
                .frame(maxWidth: .infinity)

                // Wing B: Broadcast Studio & Commercial Governance Desk
                VStack(spacing: 18) {
                    if hasBroadcastSection {
                        broadcastStudioDesk(isPad: true)
                    }

                    if hasCommercialSection {
                        commercialCatalogDesk(isPad: true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - iPad Panoramic Horizon Bar

    private var iPadMoreHorizonBar: some View {
        HStack(spacing: 16) {
            // Leading: Store Branch Switcher
            Button {
                triggerHaptic(.light)
                showingBranchSwitcher = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AdminSurface.primary.opacity(0.12))
                        Image(systemName: "building.2.crop.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(branchStore.currentBranchDisplayName.isEmpty
                                 ? Language.get("BranchContext_SelectBranch_Prompt", alter: "تحديد الفرع")
                                 : branchStore.currentBranchDisplayName)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)

                            if let code = branchStore.activeBranch?.code, !code.isEmpty {
                                Text(verbatim: "#" + code.normalizedEnglishDigits)
                                    .font(PPBrandFont.bold(size: 11))
                                    .foregroundColor(AdminSurface.primary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                            }
                        }

                        Text(Language.get("BranchContext_TapToSwitch", alter: "المس لتبديل الفرع الميداني النشط"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                        .padding(8)
                        .background(AdminSurface.primary.opacity(0.10), in: Circle())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Center: Command Center Telemetry Health Beacon
            if AdminTab.command.isAuthorized(for: session) {
                Button {
                    triggerHaptic(.light)
                    onOpenCommand()
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(pulseHealthColor.opacity(0.15))
                                .frame(width: 34, height: 34)
                            Image(systemName: pulseHealthSymbol)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(pulseHealthColor)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(Language.get("CommandCenter_Title", alter: "مركز العمليات"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.secondaryText)
                            Text(pulseHealthTitle)
                                .font(AdminType.subheadlineBold)
                                .foregroundColor(AdminSurface.primaryText)
                        }

                        Circle()
                            .fill(pulseHealthColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: pulseHealthColor.opacity(0.6), radius: 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 0.8)
                    )
                }
                .buttonStyle(V6CardButtonStyle())
            }

            Spacer()

            // Trailing: Cashier / Session Operator Status
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Text(monogram)
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.displayName)
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(session.localizedRoleName)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                Divider()
                    .frame(height: 24)
                    .background(AdminSurface.hairline)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 8, height: 8)
                        .shadow(color: Color(uiColor: .ppSuccess).opacity(0.5), radius: 4)

                    Text(Language.get("Shift_Active_Label", alter: "الوردية نشطة"))
                        .font(AdminType.captionBold)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - iPhone Branch Horizon Capsule

    private var branchHorizonPill: some View {
        Button {
            triggerHaptic(.light)
            showingBranchSwitcher = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(branchStore.currentBranchDisplayName.isEmpty
                             ? Language.get("BranchContext_SelectBranch_Prompt", alter: "تحديد الفرع")
                             : branchStore.currentBranchDisplayName)
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)

                        if let code = branchStore.activeBranch?.code, !code.isEmpty {
                            Text(verbatim: "#" + code.normalizedEnglishDigits)
                                .font(PPBrandFont.bold(size: 10))
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(Language.get("BranchContext_TapToSwitch", alter: "المس لتبديل الفرع النشط"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(Language.get("More_Switch_Branch", alter: "تبديل"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primary)
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(V6CardButtonStyle())
    }

    // MARK: - Flagship Obsidian Sovereign Console

    private func sovereignConsoleCard(isPad: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: isPad ? 24 : 22, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: isPad ? 24 : 22, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [AdminSurface.primary.opacity(0.32), Color.clear],
                                center: Language.isRTL() ? .topLeading : .topTrailing,
                                startRadius: 0,
                                endRadius: isPad ? 280 : 200
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isPad ? 24 : 22, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color.purple.opacity(0.15), Color.clear],
                                center: Language.isRTL() ? .bottomTrailing : .bottomLeading,
                                startRadius: 0,
                                endRadius: isPad ? 240 : 160
                            )
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: isPad ? 24 : 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: isPad ? 24 : 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.24), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.24), radius: 16, x: 0, y: 8)

            VStack(alignment: .leading, spacing: 16) {
                // Top Horizon: Operator Profile Card
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.70)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: isPad ? 52 : 48, height: isPad ? 52 : 48)
                            .shadow(color: AdminSurface.primary.opacity(0.4), radius: 8, x: 0, y: 3)

                        Text(monogram)
                            .font(.system(size: isPad ? 20 : 18, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(session.displayName)
                                .font(AdminType.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppSuccess))
                        }

                        HStack(spacing: 8) {
                            Text(session.localizedRoleName)
                                .font(AdminType.caption2Bold)
                                .foregroundColor(Color.white.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.12), in: Capsule())

                            if isPad {
                                Text(session.email)
                                    .font(AdminType.caption2)
                                    .foregroundColor(Color.white.opacity(0.60))
                                    .environment(\.layoutDirection, .leftToRight)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    if canAccount {
                        Button {
                            triggerHaptic(.light)
                            router.present(.account, session: session)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(Language.get("More_Profile_Button", alter: "الملف الشخصي"))
                                    .font(AdminType.captionBold)
                                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Middle: Telemetry Status Beacon (Shown on iPhone or compact)
                if !isPad && AdminTab.command.isAuthorized(for: session) {
                    Button {
                        triggerHaptic(.light)
                        onOpenCommand()
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(pulseHealthColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: pulseHealthColor.opacity(0.8), radius: 4)

                            Text(Language.get("CommandCenter_Title", alter: "مركز العمليات") + ":")
                                .font(AdminType.captionBold)
                                .foregroundColor(Color.white.opacity(0.70))

                            Text(pulseHealthTitle)
                                .font(AdminType.captionBold)
                                .foregroundColor(.white)

                            Spacer()

                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.50))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                // Bottom: Sovereign Settings v6.2 Master Launch Row
                if canSettings {
                    Button {
                        triggerHaptic(.medium)
                        router.present(.settings, session: session)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.80)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Image(systemName: "gearshape.2.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 44, height: 44)
                            .shadow(color: AdminSurface.primary.opacity(0.4), radius: 8, x: 0, y: 3)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(Language.get("Settings_CommandCenter_Title", alter: "إعدادات النظام والتطبيق"))
                                        .font(AdminType.calloutBold)
                                        .foregroundColor(.white)

                                    Text("v6.2")
                                        .font(.system(size: 10, weight: .black, design: .rounded))
                                        .foregroundColor(AdminSurface.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white, in: Capsule())
                                }

                                Text(Language.get("Settings_CommandCenter_Subtitle", alter: "التحكم السيادي، التفضيلات، الذاكرة، والتراخيص"))
                                    .font(AdminType.caption2)
                                    .foregroundColor(Color.white.opacity(0.75))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: Language.isRTL() ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(V6CardButtonStyle())
                }

                // Security Tags Ribbon (Sovereign Infrastructure)
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 6, height: 6)
                        Text(Language.get("More_Tag_AppCheck", alter: "حماية App Check نشطة"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(uiColor: .ppSuccess))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())

                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.6))
                        Text(Language.get("More_Tag_Cluster", alter: "pure-pets-49199"))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.70))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())

                    Spacer()

                    Text(Language.get("More_Tag_Version", alter: "الإصدار v6.2.0"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.50))
                }
            }
            .padding(isPad ? 20 : 16)
        }
    }

    // MARK: - Communications & Broadcast Studio

    private func broadcastStudioDesk(isPad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.blue)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("More_Broadcast_Studio_Title", alter: "مركز البث والتواصل الإداري"))
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("More_Broadcast_Studio_Subtitle", alter: "بث فوري وتنبيهات push لكافة العملاء وأعضاء الفريق"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                Spacer()
            }

            // Featured Instant Broadcast Trigger
            if canNotificationComposer {
                Button {
                    triggerHaptic(.medium)
                    router.present(.notificationComposer, session: session)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 42, height: 42)
                                .shadow(color: Color.blue.opacity(0.35), radius: 6, x: 0, y: 3)

                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(Language.get("More_Broadcast_Send_Instant", alter: "إرسال إشعار فوري للجماهير"))
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(AdminSurface.primaryText)

                                Text(Language.get("LiveDesk_Online", alter: "مباشر"))
                                    .font(.system(size: 9.5, weight: .black))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue, in: Capsule())
                            }

                            Text(Language.get("More_Broadcast_Send_Desc", alter: "صياغة وبث إشعار Push فوري عبر السحابة"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                            .padding(8)
                            .background(AdminSurface.primary.opacity(0.08), in: Circle())
                    }
                    .padding(14)
                    .background(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.08), Color.cyan.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.blue.opacity(0.20), lineWidth: 1)
                    )
                }
                .buttonStyle(V6CardButtonStyle())
            }

            // Subordinate Channels: Inbox & Settings
            if canNotifications || canNotificationSettings {
                VStack(spacing: 0) {
                    if canNotifications {
                        Button {
                            triggerHaptic(.light)
                            router.present(.notifications, session: session)
                        } label: {
                            deskActionRow(
                                title: Language.get("More_Broadcast_Inbox", alter: "صندوق الإشعارات"),
                                subtitle: Language.get("More_Broadcast_Inbox_Desc", alter: "سجل التنبيهات المرسلة والمستلمة"),
                                symbol: "bell.fill",
                                symbolColor: .indigo,
                                showsDivider: canNotificationSettings
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if canNotificationSettings {
                        Button {
                            triggerHaptic(.light)
                            router.present(.notificationSettings, session: session)
                        } label: {
                            deskActionRow(
                                title: Language.get("More_Broadcast_Settings", alter: "إعدادات وقنوات التنبيه"),
                                subtitle: Language.get("More_Broadcast_Settings_Desc", alter: "تخصيص القنوات الصوتية والإشعارات الحرجة"),
                                symbol: "bell.badge.gearshape.fill",
                                symbolColor: .purple,
                                showsDivider: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 0.8)
                )
            }
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Financial & Security Governance Desk

    private func financialAndSecurityDesk(isPad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .ppSuccess).opacity(0.12))
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("More_Governance_Title", alter: "المالية والرقابة السيادية"))
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("More_Governance_Subtitle", alter: "التسويات، الدفتر المالي، وسجل تدقيق الأمان"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                if canAccounting {
                    Button {
                        triggerHaptic(.light)
                        router.present(.accounting, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Accounting_Title", alter: "المحاسبة والتقارير المالية"),
                            subtitle: Language.get("More_Accounting_Desc", alter: "الدفتر المالي، بوابات الدفع، والتسويات"),
                            symbol: "dollarsign.circle.fill",
                            symbolColor: Color(uiColor: .ppSuccess),
                            showsDivider: canAudit
                        )
                    }
                    .buttonStyle(.plain)
                }

                if canAudit {
                    Button {
                        triggerHaptic(.light)
                        router.present(.audit, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Audit_Title", alter: "سجل التدقيق والأمان"),
                            subtitle: Language.get("More_Audit_Desc", alter: "فحص العمليات الإدارية وسجلات الحوكمة الموثقة"),
                            symbol: "doc.text.magnifyingglass",
                            symbolColor: .orange,
                            showsDivider: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Commercial Catalog & Content Bay

    private func commercialCatalogDesk(isPad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("More_Commerce_Title", alter: "إدارة الكتالوج والمحتوى التجاري"))
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("More_Commerce_Subtitle", alter: "التصنيفات، البانرات التسويقية، ومراجعة الإعلانات"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                if canCategories {
                    Button {
                        triggerHaptic(.light)
                        router.present(.categories, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Categories_Title", alter: "التصنيفات والأنواع"),
                            subtitle: Language.get("More_Categories_Desc", alter: "هيكلة الأقسام، فصائل الحيوانات، والأنواع"),
                            symbol: "square.grid.2x2.fill",
                            symbolColor: .teal,
                            showsDivider: canBanners || canListings
                        )
                    }
                    .buttonStyle(.plain)
                }

                if canBanners {
                    Button {
                        triggerHaptic(.light)
                        router.present(.banners, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Staff_Module_Banners", alter: "البانرات والعروض الترويجية"),
                            subtitle: Language.get("More_Banners_Desc", alter: "إدارة سلايدر الشاشة الرئيسية وحملات التسويق"),
                            symbol: "square.3.layers.3d.middle.filled",
                            symbolColor: .pink,
                            showsDivider: canListings
                        )
                    }
                    .buttonStyle(.plain)
                }

                if canListings {
                    Button {
                        triggerHaptic(.light)
                        router.present(.listings, session: session)
                    } label: {
                        deskActionRow(
                            title: Language.get("Staff_Module_Listings", alter: "إعلانات الحيوانات والوساطة"),
                            subtitle: Language.get("More_Listings_Desc", alter: "مراجعة إعلانات المستخدمين والاعتماد الفوري"),
                            symbol: "list.bullet.clipboard.fill",
                            symbolColor: .mint,
                            showsDivider: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Environment & Session Dock

    private var environmentAndSessionDock: some View {
        VStack(spacing: 0) {
            Button {
                triggerHaptic(.light)
                let next = Language.currentLanguageCode() == "ar" ? "en" : "ar"
                Language.userSelectedLanguage(next)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AdminSurface.primary.opacity(0.12))
                        Image(systemName: "globe")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AdminSurface.primary)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Confirm_LanguageChange_Title", alter: "لغة لوحة التحكم"))
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.currentLanguageCode() == "ar" ? "العربية (RTL)" : "English (LTR)")
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text(Language.currentLanguageCode() == "ar" ? "English" : "العربية")
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primary)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 58)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 68)
                .background(AdminSurface.hairline)

            Button(role: .destructive) {
                triggerHaptic(.medium)
                onLogout()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .ppError).opacity(0.10))
                        if isSigningOut {
                            ProgressView()
                                .tint(Color(uiColor: .ppError))
                        } else {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Color(uiColor: .ppError))
                        }
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get(isSigningOut ? "CommandCenter_Signing_Out" : "Logout", alter: "تسجيل الخروج"))
                            .font(AdminType.calloutBold)
                            .foregroundColor(Color(uiColor: .ppError))
                        Text(Language.get("Settings_Session_Logout_Confirm_Msg", alter: "إنهاء الجلسة الإدارية الحالية بأمان"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(uiColor: .ppError).opacity(0.6))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 58)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSigningOut)
        }
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Reusable High-Fidelity Desk Row

    private func deskActionRow(
        title: String,
        subtitle: String,
        symbol: String,
        symbolColor: Color,
        showsDivider: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(symbolColor.opacity(0.12))
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(symbolColor)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .contentShape(Rectangle())

            if showsDivider {
                Divider()
                    .padding(.leading, 64)
                    .background(AdminSurface.hairline)
            }
        }
    }

    // MARK: - Telemetry & Status Helpers

    private var monogram: String {
        let parts = session.displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "PP" : letters.uppercased()
    }

    private var pulseHealthTitle: String {
        guard let snapshot = commandState.currentSnapshot else {
            return Language.get("CommandCenter_Loading", alter: "جاري الفحص...")
        }
        switch snapshot.health {
        case .stable:
            return Language.get("CommandCenter_Health_Stable", alter: "العمليات واضحة")
        case let .attention(count):
            return String(format: Language.get("CommandCenter_Health_Attention_Format", alter: "%@ إجراء بحاجة انتباه"), formattedCount(count))
        case let .partial(count):
            return String(format: Language.get("CommandCenter_Health_Partial_Format", alter: "%@ تدقيق مطلوب"), formattedCount(count))
        }
    }

    private var pulseHealthColor: Color {
        guard let snapshot = commandState.currentSnapshot else { return AdminSurface.primary }
        switch snapshot.health {
        case .stable: return Color(uiColor: .ppSuccess)
        case .attention: return Color(uiColor: .ppWarning)
        case .partial: return AdminSurface.primary
        }
    }

    private var pulseHealthSymbol: String {
        guard let snapshot = commandState.currentSnapshot else { return "shield" }
        switch snapshot.health {
        case .stable: return "checkmark.shield.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .partial: return "arrow.triangle.2.circlepath"
        }
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
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
