//
//  UsersListView.swift
//  PurePetsAdmin
//

import SwiftUI
 
import UIKit
struct AdminUsersListView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            AdminLegacyViewControllerWrapper { UsersListVC(viewFor: .editAccount) }
                .ignoresSafeArea()
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

private struct AdminLegacyViewControllerWrapper: UIViewControllerRepresentable {
    let factory: () -> UIViewController
    func makeUIViewController(context: Context) -> UIViewController { factory() }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct AdminUserManagementView: View {
    let controllerFactory: () -> UIViewController
    var titleText: String
    var onDismiss: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            AdminLegacyViewControllerWrapper { controllerFactory() }
                .ignoresSafeArea()
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}


import SwiftUI
import UIKit

struct AdminSupportThreadView: View {
    let controllerFactory: () -> UIViewController
    var onDismiss: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView

                AdminLegacyViewControllerWrapper { controllerFactory() }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack {
                Button(action: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(Language.get("Back", alter: "رجوع"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .frame(minHeight: 44)
                }

                Spacer()
            }

            Text(Language.get("Chats", alter: "المحادثات") + " / " + Language.get("Support", alter: "الدعم"))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(Language.get("Support_Thread", alter: "محادثة الدعم"))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
    }
}


import SwiftUI
import UIKit

@objc(PPAdminUsersListHostingController)
public final class PPAdminUsersListHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let host = UIHostingController(
            rootView: AdminUsersListView(onDismiss: { [weak self] in
                guard let self else { return }
                if let navigationController = self.navigationController,
                   navigationController.viewControllers.count > 1 {
                    navigationController.popViewController(animated: true)
                } else {
                    self.dismiss(animated: true)
                }
            })
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc(PPAdminChatsHostingController)
public final class PPAdminChatsHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let host = UIHostingController(
            rootView: AdminChatsView(onDismiss: { [weak self] in
                guard let self else { return }
                if let navigationController = self.navigationController,
                   navigationController.viewControllers.count > 1 {
                    navigationController.popViewController(animated: true)
                } else {
                    self.dismiss(animated: true)
                }
            })
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc(PPAdminUserManagementHostingController)
public final class PPAdminUserManagementHostingController: UIViewController {
    private let contentController: UIViewController
    private let titleText: String

    @objc(initWithController:titleText:)
    public init(controller: UIViewController, titleText: String) {
        contentController = controller
        self.titleText = titleText
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PPAdminUserManagementHostingController must be created programmatically.")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let controller = contentController
        let host = UIHostingController(
            rootView: AdminUserManagementView(
                controllerFactory: { controller },
                titleText: titleText,
                onDismiss: { [weak self] in
                    guard let self else { return }
                    if let navigationController = self.navigationController,
                       navigationController.viewControllers.count > 1 {
                        navigationController.popViewController(animated: true)
                    } else {
                        self.dismiss(animated: true)
                    }
                }
            )
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc(PPAdminSupportThreadHostingController)
public final class PPAdminSupportThreadHostingController: UIViewController {
    private let contentController: UIViewController

    @objc(initWithController:)
    public init(controller: UIViewController) {
        contentController = controller
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PPAdminSupportThreadHostingController must be created programmatically.")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let controller = contentController
        let host = UIHostingController(
            rootView: AdminSupportThreadView(
                controllerFactory: { controller },
                onDismiss: { [weak self] in
                    guard let self else { return }
                    if let navigationController = self.navigationController,
                       navigationController.viewControllers.count > 1 {
                        navigationController.popViewController(animated: true)
                    } else {
                        self.dismiss(animated: true)
                    }
                }
            )
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}
