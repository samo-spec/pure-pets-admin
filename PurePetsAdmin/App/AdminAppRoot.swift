import FirebaseAuth
import SwiftUI
import UIKit

struct AdminSession: Equatable {
    let source: PPAdminSessionSnapshot
    let uid: String
    let displayName: String
    let email: String
    let roleIdentifier: String
    let permissions: Set<String>
    let scope: [String: Any]
    let grantsAllPermissions: Bool

    init(source: PPAdminSessionSnapshot) {
        self.source = source
        uid = source.uid
        displayName = source.displayName
        email = source.email
        roleIdentifier = source.roleIdentifier
        permissions = Set(source.permissions)
        scope = source.scope
        grantsAllPermissions = source.grantsAllPermissions
    }

    func hasPermission(_ permission: String) -> Bool {
        grantsAllPermissions || permissions.contains(permission)
    }

    func hasAnyPermission(_ required: [String]) -> Bool {
        required.isEmpty || grantsAllPermissions || required.contains(where: permissions.contains)
    }

    var hasGlobalScope: Bool {
        grantsAllPermissions || (scope["global"] as? Bool == true)
    }

    var localizedRoleName: String {
        PPAdminSessionBridge.localizedRoleName(for: roleIdentifier)
    }

    static func == (lhs: AdminSession, rhs: AdminSession) -> Bool {
        lhs.uid == rhs.uid &&
            lhs.roleIdentifier == rhs.roleIdentifier &&
            lhs.permissions == rhs.permissions &&
            (lhs.scope as NSDictionary).isEqual(rhs.scope as NSDictionary) &&
            lhs.grantsAllPermissions == rhs.grantsAllPermissions
    }
}

enum AdminSessionState: Equatable {
    case restoring
    case unauthenticated
    case authenticated(AdminSession)
}

@MainActor
final class AdminSessionStore: ObservableObject {
    @Published private(set) var state: AdminSessionState = .restoring
    @Published private(set) var restoreError: String?
    @Published private(set) var accessMessage: String?
    @Published private(set) var languageCode = Language.currentLanguageCode()
    @Published private(set) var isSigningOut = false

    private nonisolated(unsafe) var authHandle: AuthStateDidChangeListenerHandle?
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    private nonisolated(unsafe) var staffObservation: PPAdminSessionObservation?
    private var restoreGeneration = UUID()
    private var restoreInFlight = false

    init() {
        startObserving()
    }

