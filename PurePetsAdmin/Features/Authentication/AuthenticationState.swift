import Combine
import Foundation
import UIKit

enum AdminAuthMode: String, CaseIterable, Identifiable {
    case phone
    case email

    var id: String { rawValue }
}

enum AdminAuthenticationAction: Equatable {
    case email
    case phoneSendCode
    case phoneVerify
    case google
    case apple
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

    func signInWithApple(completion: @escaping (Bool, String?) -> Void) {
        guard let coordinator else {
            completion(false, localized("StatusLoginFailed"))
            return
        }
        coordinator.signInWithApple(completion: completion)
    }

    func sendVerificationCode(to phone: String, completion: @escaping (String?, String?) -> Void) {
        guard let coordinator else {
            completion(nil, localized("StatusLoginFailed"))
            return
        }
        coordinator.sendVerificationCode(toPhone: phone, completion: completion)
    }

    func signInWithPhone(verificationID: String, code: String, completion: @escaping (Bool, String?) -> Void) {
        guard let coordinator else {
            completion(false, localized("StatusLoginFailed"))
            return
        }
        coordinator.signIn(withPhoneVerificationID: verificationID, code: code, completion: completion)
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
    @Published var authMode: AdminAuthMode = .phone
    @Published var email: String
    @Published var password = ""
    @Published var phoneNumber: String = ""
    @Published var phoneCountryCode: String = "+974"
    @Published var verificationCode: String = ""
    @Published var verificationID: String? = nil
    @Published var isCodeSent: Bool = false
    @Published var resendCountdown: Int = 0
    @Published var rememberMe: Bool
    @Published var revealPassword = false
    @Published private(set) var activeAction: AdminAuthenticationAction?
    @Published var alert: AdminAuthenticationAlert?
    @Published private(set) var languageCode: String
    @Published private(set) var canUseBiometric: Bool

    private var countdownTimer: AnyCancellable?
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

    var formattedFullPhone: String {
        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPhone.hasPrefix("+") {
            return trimmedPhone
        }
        let code = phoneCountryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(code)\(trimmedPhone)"
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

    func sendPhoneCode() {
        let fullPhone = formattedFullPhone
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alert = AdminAuthenticationAlert(title: localized("Warning"), message: localized("auth_phone_required_message"))
            return
        }
        guard begin(.phoneSendCode) else { return }
        service.sendVerificationCode(to: fullPhone) { [weak self] vID, message in
            Task { @MainActor in
                guard let self else { return }
                self.activeAction = nil
                if let vID, !vID.isEmpty {
                    self.verificationID = vID
                    self.isCodeSent = true
                    self.verificationCode = ""
                    self.startResendTimer()
                } else if let message, !message.isEmpty {
                    self.alert = AdminAuthenticationAlert(title: self.localized("Error"), message: message)
                }
            }
        }
    }

    func verifyPhoneCode() {
        guard let vID = verificationID, !vID.isEmpty else {
            alert = AdminAuthenticationAlert(title: localized("Error"), message: localized("auth_verification_start_failed"))
            return
        }
        guard !verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alert = AdminAuthenticationAlert(title: localized("Warning"), message: localized("auth_otp_error_empty"))
            return
        }
        guard begin(.phoneVerify) else { return }
        service.signInWithPhone(verificationID: vID, code: verificationCode) { [weak self] success, message in
            Task { @MainActor in self?.complete(success: success, message: message) }
        }
    }

    func resetPhoneFlow() {
        isCodeSent = false
        verificationCode = ""
        verificationID = nil
        countdownTimer?.cancel()
        countdownTimer = nil
        resendCountdown = 0
    }

    private func startResendTimer() {
        resendCountdown = 60
        countdownTimer?.cancel()
        countdownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.resendCountdown > 0 {
                    self.resendCountdown -= 1
                } else {
                    self.countdownTimer?.cancel()
                    self.countdownTimer = nil
                }
            }
    }

    func signInWithGoogle() {
        guard begin(.google) else { return }
        service.signInWithGoogle { [weak self] success, message in
            Task { @MainActor in self?.complete(success: success, message: message) }
        }
    }

    func signInWithApple() {
        guard begin(.apple) else { return }
        service.signInWithApple { [weak self] success, message in
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
            verificationCode = ""
            countdownTimer?.cancel()
            countdownTimer = nil
            onAuthenticated()
        } else if let message, !message.isEmpty {
            alert = AdminAuthenticationAlert(title: localized("Error"), message: message)
        }
    }
}
