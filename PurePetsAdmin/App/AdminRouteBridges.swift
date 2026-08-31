//
//  AdminRouteBridges.swift
//  PurePetsAdmin
//

import SwiftUI

@objc public final class AdminPaymentListHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .ppBackground
        let session = AdminSession(source: PPAdminSessionSnapshot())
        let host = UIHostingController(rootView: AdminPaymentListView(session: session) { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        })
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
    }
    public override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: animated) }
}

@objc public final class AdminPaymentSettingsHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .ppBackground
        let session = AdminSession(source: PPAdminSessionSnapshot())
        let host = UIHostingController(rootView: AdminPaymentSettingsView(session: session) { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        })
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
    }
    public override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: animated) }
}

@objc public final class AdminPaymentDetailHostingController: UIViewController {
    private let orderID: String
    @objc public init(orderID: String) { self.orderID = orderID; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    public override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .ppBackground
        let session = AdminSession(source: PPAdminSessionSnapshot())
        let host = UIHostingController(rootView: AdminPaymentDetailView(orderID: orderID, session: session) { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        })
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
    }
}

@objc public final class AdminFulfillmentListHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .ppBackground
        let session = AdminSession(source: PPAdminSessionSnapshot())
        let host = UIHostingController(rootView: AdminFulfillmentListView(session: session) { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        })
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
    }
    public override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: animated) }
}

@objc public final class AdminDeliveryListHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .ppBackground
        let host = UIHostingController(rootView: AdminDeliveryListView { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        })
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
    }
    public override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: animated) }
}

@objc public final class AdminPOSFastSellHostingController: UIViewController {
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        hidesBottomBarWhenPushed = true
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all

        let session = AdminSession(source: PPAdminSessionSnapshot())
        let host = UIHostingController(rootView: AdminPOSFastSellView(session: session) { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        })
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc public final class AdminPOSHistoryHostingController: UIViewController {
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        hidesBottomBarWhenPushed = true
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all

        let session = AdminSession(source: PPAdminSessionSnapshot())
        let host = UIHostingController(rootView: AdminPOSHistoryView(session: session) { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        })
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc public final class AdminBranchesHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let host = UIHostingController(rootView: AdminBranchesView { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        })
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc public final class AdminHomeControlHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let host = UIHostingController(rootView: AdminHomeControlView { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        })
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc public final class AdminStaffManagementHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let host = UIHostingController(rootView: AdminStaffManagementView { [weak self] in
            if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        })
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}
