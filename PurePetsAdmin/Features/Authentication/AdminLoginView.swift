import SwiftUI
import UIKit

private enum AdminLoginField: Hashable {
    case phone
    case verificationCode
    case email
    case password
}

@MainActor
struct AdminLoginView: View {
    @ObservedObject var state: AuthenticationState
    @FocusState private var focusedField: AdminLoginField?
    @State private var isMoreMenuPresented: Bool = false
    @Environment(\.sizeCategory) private var sizeCategory

    var body: some View {
        GeometryReader { geometry in
            let windowTopInset = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?.safeAreaInsets.top ?? 0
            let statusBarHeight = max(geometry.safeAreaInsets.top, windowTopInset > 0 ? windowTopInset : 47)

            ZStack {
                AdminLoginAtmosphere()
                    .ignoresSafeArea()

                if geometry.size.width >= 760, geometry.size.height >= 620 {
                    expansiveGateway(in: geometry, statusBarHeight: statusBarHeight)
                } else {
                    accessColumn(showsIdentity: true, statusBarHeight: statusBarHeight)
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

    private func expansiveGateway(in geometry: GeometryProxy, statusBarHeight: CGFloat) -> some View {
        HStack(spacing: 32) {
            identityObservatory
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            accessColumn(showsIdentity: false, statusBarHeight: statusBarHeight)
                .frame(width: min(560, max(420, geometry.size.width * 0.44)))
                .background(AdminSurface.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 1)
                )
        }
        .padding(32)
    }

    private func accessColumn(showsIdentity: Bool, statusBarHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                commandRail
                    .padding(.top, statusBarHeight)
                    .zIndex(100)

                if showsIdentity {
                    compactIdentity
                        .zIndex(1)
                }

                accessCapsule
                    .zIndex(1)
                securityFootprint
                    .zIndex(1)
            }
            .frame(maxWidth: 580)
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboardCompat()
    }

    private var commandRail: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text(state.localized("CommandCenter_Staff_Access"))
                    .lineLimit(1)
            }
            .font(AdminType.captionBold)
            .foregroundColor(AdminSurface.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(AdminSurface.primary.opacity(0.10), in: Capsule())
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            Button(action: state.toggleLanguage) {
                HStack(spacing: 7) {
                    Image(systemName: "globe")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(state.languageToggleLabel)
                }
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(AdminSurface.control, in: Capsule())
                .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 1))
            }
            .buttonStyle(AdminLoginPressStyle())
            .accessibilityLabel(state.localized("Confirm_LanguageChange_Title"))

