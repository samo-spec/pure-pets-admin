import SwiftUI
import UIKit

// PPAlertHelper remains the Objective-C API and action owner. This bridge owns
// only transient presentation; it never routes, authenticates, or performs work.
@MainActor
@objc(PPAlertSwiftUIPresenter)
final class PPAlertSwiftUIPresenter: NSObject {
    @objc(showIn:type:title:subtitle:icon:actionTitles:actionStyles:defaultActionIndex:placeholder:initialText:secureEntry:keyboardType:allowsCancellation:selection:)
    static func show(
        in source: UIViewController?, type: Int, title: String, subtitle: String,
        icon: UIImage?, actionTitles: [String], actionStyles: [NSNumber], defaultActionIndex: Int,
        placeholder: String?, initialText: String?, secureEntry: Bool,
        keyboardType: Int, allowsCancellation: Bool,
        selection: @escaping (Int, String) -> Void
    ) {
        let request = PPAlertRequest(
            source: source, type: type, title: title, subtitle: subtitle, icon: icon,
            actions: actionTitles.enumerated().map { index, title in
                PPAlertChoice(id: index, title: title,
                              style: index < actionStyles.count ? actionStyles[index].intValue : 1)
            }, defaultActionIndex: defaultActionIndex, placeholder: placeholder,
            text: initialText ?? "", secureEntry: secureEntry,
            keyboardType: UIKeyboardType(rawValue: keyboardType) ?? .default,
            allowsCancellation: allowsCancellation, selection: selection
        )
        PPAlertPresentation.shared.enqueue(request)
    }
}

private struct PPAlertChoice: Identifiable {
    let id: Int
    let title: String
    let style: Int // Objective-C PPAlertActionStyle: primary / secondary / destructive / cancel.
    var isCancel: Bool { style == 3 }
    var isDestructive: Bool { style == 2 }
    var isProminent: Bool { style == 0 || isDestructive }
}

@MainActor
private final class PPAlertRequest: ObservableObject {
    weak var source: UIViewController?
    let hasExplicitSource: Bool
    let type: Int
    let title: String
    let subtitle: String
    let icon: UIImage?
    let actions: [PPAlertChoice]
    let defaultActionIndex: Int
    let placeholder: String?
    let secureEntry: Bool
    let keyboardType: UIKeyboardType
    let allowsCancellation: Bool
    let selection: (Int, String) -> Void
    @Published var text: String
    @Published var isReady = false
    @Published var isFinishing = false
    @Published var languageCode = Language.currentLanguageCode()
    var choose: ((Int) -> Void)?

    init(source: UIViewController?, type: Int, title: String, subtitle: String,
         icon: UIImage?, actions: [PPAlertChoice], defaultActionIndex: Int,
         placeholder: String?, text: String,
         secureEntry: Bool, keyboardType: UIKeyboardType, allowsCancellation: Bool,
         selection: @escaping (Int, String) -> Void) {
        self.source = source
        self.hasExplicitSource = source != nil
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.actions = actions
        self.defaultActionIndex = defaultActionIndex
        self.placeholder = placeholder
        self.text = text
        self.secureEntry = secureEntry
        self.keyboardType = keyboardType
        self.allowsCancellation = allowsCancellation
        self.selection = selection
    }

    var isInput: Bool { type == 5 }
    var isRTL: Bool { languageCode == "ar" }
    var cancelChoice: PPAlertChoice? {
        allowsCancellation ? actions.first(where: \.isCancel) : nil
    }
    var defaultChoice: PPAlertChoice? {
        actions.first { $0.id == defaultActionIndex && !$0.isCancel }
    }
    var sourceWindow: UIWindow? {
        var owner = source
        while let controller = owner {
            if let window = controller.viewIfLoaded?.window { return window }
            owner = controller.parent ?? controller.presentingViewController
        }
        return nil
    }
    var accent: Color {
        if actions.contains(where: \.isDestructive) { return Color(uiColor: .ppError) }
        switch type {
        case 0: return Color(uiColor: .ppSuccess)
        case 1: return Color(uiColor: .ppError)
        case 2: return Color(uiColor: .ppWarning)
        default: return Color(uiColor: .ppBrandPrimary)
        }
    }
    var symbol: String {
        switch type {
        case 0: return "checkmark"
        case 1: return "exclamationmark"
        case 2: return "exclamationmark.triangle"
        case 3: return "info"
        case 5: return "pencil.line"
        default: return "questionmark"
        }
    }
    var semanticTitle: String {
        let key: String
        switch type {
        case 0: key = "alert_eyebrow_success"
        case 1: key = "alert_eyebrow_error"
        case 2: key = "alert_eyebrow_warning"
        case 3: key = "alert_eyebrow_info"
        case 5: key = "alert_eyebrow_input"
        default: key = "alert_eyebrow_confirmation"
        }
        return Language.get(key, alter: nil)
    }
    var inputLabel: String {
        if let placeholder, !placeholder.isEmpty { return placeholder }
        return Language.get("Alert_Input_Accessibility_Label", alter: nil)
    }
    var usesLTRInput: Bool {
        switch keyboardType {
        case .emailAddress, .URL, .numberPad, .decimalPad, .phonePad,
             .asciiCapableNumberPad, .numbersAndPunctuation: return true
        default: return false
        }
    }
}

