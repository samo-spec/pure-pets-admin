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
