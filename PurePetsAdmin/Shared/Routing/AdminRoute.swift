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
        case .paymentOrder, .payments: return ["payments.view", "payments.manage", "payments.refund", "accounting.manage", "stock.manage", "stock.create", "stock.delete", "categories.manage"]
        case .paymentSettings: return ["payments.manage", "payments.refund", "accounting.manage", "settings.manage", "stock.manage", "stock.create", "stock.delete", "categories.manage"]
        case .fulfillment: return ["payments.view", "payments.manage"]
        case .delivery: return ["payments.manage"]
        case .providerApplications, .providerPlans, .providerFeatures, .providerAccounting: return ["providers.view", "providers.manage"]
        case .pointOfSale: return ["pos.view", "pos.sell"]
        case .pointOfSaleHistory: return ["pos.view", "pos.sell", "pos.history"]
        case .users: return ["users.view", "users.manage", "users.block", "users.features.view", "users.features.manage", "users.subscriptions.view", "users.subscriptions.manage", "users.restrictions.view", "users.restrictions.manage"]
        case .staff: return ["staff.view", "staff.manage"]
        case .account, .settings: return []
        case .chats: return ["support.view", "support.manage"]
        case .notifications: return ["notifications.view", "support.view", "support.manage", "moderation.view", "moderation.manage"]
        case .notificationComposer: return ["notifications.send", "support.manage", "moderation.manage", "users.block"]
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
        case .listings:
            return ["stock.manage"]
        default:
            return []
        }
    }

    func isAuthorized(for session: AdminSession) -> Bool {
        session.hasAnyPermission(requiredPermissions) &&
            requiredAllPermissions.allSatisfy(session.hasPermission)
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

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

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
        view.backgroundColor = .ppBackground

        let contextBar = makeContextBar()
        view.addSubview(contextBar)
        NSLayoutConstraint.activate([
            contextBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contextBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contextBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contextBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 42),
        ])

        let navigationController = UINavigationController(rootViewController: rootViewController)
        PPSetCommandCenterNavigationManaged(navigationController, true)
        navigationController.delegate = self
        AdminConnectedRouteChrome.apply(to: rootViewController, in: navigationController, route: route)
        addChild(navigationController)
        view.addSubview(navigationController.view)
        navigationController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navigationController.view.topAnchor.constraint(equalTo: contextBar.bottomAnchor),
            navigationController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        navigationController.didMove(toParent: self)
        view.bringSubviewToFront(contextBar)
    }

    private func makeContextBar() -> UIView {
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = .ppSurface
        bar.semanticContentAttribute = Language.isRTL() ? .forceRightToLeft : .forceLeftToRight

        let symbol = UIImageView(image: UIImage(systemName: route.symbol))
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.tintColor = .ppPrimary
        symbol.contentMode = .scaleAspectFit
        //symbol.accessibilityHidden = true

        let contextLabel = UILabel()
        contextLabel.translatesAutoresizingMaskIntoConstraints = false
        contextLabel.text = Language.get("CommandCenter_Title", alter: nil)
        contextLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: UIFont(name: "Beiruti-Medium", size: 11.0) ?? UIFont.systemFont(ofSize: 11.0)
        )
        contextLabel.textColor = .ppTextSecondary
        contextLabel.adjustsFontForContentSizeCategory = true
        contextLabel.textAlignment = .natural

        let routeLabel = UILabel()
        routeLabel.translatesAutoresizingMaskIntoConstraints = false
        routeLabel.text = Language.get(route.contextTitleKey, alter: nil)
        routeLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont(name: "Beiruti-Bold", size: 15.0) ?? UIFont.boldSystemFont(ofSize: 15.0)
        )
        routeLabel.textColor = .ppTextPrimary
        routeLabel.adjustsFontForContentSizeCategory = true
        routeLabel.numberOfLines = 2
        routeLabel.lineBreakMode = .byTruncatingTail
        routeLabel.textAlignment = .natural

        let copy = UIStackView(arrangedSubviews: [contextLabel, routeLabel])
        copy.translatesAutoresizingMaskIntoConstraints = false
        copy.axis = .vertical
        copy.alignment = .leading
        copy.spacing = 0

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .ppTextSecondary
        closeButton.accessibilityLabel = Language.get("Close", alter: nil)
        closeButton.accessibilityHint = Language.get("CommandCenter_Close_Workflow_Hint", alter: nil)
        closeButton.addTarget(dismissTarget, action: dismissAction, for: .touchUpInside)

        let content = UIStackView(arrangedSubviews: [symbol, copy])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = 10
        content.semanticContentAttribute = bar.semanticContentAttribute
        bar.addSubview(content)
        bar.addSubview(closeButton)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .ppSurfaceBorder
        bar.addSubview(divider)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: bar.layoutMarginsGuide.leadingAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: bar.topAnchor, constant: 5),
            content.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -5),
            symbol.widthAnchor.constraint(equalToConstant: 22),
            symbol.heightAnchor.constraint(equalToConstant: 22),
            closeButton.trailingAnchor.constraint(equalTo: bar.layoutMarginsGuide.trailingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
            divider.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])

        bar.isAccessibilityElement = false
        bar.accessibilityElements = [content, closeButton]
        content.isAccessibilityElement = true
        content.accessibilityTraits = .staticText
        content.accessibilityLabel = "\(Language.get("CommandCenter_Title", alter: nil)), \(Language.get(route.titleKey, alter: nil))"

        return bar
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController,
                              animated: Bool) {
        AdminConnectedRouteChrome.apply(to: viewController, in: navigationController, route: route)
    }
}

