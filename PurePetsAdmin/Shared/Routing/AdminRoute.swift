import SwiftUI
import UIKit

enum AdminRoute: Hashable, Identifiable {
    case paymentOrder(String)
    case payments
    case paymentSettings
    case fulfillment
    case delivery
    case providerApplications
    case providerPlans
    case providerFeatures
    case providerAccounting
    case pointOfSale
    case pointOfSaleHistory
    case users
    case staff
    case account
    case chats
    case notifications
    case notificationComposer
    case notificationSettings
    case settings
    case accessories
    case food
    case livePets
    case branches
    case agents
    case accounting
    case audit
    case moderation
    case homeControl
    case services
    case veterinarians
    case categories
    case banners
    case listings

    var id: String { payload.map { "\(identifier):\($0)" } ?? identifier }

    var identifier: String {
        switch self {
        case .paymentOrder: return "paymentOrder"
        case .payments: return "payments"
        case .paymentSettings: return "paymentSettings"
        case .fulfillment: return "fulfillment"
        case .delivery: return "delivery"
        case .providerApplications: return "providerApplications"
        case .providerPlans: return "providerPlans"
        case .providerFeatures: return "providerFeatures"
        case .providerAccounting: return "providerAccounting"
        case .pointOfSale: return "pos"
        case .pointOfSaleHistory: return "posHistory"
        case .users: return "users"
        case .staff: return "staff"
        case .account: return "account"
        case .chats: return "chats"
        case .notifications: return "notifications"
        case .notificationComposer: return "notificationComposer"
        case .notificationSettings: return "notificationSettings"
        case .settings: return "settings"
        case .accessories: return "accessories"
        case .food: return "food"
        case .livePets: return "livePets"
        case .branches: return "branches"
        case .agents: return "agents"
        case .accounting: return "accounting"
        case .audit: return "audit"
        case .moderation: return "moderation"
        case .homeControl: return "homeControl"
        case .services: return "services"
        case .veterinarians: return "vets"
        case .categories: return "categories"
        case .banners: return "banners"
        case .listings: return "listings"
        }
    }

    var payload: String? {
        if case let .paymentOrder(orderID) = self { return orderID }
        return nil
    }

    var titleKey: String {
        switch self {
        case .paymentOrder, .payments: return "PaymentMgmt_Dashboard_Title"
        case .paymentSettings: return "PaymentMgmt_Dashboard_Settings_Title"
        case .fulfillment: return "Fulfillment_Title"
        case .delivery: return "Delivery_Title"
        case .providerApplications: return "Providers_Applications_Title"
        case .providerPlans: return "Providers_Plans_Title"
        case .providerFeatures: return "Providers_Features_Title"
        case .providerAccounting: return "Providers_Accounting_Title"
        case .pointOfSale: return "POS_Title"
        case .pointOfSaleHistory: return "POS_History_Title"
        case .users: return "UsersSection"
        case .staff: return "Staff_Management"
        case .account: return "EditMyAccount_Title"
        case .chats: return "Chats"
        case .notifications: return "Notifications"
        case .notificationComposer: return "SendPushNotification"
        case .notificationSettings: return "Notification Settings"
        case .settings: return "Settings"
        case .accessories: return "Manage Accessories"
        case .food: return "manageFood"
        case .livePets: return "Manage Live Pets"
        case .branches: return "Branches_Title"
        case .agents: return "Agents_Title"
        case .accounting: return "Accounting_Title"
        case .audit: return "Audit_Title"
        case .moderation: return "Moderation_Title"
        case .homeControl: return "HomeControl_Title"
        case .services: return "Service_Manage_Title"
        case .veterinarians: return "Vet_Section_Title"
        case .categories: return "Categories_Title"
        case .banners: return "Staff_Module_Banners"
        case .listings: return "Staff_Module_Listings"
        }
    }