// A lane is scoped to an actual app window, not a global overlay/key window.
// Requests serialize so dismissal, callback-driven navigation, and new alerts
// cannot present over one another or dismiss an unrelated controller.
@MainActor
private final class PPAlertPresentation: NSObject {
    static let shared = PPAlertPresentation()
    private var lanes: [ObjectIdentifier: PPAlertLane] = [:]

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(sceneDisconnected(_:)),
                                               name: UIScene.didDisconnectNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func enqueue(_ request: PPAlertRequest) {
        guard let window = targetWindow(for: request.source) else {
            if let cancel = request.cancelChoice { request.selection(cancel.id, "") }
            return
        }
        lanes = lanes.filter { $0.value.window != nil }
        let key = ObjectIdentifier(window)
        let lane = lanes[key] ?? PPAlertLane(window: window)
        lanes[key] = lane
        lane.enqueue(request)
    }

    private func targetWindow(for source: UIViewController?) -> UIWindow? {
        var owner = source
        while let controller = owner {
            if let window = controller.viewIfLoaded?.window, window.windowLevel == .normal {
                return window
            }
            owner = controller.parent ?? controller.presentingViewController
        }
        if source != nil { return nil }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.alpha > 0 && $0.windowLevel == .normal && $0.rootViewController != nil }
        // A nil presenter is common on legacy call sites. Use the sole focused
        // app window; avoid directing a sensitive prompt into another scene.
        let focused = windows.filter(\.isKeyWindow)
        if focused.count == 1 { return focused[0] }
        return windows.count == 1 ? windows[0] : nil
    }

    @objc private func sceneDisconnected(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene else { return }
        let disconnected = lanes.filter { $0.value.window?.windowScene === scene }
        for (key, lane) in disconnected {
            lanes.removeValue(forKey: key)
            lane.cancelForDisconnectedScene()
        }
    }

    @objc private func becameActive() {
        for lane in lanes.values { lane.resume() }
    }
}

@MainActor
private final class PPAlertLane {
    weak var window: UIWindow?
    private var pending: [PPAlertRequest] = []
    private var active: PPAlertHostingController?
    private var isDelivering = false
    private var isWaitingForTransition = false
    private var isDisconnected = false
    private weak var previousFocus: AnyObject?

    init(window: UIWindow) { self.window = window }

    func enqueue(_ request: PPAlertRequest) {
        pending.append(request)
        drain()
    }

    func resume() { drain() }

    private func drain() {
        guard active == nil, !isDelivering, !isWaitingForTransition, !isDisconnected,
              let window, !window.isHidden, window.windowScene?.activationState == .foregroundActive,
              let root = window.rootViewController, !pending.isEmpty else { return }
        if let request = pending.first, request.hasExplicitSource, request.sourceWindow !== window {
            pending.removeFirst()
            complete(request, index: request.cancelChoice?.id, text: "")
            return
        }
        let presenter = visibleController(from: root)
        if let transition = presenter.transitionCoordinator {
            isWaitingForTransition = true
            let registered = transition.animate(alongsideTransition: nil) { [weak self] _ in
                self?.isWaitingForTransition = false
                self?.drain()
            }
            if registered { return }
            isWaitingForTransition = false
        }
        guard presenter.viewIfLoaded?.window === window else { return }
        let request = pending.removeFirst()
        let host = PPAlertHostingController(request: request)
        request.choose = { [weak self] index in self?.finish(index: index) }
        host.didLeave = { [weak self, weak host] in
            guard let self, self.active === host else { return }
            self.finishUnexpectedDismissal()
        }
        previousFocus = UIAccessibility.focusedElement(using: .notificationVoiceOver) as AnyObject?
        active = host
        presenter.present(host, animated: true)
    }