    deinit {
        if let authHandle { Auth.auth().removeStateDidChangeListener(authHandle) }
        staffObservation?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func restoreCurrentSession() {
        guard Auth.auth().currentUser != nil else {
            restoreInFlight = false
            restoreError = nil
            state = .unauthenticated
            return
        }
        guard !PPAdminLoginInProgress() else { return }
        guard !restoreInFlight else { return }

        let generation = UUID()
        restoreGeneration = generation
        restoreInFlight = true
        restoreError = nil
        accessMessage = nil
        state = .restoring

        PPAdminSessionBridge.restoreCurrentSession { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.restoreGeneration == generation else { return }
                self.restoreInFlight = false
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == PPAdminSessionBridgeErrorDomain,
                       nsError.code == PPAdminSessionBridgeErrorCode.unauthorized.rawValue ||
                       nsError.code == PPAdminSessionBridgeErrorCode.disabled.rawValue {
                        self.accessMessage = error.localizedDescription
                        self.signOutAndMarkUnauthenticated()
                    } else {
                        self.restoreError = self.localizedRestoreError(error)
                    }
                    return
                }
                guard let snapshot else {
                    NSLog("🛡️  [PPADMIN COMMAND CENTER] Root State: Unauthenticated (Presenting Login Screen)")
                    self.state = .unauthenticated
                    return
                }
                let session = AdminSession(source: snapshot)
                NSLog("🛡️  [PPADMIN COMMAND CENTER] Root State: Authenticated -> User: %@ | Role: %@ | Perms: %ld",
                      session.displayName, session.roleIdentifier, session.permissions.count)
                self.state = .authenticated(session)
                self.startStaffObservation(for: session.uid)
                PPStaffAuth.shared().fetchStaffDoc(session.uid) { staffDoc, _ in
                    PPBranchContextManager.shared().configure(withStaff: staffDoc) {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: Notification.Name("PPAdminCommandAuthorizationDidChangeNotification"),
                                object: nil
                            )
                            NotificationCenter.default.post(
                                name: Notification.Name.PPActiveBranchDidChange,
                                object: nil
                            )
                        }
                    }
                }
            }
        }
    }

    func refreshAuthorizedSession() {
        guard case .authenticated = state, Auth.auth().currentUser != nil else {
            restoreCurrentSession()
            return
        }
        restoreCurrentSessionPreservingShell()
    }

    func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        restoreInFlight = false
        restoreGeneration = UUID()
        restoreError = nil
        staffObservation?.invalidate()
        staffObservation = nil
        Task { @MainActor [weak self] in
            let signOutError: Error?
            do {
                try await PPAdminSessionBridge.signOut()
                signOutError = nil
            } catch {
                signOutError = error
            }
            guard let self else { return }
            self.isSigningOut = false
            if signOutError != nil {
                if case let .authenticated(session) = self.state {
                    self.startStaffObservation(for: session.uid)
                }
            } else {
                self.state = .unauthenticated
                BranchContextStore.shared.clear()
            }
        }
    }

    func clearAccessMessage() { accessMessage = nil }

    private func localizedRestoreError(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("app check") || message.contains("appcheck") || message.contains("attest") {
            return Language.get("StatusAppCheckInvalid", alter: nil)
        }
        if message.contains("network") || message.contains("offline") || message.contains("unavailable") {
            return Language.get("StatusNetworkError", alter: nil)
        }
        return Language.get("StatusFetchClaims", alter: nil)
    }

    private func restoreCurrentSessionPreservingShell() {
        guard !PPAdminLoginInProgress(), !restoreInFlight else { return }
        guard let authUserUID = Auth.auth().currentUser?.uid, !authUserUID.isEmpty else {
            state = .unauthenticated
            return
        }

        let generation = UUID()
        restoreGeneration = generation
        restoreInFlight = true
        PPAdminSessionBridge.restoreCurrentSession { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.restoreGeneration == generation else { return }
                self.restoreInFlight = false
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == PPAdminSessionBridgeErrorDomain,
                       nsError.code == PPAdminSessionBridgeErrorCode.unauthorized.rawValue ||
                       nsError.code == PPAdminSessionBridgeErrorCode.disabled.rawValue {
                        self.accessMessage = error.localizedDescription
                        self.signOutAndMarkUnauthenticated()
                    } else {
                        self.restoreError = self.localizedRestoreError(error)
                    }
                    return
                }
                guard let snapshot, snapshot.uid == authUserUID else {
                    self.restoreError = Language.get("StatusUserDocError", alter: nil)
                    return
                }
                self.restoreError = nil
                self.state = .authenticated(AdminSession(source: snapshot))
            }
        }
    }

    private func startStaffObservation(for uid: String) {
        staffObservation?.invalidate()
        staffObservation = PPAdminSessionBridge.observeCurrentSession { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                guard case let .authenticated(currentSession) = self.state,
                      currentSession.uid == uid else { return }
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == PPAdminSessionBridgeErrorDomain,
                       nsError.code == PPAdminSessionBridgeErrorCode.unauthorized.rawValue ||
                       nsError.code == PPAdminSessionBridgeErrorCode.disabled.rawValue {
                        self.accessMessage = error.localizedDescription
                        self.staffObservation?.invalidate()
                        self.staffObservation = nil
                        self.state = .restoring
                        self.signOutAndMarkUnauthenticated()
                    } else {
                        self.restoreError = self.localizedRestoreError(error)
                        self.staffObservation?.invalidate()
                        self.staffObservation = nil
                        self.state = .restoring
                    }
                    return
                }
                if let snapshot {
                    self.restoreError = nil
                    self.state = .authenticated(AdminSession(source: snapshot))
                }
            }
        }
    }

    private func signOutAndMarkUnauthenticated() {
        Task { @MainActor [weak self] in
            _ = try? await PPAdminSessionBridge.signOut()
            guard let self else { return }
            self.state = .unauthenticated
        }
    }

    private func startObserving() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if user == nil {
                    self.restoreGeneration = UUID()
                    self.restoreInFlight = false
                    self.staffObservation?.invalidate()
                    self.staffObservation = nil
                    self.restoreError = nil
                    self.state = .unauthenticated
                } else if !PPAdminLoginInProgress() {
                    if case let .authenticated(session) = self.state, session.uid == user?.uid { return }
                    self.restoreCurrentSession()
                }
            }
        }

        let authObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("UserManagerAuthStateDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restoreCurrentSession() }
        }
        let languageObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("LanguageDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.languageCode = Language.currentLanguageCode() }
        }
        observers = [authObserver, languageObserver]
    }
}