    /// The lane label keeps every destination visibly attached to the
    /// Operations Center taxonomy without changing the destination's production
    /// title or backend responsibility.
    var contextTitleKey: String {
        switch self {
        case .paymentOrder, .payments, .paymentSettings, .fulfillment, .pointOfSale, .pointOfSaleHistory,
             .accessories, .food, .livePets:
            return "CommandCenter_Work_Title"
        case .delivery, .providerApplications, .providerPlans, .providerFeatures, .providerAccounting,
             .branches, .agents, .homeControl, .services, .veterinarians, .moderation:
            return "CommandCenter_Operations_Title"
        case .users:
            return "CommandCenter_People_Title"
        case .staff:
            return "CommandCenter_TeamAccess_Title"
        case .chats:
            return "CommandCenter_Conversations_Title"
        case .account, .notifications, .notificationComposer, .notificationSettings, .settings,
             .accounting, .audit, .categories, .banners, .listings:
            return "CommandCenter_Tab_More"
        }
    }

    var symbol: String {
        switch self {
        case .paymentOrder, .payments: return "creditcard"
        case .paymentSettings: return "slider.horizontal.3"
        case .fulfillment: return "shippingbox"
        case .delivery: return "truck.box"
        case .providerApplications: return "person.badge.plus"
        case .providerPlans: return "list.clipboard"
        case .providerFeatures: return "gearshape.2"
        case .providerAccounting: return "chart.pie"
        case .pointOfSale: return "cart"
        case .pointOfSaleHistory: return "clock.arrow.circlepath"
        case .users: return "person.2"
        case .staff: return "person.3.sequence"
        case .account: return "person.crop.circle"
        case .chats: return "bubble.left.and.bubble.right"
        case .notifications: return "bell"
        case .notificationComposer: return "paperplane"
        case .notificationSettings: return "bell.circle"
        case .settings: return "gearshape"
        case .accessories: return "shippingbox"
        case .food: return "bag"
        case .livePets: return "pawprint"
        case .branches: return "building.2"
        case .agents: return "person.text.rectangle"
        case .accounting: return "dollarsign.circle"
        case .audit: return "doc.text.magnifyingglass"
        case .moderation: return "shield.lefthalf.filled"
        case .homeControl: return "switch.2"
        case .services: return "cross.case"
        case .veterinarians: return "stethoscope"
        case .categories: return "square.grid.2x2"
        case .banners: return "square.3.layers.3d.middle.filled"
        case .listings: return "list.bullet.clipboard"
        }
    }

    var requiredPermissions: [String] {
        switch self {
        case .paymentOrder, .payments: return ["payments.view", "payments.manage"]
        case .paymentSettings: return ["payments.manage"]
        case .fulfillment: return ["payments.view", "payments.manage", "providers.view"]
        case .delivery: return ["payments.manage"]
        case .providerApplications, .providerPlans, .providerFeatures: return ["providers.view", "providers.manage"]
        case .providerAccounting: return ["payments.view", "payments.manage"]
        case .pointOfSale: return ["pos.view", "pos.sell"]
        case .pointOfSaleHistory: return ["pos.view", "pos.sell", "pos.history"]
        case .users: return ["users.view", "users.manage", "users.block", "users.features.view", "users.features.manage", "users.subscriptions.view", "users.subscriptions.manage", "users.restrictions.view", "users.restrictions.manage"]
        case .staff: return ["staff.view", "staff.manage"]
        case .account, .settings: return []
        case .chats: return ["support.view", "support.manage"]
        case .notifications: return ["notifications.view", "support.view", "support.manage", "moderation.view", "moderation.manage"]
        case .notificationComposer: return ["notifications.send"]
        case .notificationSettings: return ["notifications.view", "notifications.send", "support.manage", "moderation.manage", "users.block"]
        case .accessories, .food, .livePets: return ["stock.manage", "stock.create", "stock.delete", "payments.manage", "payments.refund", "accounting.manage", "categories.manage"]
        case .branches: return ["branches.view", "branches.manage"]
        case .agents: return ["agents.view", "agents.manage"]
        case .homeControl: return ["settings.view", "settings.manage"]
        case .accounting: return ["accounting.view", "accounting.manage"]
        case .audit: return ["audit.view"]
        case .moderation: return ["moderation.view", "moderation.manage", "listings.moderate"]
        case .services: return ["services.view", "services.manage", "providers.manage", "veterinarians.manage"]
        case .veterinarians: return ["veterinarians.view", "veterinarians.manage", "providers.manage", "services.manage"]
        case .categories: return ["categories.view", "categories.manage"]
        case .banners: return ["banners.manage"]
        case .listings: return ["listings.view", "listings.manage", "listings.moderate"]
        }
    }