    private func visibleController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            // Wait for its dismissal transition instead of racing the parent.
            return visibleController(from: presented)
        }
        if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController {
            return visibleController(from: visible)
        }
        if let tabs = controller as? UITabBarController, let selected = tabs.selectedViewController {
            return visibleController(from: selected)
        }
        return controller
    }

    private func finish(index: Int) {
        guard let host = active, !host.request.isFinishing,
              host.request.actions.contains(where: { $0.id == index }) else { return }
        let request = host.request
        request.isFinishing = true
        // Snapshot before resigning focus: cancellation uses the action's role,
        // never an empty-string heuristic. Secure text is never logged/stored.
        let text = request.isInput ? request.text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        host.view.endEditing(true)
        UISelectionFeedbackGenerator().selectionChanged()
        // Retain the lane until UIKit finishes, including scene disconnection.
        host.dismiss(animated: true) {
            self.complete(request, index: index, text: text)
        }
    }

    private func complete(_ request: PPAlertRequest, index: Int?, text: String) {
        active = nil
        request.choose = nil
        if pending.isEmpty, let previousFocus {
            UIAccessibility.post(notification: .screenChanged, argument: previousFocus)
        }
        previousFocus = nil
        isDelivering = true
        if let index { request.selection(index, text) }
        isDelivering = false
        drain()
    }

    private func finishUnexpectedDismissal() {
        guard let request = active?.request, !request.isFinishing else { return }
        request.isFinishing = true
        complete(request, index: request.cancelChoice?.id, text: "")
    }

    func cancelForDisconnectedScene() {
        isDisconnected = true
        let queued = pending
        pending.removeAll()
        if let host = active, !host.request.isFinishing {
            let request = host.request
            request.isFinishing = true
            host.dismiss(animated: false) {
                self.complete(request, index: request.cancelChoice?.id, text: "")
            }
        }
        // A scene closing must never synthesize a confirm/destructive action.
        for request in queued {
            if let cancel = request.cancelChoice { request.selection(cancel.id, "") }
        }
    }
}

@MainActor
private final class PPAlertHostingController: UIHostingController<PPAlertSurface> {
    let request: PPAlertRequest
    var didLeave: (() -> Void)?

    init(request: PPAlertRequest) {
        self.request = request
        super.init(rootView: PPAlertSurface(request: request))
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        isModalInPresentation = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(request:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        request.isReady = true
        becomeFirstResponder()
        let feedback = UINotificationFeedbackGenerator()
        switch request.type {
        case 0: feedback.notificationOccurred(.success)
        case 1: feedback.notificationOccurred(.error)
        case 2: feedback.notificationOccurred(.warning)
        default: break
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        request.isReady = false
        if isBeingDismissed || presentingViewController == nil { didLeave?() }
    }

    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []
        if request.cancelChoice != nil {
            commands.append(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancel)))
        }
        if request.defaultChoice != nil {
            commands.append(UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(confirm)))
        }
        return commands
    }

    @objc private func cancel() {
        if let choice = request.cancelChoice { request.choose?(choice.id) }
    }
    @objc private func confirm() {
        if let choice = request.defaultChoice { request.choose?(choice.id) }
    }
    override func accessibilityPerformEscape() -> Bool {
        guard request.cancelChoice != nil else { return false }
        cancel()
        return true
    }
}