/// Presentation-only chrome for destinations reached from the Command Center.
///
/// The destination controllers remain the owners of data, actions, and nested
/// navigation. This adapter only gives the legacy UIKit stack the same surface,
/// navigation, typography, and direction treatment as the SwiftUI reference
/// shell. Keeping it at the route container boundary prevents unrelated Admin
/// entry points from inheriting the connected-workflow treatment.
private enum AdminConnectedRouteChrome {
    static func apply(to viewController: UIViewController,
                      in navigationController: UINavigationController,
                      route: AdminRoute) {
        let direction: UISemanticContentAttribute = Language.isRTL()
            ? .forceRightToLeft
            : .forceLeftToRight

        viewController.view.semanticContentAttribute = direction
        viewController.view.backgroundColor = .ppBackground
        if viewController.navigationItem.title?.isEmpty != false {
            viewController.navigationItem.title = Language.get(route.titleKey, alter: nil)
        }
        viewController.navigationItem.largeTitleDisplayMode = .never
        navigationController.view.semanticContentAttribute = direction
        navigationController.view.backgroundColor = .ppBackground
        configureNavigationBar(navigationController.navigationBar)
        applyPresentation(to: viewController.view, direction: direction)
    }

    private static func configureNavigationBar(_ navigationBar: UINavigationBar) {
        let titleBaseFont = UIFont(name: "Beiruti-Bold", size: 18.0)
            ?? UIFont.boldSystemFont(ofSize: 18.0)
        let titleFont = UIFontMetrics(forTextStyle: .headline).scaledFont(for: titleBaseFont)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .ppSurface
        appearance.shadowColor = .ppSurfaceBorder
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.ppTextPrimary,
            .font: titleFont,
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.ppTextPrimary,
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
                for: UIFont(name: "Beiruti-Bold", size: 32.0)
                    ?? UIFont.boldSystemFont(ofSize: 32.0)
            ),
        ]

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = .ppPrimary
        navigationBar.barStyle = .default
        navigationBar.isTranslucent = false
        navigationBar.prefersLargeTitles = false
    }

    private static func applyPresentation(to view: UIView,
                                          direction: UISemanticContentAttribute) {
        let preservesExplicitDirection = view.semanticContentAttribute == .forceLeftToRight ||
            view.semanticContentAttribute == .forceRightToLeft
        if !preservesExplicitDirection {
            view.semanticContentAttribute = direction
        }

        if let tableView = view as? UITableView {
            tableView.backgroundColor = .ppBackground
            tableView.separatorColor = .clear
            tableView.separatorStyle = .none
        } else if let collectionView = view as? UICollectionView {
            collectionView.backgroundColor = .ppBackground
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
            applyPresentation(to: child, direction: direction)
        }
    }
}