    /// Some legacy controllers perform a direct Firestore read whose rule is
    /// narrower than the module catalog permission. Keep that backend
    /// constraint explicit instead of showing a route that will immediately
    /// fail after navigation.
    var requiredAllPermissions: [String] {
        switch self {
        case .accessories, .food, .livePets:
            return ["stock.manage"]
        case .listings:
            return ["stock.manage"]
        default:
            return []
        }
    }

    func isAuthorized(for session: AdminSession) -> Bool {
        guard session.hasAnyPermission(requiredPermissions),
              requiredAllPermissions.allSatisfy(session.hasPermission) else {
            return false
        }
        return ![.audit, .providerAccounting].contains(self) || session.hasGlobalScope
    }
}

@MainActor
final class AdminRouter: ObservableObject {
    @Published var presentedRoute: AdminRoute?
    @Published var permissionDenied = false
    private var pendingPaymentOrderID: String?

    func resetProtectedRoutes() {
        presentedRoute = nil
        pendingPaymentOrderID = nil
        permissionDenied = false
    }

    func present(_ route: AdminRoute, session: AdminSession) {
        guard route.isAuthorized(for: session) else {
            permissionDenied = true
            return
        }
        presentedRoute = route
    }

    func enqueuePaymentOrder(_ orderID: String) {
        let trimmed = orderID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingPaymentOrderID = trimmed
    }

    func consumePendingRoute(session: AdminSession) {
        guard let pendingPaymentOrderID else { return }
        self.pendingPaymentOrderID = nil
        present(.paymentOrder(pendingPaymentOrderID), session: session)
    }
}

struct AdminLegacyRouteView: UIViewControllerRepresentable {
    let route: AdminRoute
    let languageCode: String
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = PPAdminRouteFactory.viewController(
            routeIdentifier: route.identifier,
            payload: route.payload
        ) ?? unavailableController
        return AdminLegacyRouteContainerController(
            rootViewController: controller,
            route: route,
            dismissTarget: context.coordinator,
            dismissAction: #selector(Coordinator.dismissRoute)
        )
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? AdminLegacyRouteContainerController)?
            .refreshLanguageIfNeeded(languageCode)
    }

    private var unavailableController: UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .ppBackground
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Language.get("CommandCenter_Route_Unavailable", alter: nil)
        label.textColor = .ppTextSecondary
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        label.textAlignment = .center
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: controller.view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: controller.view.layoutMarginsGuide.trailingAnchor),
        ])
        return controller
    }

    final class Coordinator: NSObject {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        @objc func dismissRoute() { onDismiss() }
    }
}

private final class AdminLegacyRouteContainerController: UIViewController, UINavigationControllerDelegate {
    private let rootViewController: UIViewController
    private let route: AdminRoute
    private let dismissTarget: AnyObject
    private let dismissAction: Selector
    private var workflowNavigationController: AdminGlobalNavigationStackController?
    private var globalNavigationController: PPGlobalNavigationHostingController?
    private var globalNavigationHeightConstraint: NSLayoutConstraint?
    private var actionItemsByIdentifier: [String: UIBarButtonItem] = [:]
    private var overflowActionItems: [UIBarButtonItem] = []
    private var actionItemObservations: [NSKeyValueObservation] = []
    private nonisolated(unsafe) var navigationItemsObserver: (any NSObjectProtocol)?
    private nonisolated(unsafe) var commandNavigationItemsObserver: (any NSObjectProtocol)?
    private var usesCompactNavigationLayout: Bool?
    private var appliedLanguageCode: String?

