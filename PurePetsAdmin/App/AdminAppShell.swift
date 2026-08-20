import SwiftUI

@MainActor
struct AdminAppShell: View {
    let session: AdminSession
    @ObservedObject var sessionStore: AdminSessionStore
    @ObservedObject var router: AdminRouter

    @State private var selectedTab: AdminTab = .command
    @State private var showsLogoutConfirmation = false
    @StateObject private var commandState: CommandCenterState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(session: AdminSession, sessionStore: AdminSessionStore, router: AdminRouter) {
        self.session = session
        self.sessionStore = sessionStore
        self.router = router
        _commandState = StateObject(wrappedValue: CommandCenterState(session: session))
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AdminCommandOrbitDashboard(session: session, languageCode: sessionStore.languageCode)
                .ignoresSafeArea(.all, edges: .top)
                .tag(AdminTab.command)

            AdminModuleListView(
                tab: .work,
                routes: available([.payments, .paymentSettings, .fulfillment, .pointOfSale, .pointOfSaleHistory, .accessories, .food, .livePets]),
                session: session,
                router: router,
                commandState: commandState,
                onOpenCommand: { selectedTab = .command }
            )
            .ignoresSafeArea(.all, edges: .top)
            .tag(AdminTab.work)

            AdminModuleListView(
                tab: .operations,
                routes: available([.delivery, .providerApplications, .providerPlans, .providerFeatures, .providerAccounting, .branches, .agents, .homeControl, .services, .veterinarians, .moderation]),
                session: session,
                router: router,
                commandState: commandState,
                onOpenCommand: { selectedTab = .command }
            )
            .ignoresSafeArea(.all, edges: .top)
            .tag(AdminTab.operations)

            AdminModuleListView(
                tab: .customers,
                routes: available([.users, .staff, .chats]),
                session: session,
                router: router,
                commandState: commandState,
                onOpenCommand: { selectedTab = .command }
            )
            .ignoresSafeArea(.all, edges: .top)
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
            .ignoresSafeArea(.all, edges: .top)
            .tag(AdminTab.more)
        }
        .tint(AdminSurface.primary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            V6GlobalTabBar(selectedTab: $selectedTab)
        }
        .fullScreenCover(item: $router.presentedRoute) { route in
            AdminLegacyRouteView(route: route, languageCode: sessionStore.languageCode) {
                router.presentedRoute = nil
            }
                // UIKit owns both safe-area edges for presented native routes;
                // each child then receives the device insets exactly once.
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
            router.consumePendingRoute(session: session)
        }
        .onChange(of: selectedTab) { tab in
            if tab != .command {
                commandState.loadIfNeeded()
            }
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
private struct AdminCommandOrbitDashboard: UIViewControllerRepresentable {
    let session: AdminSession
    let languageCode: String

    func makeUIViewController(context: Context) -> AdminCommandOrbitContainerController {
        AdminCommandOrbitContainerController()
    }

    func updateUIViewController(_ controller: AdminCommandOrbitContainerController, context: Context) {
        controller.refresh(session: session, languageCode: languageCode)
    }
}

private final class AdminCommandOrbitContainerController: UIViewController, UINavigationControllerDelegate {
    private let dashboard = PPAdminCreateCommandSpineDashboardController()
    private var workflowNavigationController: AdminCommandOrbitNavigationController?
    private var globalNavigationController: PPGlobalNavigationHostingController?
    private var globalNavigationHeightConstraint: NSLayoutConstraint?
    private var actionItemsByIdentifier: [String: UIBarButtonItem] = [:]
    private var overflowActionItems: [UIBarButtonItem] = []
    private var actionItemObservations: [NSKeyValueObservation] = []
    private nonisolated(unsafe) var navigationItemsObserver: (any NSObjectProtocol)?
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
        navigationItemsObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("PPCommandCenterNavigationItemsDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let changedController = notification.object as? UIViewController else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      self.workflowNavigationController?.topViewController === changedController else {
                    return
                }
                self.refreshGlobalNavigation()
            }
        }
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

