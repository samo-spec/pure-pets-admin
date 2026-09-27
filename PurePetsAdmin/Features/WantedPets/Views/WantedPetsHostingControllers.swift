//
//  WantedPetsHostingControllers.swift
//  Pure Pets Admin
//
//  Created for Pure Pets Platform.
//  UIKit hosting controller bridges for Wanted Pets screens.
//

import UIKit
import SwiftUI

@objc public final class WantedPetsHostingController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let host = UIHostingController(rootView: WantedPetsHomeView(onDismiss: { [weak self] in
            guard let self = self else { return }
            if let nav = self.navigationController, nav.viewControllers.first != self {
                nav.popViewController(animated: true)
            } else {
                self.dismiss(animated: true)
            }
        }))
        host.view.backgroundColor = .clear
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

@objc public final class WaitingCustomersHostingController: UIViewController {
    private let petTitle: String
    private let mainKindId: Int
    private let subkindId: Int

    @objc public init(petTitle: String, mainKindId: Int, subkindId: Int) {
        self.petTitle = petTitle
        self.mainKindId = mainKindId
        self.subkindId = subkindId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let subId: Int? = subkindId > 0 ? subkindId : nil
        let host = UIHostingController(
            rootView: WaitingCustomersView(
                petTitle: petTitle,
                mainKindId: mainKindId,
                subkindId: subId
            )
        )
        host.view.backgroundColor = .clear
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
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
}

// MARK: - Wanted Pet Detail Hosting Controller (Full Screen & Push)

@objc public final class WantedPetDetailHostingController: UIViewController {
    private let wantedPetId: String
    private let isFullScreenPresentation: Bool

    @objc public init(wantedPetId: String, isFullScreen: Bool = true) {
        self.wantedPetId = wantedPetId
        self.isFullScreenPresentation = isFullScreen
        super.init(nibName: nil, bundle: nil)
        if isFullScreen {
            self.modalPresentationStyle = .fullScreen
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc public static func present(from presenter: UIViewController, wantedPetId: String) {
        let vc = WantedPetDetailHostingController(wantedPetId: wantedPetId, isFullScreen: true)
        presenter.present(vc, animated: true)
    }

    @objc public static func push(on navigationController: UINavigationController, wantedPetId: String) {
        let vc = WantedPetDetailHostingController(wantedPetId: wantedPetId, isFullScreen: false)
        navigationController.pushViewController(vc, animated: true)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let host = UIHostingController(
            rootView: WantedPetDetailView(
                wantedPetId: wantedPetId,
                onDismiss: { [weak self] in
                    guard let self = self else { return }
                    if let nav = self.navigationController, nav.viewControllers.first != self {
                        nav.popViewController(animated: true)
                    } else {
                        self.dismiss(animated: true)
                    }
                }
            )
        )
        host.view.backgroundColor = .clear
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
