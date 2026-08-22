import SwiftUI
import UIKit

private enum AdminLoginField: Hashable {
    case email
    case password
}

@MainActor
struct AdminLoginView: View {
    @ObservedObject var state: AuthenticationState
    @FocusState private var focusedField: AdminLoginField?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AdminSurface.background.ignoresSafeArea()
                if geometry.size.width >= 760 {
                    HStack(spacing: 0) {
                        identityPanel
                            .frame(width: min(430, geometry.size.width * 0.42))
                        formScrollView(showsCompactIdentity: false)
                    }
                } else {
                    formScrollView(showsCompactIdentity: true)
                }
            }
        }
        .environment(\.layoutDirection, state.isRTL ? .rightToLeft : .leftToRight)
        .alert(item: $state.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(state.localized("OK")))
            )
        }
    }

    private func formScrollView(showsCompactIdentity: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                topBar
                if showsCompactIdentity { compactIdentity }
                loginForm
                Text(state.localized("CommandCenter_Login_Footer"))
                    .font(AdminType.footnote)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboardCompat()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Label(state.localized("CommandCenter_Staff_Access"), systemImage: "lock.shield")
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(AdminSurface.primary.opacity(0.10), in: Capsule())

            Spacer()

            HStack(spacing: 8) {
                Button(action: state.toggleLanguage) {
                    Label(state.languageToggleLabel, systemImage: "globe")
                        .font(AdminType.captionBold)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(state.localized("Confirm_LanguageChange_Title"))

                Menu {
                    Button(action: state.toggleLanguage) {
                        Label(state.localized("Confirm_LanguageChange_Title"), systemImage: "globe")
                    }
                    Button(action: state.resetPassword) {
                        Label(state.localized("ForgotPassword"), systemImage: "key")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.control)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 1))
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AdminSurface.primaryText)
                    }
                }
                .accessibilityLabel(state.localized("CommandCenter_Tab_More"))
            }
        }
    }

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            brandMark(onBrandSurface: true)
            Spacer()
            Text(state.localized("CommandCenter_Login_Eyebrow"))
                .font(AdminType.captionBold)
                .foregroundColor(.white.opacity(0.78))
                .textCase(.uppercase)
            Text(state.localized("CommandCenter_Login_Title"))
                .font(AdminType.largeTitle)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(state.localized("CommandCenter_Login_Subtitle"))
                .font(AdminType.body)
                .foregroundColor(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Label(state.localized("CommandCenter_Login_Authority"), systemImage: "checkmark.seal.fill")
                .font(AdminType.callout)
                .foregroundColor(.white)
        }
        .padding(36)
        .background(AdminSurface.primary)
        .accessibilityElement(children: .contain)
    }

    private var compactIdentity: some View {
        VStack(spacing: 14) {
            brandMark(onBrandSurface: false)
            Text(state.localized("CommandCenter_Login_Title"))
                .font(AdminType.title)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.center)
            Text(state.localized("CommandCenter_Login_Subtitle"))
                .font(AdminType.body)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func brandMark(onBrandSurface: Bool) -> some View {
        Group {
            if let image = UIImage(named: "pure shelid icon filled") {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "shield.lefthalf.filled").resizable().scaledToFit()
            }
        }
        .foregroundColor(.white)
        .frame(width: 58, height: 58)
        .padding(17)
        .background(onBrandSurface ? Color.white.opacity(0.14) : AdminSurface.primary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityHidden(true)
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.localized("AdminLoginTitle"))
                    .font(AdminType.title2)
                    .foregroundColor(AdminSurface.primaryText)
                Text(state.localized("ProLoginHint"))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            VStack(spacing: 14) {
                fieldLabel(state.localized("Email"), symbol: "envelope")
                TextField(state.localized("EmailPlaceholder"), text: $state.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
                    .adminTextFieldStyle()

                fieldLabel(state.localized("Password"), symbol: "lock")
                HStack(spacing: 8) {
                    Group {
                        if state.revealPassword {
                            TextField(state.localized("PasswordPlaceholder"), text: $state.password)
                        } else {
                            SecureField(state.localized("PasswordPlaceholder"), text: $state.password)
                        }
                    }
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit(state.submit)

                    Button(action: { state.revealPassword.toggle() }) {
                        Image(systemName: state.revealPassword ? "eye.slash" : "eye")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(state.localized(state.revealPassword ? "CommandCenter_Hide_Password" : "CommandCenter_Show_Password"))
                }
                .adminTextFieldStyle()
            }

            HStack(alignment: .center, spacing: 12) {
                Toggle(state.localized("RememberMe"), isOn: $state.rememberMe)
                    .font(AdminType.callout)
                    .tint(AdminSurface.primary)
                Spacer(minLength: 12)
                Button(state.localized("ForgotPassword"), action: state.resetPassword)
                    .font(AdminType.calloutBold)
                    .disabled(state.isBusy)
            }

            Button(action: state.submit) {
                HStack(spacing: 10) {
                    if state.activeAction == .email { ProgressView().tint(.white) }
                    Text(state.localized("Login"))
                    Image(systemName: state.isRTL ? "arrow.left" : "arrow.right")
                }
                .font(AdminType.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy)
            .opacity(state.isBusy && state.activeAction != .email ? 0.55 : 1)

            Button(action: state.signInWithGoogle) {
                HStack(spacing: 12) {
                    if state.activeAction == .google {
                        ProgressView().tint(AdminSurface.primary)
                    } else {
                        Text("G").font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    Text(state.localized("SignInWithGoogle"))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy)

            if state.canUseBiometric {
                Button(action: state.signInWithBiometric) {
                    Label(state.biometricTitle, systemImage: "faceid")
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .disabled(state.isBusy)
            }
        }
        .padding(24)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AdminSurface.hairline))
    }

    private func fieldLabel(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(AdminType.captionBold)
            .foregroundColor(AdminSurface.secondaryText)
    }
}

extension View {
    fileprivate func adminTextFieldStyle() -> some View {
        self
            .font(AdminType.body)
            .foregroundColor(AdminSurface.primaryText)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline))
    }

    @ViewBuilder
    fileprivate func scrollDismissesKeyboardCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}

