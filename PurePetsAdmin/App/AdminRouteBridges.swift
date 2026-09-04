//
//  AdminRouteBridges.swift
//  PurePetsAdmin
//

import SwiftUI

@objc public class AdminPaymentListHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .ppBackground
        let session = AdminSession(source: PPAdminSessionSnapshot())
        let host = UIHostingController(rootView: AdminPaymentListView(session: session) { [weak self] in
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
        })
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
    }
    public override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: animated) }
}

@objc public final class AdminFulfillmentOverrideHostingController: UIViewController {
    private let record: PPFulfillmentRecord
    @objc public init(record: PPFulfillmentRecord) {
        self.record = record
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let snap = FulfillmentRecordSnapshot(record: record)
        let host = UIHostingController(rootView: FulfillmentOverrideView(
            record: snap,
            isPushMode: true,
            onDismiss: { [weak self] in
                guard let self = self else {
                    PPAdminNavigationFallback.popOrDismiss()
                    return
                }
                PPAdminNavigationFallback.popOrDismiss(from: self)
            },
            onCommit: { expectedStatus, target, reason, note, notify, completion in
                PPFulfillmentService.shared().adminOverride(
                    snap.id,
                    expectedStatus: expectedStatus,
                    targetStatus: target,
                    reason: reason,
                    note: note,
                    notify: notify,
                    commandID: "override_\(UUID().uuidString.prefix(8))"
                ) { _, error in
                    Task { @MainActor in
                        if let error = error {
                            completion(FulfillmentOverrideCommitResult.from(error: error))
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            completion(.succeeded)
                        }
                    }
                }
            }
        ))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    private var priorNavigationBarHidden: Bool?

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        priorNavigationBarHidden = navigationController?.isNavigationBarHidden
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let prior = priorNavigationBarHidden {
            navigationController?.setNavigationBarHidden(prior, animated: animated)
        }
    }
}

@objc public final class AdminDeliveryListHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .ppBackground
        let host = UIHostingController(rootView: AdminDeliveryListView { [weak self] in
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
        })
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
    }
    public override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: animated) }
}

@objc public final class AdminPOSFastSellHostingController: UIViewController {
    private let sessionActivityIndicator = UIActivityIndicatorView(style: .large)
    private var sessionRestoreGeneration = UUID()
    private var hasInstalledPOSHost = false

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
        showSessionRestoreLoadingState()
        restoreCanonicalSession()
    }

    private func showSessionRestoreLoadingState() {
        sessionActivityIndicator.translatesAutoresizingMaskIntoConstraints = false
        sessionActivityIndicator.color = .ppPrimary
        sessionActivityIndicator.startAnimating()
        view.addSubview(sessionActivityIndicator)
        NSLayoutConstraint.activate([
            sessionActivityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sessionActivityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func restoreCanonicalSession() {
        let generation = UUID()
        sessionRestoreGeneration = generation

        PPAdminSessionBridge.restoreCurrentSession { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self, self.sessionRestoreGeneration == generation, !self.hasInstalledPOSHost else { return }
                guard let snapshot, !snapshot.uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.presentSessionRestoreFailure(error)
                    return
                }
                self.installPOSHost(session: AdminSession(source: snapshot))
            }
        }
    }

    private func installPOSHost(session: AdminSession) {
        guard !hasInstalledPOSHost else { return }
        hasInstalledPOSHost = true
        sessionActivityIndicator.stopAnimating()
        sessionActivityIndicator.removeFromSuperview()

        let host = UIHostingController(rootView: AdminPOSFastSellView(session: session) { [weak self] in
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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

    private func presentSessionRestoreFailure(_ error: Error?) {
        sessionActivityIndicator.stopAnimating()
        let message = error?.localizedDescription ?? Language.get("StatusUserDocError", alter: nil)
        let alert = UIAlertController(
            title: Language.get("Error", alter: nil),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Language.get("OK", alter: nil), style: .default) { [weak self] _ in
            guard let self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
        })
        present(alert, animated: true)
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
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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

@objc public final class AdminAccountingHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let session = AdminSession(source: PPAdminSessionSnapshot())
        let host = UIHostingController(rootView: AdminAccountingView(session: session) { [weak self] in
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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

@objc public final class AdminCategoriesHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let host = UIHostingController(rootView: AdminCategoriesView { [weak self] in
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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

@objc public final class AdminPetsHotelHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let host = UIHostingController(rootView: AdminPetsHotelHubView { [weak self] in
            guard let self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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

@objc public final class AdminRoleRankSecurityLevelsHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let host = UIHostingController(rootView: AdminRoleRankSecurityLevelsView { [weak self] in
            guard let self = self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
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

@objc @MainActor public final class AdminRoleRankHostingBridge: NSObject {
    @objc(makeViewController)
    public static func makeViewController() -> UIViewController {
        return makeViewController(onDismiss: nil)
    }

    @objc(makeViewControllerWithOnDismiss:)
    public static func makeViewController(onDismiss: (() -> Void)? = nil) -> UIViewController {
        let view = AdminRoleRankSecurityLevelsView(onDismiss: onDismiss)
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        return host
    }
}