@MainActor
struct AdminAppRoot: View {
    @ObservedObject var sessionStore: AdminSessionStore
    @ObservedObject var authenticationState: AuthenticationState
    @ObservedObject var router: AdminRouter
    @ObservedObject private var branchStore = BranchContextStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch sessionStore.state {
            case .restoring:
                restoringView
            case .unauthenticated:
                AdminLoginView(state: authenticationState)
            case let .authenticated(session):
                AdminAppShell(session: session, sessionStore: sessionStore, router: router)
                    .fullScreenCover(isPresented: Binding(
                        get: { branchStore.needsBranchSelection },
                        set: { _ in }
                    )) {
                        PPBranchSelectionGateView()
                    }
            }
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: sessionStore.languageCode == "ar" ? "ar_QA" : "en_QA"))
        .onChange(of: sessionStore.languageCode) { _ in
            authenticationState.refreshLanguage()
        }
        .onChange(of: sessionStore.state) { state in
            if case .unauthenticated = state {
                router.resetProtectedRoutes()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                sessionStore.refreshAuthorizedSession()
            }
        }
        .alert(
            Language.get("CommandCenter_Access_Denied_Title", alter: nil),
            isPresented: Binding(
                get: { sessionStore.accessMessage != nil },
                set: { if !$0 { sessionStore.clearAccessMessage() } }
            )
        ) {
            Button(Language.get("OK", alter: nil), role: .cancel) { sessionStore.clearAccessMessage() }
        } message: {
            Text(sessionStore.accessMessage ?? "")
        }
    }

    private var restoringView: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .accessibilityHidden(true)
                ProgressView()
                    .tint(AdminSurface.primary)
                Text(Language.get("CommandCenter_Restoring_Title", alter: nil))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                if let restoreError = sessionStore.restoreError {
                    Text(restoreError)
                        .font(AdminType.callout)
                        .foregroundColor(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                    Button(Language.get("Retry", alter: nil), action: sessionStore.restoreCurrentSession)
                        .buttonStyle(.borderedProminent)
                        .tint(AdminSurface.primary)
                }
            }
            .padding(28)
            .frame(maxWidth: 420)
        }
    }
}

@MainActor
@objcMembers
final class AdminAppRootHostingController: UIViewController {
    private let sessionStore = AdminSessionStore()
    private let authenticationService = AdminAuthenticationService()
    private let router = AdminRouter()
    private var hostingController: UIHostingController<AdminAppRoot>?
    private var authenticationState: AuthenticationState?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        authenticationService.attach(presentingViewController: self)

        let authenticationState = AuthenticationState(
            service: authenticationService,
            onAuthenticated: { [weak sessionStore] in sessionStore?.restoreCurrentSession() }
        )
        self.authenticationState = authenticationState

        let host = UIHostingController(rootView: AdminAppRoot(
            sessionStore: sessionStore,
            authenticationState: authenticationState,
            router: router
        ))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        hostingController = host
        sessionStore.restoreCurrentSession()
    }

    func routeToPaymentOrderID(_ orderID: String) {
        router.enqueuePaymentOrder(orderID)
        if case let .authenticated(session) = sessionStore.state {
            router.consumePendingRoute(session: session)
        }
    }

    func refreshForLanguageChange() {
        authenticationState?.refreshLanguage()
        sessionStore.objectWillChange.send()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }
}
