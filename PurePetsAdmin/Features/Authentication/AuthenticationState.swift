import Combine
import Foundation
import UIKit

enum AdminAuthenticationAction: Equatable {
    case email
    case google
    case biometric
    case passwordReset
}

struct AdminAuthenticationAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func == (lhs: AdminAuthenticationAlert, rhs: AdminAuthenticationAlert) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class AdminAuthenticationService {
    private weak var presentingViewController: UIViewController?
    private var coordinator: PPProLoginCoordinator?

    func attach(presentingViewController: UIViewController) {
        guard self.presentingViewController !== presentingViewController else { return }
        self.presentingViewController = presentingViewController
        coordinator = PPProLoginCoordinator(presenting: presentingViewController)
    }

    var savedEmail: String { coordinator?.savedEmail() ?? "" }
    var rememberMeEnabled: Bool { coordinator?.isRememberMeEnabled() ?? false }
    var canUseBiometric: Bool { coordinator?.canUseBiometricLogin() ?? false }
    var biometricTitle: String { coordinator?.biometricDisplayTitle() ?? localized("LoginWithFaceID") }

    func signIn(email: String, password: String, remember: Bool, completion: @escaping (Bool, String?) -> Void) {
        guard let coordinator else {
            completion(false, localized("StatusLoginFailed"))
            return
        }
        coordinator.signIn(withEmail: email, password: password, remember: remember, completion: completion)
    }

    func signInWithGoogle(completion: @escaping (Bool, String?) -> Void) {
        guard let coordinator else {
            completion(false, localized("StatusLoginFailed"))
            return
        }
        coordinator.signInWithGoogle(completion: completion)
    }

    func signInWithBiometric(completion: @escaping (Bool, String?) -> Void) {
        guard let coordinator else {
            completion(false, localized("BiometricNotAvailable"))
            return
        }
        coordinator.signInWithBiometric(completion: completion)
    }

    func requestPasswordReset(email: String, completion: @escaping (Bool, String?) -> Void) {
        guard let coordinator else {
            completion(false, localized("StatusLoginFailed"))
            return
        }
        coordinator.requestPasswordReset(forEmail: email, completion: completion)
    }

    private func localized(_ key: String) -> String {
        Language.get(key, alter: nil)
    }
}

@MainActor
final class AuthenticationState: ObservableObject {
    @Published var email: String
    @Published var password = ""
    @Published var rememberMe: Bool
    @Published var revealPassword = false
    @Published private(set) var activeAction: AdminAuthenticationAction?
    @Published var alert: AdminAuthenticationAlert?
    @Published private(set) var languageCode: String
    @Published private(set) var canUseBiometric: Bool

    private let service: AdminAuthenticationService
    private let onAuthenticated: () -> Void

    init(service: AdminAuthenticationService, onAuthenticated: @escaping () -> Void) {
        self.service = service
        self.onAuthenticated = onAuthenticated
        email = service.savedEmail
        rememberMe = service.rememberMeEnabled
        languageCode = Language.currentLanguageCode()
        canUseBiometric = service.canUseBiometric
    }

    var isBusy: Bool { activeAction != nil }
    var isRTL: Bool { Language.isRTL() }
    var biometricTitle: String { service.biometricTitle }
    var languageToggleLabel: String {
        localized(languageCode == "ar" ? "Language_English_Code" : "Language_Arabic_Code")
    }

    func localized(_ key: String) -> String { Language.get(key, alter: nil) }

    func toggleLanguage() {
        guard !isBusy else { return }
        let next = languageCode == "ar" ? "en" : "ar"
        Language.userSelectedLanguage(next)
        languageCode = next
    }

    func refreshLanguage() {
        languageCode = Language.currentLanguageCode()
    }

    func submit() {
        guard begin(.email) else { return }
        service.signIn(email: email, password: password, remember: rememberMe) { [weak self] success, message in
            Task { @MainActor in self?.complete(success: success, message: message) }
        }
    }

    func signInWithGoogle() {
        guard begin(.google) else { return }
        service.signInWithGoogle { [weak self] success, message in
            Task { @MainActor in self?.complete(success: success, message: message) }
        }
    }

    func signInWithBiometric() {
        guard begin(.biometric) else { return }
        service.signInWithBiometric { [weak self] success, message in
            Task { @MainActor in self?.complete(success: success, message: message) }
        }
    }

    func resetPassword() {
        guard begin(.passwordReset) else { return }
        service.requestPasswordReset(email: email) { [weak self] success, message in
            Task { @MainActor in
                guard let self else { return }
                self.activeAction = nil
                if let message, !message.isEmpty {
                    self.alert = AdminAuthenticationAlert(
                        title: self.localized(success ? "Success_Title" : "Warning"),
                        message: message
                    )
                }
            }
        }
    }

    private func begin(_ action: AdminAuthenticationAction) -> Bool {
        guard activeAction == nil else { return false }
        activeAction = action
        return true
    }

    private func complete(success: Bool, message: String?) {
        activeAction = nil
        canUseBiometric = service.canUseBiometric
        if success {
            password = ""
            onAuthenticated()
        } else if let message, !message.isEmpty {
            alert = AdminAuthenticationAlert(title: localized("Error"), message: message)
        }
    }
}