    init(rootViewController: UIViewController,
         route: AdminRoute,
         dismissTarget: AnyObject,
         dismissAction: Selector) {
        self.rootViewController = rootViewController
        self.route = route
        self.dismissTarget = dismissTarget
        self.dismissAction = dismissAction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let usesClearCanvas = route == .homeControl
        view.backgroundColor = usesClearCanvas ? .clear : .ppBackground
        view.isOpaque = !usesClearCanvas
        view.semanticContentAttribute = Language.isRTL() ? .forceRightToLeft : .forceLeftToRight

        let navigationController = AdminGlobalNavigationStackController(rootViewController: rootViewController)
        workflowNavigationController = navigationController
        PPSetCommandCenterNavigationManaged(navigationController, true)
        navigationController.delegate = self
        commandNavigationItemsObserver = NotificationCenter.default.addObserver(
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
        navigationItemsObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("PPHomeControlNavigationItemsDidChangeNotification"),
            object: rootViewController,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshGlobalNavigation()
            }
        }
        AdminConnectedRouteChrome.apply(to: rootViewController, in: navigationController, route: route)
        if let deliveryController = rootViewController as? PPDeliveryManagementViewController {
            deliveryController.globalNavigationStateDidChange = { [weak self] in
                self?.refreshGlobalNavigation()
            }
        }