            moreActionsMenuTrigger
        }
    }

    private var moreActionsMenuTrigger: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isMoreMenuPresented.toggle()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(isMoreMenuPresented ? AdminSurface.primary : AdminSurface.primaryText)
                .frame(width: 44, height: 44)
                .background(isMoreMenuPresented ? AdminSurface.primary.opacity(0.12) : AdminSurface.control, in: Circle())
                .overlay(Circle().stroke(isMoreMenuPresented ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline, lineWidth: 1))
        }
        .buttonStyle(AdminLoginPressStyle())
        .accessibilityLabel(state.localized("CommandCenter_Tab_More"))
        .background {
            if isMoreMenuPresented {
                Color.black.opacity(0.001)
                    .frame(width: 2500, height: 2500)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            isMoreMenuPresented = false
                        }
                    }
            }
        }
        .overlay(alignment: state.isRTL ? .topLeading : .topTrailing) {
            if isMoreMenuPresented {
                customMoreActionsMenuCard
                    .offset(y: 52)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.88, anchor: state.isRTL ? .topLeading : .topTrailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(300)
            }
        }
    }

    private var customMoreActionsMenuCard: some View {
        VStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    isMoreMenuPresented = false
                }
                state.toggleLanguage()
            } label: {
                HStack(spacing: 12) {
                    Text(state.localized("Confirm_LanguageChange_Title"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(AdminLoginPressStyle())

            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.75)
                .padding(.horizontal, 12)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    isMoreMenuPresented = false
                }
                state.resetPassword()
            } label: {
                HStack(spacing: 12) {
                    Text(state.localized("ForgotPassword"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "key")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(AdminLoginPressStyle())
        }
        .frame(width: 220)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: 10)
        .environment(\.layoutDirection, state.isRTL ? .rightToLeft : .leftToRight)
    }

    private var compactIdentity: some View {
        VStack(spacing: 18) {
            brandPortal(onBrandSurface: false, diameter: 108)

            VStack(spacing: 8) {
                Text(state.localized("CommandCenter_Login_Title"))
                    .font(AdminType.title)
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(state.localized("CommandCenter_Login_Subtitle"))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }

    private var identityObservatory: some View {
        VStack(alignment: .leading, spacing: 24) {
            staffPulse

            Spacer(minLength: 20)

            brandPortal(onBrandSurface: true, diameter: 164)

            VStack(alignment: .leading, spacing: 12) {
                Text(state.localized("CommandCenter_Login_Eyebrow"))
                    .font(AdminType.captionBold)
                    .foregroundColor(.white.opacity(0.76))
                    .textCase(.uppercase)

                Text(state.localized("CommandCenter_Login_Title"))
                    .font(AdminType.largeTitle)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(state.localized("CommandCenter_Login_Subtitle"))
                    .font(AdminType.callout)
                    .foregroundColor(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 20)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityHidden(true)
                Text(state.localized("CommandCenter_Login_Authority"))
                    .font(AdminType.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(.white)
            .accessibilityElement(children: .combine)
        }
        .padding(40)
        .background {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(AdminSurface.primary)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 280, height: 280)
                        .offset(x: 92, y: -98)
                }
                .overlay(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 54, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                        .frame(width: 250, height: 120)
                        .rotationEffect(.degrees(-19))
                        .offset(x: -72, y: 68)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var staffPulse: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(state.localized("CommandCenter_Staff_Access"))
        }
        .font(AdminType.captionBold)
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(.white.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func brandPortal(onBrandSurface: Bool, diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke((onBrandSurface ? Color.white : AdminSurface.primary).opacity(0.17), lineWidth: 1)
                .frame(width: diameter, height: diameter)

            Circle()
                .stroke((onBrandSurface ? Color.white : AdminSurface.primary).opacity(0.12), lineWidth: 1)
                .frame(width: diameter * 0.76, height: diameter * 0.76)

            Group {
                if let image = UIImage(named: "pure shelid icon filled") {
                    Image(uiImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "shield.lefthalf.filled")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                }
            }
            .foregroundColor(.white)
            .frame(width: diameter * 0.40, height: diameter * 0.40)
            .padding(diameter * 0.16)
            .background(
                onBrandSurface ? Color.white.opacity(0.14) : AdminSurface.primary,
                in: RoundedRectangle(cornerRadius: diameter * 0.23, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: diameter * 0.23, style: .continuous)
                    .stroke(.white.opacity(onBrandSurface ? 0.20 : 0.16), lineWidth: 1)
            )
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private var accessCapsule: some View {
        VStack(alignment: .leading, spacing: 20) {
            accessCapsuleHeader
            authModeSwitcher
            if state.authMode == .phone {
                phoneAuthSection
            } else {
                emailAuthSection
            }
            alternativeGate
            providerActions
        }
        .padding(24)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
        .shadow(color: AdminSurface.primary.opacity(0.08), radius: 24, y: 12)
    }

    private var authModeSwitcher: some View {
        HStack(spacing: 6) {
            authModeTab(
                mode: .phone,
                title: state.localized("LoginWithPhone"),
                systemImage: "phone.fill"
            )
            authModeTab(
                mode: .email,
                title: state.localized("LoginWithEmail"),
                systemImage: "envelope.fill"
            )
        }
        .padding(4)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func authModeTab(mode: AdminAuthMode, title: String, systemImage: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                state.authMode = mode
                focusedField = nil
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(AdminType.calloutBold)
                    .lineLimit(1)
            }
            .foregroundColor(state.authMode == mode ? .white : AdminSurface.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                state.authMode == mode ? AdminSurface.primary : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var phoneAuthSection: some View {
        VStack(spacing: 16) {
            if !state.isCodeSent {
                VStack(alignment: .leading, spacing: 8) {
                    Label(state.localized("PhoneNumber"), systemImage: "phone")
                        .font(AdminType.captionBold)
                        .foregroundColor(focusedField == .phone ? AdminSurface.primary : AdminSurface.secondaryText)
                        .accessibilityHidden(true)

                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Text("🇶🇦")
                                .font(.system(size: 16))
                            Text(state.phoneCountryCode)
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 42)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 1)
                        )

                        TextField(state.localized("PhoneNumberPlaceholder"), text: $state.phoneNumber)
                            .font(AdminType.body)
                            .foregroundColor(AdminSurface.primaryText)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .phone)
                            .onSubmit {
                                focusedField = nil
                                state.sendPhoneCode()
                            }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 58)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(focusedField == .phone ? AdminSurface.primary.opacity(0.75) : AdminSurface.hairline, lineWidth: focusedField == .phone ? 1.5 : 1)
                    )
                    .shadow(color: focusedField == .phone ? AdminSurface.primary.opacity(0.12) : .clear, radius: 12, y: 4)
                }

                Text(state.localized("auth_phone_live_hint"))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    focusedField = nil
                    state.sendPhoneCode()
                } label: {
                    HStack(spacing: 10) {
                        if state.activeAction == .phoneSendCode {
                            ProgressView()
                                .tint(.white)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .accessibilityHidden(true)
                        }

                        Text(state.localized("SendVerificationCode"))
                        Spacer(minLength: 8)
                        Image(systemName: state.isRTL ? "arrow.left" : "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .font(AdminType.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(
                        LinearGradient(
                            colors: [AdminSurface.primary, AdminSurface.primaryPressed],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .shadow(color: AdminSurface.primary.opacity(0.24), radius: 14, y: 8)
                }
                .buttonStyle(AdminLoginPressStyle())
                .disabled(state.isBusy)
                .opacity(state.isBusy && state.activeAction != .phoneSendCode ? 0.55 : 1)

            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(state.localized("VerificationCode"), systemImage: "key.fill")
                            .font(AdminType.captionBold)
                            .foregroundColor(focusedField == .verificationCode ? AdminSurface.primary : AdminSurface.secondaryText)

                        Spacer()

                        Button {
                            state.resetPhoneFlow()
                        } label: {
                            Text(state.localized("ChangePhoneNumber"))
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.primary)
                        }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(focusedField == .verificationCode ? AdminSurface.primary : AdminSurface.secondaryText)
                            .frame(width: 20)
                            .accessibilityHidden(true)

                        TextField(state.localized("VerificationCodePlaceholder"), text: $state.verificationCode)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(AdminSurface.primaryText)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .verificationCode)
                            .onSubmit {
                                focusedField = nil
                                state.verifyPhoneCode()
                            }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 58)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(focusedField == .verificationCode ? AdminSurface.primary.opacity(0.75) : AdminSurface.hairline, lineWidth: focusedField == .verificationCode ? 1.5 : 1)
                    )
                    .shadow(color: focusedField == .verificationCode ? AdminSurface.primary.opacity(0.12) : .clear, radius: 12, y: 4)
                }

                HStack {
                    if state.resendCountdown > 0 {
                        Text(String(format: state.localized("ResendCodeInFormat"), state.resendCountdown))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                    } else {
                        Button {
                            state.sendPhoneCode()
                        } label: {
                            Text(state.localized("ResendCode"))
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.primary)
                        }
                    }
                    Spacer()
                }

                Button {
                    focusedField = nil
                    state.verifyPhoneCode()
                } label: {
                    HStack(spacing: 10) {
                        if state.activeAction == .phoneVerify {
                            ProgressView()
                                .tint(.white)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .accessibilityHidden(true)
                        }

                        Text(state.localized("VerifyAndLogin"))
                        Spacer(minLength: 8)
                        Image(systemName: state.isRTL ? "arrow.left" : "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .font(AdminType.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(
                        LinearGradient(
                            colors: [AdminSurface.primary, AdminSurface.primaryPressed],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .shadow(color: AdminSurface.primary.opacity(0.24), radius: 14, y: 8)
                }
                .buttonStyle(AdminLoginPressStyle())
                .disabled(state.isBusy)
                .opacity(state.isBusy && state.activeAction != .phoneVerify ? 0.55 : 1)
            }
        }
    }

    private var emailAuthSection: some View {
        VStack(spacing: 20) {
            credentialFields
            metaControls
            primaryAction
        }
    }

    private var accessCapsuleHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 48, height: 48)
                .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.localized("AdminLoginTitle"))
                    .font(AdminType.title2)
                    .foregroundColor(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(state.localized("ProLoginHint"))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var credentialFields: some View {
        VStack(spacing: 14) {
            credentialField(
                title: state.localized("Email"),
                symbol: "envelope",
                isFocused: focusedField == .email
            ) {
                TextField(state.localized("EmailPlaceholder"), text: $state.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            credentialField(
                title: state.localized("Password"),
                symbol: "lock",
                isFocused: focusedField == .password
            ) {
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
                    .onSubmit {
                        focusedField = nil
                        state.submit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: { state.revealPassword.toggle() }) {
                        Image(systemName: state.revealPassword ? "eye.slash" : "eye")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AdminSurface.secondaryText)
                            .frame(width: 44, height: 44)
                            .background(AdminSurface.primary.opacity(state.revealPassword ? 0.10 : 0.001), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(state.localized(state.revealPassword ? "CommandCenter_Hide_Password" : "CommandCenter_Show_Password"))
                }
            }
        }
    }

    private func credentialField<Content: View>(
        title: String,
        symbol: String,
        isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(AdminType.captionBold)
                .foregroundColor(isFocused ? AdminSurface.primary : AdminSurface.secondaryText)
                .accessibilityHidden(true)

            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isFocused ? AdminSurface.primary : AdminSurface.secondaryText)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                content()
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primaryText)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isFocused ? AdminSurface.primary.opacity(0.75) : AdminSurface.hairline, lineWidth: isFocused ? 1.5 : 1)
            )
            .shadow(color: isFocused ? AdminSurface.primary.opacity(0.12) : .clear, radius: 12, y: 4)
        }
    }

    private var metaControls: some View {
        Group {
            if sizeCategory.isAccessibilityCategory {
                VStack(alignment: .leading, spacing: 10) {
                    rememberMeToggle
                    passwordRecoveryAction
                }
            } else {
                HStack(spacing: 12) {
                    rememberMeToggle
                    Spacer(minLength: 12)
                    passwordRecoveryAction
                }
            }
        }
    }

    private var rememberMeToggle: some View {
        Toggle(state.localized("RememberMe"), isOn: $state.rememberMe)
            .font(AdminType.callout)
            .foregroundColor(AdminSurface.primaryText)
            .tint(AdminSurface.primary)
            .frame(minHeight: 44)
    }

    private var passwordRecoveryAction: some View {
        Button(action: state.resetPassword) {
            Label(state.localized("ForgotPassword"), systemImage: "key")
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primary)
                .frame(minHeight: 44)
        }
        .buttonStyle(AdminLoginPressStyle())
        .disabled(state.isBusy)
    }

    private var primaryAction: some View {
        Button {
            focusedField = nil
            state.submit()
        } label: {
            HStack(spacing: 10) {
                if state.activeAction == .email {
                    ProgressView()
                        .tint(.white)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .accessibilityHidden(true)
                }

                Text(state.localized("Login"))
                Spacer(minLength: 8)
                Image(systemName: state.isRTL ? "arrow.left" : "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(AdminType.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                LinearGradient(
                    colors: [AdminSurface.primary, AdminSurface.primaryPressed],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .shadow(color: AdminSurface.primary.opacity(0.24), radius: 14, y: 8)
        }
        .buttonStyle(AdminLoginPressStyle())
        .disabled(state.isBusy)
        .opacity(state.isBusy && state.activeAction != .email ? 0.55 : 1)
    }

    private var alternativeGate: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 1)
            Image(systemName: "shield.checkered")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AdminSurface.secondaryText)
                .accessibilityHidden(true)
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private var providerActions: some View {
        VStack(spacing: 12) {
            Button {
                focusedField = nil
                state.signInWithApple()
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if state.activeAction == .apple {
                            ProgressView()
                                .tint(AdminSurface.primary)
                        } else {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 19, weight: .semibold))
                        }
                    }
                    .frame(width: 24)
                    .accessibilityHidden(true)

                    Text(state.localized("SignInWithApple"))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .bold))
                        .accessibilityHidden(true)
                }
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(AdminLoginPressStyle())
            .disabled(state.isBusy)

            Button {
                focusedField = nil
                state.signInWithGoogle()
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if state.activeAction == .google {
                            ProgressView()
                                .tint(AdminSurface.primary)
                        } else {
                            Text("G")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                    }
                    .frame(width: 24)
                    .accessibilityHidden(true)

                    Text(state.localized("SignInWithGoogle"))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .bold))
                        .accessibilityHidden(true)
                }
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(AdminLoginPressStyle())
            .disabled(state.isBusy)

            if state.canUseBiometric {
                Button(action: state.signInWithBiometric) {
                    Label(state.biometricTitle, systemImage: "faceid")
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(AdminLoginPressStyle())
                .disabled(state.isBusy)
            }
        }
    }

    private var securityFootprint: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .accessibilityHidden(true)
                Text(state.localized("CommandCenter_Login_Authority"))
                    .font(AdminType.footnote)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: 460, alignment: .leading)
            .accessibilityElement(children: .combine)

            Text(state.localized("CommandCenter_Login_Footer"))
                .font(AdminType.footnote)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