    deinit {
        if let navigationItemsObserver {
            NotificationCenter.default.removeObserver(navigationItemsObserver)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let preferredHeight = globalNavigationController?.preferredBarHeight,
           abs((globalNavigationHeightConstraint?.constant ?? 0) - preferredHeight) > 0.5 {
            globalNavigationHeightConstraint?.constant = preferredHeight
            view.setNeedsLayout()
        }
        refreshBottomDockLanguage()
        applyBottomDockPolish()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let preferredHeight = globalNavigationController?.preferredBarHeight,
           abs((globalNavigationHeightConstraint?.constant ?? 0) - preferredHeight) > 0.5 {
            globalNavigationHeightConstraint?.constant = preferredHeight
            view.setNeedsLayout()
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if let preferredHeight = globalNavigationController?.preferredBarHeight,
           abs((globalNavigationHeightConstraint?.constant ?? 0) - preferredHeight) > 0.5 {
            globalNavigationHeightConstraint?.constant = preferredHeight
            view.setNeedsLayout()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyBottomDockPolish()
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }
        globalNavigationHeightConstraint?.constant = globalNavigationController?.preferredBarHeight ?? 0
        refreshGlobalNavigation()
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
        globalNavigationController?.view.semanticContentAttribute = direction
        globalNavigationController?.view.backgroundColor = .ppBackground
        workflowNavigationController?.view.semanticContentAttribute = direction
        workflowNavigationController?.view.backgroundColor = .ppBackground
        workflowNavigationController?.topViewController?.view.semanticContentAttribute = direction
        workflowNavigationController?.topViewController?.view.backgroundColor = .ppBackground
        refreshBottomDockLanguage()
        applyBottomDockPolish()
        refreshGlobalNavigation()

        if authorizationChanged, dashboard.isViewLoaded {
            authorizationRefreshGeneration &+= 1
            let generation = authorizationRefreshGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.authorizationRefreshGeneration == generation,
                      self.appliedSession == session else {
                    return
                }
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

    private func navigationConfiguration(for viewController: UIViewController) -> PPGlobalNavigationConfiguration {
        let isRoot = workflowNavigationController?.viewControllers.first === viewController
        return PPGlobalNavigationConfiguration(
            style: .contextDeck,
            title: isRoot ? Language.get("AdminCommand_Title", alter: nil) : resolvedTitle(for: viewController),
            eyebrow: Language.get("CommandCenter_Eyebrow", alter: nil),
            subtitle: isRoot ? Language.get("AdminCommand_Subtitle", alter: nil) : nil,
            leadingAction: isRoot ? nil : backAction,
            trailingActions: trailingActions(for: viewController),
            showsContextFilament: true
        )
    }

    private var backAction: PPGlobalNavigationAction {
        PPGlobalNavigationAction(
            id: "admin-command-spine-back",
            kind: .back,
            accessibilityLabel: Language.get("Back", alter: nil)
        )
    }

    private func resolvedTitle(for viewController: UIViewController) -> String {
        let titles = [viewController.navigationItem.title, viewController.title]
        if let title = titles
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return title
        }
        return Language.get("AdminCommand_Title", alter: nil)
    }

    private func trailingActions(for viewController: UIViewController) -> [PPGlobalNavigationAction] {
        actionItemsByIdentifier.removeAll()
        overflowActionItems.removeAll()

        let items = (viewController.navigationItem.rightBarButtonItems ?? []) +
            (viewController.navigationItem.leftBarButtonItems ?? [])
        observeActionItems(items)
        var actions: [PPGlobalNavigationAction] = []

        for item in items {
            let fallbackIdentifier = "admin-command-spine-action-\(actions.count + overflowActionItems.count)"
            if actions.count >= maximumDirectActions {
                overflowActionItems.append(item)
                continue
            }

            let identifier = item.accessibilityIdentifier ?? fallbackIdentifier
            actionItemsByIdentifier[identifier] = item
            actions.append(globalNavigationAction(for: item, identifier: identifier))
        }

        if !overflowActionItems.isEmpty {
            actions.append(PPGlobalNavigationAction(
                id: "admin-command-spine-overflow",
                kind: .more,
                accessibilityLabel: Language.get("CommandCenter_Tab_More", alter: nil)
            ))
        }
        return actions
    }

    private func observeActionItems(_ items: [UIBarButtonItem]) {
        var observations: [NSKeyValueObservation] = []
        for item in items {
            observations.append(item.observe(\.isEnabled, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshGlobalNavigation()
                }
            })
            if let control = item.customView as? UIControl {
                observations.append(control.observe(\.isEnabled, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in
                        self?.refreshGlobalNavigation()
                    }
                })
            }
        }
        actionItemObservations = observations
    }

    private var maximumDirectActions: Int {
        traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 1 : 2
    }

    private func actionIsEnabled(_ item: UIBarButtonItem) -> Bool {
        item.isEnabled && ((item.customView as? UIControl)?.isEnabled ?? true)
    }

    private func title(for item: UIBarButtonItem) -> String {
        let customViewLabel = item.customView?.accessibilityLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [item.accessibilityLabel, item.title, customViewLabel]
        if let title = candidates
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return title
        }
        return Language.get("CommandCenter_Tab_More", alter: nil)
    }

