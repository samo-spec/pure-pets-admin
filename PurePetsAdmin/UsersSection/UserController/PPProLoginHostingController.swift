import SwiftUI
import UIKit

private extension Color {
    static func pp(_ name: String) -> Color {
        switch name {
        case "AppPrimaryClr":
            return Color(uiColor: .ppPrimary)
        case "AppPrimaryClrDarker":
            return Color(uiColor: .ppPressedAction)
        case "AppPrimaryClrShiner":
            return Color(uiColor: .ppPrimaryShiner)
        case "AppBackgroundClr":
            return Color(uiColor: .ppBackground)
        case "AppBackgroundClrShiner", "AppForgroundColr":
            return Color(uiColor: .ppElevatedSurface)
        case "PrimaryTextClr":
            return Color(uiColor: .ppTextPrimary)
        case "SeconderyTextClr":
            return Color(uiColor: .ppTextSecondary)
        default:
            return Color(uiColor: .ppTextSecondary)
        }
    }
}

private struct PPProAlertPayload: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum PPProLoginField: Hashable {
    case email
    case password
}

private enum PPProLoginAction: Hashable {
    case email
    case google
    case biometric
}

@MainActor
private final class PPProLoginViewModel: ObservableObject {
    @Published var email: String
    @Published var password = ""
    @Published var rememberMe: Bool
    @Published var activeAction: PPProLoginAction?
    @Published var revealPassword = false
    @Published var alertPayload: PPProAlertPayload?
    @Published var canUseBiometric: Bool
    @Published var currentLanguageCode: String

    let coordinator: PPProLoginCoordinator

    init(coordinator: PPProLoginCoordinator) {
        self.coordinator = coordinator
        self.email = coordinator.savedEmail()
        self.rememberMe = coordinator.isRememberMeEnabled()
        self.canUseBiometric = coordinator.canUseBiometricLogin()
        self.currentLanguageCode = Language.currentLanguageCode()
    }

    var isRTL: Bool {
        Language.languageVal() == 1
    }

    var layoutDirection: LayoutDirection {
        isRTL ? .rightToLeft : .leftToRight
    }

    var biometricTitle: String {
        coordinator.biometricDisplayTitle()
    }

    var isBusy: Bool {
        activeAction != nil
    }

    func localized(_ key: String) -> String {
        Language.get(key, alter: nil)
    }

    func isPerforming(_ action: PPProLoginAction) -> Bool {
        activeAction == action
    }

    func toggleLanguage() {
        let next = currentLanguageCode == "en" ? "ar" : "en"
        currentLanguageCode = next
        Language.userSelectedLanguage(next)
    }

    func submit() {
        guard !isBusy else { return }
        activeAction = .email
        coordinator.signIn(withEmail: email, password: password, remember: rememberMe) { [weak self] success, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.activeAction = nil
                if !success, let message, !message.isEmpty {
                    self.alertPayload = PPProAlertPayload(title: self.localized("Error"), message: message)
                }
            }
        }
    }

    func signInWithGoogle() {
        guard !isBusy else { return }
        activeAction = .google
        coordinator.signInWithGoogle { [weak self] success, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.activeAction = nil
                if !success, let message, !message.isEmpty {
                    self.alertPayload = PPProAlertPayload(title: self.localized("Error"), message: message)
                }
            }
        }
    }

    func requestPasswordReset() {
        guard !isBusy else { return }
        coordinator.requestPasswordReset(forEmail: email) { [weak self] success, message in
            DispatchQueue.main.async {
                guard let self, let message else { return }
                let title = success ? self.localized("Success_Title") : self.localized("Warning")
                self.alertPayload = PPProAlertPayload(title: title, message: message)
            }
        }
    }

    func useBiometricLogin() {
        guard !isBusy else { return }
        activeAction = .biometric
        coordinator.signInWithBiometric { [weak self] success, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.activeAction = nil
                if !success, let message, !message.isEmpty {
                    self.alertPayload = PPProAlertPayload(title: self.localized("Error"), message: message)
                }
            }
        }
    }
}

