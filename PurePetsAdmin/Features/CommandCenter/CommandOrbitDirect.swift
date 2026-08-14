import Combine
import SwiftUI
import UIKit

// MARK: - Objective-C presentation bridge

/// A presentation-only value supplied by `AdminDashboardViewController`.
/// The Objective-C dashboard remains the single owner of permissions, Firebase
/// listeners, priority computation, and the concrete destination route.
@objcMembers
public final class AdminCommandOrbitSignalDescriptor: NSObject {
    public var identifier = ""
    public var moduleTitle = ""
    public var title = ""
    public var detail = ""
    public var symbolName = "square.grid.2x2"
    public var urgency = 0
    public var count = 0
    public var isLive = false
}

/// Hosts the presentation-only command center. It intentionally has one input
/// (`applyRoleName`) and one output (`onRoute`): it does not observe Firebase,
/// inspect permissions, own session state, or create navigation routes.
@objcMembers
public final class AdminCommandOrbitHostingController: UIViewController {
    public var onRoute: ((String) -> Void)?

    private let store = AdminCommandOrbitStore()
    private var hostingController: UIHostingController<AdminCommandOrbitDirectView>?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage()

        let root = AdminCommandOrbitDirectView(store: store) { [weak self] tag in
            self?.onRoute?(tag)
        }
        let hostingController = UIHostingController(rootView: root)
        hostingController.view.backgroundColor = .clear
        hostingController.view.semanticContentAttribute = view.semanticContentAttribute

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange(_:)),
            name: Notification.Name("LanguageDidChangeNotification"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func applyRoleName(
        _ roleName: String,
        capabilityCount: Int,
        signals rawSignals: [AdminCommandOrbitSignalDescriptor],
        animated: Bool
    ) {
        var seenIdentifiers = Set<String>()
        var signals: [AdminCommandOrbitSignal] = []
        for descriptor in rawSignals {
            let signal = AdminCommandOrbitSignal(descriptor)
            guard !signal.id.isEmpty, seenIdentifiers.insert(signal.id).inserted else { continue }
            signals.append(signal)
            if signals.count == 6 { break }
        }
        let snapshot = AdminCommandOrbitSnapshot(
            roleName: roleName,
            capabilityCount: max(0, capabilityCount),
            isRTL: Language.isRTL(),
            signals: signals
        )
        store.apply(snapshot, animated: animated && !UIAccessibility.isReduceMotionEnabled)
        applyCurrentLanguageDirection()
    }

    @objc private func languageDidChange(_ notification: Notification) {
        _ = notification
        store.refreshLanguage()
        applyCurrentLanguageDirection()
    }

    private func applyCurrentLanguageDirection() {
        let direction = Language.semanticAttributeForCurrentLanguage()
        view.semanticContentAttribute = direction
        hostingController?.view.semanticContentAttribute = direction
    }
}

// MARK: - Presentation state

private struct AdminCommandOrbitSignal: Identifiable, Equatable {
    enum Priority: Int, Comparable {
        case normal
        case elevated
        case critical

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var localizationKey: String {
            switch self {
            case .normal: return "AdminCommandOrbit_Priority_Normal"
            case .elevated: return "AdminCommandOrbit_Priority_Elevated"
            case .critical: return "AdminCommandOrbit_Priority_Critical"
            }
        }
    }

    let id: String
    let moduleTitle: String
    let title: String
    let detail: String
    let symbolName: String
    let urgency: Int
    let count: Int
    let isLive: Bool

    init(_ descriptor: AdminCommandOrbitSignalDescriptor) {
        id = descriptor.identifier
        moduleTitle = descriptor.moduleTitle
        title = descriptor.title
        detail = descriptor.detail
        symbolName = descriptor.symbolName
        urgency = max(0, min(100, descriptor.urgency))
        count = max(0, descriptor.count)
        isLive = descriptor.isLive
    }