// The decision surface: an asymmetric status signature and reading column,
// with an adaptive action shelf. All content can scroll at AX5, including
// actions, and the keyboard's safe area remains owned by SwiftUI.
private struct PPAlertSurface: View {
    @ObservedObject var request: PPAlertRequest
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var inputFocused: Bool
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let margin: CGFloat = geometry.size.width < 360 ? 16 : 24
            let wide = geometry.size.width >= 600
            ZStack {
                Color.black.opacity(0.36)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { cancelIfAllowed() }
                    .accessibilityHidden(true)
                decisionSurface(padding: margin)
                    .frame(maxWidth: wide ? 520 : 440)
                    .frame(maxHeight: max(0, geometry.size.height - margin * 2),
                           alignment: wide ? .center : .bottom)
                    .padding(margin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: wide ? .center : .bottom)
            }
        }
        .environment(\.layoutDirection, request.isRTL ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: request.languageCode))
        .onChange(of: request.isReady) { _, ready in
            if ready {
                if UIAccessibility.isVoiceOverRunning { headingFocused = true }
                else if request.isInput { inputFocused = true }
            } else { inputFocused = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name(PPLanguageDidChangeNotification))) { _ in
            request.languageCode = Language.currentLanguageCode()
        }
        .onChange(of: request.isFinishing) { _, finishing in
            if finishing { inputFocused = false }
        }
        .onDisappear { inputFocused = false }
    }

    private func decisionSurface(padding: CGFloat) -> some View {
        ViewThatFits(in: .vertical) {
            content(padding: padding)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) {
                content(padding: padding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(uiColor: .ppElevatedSurface))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: Color(uiColor: .ppShadow).opacity(0.16), radius: 24, x: 0, y: 12)
        .disabled(request.isFinishing)
        .accessibilityIdentifier("pp.alert.surface")
    }

    private func content(padding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                statusSignature
                    Text(verbatim: request.title.isEmpty ? request.semanticTitle : request.title)
                        .font(PPBrandFont.bold(30, relativeTo: .title))
                        .foregroundStyle(Color(uiColor: .ppTextPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)
                if !request.subtitle.isEmpty {
                    Text(verbatim: request.subtitle)
                        .font(PPBrandFont.regular(18, relativeTo: .body))
                        .foregroundStyle(Color(uiColor: .ppTextSecondary))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if request.isInput { inputSurface }
            }
            Rectangle()
                .fill(Color(uiColor: .ppSeparator))
                .frame(height: 1)
                .accessibilityHidden(true)
            actionShelf
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusSignature: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = request.icon {
                    Image(uiImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: request.symbol).font(.system(size: 21, weight: .semibold))
                }
            }
            .foregroundStyle(request.accent)
            .frame(width: 24, height: 24)
            .frame(width: 44, height: 44)
            .background(request.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)
            Text(verbatim: request.semanticTitle)
                .font(PPBrandFont.medium(16, relativeTo: .subheadline))
                .foregroundStyle(Color(uiColor: .ppTextPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .accessibilityHidden(request.title.isEmpty)
            Spacer(minLength: 0)
        }
    }

    private var inputSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Visible label survives once the placeholder disappears.
            Text(verbatim: request.inputLabel)
                .font(PPBrandFont.medium(15, relativeTo: .subheadline))
                .foregroundStyle(Color(uiColor: .ppTextSecondary))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Group {
                if request.secureEntry {
                    SecureField("", text: $request.text)
                        .textContentType(.password)
                } else {
                    TextField("", text: $request.text)
                }
            }
            .font(PPBrandFont.regular(19, relativeTo: .body))
            .foregroundStyle(Color(uiColor: .ppTextPrimary))
            .keyboardType(request.keyboardType)
            .textInputAutocapitalization(request.secureEntry || request.usesLTRInput ? .never : .sentences)
            .autocorrectionDisabled(request.secureEntry || request.usesLTRInput)
            .submitLabel(.done)
            .focused($inputFocused)
            .onSubmit { confirmDefault() }
            .multilineTextAlignment(.leading)
            .environment(\.layoutDirection, request.usesLTRInput ? .leftToRight : (request.isRTL ? .rightToLeft : .leftToRight))
            .padding(16)
            .frame(minHeight: 56)
            .background(Color(uiColor: .ppBackgroundSecondary), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(inputFocused ? Color(uiColor: .ppAccentText) : Color(uiColor: .ppTextSecondary),
                                  lineWidth: inputFocused ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel(request.inputLabel)
            .accessibilityIdentifier("pp.alert.input")
        }
    }

    @ViewBuilder private var actionShelf: some View {
        if request.actions.count == 2 && !dynamicType.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    ForEach(request.actions) { choice in
                        actionButton(choice).fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                stackedActions
            }
        } else { stackedActions }
    }

    private var stackedActions: some View {
        VStack(spacing: 10) {
            ForEach(request.actions) { actionButton($0) }
        }
    }

    private func actionButton(_ choice: PPAlertChoice) -> some View {
        Button(role: choice.isCancel ? .cancel : (choice.isDestructive ? .destructive : nil)) {
            request.choose?(choice.id)
        } label: {
            Text(verbatim: choice.title)
                .font(PPBrandFont.bold(18, relativeTo: .headline))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PPAlertButtonStyle(prominent: choice.isProminent, destructive: choice.isDestructive,
                                       reduceMotion: reduceMotion))
        .accessibilityIdentifier("pp.alert.action.\(choice.id)")
    }

    private func cancelIfAllowed() {
        if let choice = request.cancelChoice { request.choose?(choice.id) }
    }
    private func confirmDefault() {
        if let choice = request.defaultChoice { request.choose?(choice.id) }
    }
}

private struct PPAlertButtonStyle: ButtonStyle {
    let prominent: Bool
    let destructive: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fill = destructive ? Color(uiColor: .ppError) : Color(uiColor: .ppBrandPrimary)
        configuration.label
            .foregroundStyle(prominent ? Color.white : Color(uiColor: .ppTextPrimary))
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent ? fill : Color(uiColor: .ppBackgroundSecondary))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.09 : 0))
                    .allowsHitTesting(false)
            }
            // Immediate, bounded pressure feedback; no entrance choreography,
            // delayed actions, repeating animation, or keyboard-driven motion.
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
    }
}