private struct AdminLoginAtmosphere: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AdminSurface.background

                Circle()
                    .fill(AdminSurface.primary.opacity(0.075))
                    .frame(width: max(geometry.size.width * 0.86, 520), height: max(geometry.size.width * 0.86, 520))
                    .offset(x: geometry.size.width * 0.42, y: -geometry.size.height * 0.42)

                RoundedRectangle(cornerRadius: 96, style: .continuous)
                    .fill(AdminSurface.primarySoft.opacity(0.20))
                    .frame(width: max(geometry.size.width * 0.78, 420), height: 180)
                    .rotationEffect(.degrees(-17))
                    .offset(x: -geometry.size.width * 0.46, y: geometry.size.height * 0.39)

                VStack(spacing: 10) {
                    ForEach(0 ..< 7, id: \.self) { _ in
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.13))
                            .frame(width: 4, height: 4)
                    }
                }
                .offset(x: geometry.size.width * 0.40, y: geometry.size.height * 0.29)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

private struct AdminLoginPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.986 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78),
                value: configuration.isPressed
            )
    }
}

extension View {
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
    static let caption = Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption)
    static let caption1 = Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption)
    static let caption1Bold = Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption)
    static let caption2 = Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2)
    static let caption2Bold = Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2)
    static let captionBold = Font.custom("Beiruti-Medium", size: 13, relativeTo: .caption)
}
