import SwiftUI
import UIKit

private enum AdminLoginField: Hashable {
    case phone, verificationCode, email, password
}

@MainActor
struct AdminLoginView: View {
    @ObservedObject var state: AuthenticationState
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focus: AdminLoginField?

    private var enteringCode: Bool { state.authMode == .phone && state.isCodeSent }
    private var accent: Color { Color(uiColor: .ppAccentText) }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 800 && !typeSize.isAccessibilitySize
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .center, spacing: 0))
                : AnyLayout(VStackLayout(alignment: .center, spacing: 0))

            ScrollView {
                layout {
                    masthead(wide: wide)
                    LoginPassFold(vertical: wide)
                    form
                        .padding(wide ? 36 : 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(AdminSurface.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .frame(maxWidth: wide ? 900 : 510)
                .padding(.horizontal, wide ? 40 : 16)
                .padding(.vertical, wide ? 32 : 16)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .foregroundStyle(AdminSurface.primaryText)
        .font(AdminType.body)
        .tint(accent)
        .environment(\.layoutDirection, state.isRTL ? .rightToLeft : .leftToRight)
        .onChange(of: state.isCodeSent) { _, sent in
            if sent && state.authMode == .phone { focus = .verificationCode }
        }
        .alert(item: $state.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message),
                  dismissButton: .default(Text(state.localized("OK"))))
        }
    }

    private func masthead(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: wide ? 32 : 14) {
            HStack(alignment: .center, spacing: 12) {
                Image("pure shelid icon filled full size")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: wide ? 90 : 56, height: wide ? 90 : 56)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Button(action: state.toggleLanguage) {
                    Label(state.localized("StaffLogin_OtherLanguage"), systemImage: "globe")
                        .font(AdminType.calloutBold)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel(state.localized("StaffLogin_SwitchLanguage"))
                .disabled(state.isBusy)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(state.localized("StaffLogin_Brand"))
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(accent)
                Text(state.localized(enteringCode ? "StaffLogin_CodeTitle" : "StaffLogin_Title"))
                    .font(AdminType.largeTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if state.canUseBiometric {
                Button {
                    focus = nil
                    state.signInWithBiometric()
                } label: {
                    HStack(spacing: 9) {
                        if state.activeAction == .biometric {
                            ProgressView().accessibilityHidden(true)
                        } else {
                            Image(systemName: state.biometricTitle == state.localized("LoginWithTouchID") ? "touchid" : "faceid")
                                .accessibilityHidden(true)
                        }
                        Text(state.biometricTitle)
                            .multilineTextAlignment(.leading)
                    }
                    .font(AdminType.calloutBold)
                    .frame(minHeight: 44)
                }
                .disabled(state.isBusy)
            }
        }
        .buttonStyle(.plain)
        .padding(wide ? 32 : 22)
        .frame(width: wide ? 280 : nil)
        .frame(maxWidth: wide ? nil : .infinity, maxHeight: wide ? .infinity : nil, alignment: .leading)
        .background(Color(uiColor: .ppSurfaceOverlay))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 22) {
            methodPicker
            VStack(alignment: .leading, spacing: 14) {
                if enteringCode {
                    codeEntry
                } else if state.authMode == .phone {
                    phoneEntry
                } else {
                    emailEntry
                }
                submitButton
                if enteringCode { resendControl }
            }
            providerMethods
        }
        .disabled(state.isBusy)
    }

    private var methodPicker: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 20))
        return layout {
            method(.phone, "PhoneTitle")
            method(.email, "Email")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func method(_ mode: AdminAuthMode, _ title: String) -> some View {
        let selected = state.authMode == mode
        return Button {
            guard mode != state.authMode else { return }
            focus = nil
            state.authMode = mode
        } label: {
            Text(state.localized(title))
                .font(selected ? AdminType.headline : AdminType.body)
                .foregroundStyle(selected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                .padding(.horizontal, 3)
                .frame(minWidth: 44, minHeight: 44)
                .overlay(alignment: .bottom) {
                    if selected { Capsule().fill(accent).frame(height: 3) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func field<Content: View>(_ key: String, focus expectedFocus: AdminLoginField,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(state.localized(key))
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.secondaryText)
                .accessibilityHidden(true)
            content()
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            Rectangle()
                .fill(focus == expectedFocus ? accent : Color(uiColor: .ppSeparator))
                .frame(height: focus == expectedFocus ? 2 : 1)
                .accessibilityHidden(true)
        }
    }

    private var phoneEntry: some View {
        let includesPrefix = state.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+")
        return field("PhoneNumber", focus: .phone) {
            HStack(spacing: 10) {
                if !includesPrefix {
                    Text(verbatim: state.phoneCountryCode)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .accessibilityHidden(true)
                    Divider().frame(height: 20).accessibilityHidden(true)
                }
                TextField(state.localized("PhoneNumberPlaceholder"), text: $state.phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($focus, equals: .phone)
                    .accessibilityLabel(state.localized("PhoneNumber") + (includesPrefix ? "" : " " + state.phoneCountryCode))
                    .onSubmit { performPrimaryAction() }
            }
            .font(AdminType.title2)
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    @ViewBuilder private var codeEntry: some View {
        Text(String(format: state.localized("StaffLogin_CodeDestination"), "\u{2066}" + state.formattedFullPhone + "\u{2069}"))
            .font(AdminType.callout)
            .fixedSize(horizontal: false, vertical: true)
        field("VerificationCode", focus: .verificationCode) {
            TextField(state.localized("VerificationCodePlaceholder"), text: $state.verificationCode)
                .font(AdminType.title2)
                .monospacedDigit()
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focus, equals: .verificationCode)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(state.localized("VerificationCode"))
                .onSubmit { performPrimaryAction() }
        }
    }

    @ViewBuilder private var emailEntry: some View {
        field("Email", focus: .email) {
            TextField(state.localized("EmailPlaceholder"), text: $state.email)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(state.localized("Email"))
                .submitLabel(.next)
                .onSubmit { focus = .password }
        }
        field("Password", focus: .password) {
            HStack(spacing: 8) {
                Group {
                    if state.revealPassword {
                        TextField(state.localized("PasswordPlaceholder"), text: $state.password)
                    } else {
                        SecureField(state.localized("PasswordPlaceholder"), text: $state.password)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .password)
                .accessibilityLabel(state.localized("Password"))
                .submitLabel(.go)
                .onSubmit { performPrimaryAction() }
                Button {
                    state.revealPassword.toggle()
                    focus = .password
                } label: {
                    Image(systemName: state.revealPassword ? "eye.slash" : "eye")
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.localized(state.revealPassword ? "CommandCenter_Hide_Password" : "CommandCenter_Show_Password"))
            }
        }
        Toggle(state.localized("RememberMe"), isOn: $state.rememberMe)
            .font(AdminType.callout)
            .frame(minHeight: 44)
        Button {
            if state.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { focus = .email }
            state.resetPassword()
        } label: {
            HStack(spacing: 8) {
                if state.activeAction == .passwordReset { ProgressView() }
                Text(state.localized("ForgotPassword"))
            }
            .font(AdminType.calloutBold)
            .frame(minHeight: 44)
        }
    }

    private var primaryAction: AdminAuthenticationAction {
        if enteringCode { return .phoneVerify }
        return state.authMode == .phone ? .phoneSendCode : .email
    }

    private func performPrimaryAction() {
        guard !state.isBusy else { return }
        focus = nil
        if enteringCode { state.verifyPhoneCode() }
        else if state.authMode == .phone { state.sendPhoneCode() }
        else { state.submit() }
    }

    private var submitButton: some View {
        let key = enteringCode ? "VerifyAndLogin" : (state.authMode == .phone ? "SendVerificationCode" : "Login")
        return Button(action: performPrimaryAction) {
            HStack(spacing: 12) {
                Text(state.localized(key))
                    .font(AdminType.headline)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if state.activeAction == primaryAction {
                    ProgressView().tint(.white).accessibilityHidden(true)
                } else {
                    Image(systemName: "arrow.forward").accessibilityHidden(true)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(state.activeAction == primaryAction ? state.localized("Please wait") : "")
    }

    private var resendControl: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { codeActions.fixedSize(horizontal: true, vertical: false) }
            VStack(alignment: .leading, spacing: 2) { codeActions }
        }
        .font(AdminType.callout)
    }

    @ViewBuilder private var codeActions: some View {
        Button(state.localized("ChangePhoneNumber")) {
            state.resetPhoneFlow()
            focus = .phone
        }
        .frame(minHeight: 44)
        if state.activeAction == .phoneSendCode {
            ProgressView().accessibilityLabel(state.localized("ResendCode"))
        } else if state.resendCountdown > 0 {
            Text(String(format: state.localized("ResendCodeInFormat"), state.resendCountdown))
                .monospacedDigit()
                .foregroundStyle(AdminSurface.secondaryText)
        } else {
            Button(state.localized("ResendCode")) {
                focus = nil
                state.sendPhoneCode()
            }
            .frame(minHeight: 44)
        }
    }

    private var providerMethods: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.localized("StaffLogin_OtherMethods"))
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.secondaryText)
                .accessibilityAddTraits(.isHeader)
            provider("SignInWithApple", action: .apple, perform: state.signInWithApple)
            Divider()
            provider("SignInWithGoogle", action: .google, perform: state.signInWithGoogle)
        }
    }

    private func provider(_ key: String, action: AdminAuthenticationAction,
                          perform: @escaping () -> Void) -> some View {
        Button {
            focus = nil
            perform()
        } label: {
            HStack(spacing: 12) {
                Text(state.localized(key)).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if state.activeAction == action {
                    ProgressView().accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .font(AdminType.calloutBold)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(state.activeAction == action ? state.localized("Please wait") : "")
    }
}

// The dashed fold and its two open ends rotate as the pass opens on iPad.
private struct LoginPassFold: View {
    let vertical: Bool

    var body: some View {
        Canvas { context, size in
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            let start = vertical ? CGPoint(x: middle.x, y: 0) : CGPoint(x: 0, y: middle.y)
            let end = vertical ? CGPoint(x: middle.x, y: size.height) : CGPoint(x: size.width, y: middle.y)
            var line = Path()
            line.move(to: start)
            line.addLine(to: end)
            context.stroke(line, with: .color(Color(uiColor: .ppSeparator)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            for point in [start, end] {
                let notch = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: notch), with: .color(AdminSurface.background))
            }
        }
        .frame(width: vertical ? 14 : nil, height: vertical ? nil : 14)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

enum AdminSurface {
    static let primary = Color(uiColor: .ppPrimary)
    static let primaryPressed = Color(uiColor: .ppPressedAction)
    static let primarySoft = Color(uiColor: .ppPrimaryShiner)
    static let background = Color(uiColor: .ppBackground)
    static let backgroundSecondary = Color(uiColor: .ppBackgroundSecondary)
    static let control = Color(uiColor: .ppElevatedSurface)
    static let container = Color(uiColor: .ppElevatedSurface)
    static let fieldBackground = Color(uiColor: .ppElevatedSurface)
    static let surface = Color(uiColor: .ppSurface)
    static let card = Color(uiColor: .ppSurface)
    static let cardElevated = Color(uiColor: .ppElevatedSurface)
    static let amber = Color(uiColor: .ppWarning)
    static let emerald = Color(uiColor: .ppSuccess)
    static let crimson = Color(uiColor: .ppError)
    static let danger = Color(uiColor: .ppError)
    static let primaryText = Color(uiColor: .ppTextPrimary)
    static let secondaryText = Color(uiColor: .ppTextSecondary)
    static let hairline = Color(uiColor: .ppSurfaceBorder)
    static let borderSubtle = Color(uiColor: .ppSurfaceBorder)
}

enum AdminType {
    static let largeTitle = Font.custom("Beiruti-Bold", size: 38, relativeTo: .largeTitle)
    static let title = Font.custom("Beiruti-Bold", size: 32, relativeTo: .largeTitle)
    static let title2 = Font.custom("Beiruti-Bold", size: 24, relativeTo: .title2)
    static let title2Bold = Font.custom("Beiruti-Bold", size: 24, relativeTo: .title2)
    static let title3 = Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3)
    static let title3Bold = Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3)
    static let headline = Font.custom("Beiruti-Bold", size: 17, relativeTo: .headline)
    static let headlineBold = Font.custom("Beiruti-Bold", size: 17, relativeTo: .headline)
    static let subheadline = Font.custom("Beiruti-Regular", size: 15, relativeTo: .subheadline)
    static let subheadlineBold = Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline)
    static let body = Font.custom("Beiruti-Regular", size: 17, relativeTo: .body)
    static let bodyBold = Font.custom("Beiruti-Bold", size: 17, relativeTo: .body)
    static let callout = Font.custom("Beiruti-Regular", size: 16, relativeTo: .callout)
    static let calloutBold = Font.custom("Beiruti-Medium", size: 16, relativeTo: .callout)
    static let footnote = Font.custom("Beiruti-Regular", size: 14, relativeTo: .footnote)
    static let footnoteBold = Font.custom("Beiruti-Bold", size: 14, relativeTo: .footnote)
    static let caption = Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption)
    static let captionRegular = Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption)
    static let caption1 = Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption)
    static let caption1Bold = Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption)
    static let caption2 = Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2)
    static let caption2Medium = Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2)
    static let caption2Bold = Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2)
    static let captionBold = Font.custom("Beiruti-Medium", size: 13, relativeTo: .caption)
}

typealias AdminFont = AdminType