private struct PPProLoginScreen: View {
    @ObservedObject var viewModel: PPProLoginViewModel
    @FocusState private var focusedField: PPProLoginField?
    @State private var drift = false

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    headerBar
                    heroSection
                    loginCard
                    footerLabel
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .environment(\.layoutDirection, viewModel.layoutDirection)
        .background(Color.pp("AppBackgroundClr"))
        .onAppear {
            focusedField = nil
            withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
        }
        .alert(item: $viewModel.alertPayload) { payload in
            Alert(
                title: Text(payload.title),
                message: Text(payload.message),
                dismissButton: .default(Text(viewModel.localized("OK")))
            )
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.pp("AppBackgroundClr"),
                    Color.pp("AppBackgroundClrShiner").opacity(0.95),
                    Color.pp("AppBackgroundClr")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.pp("AppPrimaryClr").opacity(0.16))
                .frame(width: 240, height: 240)
                .blur(radius: 18)
                .offset(x: drift ? 116 : 72, y: -190)

            Circle()
                .fill(Color.pp("AppPrimaryClrShiner").opacity(0.18))
                .frame(width: 180, height: 180)
                .blur(radius: 20)
                .offset(x: drift ? -114 : -72, y: 210)

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(y: -40)
        }
    }

    private var headerBar: some View {
        HStack {
            Text(viewModel.localized("ProLoginWelcomeBadge"))
                .font(.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(Color.pp("AppPrimaryClrDarker"))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.58))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.65), lineWidth: 1)
                        )
                )

            Spacer()

            Button(action: viewModel.toggleLanguage) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.custom("Beiruti-Bold", size: 15))
                    Text(viewModel.currentLanguageCode == "en" ? "AR" : "EN")
                        .font(.custom("Beiruti-Bold", size: 15))
                }
                .foregroundStyle(Color.pp("PrimaryTextClr"))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.48))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.62), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PPProScaleButtonStyle())
        }
        .padding(.top, 6)
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.pp("AppForgroundColr"),
                                Color.pp("AppBackgroundClrShiner")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: 18)

                Circle()
                    .stroke(Color.white.opacity(0.88), lineWidth: 1.4)
                    .frame(width: 88, height: 88)

                brandImage
                    .frame(width: 56, height: 56)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text(viewModel.localized("ProLoginTitle"))
                    .font(.custom("Beiruti-Bold", size: 36))
                    .foregroundStyle(Color.pp("PrimaryTextClr"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text(viewModel.localized("ProLoginSubtitle"))
                    .font(.custom("Beiruti-Regular", size: 18))
                    .foregroundStyle(Color.pp("SeconderyTextClr"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 10)
            }
        }
    }

    private var brandImage: some View {
        Group {
            if let image = UIImage(named: "pure shelid icon filled") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.pp("AppPrimaryClr"))
            }
        }
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(viewModel.localized("AdminLoginTitle"))
                .font(.custom("Beiruti-Bold", size: 24))
                .foregroundStyle(Color.pp("PrimaryTextClr"))

            VStack(spacing: 14) {
                PPProFieldRow(
                    icon: "envelope",
                    title: viewModel.localized("Email"),
                    text: $viewModel.email,
                    isSecure: false,
                    revealSecureText: .constant(false),
                    keyboardType: .emailAddress,
                    textContentType: .username,
                    submitLabel: .next,
                    focusedField: $focusedField,
                    field: .email,
                    onSubmit: { focusedField = .password }
                )

                PPProFieldRow(
                    icon: "lock",
                    title: viewModel.localized("Password"),
                    text: $viewModel.password,
                    isSecure: true,
                    revealSecureText: $viewModel.revealPassword,
                    keyboardType: .default,
                    textContentType: .password,
                    submitLabel: .go,
                    focusedField: $focusedField,
                    field: .password,
                    onSubmit: { viewModel.submit() }
                )
            }

            HStack(alignment: .center, spacing: 12) {
                Toggle(isOn: $viewModel.rememberMe) {
                    Text(viewModel.localized("RememberMe"))
                        .font(.custom("Beiruti-Medium", size: 16))
                        .foregroundStyle(Color.pp("PrimaryTextClr"))
                }
                .toggleStyle(SwitchToggleStyle(tint: Color.pp("AppPrimaryClr")))

                Spacer(minLength: 12)

                Button(action: viewModel.requestPasswordReset) {
                    Text(viewModel.localized("ForgotPassword"))
                        .font(.custom("Beiruti-Medium", size: 15))
                        .foregroundStyle(Color.pp("AppPrimaryClr"))
                }
                .buttonStyle(.plain)
            }

            Button(action: viewModel.submit) {
                HStack(spacing: 12) {
                    if viewModel.isPerforming(.email) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .tint(.white)
                    } else {
                        Image(systemName: viewModel.isRTL ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                            .font(.custom("Beiruti-Medium", size: 18))
                    }

                    Text(viewModel.localized("Login"))
                        .font(.custom("Beiruti-Medium", size: 19))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.pp("AppPrimaryClr"),
                                    Color.pp("AppPrimaryClrDarker").opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: Color.pp("AppPrimaryClr").opacity(0.28), radius: 18, x: 0, y: 14)
            }
            .buttonStyle(PPProScaleButtonStyle())
            .disabled(viewModel.isBusy)
            .opacity(viewModel.isBusy ? 0.92 : 1)

            Button(action: viewModel.signInWithGoogle) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 30, height: 30)
                        if viewModel.isPerforming(.google) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .tint(Color.pp("AppPrimaryClr"))
                                .scaleEffect(0.76)
                        } else {
                            Text("G")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.pp("AppPrimaryClr"))
                        }
                    }

                    Text(viewModel.localized("SignInWithGoogle"))
                        .font(.custom("Beiruti-Medium", size: 18))

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.custom("Beiruti-Medium", size: 15))
                        .foregroundStyle(Color.pp("AppPrimaryClr").opacity(0.9))
                }
                .foregroundStyle(Color.pp("PrimaryTextClr"))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.82))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.94), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 8)
            }
            .buttonStyle(PPProScaleButtonStyle())
            .disabled(viewModel.isBusy)
            .opacity(viewModel.isBusy && !viewModel.isPerforming(.google) ? 0.7 : 1)

            if viewModel.canUseBiometric {
                Button(action: viewModel.useBiometricLogin) {
                    HStack(spacing: 10) {
                        if viewModel.isPerforming(.biometric) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .tint(Color.pp("AppPrimaryClrDarker"))
                        } else {
                            Image(systemName: "faceid")
                                .font(.custom("Beiruti-Medium", size: 18))
                        }
                        Text(viewModel.biometricTitle)
                            .font(.custom("Beiruti-Bold", size: 17))
                    }
                    .foregroundStyle(Color.pp("AppPrimaryClrDarker"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    )
                }
                .buttonStyle(PPProScaleButtonStyle())
                .disabled(viewModel.isBusy)
            }

            Text(viewModel.localized("ProLoginHint"))
                .font(.custom("Beiruti-Regular", size: 15))
                .foregroundStyle(Color.pp("SeconderyTextClr"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
        .padding(24)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 32, x: 0, y: 16)
    }

    private var footerLabel: some View {
        Text(viewModel.localized("ProLoginFooter"))
            .font(.custom("Beiruti-Regular", size: 14))
            .foregroundStyle(Color.pp("SeconderyTextClr"))
            .padding(.bottom, 4)
    }
}