enum AdminSurface {
    static let primary = Color(uiColor: .ppPrimary)
    static let primaryPressed = Color(uiColor: .ppPressedAction)
    static let primarySoft = Color(uiColor: .ppPrimaryShiner)
    static let background = Color(uiColor: .ppBackground)
    static let control = Color(uiColor: .ppElevatedSurface)
    static let surface = Color(uiColor: .ppSurface)
    static let primaryText = Color(uiColor: .ppTextPrimary)
    static let secondaryText = Color(uiColor: .ppTextSecondary)
    static let hairline = Color(uiColor: .ppSurfaceBorder)
}

enum AdminType {
    static let largeTitle = Font.custom("Beiruti-Bold", size: 38, relativeTo: .largeTitle)
    static let title = Font.custom("Beiruti-Bold", size: 32, relativeTo: .largeTitle)
    static let title2 = Font.custom("Beiruti-Bold", size: 24, relativeTo: .title2)
    static let title3 = Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3)
    static let headline = Font.custom("Beiruti-Bold", size: 17, relativeTo: .headline)
    static let subheadline = Font.custom("Beiruti-Regular", size: 15, relativeTo: .subheadline)
    static let subheadlineBold = Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline)
    static let body = Font.custom("Beiruti-Regular", size: 17, relativeTo: .body)
    static let callout = Font.custom("Beiruti-Regular", size: 16, relativeTo: .callout)
    static let calloutBold = Font.custom("Beiruti-Medium", size: 16, relativeTo: .callout)
    static let footnote = Font.custom("Beiruti-Regular", size: 14, relativeTo: .footnote)
    static let footnoteBold = Font.custom("Beiruti-Bold", size: 14, relativeTo: .footnote)
    static let caption1 = Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption)
    static let caption2 = Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2)
    static let caption2Bold = Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2)
    static let captionBold = Font.custom("Beiruti-Medium", size: 13, relativeTo: .caption)
}