        let globalNavigation = PPGlobalNavigationHostingController(
            configuration: navigationConfiguration(for: rootViewController)
        ) { [weak self] action in
            self?.handleGlobalNavigationAction(action)
        }
        globalNavigation.onPreferredBarHeightChange = { [weak self] height in
            guard let self,
                  abs((self.globalNavigationHeightConstraint?.constant ?? height) - height) > 0.5 else {
                return
            }
            self.globalNavigationHeightConstraint?.constant = height
            self.view.setNeedsLayout()
        }
        globalNavigationController = globalNavigation
        addChild(globalNavigation)
        view.addSubview(globalNavigation.view)
        globalNavigation.view.translatesAutoresizingMaskIntoConstraints = false
        globalNavigation.view.semanticContentAttribute = view.semanticContentAttribute
        let heightConstraint = globalNavigation.view.heightAnchor.constraint(
            equalToConstant: globalNavigation.preferredBarHeight
        )
        globalNavigationHeightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            globalNavigation.view.topAnchor.constraint(equalTo: view.topAnchor),
            globalNavigation.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            globalNavigation.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heightConstraint,
        ])
        heightConstraint.constant = globalNavigation.preferredBarHeight
        globalNavigation.didMove(toParent: self)

        addChild(navigationController)
        view.addSubview(navigationController.view)
        navigationController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navigationController.view.topAnchor.constraint(equalTo: globalNavigation.view.bottomAnchor),
            navigationController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        navigationController.didMove(toParent: self)
        view.bringSubviewToFront(globalNavigation.view)
    }

    deinit {
        if let navigationItemsObserver {
            NotificationCenter.default.removeObserver(navigationItemsObserver)
        }
        if let commandNavigationItemsObserver {
            NotificationCenter.default.removeObserver(commandNavigationItemsObserver)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let preferredHeight = globalNavigationController?.preferredBarHeight,
           abs((globalNavigationHeightConstraint?.constant ?? 0) - preferredHeight) > 0.5 {
            globalNavigationHeightConstraint?.constant = preferredHeight
            view.setNeedsLayout()
        }
        let compact = shouldUseCompactNavigationLayout
        guard usesCompactNavigationLayout != compact else { return }
        usesCompactNavigationLayout = compact
        refreshGlobalNavigation()
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
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }
        globalNavigationHeightConstraint?.constant = globalNavigationController?.preferredBarHeight ?? 0
        refreshGlobalNavigation()
    }

    func refreshLanguageIfNeeded(_ languageCode: String) {
        guard appliedLanguageCode != languageCode else { return }
        appliedLanguageCode = languageCode
        guard isViewLoaded else { return }

        let direction = Language.semanticAttributeForCurrentLanguage()
        view.semanticContentAttribute = direction
        globalNavigationController?.view.semanticContentAttribute = direction
        workflowNavigationController?.view.semanticContentAttribute = direction

        guard let navigationController = workflowNavigationController,
              let visibleController = navigationController.topViewController else {
            return
        }
        if navigationController.viewControllers.first === visibleController {
            let title = Language.get(route.titleKey, alter: nil)
            visibleController.title = title
            visibleController.navigationItem.title = title
        }
        AdminConnectedRouteChrome.apply(to: visibleController, in: navigationController, route: route)
        refreshGlobalNavigation()
    }

    private func navigationConfiguration(for viewController: UIViewController) -> PPGlobalNavigationConfiguration {
        let isRoot = workflowNavigationController?.viewControllers.first === viewController
        let title = resolvedTitle(for: viewController)
        let leadingAction = isRoot ? closeAction : backAction

        return PPGlobalNavigationConfiguration(
            style: .contextDeck,
            title: title,
            // Route screens must use the same brand/context line as the Home
            // shell.  Using the Operations Center title here created a second
            // navigation hierarchy and made pushed legacy screens visibly drift
            // from the shared Home global bar.
            eyebrow: Language.get("CommandCenter_Eyebrow", alter: nil),
            subtitle: isRoot ? Language.get(route.contextTitleKey, alter: nil) : nil,
            context: Language.get(route.contextTitleKey, alter: nil),
            leadingAction: leadingAction,
            trailingActions: trailingActions(for: viewController),
            showsContextFilament: false
        )
    }

    private var closeAction: PPGlobalNavigationAction {
        PPGlobalNavigationAction(
            id: "admin-route-close",
            kind: .close,
            accessibilityLabel: Language.get("Close", alter: nil),
            accessibilityHint: Language.get("CommandCenter_Close_Workflow_Hint", alter: nil)
        )
    }

    private var backAction: PPGlobalNavigationAction {
        PPGlobalNavigationAction(
            id: "admin-route-back",
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
        return Language.get(route.titleKey, alter: nil)
    }

    private func trailingActions(for viewController: UIViewController) -> [PPGlobalNavigationAction] {
        actionItemsByIdentifier.removeAll()
        overflowActionItems.removeAll()

        let items = (viewController.navigationItem.rightBarButtonItems ?? []) +
            (viewController.navigationItem.leftBarButtonItems ?? [])
        observeActionItems(items)
        var actions: [PPGlobalNavigationAction] = []

        for item in items {
            let identifier = "admin-route-action-\(actions.count + overflowActionItems.count)"
            if actions.count >= maximumDirectActions {
                overflowActionItems.append(item)
                continue
            }

            let mappedIdentifier = item.accessibilityIdentifier ?? identifier
            actionItemsByIdentifier[mappedIdentifier] = item
            actions.append(globalNavigationAction(for: item, identifier: mappedIdentifier))
        }

        if !overflowActionItems.isEmpty {
            actions.append(PPGlobalNavigationAction(
                id: "admin-route-overflow",
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
        shouldUseCompactNavigationLayout ? 1 : 2
    }

    private func actionIsEnabled(_ item: UIBarButtonItem) -> Bool {
        item.isEnabled && ((item.customView as? UIControl)?.isEnabled ?? true)
    }

    private var shouldUseCompactNavigationLayout: Bool {
        traitCollection.preferredContentSizeCategory.isAccessibilityCategory ||
            (view.bounds.width > 0 && view.bounds.width < 350)
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
        case "admin-route-close":
            if let target = dismissTarget as? NSObject {
                _ = target.perform(dismissAction)
            }
        case "admin-route-back":
            requestBackFromVisibleController()
        case "admin-route-overflow":
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

    private func refreshGlobalNavigation() {
        guard let visibleController = workflowNavigationController?.topViewController else { return }
        globalNavigationController?.update(
            configuration: navigationConfiguration(for: visibleController)
        ) { [weak self] action in
            self?.handleGlobalNavigationAction(action)
        }
        globalNavigationHeightConstraint?.constant = globalNavigationController?.preferredBarHeight ?? 0
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        AdminConnectedRouteChrome.apply(to: viewController, in: navigationController, route: route)
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

private final class AdminGlobalNavigationStackController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        super.setNavigationBarHidden(true, animated: false)
    }

    override func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        super.setNavigationBarHidden(true, animated: false)
    }
}

/// Presentation-only chrome for destinations reached from the Command Center.
///
/// The destination controllers remain the owners of data, actions, and nested
/// navigation. This adapter only gives the legacy UIKit stack the same surface,
/// navigation, typography, and direction treatment as the SwiftUI reference
/// shell. Keeping it at the route container boundary prevents unrelated Admin
/// entry points from inheriting the connected-workflow treatment.
@MainActor
private enum AdminConnectedRouteChrome {
    static func apply(to viewController: UIViewController,
                      in navigationController: UINavigationController,
                      route: AdminRoute) {
        let direction: UISemanticContentAttribute = Language.isRTL()
            ? .forceRightToLeft
            : .forceLeftToRight

        viewController.view.semanticContentAttribute = direction
        let usesClearCanvas = route == .homeControl
        let canvasColor: UIColor = usesClearCanvas ? .clear : .ppBackground
        viewController.view.backgroundColor = canvasColor
        viewController.view.isOpaque = !usesClearCanvas
        if viewController.navigationItem.title?.isEmpty != false {
            viewController.navigationItem.title = Language.get(route.titleKey, alter: nil)
        }
        viewController.navigationItem.largeTitleDisplayMode = .never
        navigationController.view.semanticContentAttribute = direction
        navigationController.view.backgroundColor = canvasColor
        navigationController.view.isOpaque = !usesClearCanvas
        navigationController.setNavigationBarHidden(true, animated: false)
        applyPresentation(to: viewController.view,
                          canvasColor: canvasColor,
                          usesClearCanvas: usesClearCanvas)
    }

    private static func applyPresentation(to view: UIView,
                                          canvasColor: UIColor,
                                          usesClearCanvas: Bool) {
        if let tableView = view as? UITableView {
            tableView.backgroundColor = canvasColor
            tableView.isOpaque = !usesClearCanvas
            tableView.separatorColor = .clear
            tableView.separatorStyle = .none
        } else if let collectionView = view as? UICollectionView {
            collectionView.backgroundColor = canvasColor
            collectionView.isOpaque = !usesClearCanvas
        } else if let textField = view as? UITextField {
            textField.tintColor = .ppPrimary
            textField.textColor = .ppTextPrimary
            textField.backgroundColor = textField.backgroundColor ?? .ppSurface
        } else if let textView = view as? UITextView {
            textView.tintColor = .ppPrimary
            textView.textColor = .ppTextPrimary
            textView.backgroundColor = textView.backgroundColor ?? .ppSurface
        } else if let searchBar = view as? UISearchBar {
            searchBar.tintColor = .ppPrimary
        } else if let switchControl = view as? UISwitch {
            switchControl.onTintColor = .ppPrimary
            switchControl.tintColor = .ppSurfaceBorder
        } else if let activityIndicator = view as? UIActivityIndicatorView {
            activityIndicator.color = .ppPrimary
        }

        for child in view.subviews {
            applyPresentation(to: child,
                              canvasColor: canvasColor,
                              usesClearCanvas: usesClearCanvas)
        }
    }
}