private struct PPProFieldRow: View {
    let icon: String
    let title: String
    @Binding var text: String
    let isSecure: Bool
    @Binding var revealSecureText: Bool
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let submitLabel: SubmitLabel
    let focusedField: FocusState<PPProLoginField?>.Binding
    let field: PPProLoginField
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.pp("AppBackgroundClr"))
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.custom("Beiruti-Medium", size: 17))
                    .foregroundStyle(Color.pp("AppPrimaryClr"))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.custom("Beiruti-Medium", size: 15))
                    .foregroundStyle(Color.pp("SeconderyTextClr"))

                Group {
                    if isSecure && !revealSecureText {
                        SecureField(title, text: $text)
                    } else {
                        TextField(title, text: $text)
                    }
                }
                .font(.custom("Beiruti-Medium", size: 18))
                .foregroundStyle(Color.pp("PrimaryTextClr"))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .submitLabel(submitLabel)
                .focused(focusedField, equals: field)
                .onSubmit(onSubmit)
            }

            if isSecure {
                Button(action: { revealSecureText.toggle() }) {
                    Image(systemName: revealSecureText ? "eye.slash" : "eye")
                        .font(.custom("Beiruti-Medium", size: 17))
                        .foregroundStyle(Color.pp("SeconderyTextClr"))
                        .padding(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.68))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(focusedField.wrappedValue == field ? Color.pp("AppPrimaryClr").opacity(0.35) : Color.white.opacity(0.66), lineWidth: 1.2)
                )
        )
    }
}

private struct PPProScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

@MainActor
@objcMembers
final class PPProLoginHostingController: UIViewController {
    private var hostingController: UIHostingController<PPProLoginScreen>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let coordinator = PPProLoginCoordinator(presenting: self)
        let viewModel = PPProLoginViewModel(coordinator: coordinator)
        let host = UIHostingController(rootView: PPProLoginScreen(viewModel: viewModel))
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .darkContent
    }
}
