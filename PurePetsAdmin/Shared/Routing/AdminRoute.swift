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
        // `payments.manage` is an isolated official-fleet compatibility bridge.
        // New staff grants must use the dedicated delivery permission.
        case .delivery: return ["delivery.view", "payments.manage"]
        case .providerApplications, .providerPlans, .providerFeatures: return ["providers.view", "providers.manage"]
        case .providerAccounting: return ["payments.view", "payments.manage"]
        case .pointOfSale: return ["pos.sell"]
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

    /// Routes are pushed by the SwiftUI shell, which owns an outer UIKit
    /// navigation controller. The legacy route container owns the visible
    /// command-center header through its embedded stack, so the outer bar must
    /// stay hidden or its back/add controls are rendered in addition to the
    /// destination's own controls.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Reassert after the SwiftUI push transition. UIKit can otherwise
        // restore the outer bar while attaching the representable controller.
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

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

        AdminConnectedRouteChrome.apply(to: rootViewController, in: navigationController, route: route)

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

    func refreshLanguageIfNeeded(_ languageCode: String) {
        guard appliedLanguageCode != languageCode else { return }
        appliedLanguageCode = languageCode
        guard isViewLoaded else { return }

        let direction = Language.semanticAttributeForCurrentLanguage()
        view.semanticContentAttribute = direction
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
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        AdminConnectedRouteChrome.apply(to: viewController, in: navigationController, route: route)
    }

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController,
                              animated: Bool) {
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
