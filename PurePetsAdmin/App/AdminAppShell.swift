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
                    AdminModuleListView(
                        tab: .operations,
                        routes: available([.delivery, .providerApplications, .providerPlans, .providerFeatures, .providerAccounting, .branches, .agents, .homeControl, .services, .veterinarians, .moderation, .hotel]),
                        session: session,
                        router: router,
                        commandState: commandState,
                        onOpenCommand: { selectedTab = .command }
                    )
                    .ignoresSafeArea()

                case .customers:
                    AdminModuleListView(
                        tab: .customers,
                        routes: available([.users, .staff, .chats]),
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
                V6GlobalTabBar(selectedTab: $selectedTab, tabs: availableTabs)
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
                // UIKit continues to own both safe-area edges for legacy route
                // containers; the push only replaces the former modal handoff.
                .ignoresSafeArea()
                .navigationBarHidden(true)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabAnimationNamespace
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(tabs) { tab in
                tabItem(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: 60)
        .background(
            ZStack {
                // Glassmorphic Base
                RoundedRectangle(cornerRadius: AdminShellMetric.dockCornerRadius, style: .continuous)
                    .fill(AdminSurface.surface.opacity(colorScheme == .dark ? 0.90 : 0.95))

                RoundedRectangle(cornerRadius: AdminShellMetric.dockCornerRadius, style: .continuous)
                    .fill(Material.ultraThinMaterial)

                // Specular Border Highlight
                RoundedRectangle(cornerRadius: AdminShellMetric.dockCornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.60),
                                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18),
                                AdminSurface.hairline.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: AdminShellMetric.dockCornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.08), radius: 18, x: 0, y: 8)
        .shadow(color: AdminSurface.primary.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
    }

    private func tabItem(_ tab: AdminTab) -> some View {
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
                    RoundedRectangle(cornerRadius: AdminShellMetric.dockItemRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AdminSurface.primary.opacity(colorScheme == .dark ? 0.24 : 0.12),
                                    AdminSurface.primary.opacity(colorScheme == .dark ? 0.15 : 0.06)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AdminShellMetric.dockItemRadius, style: .continuous)
                                .strokeBorder(AdminSurface.primary.opacity(0.22), lineWidth: 0.75)
                        )
                        .matchedGeometryEffect(id: "ActiveTabIndicator", in: tabAnimationNamespace)
                }

                VStack(spacing: 2) {
                    // Micro-Beacon Dot for Active State
                    Circle()
                        .fill(isSelected ? AdminSurface.primary : Color.clear)
                        .frame(width: 4, height: 4)
                        .opacity(isSelected ? 1.0 : 0.0)
                        .scaleEffect(isSelected ? 1.0 : 0.2)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                        .accessibilityHidden(true)

                    Image(systemName: symbol)
                        .font(.system(size: isSelected ? 17 : 16, weight: isSelected ? .semibold : .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.80))
                        .frame(height: 19)
                        .scaleEffect(isSelected ? 1.06 : 1.0)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(isSelected ? Font.custom("Beiruti-Bold", size: 11.5) : Font.custom("Beiruti-Medium", size: 11))
                        .foregroundColor(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.80))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(RoundedRectangle(cornerRadius: AdminShellMetric.dockItemRadius, style: .continuous))
        }
        .buttonStyle(V6TabButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                        RadialGradient(
                            colors: [AdminSurface.primary.opacity(0.35), Color.clear],
                            center: Language.isRTL() ? .topLeading : .topTrailing,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
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
                    RadialGradient(
                        colors: [AdminSurface.primary.opacity(0.32), Color.clear],
                        center: Language.isRTL() ? .topLeading : .topTrailing,
                        startRadius: 0,
                        endRadius: 260
                    )
                )
                .overlay(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.12), Color.clear],
                        center: Language.isRTL() ? .bottomTrailing : .bottomLeading,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
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
                        .fill(Color(uiColor: .ppSuccess).opacity(0.12))
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("CommandCenter_Title", alter: "مركز العمليات المركزي"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)

                    Text(Language.get("CommandCenter_Health_Stable", alter: "كافة المؤشرات التشغيلية منتظمة"))
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
                PPAdminBranchSwitcherBar()

                if AdminTab.command.isAuthorized(for: session) {
                    AdminCommandPulseStrip(state: commandState, onOpenCommand: onOpenCommand)
                }

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
            .padding(.bottom, 104)
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
                PPAdminBranchSwitcherBar()

                if AdminTab.command.isAuthorized(for: session) {
                    AdminCommandPulseStrip(state: commandState, onOpenCommand: onOpenCommand)
                }

                Button {
                    router.present(.account, session: session)
                } label: {
                    AdminProfileSummaryCard(session: session)
                }
                .buttonStyle(V6CardButtonStyle())

                if AdminRoute.settings.isAuthorized(for: session) {
                    AdminFeaturedSettingsCard(session: session) {
                        router.present(.settings, session: session)
                    }
                }

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
            .padding(.bottom, 104)
        }
    }
}

private struct AdminFeaturedSettingsCard: View {
    let session: AdminSession
    let onOpenSettings: () -> Void

    var body: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AdminSurface.primary,
                                    AdminSurface.primary.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 48, height: 48)
                .shadow(color: AdminSurface.primary.opacity(0.28), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(Language.get("Settings_CommandCenter_Title", alter: "إعدادات النظام والتطبيق"))
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)

                        Text("v6.2")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    }

                    Text(Language.get("Settings_CommandCenter_Subtitle", alter: "التحكم السيادي، التفضيلات، الذاكرة، والتراخيص"))
                        .font(AdminType.footnote)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                    .padding(8)
                    .background(AdminSurface.control.opacity(0.6), in: Circle())
            }
            .padding(16)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminShellMetric.groupRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminShellMetric.groupRadius, style: .continuous)
                    .stroke(AdminSurface.primary.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(V6CardButtonStyle())
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

            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
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