    private func globalNavigationAction(for item: UIBarButtonItem,
                                        identifier: String) -> PPGlobalNavigationAction {
        let label = title(for: item)
        switch identifier {
        case "admin-accessory-editor-save":
            return PPGlobalNavigationAction(
                id: identifier,
                kind: .confirm,
                accessibilityLabel: label,
                accessibilityHint: item.accessibilityHint,
                prominence: .emphasized,
                isEnabled: actionIsEnabled(item),
                title: Language.get("Save", alter: nil)
            )
        case "admin-notification-composer-send":
            return PPGlobalNavigationAction(
                id: identifier,
                kind: .confirm,
                accessibilityLabel: label,
                accessibilityHint: item.accessibilityHint,
                prominence: .emphasized,
                isEnabled: actionIsEnabled(item),
                title: Language.get("NotificationComposer_Action_Send", alter: nil)
            )
        default:
            return PPGlobalNavigationAction(
                id: identifier,
                kind: identifier == "admin-delivery-refresh" ? .refresh : .custom(symbol: "ellipsis.circle"),
                accessibilityLabel: label,
                accessibilityHint: item.accessibilityHint,
                prominence: .standard,
                isEnabled: actionIsEnabled(item)
            )
        }
    }

    private func handleGlobalNavigationAction(_ action: PPGlobalNavigationAction) {
        switch action.id {
        case "admin-command-spine-back":
            requestBackFromVisibleController()
        case "admin-command-spine-overflow":
            presentOverflowActions()
        default:
            guard let item = actionItemsByIdentifier[action.id] else { return }
            perform(item)
        }
    }

    private func requestBackFromVisibleController() {
        guard let navigationController = workflowNavigationController,
              let visibleController = navigationController.topViewController else {
            return
        }
        let selector = NSSelectorFromString("onBack")
        if PPCommandCenterNavigationHasCustomBackAction(visibleController) {
            _ = visibleController.perform(selector)
        } else {
            navigationController.popViewController(animated: true)
        }
    }