    var priority: Priority {
        if urgency >= 90 { return .critical }
        if urgency >= 60 { return .elevated }
        return .normal
    }

    var tint: Color {
        switch priority {
        case .critical:
            return Color(uiColor: .ppError)
        case .elevated:
            return Color(uiColor: .ppWarning)
        case .normal:
            return isLive ? Color(uiColor: .ppInfo) : AdminSurface.primary
        }
    }
}

private struct AdminCommandOrbitSnapshot: Equatable {
    let roleName: String
    let capabilityCount: Int
    let isRTL: Bool
    let signals: [AdminCommandOrbitSignal]

    static let empty = AdminCommandOrbitSnapshot(
        roleName: "",
        capabilityCount: 0,
        isRTL: false,
        signals: []
    )

    var dominantSignal: AdminCommandOrbitSignal? { signals.first }
    var remainingSignals: ArraySlice<AdminCommandOrbitSignal> { signals.dropFirst() }
    var liveCount: Int { signals.filter(\.isLive).count }
    var urgentCount: Int { signals.filter { $0.urgency >= 90 }.count }
}

private struct AdminCommandOrbitPresentation: Equatable {
    let snapshot: AdminCommandOrbitSnapshot
    let changedSignalIDs: Set<String>
    let animatesChanges: Bool
    let languageCode: String
    let revision: Int

    static func empty(languageCode: String) -> AdminCommandOrbitPresentation {
        AdminCommandOrbitPresentation(
            snapshot: .empty,
            changedSignalIDs: [],
            animatesChanges: false,
            languageCode: languageCode,
            revision: 0
        )
    }
}

@MainActor
private final class AdminCommandOrbitStore: ObservableObject {
    @Published private(set) var presentation: AdminCommandOrbitPresentation

    init() {
        presentation = .empty(languageCode: Language.currentLanguageCode())
    }

    func apply(_ snapshot: AdminCommandOrbitSnapshot, animated: Bool) {
        let previous = presentation.snapshot
        let previousSignals = Dictionary(uniqueKeysWithValues: previous.signals.map { ($0.id, $0) })
        var changedSignalIDs = Set(snapshot.signals.compactMap { signal in
            previousSignals[signal.id] == signal ? nil : signal.id
        })
        if previous.dominantSignal?.id != snapshot.dominantSignal?.id,
           let dominantID = snapshot.dominantSignal?.id {
            changedSignalIDs.insert(dominantID)
        }

        publish(
            snapshot: snapshot,
            changedSignalIDs: changedSignalIDs,
            animated: animated && !changedSignalIDs.isEmpty,
            languageCode: Language.currentLanguageCode()
        )
    }

    func refreshLanguage() {
        let current = presentation.snapshot
        let refreshed = AdminCommandOrbitSnapshot(
            roleName: current.roleName,
            capabilityCount: current.capabilityCount,
            isRTL: Language.isRTL(),
            signals: current.signals
        )
        publish(
            snapshot: refreshed,
            changedSignalIDs: [],
            animated: false,
            languageCode: Language.currentLanguageCode()
        )
    }

    private func publish(
        snapshot: AdminCommandOrbitSnapshot,
        changedSignalIDs: Set<String>,
        animated: Bool,
        languageCode: String
    ) {
        let next = AdminCommandOrbitPresentation(
            snapshot: snapshot,
            changedSignalIDs: changedSignalIDs,
            animatesChanges: animated,
            languageCode: languageCode,
            revision: presentation.revision &+ 1
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation = next
        }
    }
}

// MARK: - Priority Handoff

@MainActor
private struct AdminCommandOrbitDirectView: View {
    @ObservedObject var store: AdminCommandOrbitStore
    let onRoute: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var routeActivationID: String?
    @State private var feedbackSignalIDs: Set<String> = []
    @State private var feedbackOpacity = 1.0
    @State private var feedbackCycle = 0
    @State private var isVisible = false
    @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
    @State private var isSwitchControlRunning = UIAccessibility.isSwitchControlRunning

