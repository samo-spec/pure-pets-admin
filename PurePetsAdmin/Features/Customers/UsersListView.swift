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

            VStack(spacing: 0) {
                dossierHeaderView

                AdminLegacyViewControllerWrapper { UsersListVC(viewFor: .editAccount) }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Dossier Header (PPAccessoryEditorView Pattern)

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

            Text(Language.get("CommandCenter_Customers_Workspace", alter: "مساحة العملاء") + " / " + Language.get("UsersSection", alter: "المستخدمين"))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(Language.get("UsersSection", alter: "إدارة المستخدمين"))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
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

            Text(Language.get("UsersSection", alter: "المستخدمين") + " / " + titleText)
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(titleText)
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
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
public class PPAdminUsersListHostingController: UIHostingController<AnyView> {
    @objc public init() {
        super.init(rootView: AnyView(EmptyView()))
        self.rootView = AnyView(AdminUsersListView(onDismiss: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }))
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc(PPAdminChatsHostingController)
public class PPAdminChatsHostingController: UIHostingController<AnyView> {
    @objc public init() {
        super.init(rootView: AnyView(EmptyView()))
        self.rootView = AnyView(AdminChatsView(onDismiss: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }))
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc(PPAdminUserManagementHostingController)
public class PPAdminUserManagementHostingController: UIHostingController<AnyView> {
    @objc public init(controller: UIViewController, titleText: String) {
        super.init(rootView: AnyView(EmptyView()))
        self.rootView = AnyView(AdminUserManagementView(controllerFactory: { controller }, titleText: titleText, onDismiss: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }))
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

@objc(PPAdminSupportThreadHostingController)
public class PPAdminSupportThreadHostingController: UIHostingController<AnyView> {
    @objc public init(controller: UIViewController) {
        super.init(rootView: AnyView(EmptyView()))
        self.rootView = AnyView(AdminSupportThreadView(controllerFactory: { controller }, onDismiss: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }))
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}