    private func presentOverflowActions() {
        guard !overflowActionItems.isEmpty else { return }
        let controller = UIAlertController(
            title: Language.get("CommandCenter_Tab_More", alter: nil),
            message: nil,
            preferredStyle: .actionSheet
        )
        for item in overflowActionItems where actionIsEnabled(item) {
            controller.addAction(UIAlertAction(title: title(for: item), style: .default) { [weak self] _ in
                self?.perform(item)
            })
        }
        controller.addAction(UIAlertAction(
            title: Language.get("Cancel", alter: nil),
            style: .cancel
        ))
        if let popover = controller.popoverPresentationController,
           let sourceView = globalNavigationController?.view {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        present(controller, animated: true)
    }

    private func perform(_ item: UIBarButtonItem) {
        guard actionIsEnabled(item) else { return }
        if let control = item.customView as? UIControl {
            control.sendActions(for: .touchUpInside)
            return
        }
        guard let action = item.action else { return }
        UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil)
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

    private func refreshGlobalNavigation() {
        guard let visibleController = workflowNavigationController?.topViewController else { return }
        globalNavigationController?.update(
            configuration: navigationConfiguration(for: visibleController)
        ) { [weak self] action in
            self?.handleGlobalNavigationAction(action)
        }
        globalNavigationHeightConstraint?.constant = globalNavigationController?.preferredBarHeight ?? 0
    }

    /// Delivery owns request loading; the shell observes only its navigation
    /// action state so the shared global trailing refresh remains current.
    private func connectGlobalNavigationStateBridge(to viewController: UIViewController) {
        guard let deliveryController = viewController as? PPDeliveryManagementViewController else { return }
        deliveryController.globalNavigationStateDidChange = { [weak self, weak deliveryController] in
            guard let self,
                  self.workflowNavigationController?.topViewController === deliveryController else {
                return
            }
            self.refreshGlobalNavigation()
        }
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        applyGlobalNavigationPresentation(to: viewController, in: navigationController)
        connectGlobalNavigationStateBridge(to: viewController)
        refreshGlobalNavigation()
        DispatchQueue.main.async { [weak self, weak navigationController, weak viewController] in
            guard let self,
                  let navigationController,
                  let viewController,
                  navigationController.topViewController === viewController else {
                return
            }
            self.refreshGlobalNavigation()
        }
    }

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
        refreshGlobalNavigation()
    }
}

private final class AdminCommandOrbitNavigationController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        super.setNavigationBarHidden(true, animated: false)
    }

    override func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        super.setNavigationBarHidden(true, animated: false)
    }
}

// MARK: - V6 Global Tab Bar

struct V6GlobalTabBar: View {
    @Binding var selectedTab: AdminTab
    
    var body: some View {
        HStack {
            tabItem(title: "الرئيسية", icon: "command", tab: .command)
            Spacer()
            tabItem(title: "العمل", icon: "square.stack.3d.up.fill", tab: .work)
            Spacer()
            tabItem(title: "العمليات", icon: "waveform.path.ecg", tab: .operations)
            Spacer()
            tabItem(title: "الأشخاص", icon: "person.2.fill", tab: .customers)
            Spacer()
            tabItem(title: "المزيد", icon: "ellipsis.circle.fill", tab: .more)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground).ignoresSafeArea(.all, edges: .bottom)) // V6.cardBackgroundElevated
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: -4)
    }
    
    private func tabItem(title: String, icon: String, tab: AdminTab) -> some View {
        let isSelected = (selectedTab == tab)
        let criticalColor = Color(red: 0.89, green: 0.15, blue: 0.21)
        
        return Button {
            if selectedTab != tab {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    selectedTab = tab
                }
            }
        } label: {
            if isSelected {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                    Text(title)
                        .font(.custom("Beiruti-Bold", size: 14))
                }
                .foregroundStyle(criticalColor)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(criticalColor.opacity(0.12), in: Capsule())
            } else {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                    Text(title)
                        .font(.custom("Beiruti-Medium", size: 12))
                }
                .foregroundStyle(Color(uiColor: .label))
                .frame(minWidth: 44)
            }
        }
        .buttonStyle(V6CardButtonStyle())
    }
}

// MARK: - V6 Button Style (Global)

struct V6CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
            LazyVStack(alignment: .leading, spacing: 14) {
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
            .padding(.horizontal, 20)
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
            .padding(.horizontal, 20)
        }
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