    private var presentation: AdminCommandOrbitPresentation { store.presentation }
    private var snapshot: AdminCommandOrbitSnapshot { presentation.snapshot }
    private var isRTL: Bool {
        presentation.languageCode == "ar" ||
            (presentation.languageCode.isEmpty && snapshot.isRTL)
    }
    private var locale: Locale { Locale(identifier: isRTL ? "ar_QA" : "en_QA") }
    private var usesRegularLayout: Bool {
        horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
    }
    private var usesAssistiveNavigation: Bool {
        isVoiceOverRunning || isSwitchControlRunning
    }
    private var suppressesChangeFeedback: Bool {
        reduceMotion ||
            reduceTransparency ||
            dynamicTypeSize.isAccessibilitySize ||
            isLowPowerModeEnabled ||
            usesAssistiveNavigation
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    contextHeader

                    if snapshot.signals.isEmpty {
                        emptyState
                    } else {
                        priorityContent
                    }

                    AdminPrioritySummaryRail(
                        liveCount: formatted(snapshot.liveCount),
                        urgentCount: formatted(snapshot.urgentCount),
                        capabilityCount: formatted(snapshot.capabilityCount),
                        usesVerticalLayout: dynamicTypeSize.isAccessibilitySize
                    )
                }
                .frame(maxWidth: 1040)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        .environment(\.locale, locale)
        .onAppear {
            isVisible = true
            startChangeFeedbackIfEligible()
        }
        .onDisappear {
            isVisible = false
            cancelChangeFeedback()
            clearRouteActivation()
        }
        .onChange(of: presentation.revision) { _ in
            startChangeFeedbackIfEligible()
        }
        .onChange(of: reduceMotion) { _ in
            if suppressesChangeFeedback { cancelChangeFeedback() }
        }
        .onChange(of: reduceTransparency) { _ in
            if suppressesChangeFeedback { cancelChangeFeedback() }
        }
        .onChange(of: dynamicTypeSize) { _ in
            if suppressesChangeFeedback { cancelChangeFeedback() }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                cancelChangeFeedback()
                clearRouteActivation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            if suppressesChangeFeedback { cancelChangeFeedback() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
            if suppressesChangeFeedback { cancelChangeFeedback() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in
            isSwitchControlRunning = UIAccessibility.isSwitchControlRunning
            if suppressesChangeFeedback { cancelChangeFeedback() }
        }
    }

    @ViewBuilder
    private var contextHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                operationalStatus
                roleContext
            }
        } else {
            HStack(alignment: .top, spacing: 24) {
                operationalStatus
                Spacer(minLength: 16)
                roleContext
            }
        }
    }

    private var operationalStatus: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(overallTint)
                .frame(width: 36, height: 36)
                .background(overallTint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.liveCount > 0 ? L10n("AdminCommandOrbit_Live") : L10n("AdminCommandOrbit_Stable"))
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(orbitStatusTitle)
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilitySortPriority(220)
    }

    private var roleContext: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(L10n("AdminCommandOrbit_Role"))
                .font(AdminType.caption1)
                .foregroundStyle(AdminSurface.secondaryText)
            Text(snapshot.roleName.isEmpty ? L10n("AdminCommandOrbit_Staff") : snapshot.roleName)
                .font(AdminType.calloutBold)
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilitySortPriority(210)
    }

    @ViewBuilder
    private var priorityContent: some View {
        if usesRegularLayout, !snapshot.remainingSignals.isEmpty {
            HStack(alignment: .top, spacing: 24) {
                dominantSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
                remainingSection
                    .frame(maxWidth: 380, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                dominantSection
                if !snapshot.remainingSignals.isEmpty {
                    remainingSection
                }
            }
        }
    }

    private var dominantSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n("AdminCommandOrbit_Primary_Signal"))
                .font(AdminType.captionBold)
                .foregroundStyle(AdminSurface.secondaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(200)

            if let signal = snapshot.dominantSignal {
                AdminPriorityDominantCard(
                    signal: signal,
                    locale: locale,
                    isRTL: isRTL,
                    feedbackOpacity: feedbackOpacity(for: signal.id),
                    isDisabled: routeActivationID != nil,
                    action: { route(signal) }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(200)
    }

    private var remainingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n("AdminCommandOrbit_Remaining_Signals"))
                .font(AdminType.title3)
                .foregroundStyle(AdminSurface.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(200)

            VStack(spacing: 10) {
                ForEach(Array(snapshot.remainingSignals), id: \.id) { signal in
                    AdminPriorityLedgerRow(
                        signal: signal,
                        locale: locale,
                        isRTL: isRTL,
                        feedbackOpacity: feedbackOpacity(for: signal.id),
                        isDisabled: routeActivationID != nil,
                        action: { route(signal) }
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(100)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 48, height: 48)
                .background(AdminSurface.primarySoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            Text(L10n("AdminCommandOrbit_Empty_Title"))
                .font(AdminType.title3)
                .foregroundStyle(AdminSurface.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text(L10n("AdminCommandOrbit_Empty_Detail"))
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilitySortPriority(200)
    }

    private var overallTint: Color {
        if snapshot.urgentCount > 0 { return Color(uiColor: .ppError) }
        if snapshot.liveCount > 0 { return Color(uiColor: .ppInfo) }
        return Color(uiColor: .ppSuccess)
    }

    private var statusSymbol: String {
        if snapshot.urgentCount > 0 { return "exclamationmark.triangle.fill" }
        if snapshot.liveCount > 0 { return "waveform.path.ecg" }
        return "checkmark.circle.fill"
    }

    private var orbitStatusTitle: String {
        if snapshot.signals.isEmpty { return L10n("AdminCommandOrbit_Stable") }
        if snapshot.urgentCount > 0 {
            return String(
                format: L10n("AdminCommandOrbit_Critical_Format"),
                locale: locale,
                snapshot.urgentCount
            )
        }
        return snapshot.liveCount > 0
            ? L10n("AdminCommandOrbit_Active")
            : L10n("AdminCommandOrbit_Stable")
    }

    private func formatted(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    private func feedbackOpacity(for signalID: String) -> Double {
        feedbackSignalIDs.contains(signalID) ? feedbackOpacity : 1
    }

    private func startChangeFeedbackIfEligible() {
        cancelChangeFeedback()
        guard isVisible,
              scenePhase == .active,
              presentation.animatesChanges,
              !presentation.changedSignalIDs.isEmpty,
              !suppressesChangeFeedback else {
            return
        }

        feedbackCycle &+= 1
        let cycle = feedbackCycle
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            feedbackSignalIDs = presentation.changedSignalIDs
            feedbackOpacity = 0.88
        }

        DispatchQueue.main.async { @MainActor in
            guard self.feedbackCycle == cycle else { return }
            guard self.isVisible,
                  self.scenePhase == .active,
                  !self.suppressesChangeFeedback else {
                self.cancelChangeFeedback()
                return
            }
            withAnimation(.easeOut(duration: 0.12)) {
                self.feedbackOpacity = 1
            }
        }
    }

    private func cancelChangeFeedback() {
        feedbackCycle &+= 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            feedbackSignalIDs.removeAll()
            feedbackOpacity = 1
        }
    }

    private func route(_ signal: AdminCommandOrbitSignal) {
        guard routeActivationID == nil, !signal.id.isEmpty else { return }
        cancelChangeFeedback()

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            routeActivationID = signal.id
        }
        onRoute(signal.id)

        DispatchQueue.main.async { @MainActor in
            guard self.routeActivationID == signal.id else { return }
            self.clearRouteActivation()
        }
    }

    private func clearRouteActivation() {
        guard routeActivationID != nil else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            routeActivationID = nil
        }
    }
}

// MARK: - Priority components

private struct AdminPriorityDominantCard: View {
    let signal: AdminCommandOrbitSignal
    let locale: Locale
    let isRTL: Bool
    let feedbackOpacity: Double
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                identityHeader

                VStack(alignment: .leading, spacing: 7) {
                    Text(signal.title)
                        .font(AdminType.title2)
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !signal.detail.isEmpty {
                        Text(signal.detail)
                            .font(AdminType.body)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                routeFooter
                    .padding(.top, 2)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
                shape.fill(AdminSurface.surface)
                shape.fill(signal.tint.opacity(colorScheme == .dark ? 0.09 : 0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(
                        signal.isLive
                            ? signal.tint.opacity(contrast == .increased ? 1 : 0.48)
                            : AdminSurface.hairline.opacity(contrast == .increased ? 1 : 0.86),
                        lineWidth: contrast == .increased ? 1.6 : 1
                    )
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(signal.tint)
                    .frame(width: contrast == .increased ? 5 : 4)
                    .padding(.vertical, 18)
                    .accessibilityHidden(true)
            }
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(feedbackOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(L10n("AdminCommandOrbit_Route_Hint"))
    }

    @ViewBuilder
    private var identityHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                AdminPrioritySignalIcon(signal: signal, size: 54)
                identityLabels
                countMetric
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                AdminPrioritySignalIcon(signal: signal, size: 54)
                identityLabels
                Spacer(minLength: 10)
                countMetric
            }
        }
    }

    private var identityLabels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(signal.moduleTitle)
                .font(AdminType.captionBold)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n(signal.priority.localizationKey))
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var countMetric: some View {
        if signal.count > 0 {
            Text(signal.count.formatted(.number.locale(locale)))
                .font(AdminType.largeTitle)
                .foregroundStyle(AdminSurface.primaryText)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var routeFooter: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                liveStatus
                routeLabel
            }
        } else {
            HStack(spacing: 8) {
                liveStatus
                Spacer(minLength: 12)
                routeLabel
            }
        }
    }

    @ViewBuilder
    private var liveStatus: some View {
        if signal.isLive {
            HStack(spacing: 8) {
                Circle()
                    .fill(signal.tint)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(L10n("AdminCommandOrbit_Live"))
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primaryText)
            }
        }
    }

    private var routeLabel: some View {
        HStack(spacing: 8) {
            Text(String(
                format: L10n("AdminCommand_Open_Format"),
                locale: locale,
                signal.moduleTitle
            ))
                .font(AdminType.calloutBold)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(signal.tint)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityLabel: String {
        [signal.moduleTitle, signal.title]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if signal.count > 0 {
            values.append(signal.count.formatted(.number.locale(locale)))
        }
        if !signal.detail.isEmpty { values.append(signal.detail) }
        values.append(L10n(signal.priority.localizationKey))
        if signal.isLive { values.append(L10n("AdminCommandOrbit_AttentionRequired")) }
        return values.joined(separator: ". ")
    }
}

private struct AdminPriorityLedgerRow: View {
    let signal: AdminCommandOrbitSignal
    let locale: Locale
    let isRTL: Bool
    let feedbackOpacity: Double
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            rowContent
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                shape.fill(AdminSurface.surface)
                if signal.isLive {
                    shape.fill(signal.tint.opacity(colorScheme == .dark ? 0.08 : 0.035))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        signal.isLive
                            ? signal.tint.opacity(contrast == .increased ? 1 : 0.36)
                            : AdminSurface.hairline.opacity(contrast == .increased ? 1 : 0.82),
                        lineWidth: contrast == .increased ? 1.5 : 1
                    )
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(signal.tint)
                    .frame(width: contrast == .increased ? 4 : 3)
                    .padding(.vertical, 14)
                    .accessibilityHidden(true)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(feedbackOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(L10n("AdminCommandOrbit_Route_Hint"))
    }

    @ViewBuilder
    private var rowContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                AdminPrioritySignalIcon(signal: signal, size: 44)
                signalText
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    countMetric
                    Spacer(minLength: 8)
                    routeLabel
                }
            }
        } else {
            HStack(alignment: .top, spacing: 13) {
                AdminPrioritySignalIcon(signal: signal, size: 44)
                signalText
                Spacer(minLength: 8)
                compactTrailing
            }
        }
    }

    private var signalText: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(signal.moduleTitle)
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if signal.isLive {
                    Text(L10n("AdminCommandOrbit_Live"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }

            Text(signal.title)
                .font(AdminType.calloutBold)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !signal.detail.isEmpty {
                Text(signal.detail)
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var countMetric: some View {
        if signal.count > 0 {
            Text(signal.count.formatted(.number.locale(locale)))
                .font(AdminType.title3)
                .foregroundStyle(AdminSurface.primaryText)
                .monospacedDigit()
        }
    }

    private var compactTrailing: some View {
        VStack(alignment: .trailing, spacing: 8) {
            countMetric
            Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(signal.tint)
                .accessibilityHidden(true)
        }
    }

    private var routeLabel: some View {
        HStack(spacing: 8) {
            Text(String(
                format: L10n("AdminCommand_Open_Format"),
                locale: locale,
                signal.moduleTitle
            ))
                .font(AdminType.calloutBold)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(signal.tint)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityLabel: String {
        [signal.moduleTitle, signal.title]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if signal.count > 0 {
            values.append(signal.count.formatted(.number.locale(locale)))
        }
        if !signal.detail.isEmpty { values.append(signal.detail) }
        values.append(L10n(signal.priority.localizationKey))
        if signal.isLive { values.append(L10n("AdminCommandOrbit_AttentionRequired")) }
        return values.joined(separator: ". ")
    }
}

private struct AdminPrioritySignalIcon: View {
    let signal: AdminCommandOrbitSignal
    let size: CGFloat

    var body: some View {
        Image(systemName: signal.symbolName)
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(AdminSurface.primaryText)
            .frame(width: size, height: size)
            .background(signal.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: size * 0.31, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                    .stroke(signal.tint.opacity(0.20), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

private struct AdminPrioritySummaryRail: View {
    let liveCount: String
    let urgentCount: String
    let capabilityCount: String
    let usesVerticalLayout: Bool

    var body: some View {
        Group {
            if usesVerticalLayout {
                VStack(spacing: 12) {
                    metric(value: liveCount, title: L10n("AdminCommandOrbit_Rail_Priorities"))
                    Divider().overlay(AdminSurface.hairline)
                    metric(value: urgentCount, title: L10n("AdminCommandOrbit_Rail_Urgent"))
                    Divider().overlay(AdminSurface.hairline)
                    metric(value: capabilityCount, title: L10n("AdminCommandOrbit_Rail_Authorized"))
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    metric(value: liveCount, title: L10n("AdminCommandOrbit_Rail_Priorities"))
                    Divider().overlay(AdminSurface.hairline).padding(.vertical, 5)
                    metric(value: urgentCount, title: L10n("AdminCommandOrbit_Rail_Urgent"))
                    Divider().overlay(AdminSurface.hairline).padding(.vertical, 5)
                    metric(value: capabilityCount, title: L10n("AdminCommandOrbit_Rail_Authorized"))
                }
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func metric(value: String, title: String) -> some View {
        Group {
            if usesVerticalLayout {
                VStack(alignment: .leading, spacing: 4) {
                    metricValue(value)
                    metricTitle(title)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    metricValue(value)
                    metricTitle(title)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }

    private func metricValue(_ value: String) -> some View {
        Text(value)
            .font(AdminType.title3)
            .foregroundStyle(AdminSurface.primaryText)
            .monospacedDigit()
    }

    private func metricTitle(_ title: String) -> some View {
        Text(title)
            .font(AdminType.caption1)
            .foregroundStyle(AdminSurface.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func L10n(_ key: String) -> String {
    Language.get(key, alter: nil)
}
