//
//  AdminCommandCenterScreen.swift
//  PurePetsAdmin
//
//  SwiftyMax NextGen V6 redesign of the Admin command surface.
//  The Objective-C bridge, route identifiers, permissions, and live feed owners
//  remain unchanged; this file owns presentation only.
//

import SwiftUI
import Combine
import UIKit
import Firebase
@preconcurrency import FirebaseFirestore
import FirebaseAuth

// MARK: - Bridge Descriptor (Preserved Obj-C Contract)

/// A presentation-only value supplied by the Objective-C backend
/// (`AdminDashboardViewController`). Field names and types are frozen.
@objc public class AdminCommandOrbitSignalDescriptor: NSObject {
    @objc public var identifier: String = ""
    @objc public var moduleTitle: String = ""
    @objc public var title: String = ""
    @objc public var detail: String = ""
    @objc public var symbolName: String = "square.grid.2x2"
    @objc public var urgency: Int = 0
    @objc public var count: Int = 0
    @objc public var isLive: Bool = false
}

// MARK: - Internal Domain Models

struct AdminCommandOrbitSignal: Identifiable, Hashable {
    let id: String
    let moduleTitle: String
    let title: String
    let detail: String
    let symbolName: String
    let urgency: Int
    let count: Int
    let isLive: Bool

    var isAttentionBearing: Bool {
        count > 0 || isLive || urgency >= 80
    }

    fileprivate var tier: AdminCommandPriorityTier {
        if urgency >= 90 || urgency == 2 { return .critical }
        if urgency >= 50 || urgency == 1 { return .elevated }
        return isAttentionBearing ? .watch : .ready
    }
}

struct AdminCommandOrbitReadiness: Equatable {
    let loadingAreas: [String]
    let failedAreas: [String]
    let updatedAt: Date?
}

struct AdminCommandOrbitSnapshot: Equatable {
    var signals: [AdminCommandOrbitSignal]
    var displayName: String
    var avatarURL: String
    var roleName: String
    var capabilityCount: Int
    var isInitialized: Bool

    static let empty = AdminCommandOrbitSnapshot(
        signals: [],
        displayName: "",
        avatarURL: "",
        roleName: "",
        capabilityCount: 0,
        isInitialized: false
    )
}

enum AdminCommandOrbitPhase: Equatable {
    case connecting
    case loading
    case ready
    case allClear
    case degradedEmpty
    case denied
}

fileprivate enum AdminCommandPriorityTier: Int, Comparable {
    case critical = 0
    case elevated = 1
    case watch = 2
    case ready = 3

    static func < (lhs: AdminCommandPriorityTier, rhs: AdminCommandPriorityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var tone: AdminCommandTone {
        switch self {
        case .critical: return .critical
        case .elevated: return .elevated
        case .watch: return .info
        case .ready: return .stable
        }
    }

    var localizedLabel: String {
        switch self {
        case .critical: return Language.get("AdminCommandCenter_Priority_Critical", alter: nil)
        case .elevated: return Language.get("AdminCommandCenter_Priority_Elevated", alter: nil)
        case .watch: return Language.get("AdminCommandCenter_Priority_Watch", alter: nil)
        case .ready: return Language.get("AdminCommandCenter_Priority_Normal", alter: nil)
        }
    }
}

// MARK: - Observable Store

@MainActor
final class AdminCommandCenterStore: ObservableObject {
    @Published var snapshot: AdminCommandOrbitSnapshot = .empty
    @Published var readiness: AdminCommandOrbitReadiness = .init(loadingAreas: [], failedAreas: [], updatedAt: nil)
    @Published var localeCode: String = Language.currentLanguageCode()
    @Published private(set) var canAccessHotel = false
    @Published private(set) var canOpenWantedPets = false
    @Published private(set) var revision: Int = 0

    var onRoute: ((String) -> Void)?
    var onRefresh: (() -> Void)?
    var onRequestLogout: (() -> Void)?
    var onToggleLanguage: (() -> Void)?
    var onSelectTab: ((Int) -> Void)?

    func apply(
        displayName: String?,
        avatarURL: String?,
        roleName: String?,
        capabilityCount: Int,
        signals: [AdminCommandOrbitSignalDescriptor],
        animated: Bool
    ) {
        let mapped = signals.prefix(6).map { descriptor in
            AdminCommandOrbitSignal(
                id: descriptor.identifier,
                moduleTitle: descriptor.moduleTitle,
                title: descriptor.title,
                detail: descriptor.detail,
                symbolName: descriptor.symbolName.isEmpty ? "square.grid.2x2" : descriptor.symbolName,
                urgency: descriptor.urgency,
                count: descriptor.count,
                isLive: descriptor.isLive
            )
        }
        let nextSnapshot = AdminCommandOrbitSnapshot(
            signals: mapped,
            displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            avatarURL: avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            roleName: roleName ?? "",
            capabilityCount: capabilityCount,
            isInitialized: true
        )

        let change = {
            self.snapshot = nextSnapshot
            self.revision += 1
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            withAnimation(.easeOut(duration: 0.18)) {
                change()
            }
        } else {
            change()
        }
    }

    func applyReadiness(loadingAreas: [String], failedAreas: [String], updatedAt: Date?) {
        let nextReadiness = AdminCommandOrbitReadiness(
            loadingAreas: loadingAreas,
            failedAreas: failedAreas,
            updatedAt: updatedAt
        )
        let change = {
            self.readiness = nextReadiness
            self.revision += 1
        }
        if UIAccessibility.isReduceMotionEnabled {
            change()
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                change()
            }
        }
    }

    func applyHotelAccess(_ allowed: Bool) {
        guard canAccessHotel != allowed else { return }
        canAccessHotel = allowed
        revision += 1
    }

    func applyWantedPetsAccess(_ allowed: Bool) {
        guard canOpenWantedPets != allowed else { return }
        canOpenWantedPets = allowed
        revision += 1
    }
}

// MARK: - Hosting Controller (Preserved Obj-C Bridge)

@MainActor
@objcMembers
public final class AdminCommandOrbitHostingController: UIViewController {

    public var onRoute: ((String) -> Void)? {
        didSet { store.onRoute = onRoute }
    }
    public var onRefresh: (() -> Void)? {
        didSet { store.onRefresh = onRefresh }
    }
    public var onRequestLogout: (() -> Void)? {
        didSet { store.onRequestLogout = onRequestLogout }
    }
    public var onToggleLanguage: (() -> Void)? {
        didSet { store.onToggleLanguage = onToggleLanguage }
    }
    public var onSelectTab: ((Int) -> Void)? {
        didSet { store.onSelectTab = onSelectTab }
    }

    let store: AdminCommandCenterStore
    private var hostingController: UIHostingController<AdminCommandCenterScreenView>?

    public init() {
        let store = AdminCommandCenterStore()
        store.localeCode = Language.currentLanguageCode()
        self.store = store
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true

        let root = AdminCommandCenterScreenView(store: store)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configureScrollViews(in: view)
        hostingController?.view.frame = view.bounds
        hostingController?.view.setNeedsLayout()
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self = self else { return }
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
            self.hostingController?.view.frame = CGRect(origin: .zero, size: size)
            self.hostingController?.view.setNeedsLayout()
            self.hostingController?.view.layoutIfNeeded()
        }) { [weak self] _ in
            guard let self = self else { return }
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
            self.hostingController?.view.frame = self.view.bounds
            self.hostingController?.view.setNeedsLayout()
            self.hostingController?.view.layoutIfNeeded()
        }
    }

    private func configureScrollViews(in container: UIView) {
        for subview in container.subviews {
            if let scrollView = subview as? UIScrollView {
                scrollView.delaysContentTouches = false
                scrollView.canCancelContentTouches = true
            }
            configureScrollViews(in: subview)
        }
    }

    public func applyIdentityDisplayName(
        _ displayName: String?,
        avatarURL: String?,
        roleName: String?,
        capabilityCount: Int,
        signals: [AdminCommandOrbitSignalDescriptor],
        animated: Bool
    ) {
        store.apply(
            displayName: displayName,
            avatarURL: avatarURL,
            roleName: roleName,
            capabilityCount: capabilityCount,
            signals: signals,
            animated: animated
        )
    }

    /// Compatibility seam for existing Objective-C callers that do not supply
    /// profile presentation data. It preserves the latest known identity.
    public func applyRoleName(_ roleName: String?, capabilityCount: Int, signals: [AdminCommandOrbitSignalDescriptor], animated: Bool) {
        applyIdentityDisplayName(
            store.snapshot.displayName,
            avatarURL: store.snapshot.avatarURL,
            roleName: roleName,
            capabilityCount: capabilityCount,
            signals: signals,
            animated: animated
        )
    }

    public func applyReadinessWithLoadingAreas(_ loadingAreas: [String], failedAreas: [String], updatedAt: Date?) {
        store.applyReadiness(loadingAreas: loadingAreas, failedAreas: failedAreas, updatedAt: updatedAt)
    }

    public func applyHotelAccess(_ allowed: Bool) {
        store.applyHotelAccess(allowed)
    }

    public func applyWantedPetsAccess(_ allowed: Bool) {
        store.applyWantedPetsAccess(allowed)
    }

}

// MARK: - Command Center Presentation

private enum AdminCommandMetric {
    static let pageMargin: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let surfaceRadius: CGFloat = 22
    static let heroRadius: CGFloat = 26
    static let tightRadius: CGFloat = 14
    static let minimumActionHeight: CGFloat = 52
    static let commandBarHeight: CGFloat = 58
    static let commandBarRadius: CGFloat = 18
    static let spineHeight: CGFloat = 12
    static let rowMinimumHeight: CGFloat = 76
    static let tabBarBottomInset: CGFloat = 124
}

private enum AdminCommandTypography {
    static let loadValue = Font.custom("Beiruti-Bold", size: 54, relativeTo: .largeTitle)
    static let decisionTitle = Font.custom("Beiruti-Bold", size: 26, relativeTo: .title)
}

enum AdminCommandInk {
    static let primary = AdminSurface.primaryText.opacity(0.86)
    static let secondary = AdminSurface.primaryText.opacity(0.72)
    static let tertiary = AdminSurface.primaryText.opacity(0.58)
}

private enum AdminCommandTone: Equatable {
    case critical
    case elevated
    case stable
    case info
    case muted

    var color: Color {
        switch self {
        case .critical: return Color(uiColor: .ppPressedAction)
        case .elevated: return AdminSurface.primaryText
        case .stable: return AdminSurface.primaryText
        case .info: return AdminSurface.primaryPressed
        case .muted: return AdminCommandInk.secondary
        }
    }

    var accent: Color {
        switch self {
        case .critical: return Color(uiColor: .ppPressedAction)
        case .elevated: return Color(uiColor: .ppWarning)
        case .stable: return Color(uiColor: .ppSuccess)
        case .info: return AdminSurface.primary
        case .muted: return AdminCommandInk.tertiary
        }
    }

    var softFill: Color {
        switch self {
        case .critical: return Color(uiColor: .ppSoftRose)
        case .elevated: return Color(uiColor: .ppMineralBeige)
        case .stable: return Color(uiColor: .ppQuietLilac)
        case .info: return Color(uiColor: .ppSoftRose)
        case .muted: return AdminSurface.control
        }
    }

    var actionFill: Color {
        switch self {
        case .critical: return Color(uiColor: .ppPressedAction)
        default: return AdminSurface.primaryPressed
        }
    }

    var symbol: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .elevated: return "exclamationmark.circle.fill"
        case .stable: return "checkmark.shield.fill"
        case .info: return "arrow.triangle.2.circlepath"
        case .muted: return "shield"
        }
    }
}

private struct CommandSoftSurfaceModifier: ViewModifier {
    let radius: CGFloat
    let fill: Color
    let borderOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AdminSurface.hairline.opacity(borderOpacity), lineWidth: 1)
            }
    }
}

private extension View {
    func commandSoftSurface(
        radius: CGFloat = AdminCommandMetric.surfaceRadius,
        fill: Color = AdminSurface.surface,
        borderOpacity: Double = 0.72
    ) -> some View {
        modifier(CommandSoftSurfaceModifier(radius: radius, fill: fill, borderOpacity: borderOpacity))
    }
}

private struct AdminCommandSituation: Equatable {
    let tone: AdminCommandTone
    let title: String
    let detail: String
    let badge: String
    let symbol: String
    let showsProgress: Bool
}

// MARK: - Screen Entrance Choreography

private struct CommandSectionEntranceModifier: ViewModifier {
    let index: Int
    let isAppeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isAppeared ? 1.0 : 0.0)
            .offset(y: reduceMotion || isAppeared ? 0 : 28)
            .scaleEffect(reduceMotion || isAppeared ? 1.0 : 0.968, anchor: .center)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.20)
                    : .spring(response: 0.52, dampingFraction: 0.82)
                        .delay(Double(index) * 0.055),
                value: isAppeared
            )
    }
}

private struct CommandHeaderEntranceModifier: ViewModifier {
    let isAppeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isAppeared ? 1.0 : 0.0)
            .offset(y: reduceMotion || isAppeared ? 0 : -12)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.20)
                    : .spring(response: 0.48, dampingFraction: 0.84),
                value: isAppeared
            )
    }
}

extension View {
    fileprivate func commandSectionEntrance(
        index: Int,
        isAppeared: Bool,
        reduceMotion: Bool
    ) -> some View {
        modifier(CommandSectionEntranceModifier(
            index: index,
            isAppeared: isAppeared,
            reduceMotion: reduceMotion
        ))
    }

    fileprivate func commandHeaderEntrance(
        isAppeared: Bool,
        reduceMotion: Bool
    ) -> some View {
        modifier(CommandHeaderEntranceModifier(
            isAppeared: isAppeared,
            reduceMotion: reduceMotion
        ))
    }
}

struct AdminCommandCenterScreenView: View {
    @ObservedObject var store: AdminCommandCenterStore
    @ObservedObject private var branchContext = BranchContextStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingSourceIssueDetails = false
    @State private var isReplacingBranchData = false
    @State private var isShowingBranchSelection = false
    @State private var sectionsAppeared = true

    private var locale: Locale {
        Locale(identifier: store.localeCode == "ar" ? "ar_QA" : "en_QA")
    }

    private var direction: LayoutDirection {
        store.localeCode == "ar" ? .rightToLeft : .leftToRight
    }

    private var phase: AdminCommandOrbitPhase {
        let snapshot = store.snapshot
        if isReplacingBranchData { return .loading }
        if !snapshot.isInitialized { return .connecting }
        if snapshot.roleName.isEmpty { return .denied }
        if !store.readiness.loadingAreas.isEmpty,
           snapshot.signals.isEmpty,
           store.readiness.failedAreas.isEmpty {
            return .loading
        }
        if !store.readiness.failedAreas.isEmpty, snapshot.signals.isEmpty {
            return .degradedEmpty
        }
        if snapshot.signals.isEmpty { return .allClear }
        return .ready
    }

    var body: some View {
        GeometryReader { geometry in
            let safeTop = max(geometry.safeAreaInsets.top, PPStatusBarHelper.statusBarHeight, 44)
            let isRegular = geometry.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize
            let isLandscape = geometry.size.width > geometry.size.height
            let ipadMaxWidth: CGFloat = 1160
            let heroInset = AdminCommandMetric.pageMargin
            let contentAvailableWidth = max(min(geometry.size.width - 2 * heroInset, isRegular ? min(ipadMaxWidth, geometry.size.width - 2 * heroInset) : geometry.size.width - 2 * heroInset), 320)

            // Large text and compact-height windows need the header to scroll
            // with the existing content, rather than consume its whole viewport.
            let scrollsHeader = dynamicTypeSize.isAccessibilitySize || geometry.size.height < 600

            VStack(spacing: 0) {
                if !scrollsHeader {
                    fixedNavBar(safeTop: safeTop, isRegular: isRegular, containerWidth: contentAvailableWidth)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if scrollsHeader {
                            fixedNavBar(safeTop: safeTop, isRegular: isRegular, containerWidth: contentAvailableWidth)
                        }

                        VStack(alignment: .leading, spacing: AdminSectionSpacing.interSection(isRegular: isRegular)) {
                            phaseContent(isRegular: isRegular, isLandscape: isLandscape, containerWidth: contentAvailableWidth)
                        }
                        .padding(.horizontal, AdminCommandMetric.pageMargin)
                        .padding(.top, AdminSectionSpacing.navBarToFirstSection(isRegular: isRegular))
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom + 88, AdminCommandMetric.tabBarBottomInset))
                        .frame(maxWidth: isRegular ? min(ipadMaxWidth, geometry.size.width) : .infinity)
                        .frame(maxWidth: .infinity)
                    }
                }
                .clipped()
                .scrollBounceBehavior(.always, axes: .vertical)
                .refreshable {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.prepare()
                    impact.impactOccurred()
                    refresh()
                    try? await Task.sleep(nanoseconds: 650_000_000)
                }
            }
            .background(AdminSurface.background.ignoresSafeArea())
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, direction)
        .environment(\.locale, locale)
        .sheet(isPresented: $isShowingBranchSelection) {
            PPBranchSelectionGateView()
                .environment(\.layoutDirection, direction)
                .environment(\.locale, locale)
        }
        .sheet(isPresented: $isShowingSourceIssueDetails) {
            sourceIssueSheet
                .environment(\.layoutDirection, direction)
                .environment(\.locale, locale)
        }
        .onAppear {
            refresh()
            triggerEntranceAnimation()
        }
        .onChange(of: phase) { newPhase in
            if newPhase == .ready || newPhase == .allClear {
                triggerEntranceAnimation()
            }
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: Notification.Name("LanguageDidChangeNotification"))
                .receive(on: RunLoop.main)
        ) { _ in
            store.localeCode = Language.currentLanguageCode()
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSNotification.Name.PPActiveBranchDidChange)
                .receive(on: RunLoop.main)
        ) { _ in
            refresh()
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: Notification.Name("PPAdminCommandAuthorizationDidChangeNotification"))
                .receive(on: RunLoop.main)
        ) { _ in
            refresh()
        }
    }

    private func triggerEntranceAnimation() {
        guard !sectionsAppeared else { return }
        if reduceMotion {
            sectionsAppeared = true
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                sectionsAppeared = true
            }
        }
    }

    private func fixedNavBar(safeTop: CGFloat, isRegular: Bool, containerWidth: CGFloat = 0) -> some View {
        let ipadMaxWidth: CGFloat = 1160
        return CommandCenterChrome(
            displayName: store.snapshot.displayName,
            avatarURL: store.snapshot.avatarURL,
            roleName: roleDisplayName,
            capabilityText: capabilityText,
            readinessText: compactReadinessText,
            readinessTone: readinessTone,
            onReadinessTap: store.readiness.failedAreas.isEmpty ? nil : {
                isShowingSourceIssueDetails = true
            },
            languageTitle: languageToggleTitle,
            onAccount: { route("editMyAccount") },
            onRefresh: { refresh() },
            onLanguage: { store.onToggleLanguage?() },
            onLogout: { store.onRequestLogout?() },
            onSelectBranch: { isShowingBranchSelection = true },
            isRegular: isRegular,
            containerWidth: containerWidth
        )
        .padding(.horizontal, AdminCommandMetric.pageMargin)
        .padding(.top, safeTop)
        .padding(.bottom, 6)
        .frame(maxWidth: isRegular ? min(ipadMaxWidth, containerWidth > 0 ? (containerWidth + 2 * AdminCommandMetric.pageMargin) : ipadMaxWidth) : .infinity)
        .frame(maxWidth: .infinity)
        .zIndex(100)
        .commandHeaderEntrance(isAppeared: sectionsAppeared, reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private var sourceIssueSheet: some View {
        let sheet = CommandSourceIssueSheet(
            sourceNames: localizedAreaNames(store.readiness.failedAreas),
            detail: failedDetail,
            updatedText: updatedText,
            onRetry: refresh
        )

        if #available(iOS 16.0, *) {
            sheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            sheet
        }
    }

    @ViewBuilder
    private func phaseContent(isRegular: Bool, isLandscape: Bool, containerWidth: CGFloat) -> some View {
        switch phase {
        case .connecting:
            EmptyView()
        case .loading:
            EmptyView()
        case .ready, .allClear:
            readyContent(isRegular: isRegular, isLandscape: isLandscape, containerWidth: containerWidth)
        case .degradedEmpty:
            CommandCenterSourcePanel(
                tone: .critical,
                title: L10n("AdminCommandCenter_Offline_Title"),
                detail: failedDetail,
                sourceNames: localizedAreaNames(store.readiness.failedAreas),
                showsProgress: false,
                actionTitle: L10n("AdminCommandCenter_Retry"),
                action: refresh
            )
            .commandSectionEntrance(index: 1, isAppeared: sectionsAppeared, reduceMotion: reduceMotion)
            .onAppear {
                triggerEntranceAnimation()
            }
        case .denied:
            EmptyView()
        }
    }

    private func readyContent(isRegular: Bool, isLandscape: Bool, containerWidth: CGFloat) -> some View {
        let hasHotel = store.canAccessHotel
        return VStack(alignment: .leading, spacing: AdminSectionSpacing.interSection(isRegular: isRegular)) {
            // Deck 1: Sovereign POS Console Station (Fast Sell & POS History)
            CommandPOSDeck(
                isRegular: isRegular,
                isLandscape: isLandscape,
                containerWidth: containerWidth,
                canOpenWantedPets: store.canOpenWantedPets,
                onRoute: { route($0) }
            )
            .commandSectionEntrance(index: 1, isAppeared: sectionsAppeared, reduceMotion: reduceMotion)

            // Deck 2: Sovereign Stock & Catalog Horizon (Accessories, Food & Live Pets)
            CommandStockDeck(
                signals: store.snapshot.signals,
                isRegular: isRegular,
                isLandscape: isLandscape,
                containerWidth: containerWidth,
                onRoute: { route($0) }
            )
            .commandSectionEntrance(index: 2, isAppeared: sectionsAppeared, reduceMotion: reduceMotion)

            // Deck 3: Operations Launchpad & Quick Actions Matrix
            CommandQuickActionsDeck(
                signals: store.snapshot.signals,
                isRegular: isRegular,
                isLandscape: isLandscape,
                containerWidth: containerWidth,
                onRoute: { route($0) }
            )
            .commandSectionEntrance(index: 3, isAppeared: sectionsAppeared, reduceMotion: reduceMotion)

            // Deck 4: Financial & Treasury Horizon (Accounting)
            VStack(alignment: .leading, spacing: AdminSectionSpacing.headerToContent(isRegular: isRegular)) {
                AdminSectionHeader(
                    title: Language.get("AdminAccounting_SectionTitle", alter: "الخزينة والمالية"),
                    subtitle: Language.get("AdminAccounting_SectionDetail", alter: "تتبع مباشر للإيرادات التشغيلية، المصروفات، وصافي الأرباح"),
                    eyebrow: Language.get("AdminAccounting_SectionEyebrow", alter: "المؤشرات المالية"),
                    symbol: "chart.line.uptrend.xyaxis",
                    themeColor: Color(red: 0.05, green: 0.65, blue: 0.95),
                    state: .normal,
                    isRegular: isRegular
                )

                CommandAccountingSovereignCard(
                    onRoute: { route("accounting") }
                )
            }
            .commandSectionEntrance(index: 4, isAppeared: sectionsAppeared, reduceMotion: reduceMotion)

            // Deck 4B: Sovereign Pets Hotel & Boarding Operations
            if hasHotel {
                CommandHotelDeck(
                    isRegular: isRegular,
                    onRoute: { route($0) },
                    onOpenArrivals: {
                        AdminPetsHotelViewModel.shared.selectedTab = .reservations
                        route("hotel")
                    },
                    onOpenDepartures: {
                        AdminPetsHotelViewModel.shared.selectedTab = .guests
                        route("hotel")
                    }
                )
                .commandSectionEntrance(index: 5, isAppeared: sectionsAppeared, reduceMotion: reduceMotion)
            }

            // Deck 5: Panoramic Tactical Operational Beacon
            CommandEscalationHero(
                model: heroModel,
                isRegular: isRegular,
                onPrimary: { signal in route(signal.id) }
            )
            .transition(reduceMotion ? .identity : .opacity)
            .commandSectionEntrance(index: hasHotel ? 6 : 5, isAppeared: sectionsAppeared, reduceMotion: reduceMotion)

            if isRegular && isLandscape && containerWidth >= 950 {
                // Deck 6 & 7: iPad Dual-Wing Base Deck (Priority Runway + Source Ledger) — Landscape ONLY
                HStack(alignment: .top, spacing: 14) {
                    CommandPriorityRunway(
                        title: runwayTitle,
                        detail: runwayDetail,
                        signals: store.snapshot.signals,
                        locale: locale,
                        isRegular: true,
                        action: { route($0.id) }
                    )
                    .frame(maxWidth: .infinity)

                    CommandSourceLedger(
                        title: L10n("AdminCommandCenter_SourceLedger"),
                        detail: L10n("AdminCommandCenter_SourceLedger_Detail"),
                        loadingSources: localizedAreaNames(store.readiness.loadingAreas),
                        failedSources: localizedAreaNames(store.readiness.failedAreas),
                        updatedText: updatedText,
                        isRegular: true
                    )
                    .frame(maxWidth: .infinity)
                }
                .commandSectionEntrance(index: hasHotel ? 7 : 6, isAppeared: sectionsAppeared, reduceMotion: reduceMotion)
            } else {
                // Deck 6 & 7: Portrait iPad & iPhone - stacked vertically so each gets 100% width with zero overflow
                CommandPriorityRunway(
                    title: runwayTitle,
                    detail: runwayDetail,
                    signals: store.snapshot.signals,
                    locale: locale,
                    isRegular: isRegular,
                    action: { route($0.id) }
                )
                .commandSectionEntrance(index: hasHotel ? 7 : 6, isAppeared: sectionsAppeared, reduceMotion: reduceMotion)

                CommandSourceLedger(
                    title: L10n("AdminCommandCenter_SourceLedger"),
                    detail: L10n("AdminCommandCenter_SourceLedger_Detail"),
                    loadingSources: localizedAreaNames(store.readiness.loadingAreas),
                    failedSources: localizedAreaNames(store.readiness.failedAreas),
                    updatedText: updatedText,
                    isRegular: isRegular
                )
                .commandSectionEntrance(index: hasHotel ? 8 : 7, isAppeared: sectionsAppeared, reduceMotion: reduceMotion)
            }
        }
        .onAppear {
            triggerEntranceAnimation()
        }
    }

    private var situation: AdminCommandSituation {
        switch phase {
        case .connecting:
            return AdminCommandSituation(
                tone: .info,
                title: L10n("AdminCommandCenter_Connecting"),
                detail: L10n("AdminCommandCenter_Connecting_Detail"),
                badge: L10n("AdminCommandOrbit_Connecting_Badge"),
                symbol: "antenna.radiowaves.left.and.right",
                showsProgress: true
            )
        case .loading:
            return AdminCommandSituation(
                tone: .info,
                title: L10n("AdminCommandCenter_Confirming"),
                detail: confirmingDetail,
                badge: L10n("AdminCommandCenter_LoadingSources"),
                symbol: "arrow.triangle.2.circlepath",
                showsProgress: true
            )
        case .ready:
            if totalAttentionCount > 0 {
                return AdminCommandSituation(
                    tone: highestTone,
                    title: L10n("CommandCenter_Health_Attention"),
                    detail: String(format: L10n("CommandCenter_Health_Attention_Format"), formattedCount(totalAttentionCount)),
                    badge: L10n("AdminCommandCenter_LiveSystem"),
                    symbol: highestTone.symbol,
                    showsProgress: false
                )
            }
            return AdminCommandSituation(
                tone: .stable,
                title: L10n("CommandCenter_Health_Stable"),
                detail: L10n("CommandCenter_Health_Stable_Detail"),
                badge: L10n("AdminCommandCenter_LiveSystem"),
                symbol: "checkmark.shield.fill",
                showsProgress: false
            )
        case .allClear:
            return AdminCommandSituation(
                tone: .stable,
                title: L10n("AdminCommandCenter_AllClear_Title"),
                detail: L10n("AdminCommandCenter_AllClear_Detail"),
                badge: L10n("AdminCommandCenter_NoAttention"),
                symbol: "checkmark.seal.fill",
                showsProgress: false
            )
        case .degradedEmpty:
            return AdminCommandSituation(
                tone: .critical,
                title: L10n("AdminCommandCenter_Offline_Title"),
                detail: failedDetail,
                badge: L10n("AdminCommandCenter_SourceIssue_Title"),
                symbol: "wifi.exclamationmark",
                showsProgress: false
            )
        case .denied:
            return AdminCommandSituation(
                tone: .muted,
                title: L10n("AdminCommandCenter_NoAccess_Title"),
                detail: L10n("AdminCommandCenter_NoAccess_Detail"),
                badge: L10n("AdminCommandCenter_AccessScope"),
                symbol: "lock.shield",
                showsProgress: false
            )
        }
    }

    private var primarySignal: AdminCommandOrbitSignal? {
        prioritizedSignals.first
    }

    /// Signals ordered by escalation priority: tier, then urgency, then load.
    /// The hero spine, the tier legend, and the primary command all read from
    /// this single ordering so the visual sequence matches the decision order.
    private var prioritizedSignals: [AdminCommandOrbitSignal] {
        store.snapshot.signals.sorted {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.urgency != $1.urgency { return $0.urgency > $1.urgency }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.id < $1.id
        }
    }

    private var heroModel: CommandHeroModel {
        let currentSituation = situation
        let primary = primarySignal
        return CommandHeroModel(
            situation: currentSituation,
            totalCountText: formattedCount(totalAttentionCount),
            usesNumericLoad: !store.snapshot.signals.isEmpty || currentSituation.tone == .stable,
            segments: loadSegments,
            tierGroups: tierGroups,
            stateClassLabel: stateClassLabel,
            capabilityText: capabilityText,
            updatedText: updatedText,
            primarySignal: primary,
            primaryActionTitle: primary.map(primaryActionTitle(for:)) ?? "",
            primaryCountText: primary.flatMap { $0.count > 0 ? formattedCount($0.count) : nil },
            hasLiveSignal: store.snapshot.signals.contains { $0.isLive },
            loadAccessibilityValue: loadAccessibilityValue,
            distributionAccessibilityValue: distributionAccessibilityValue
        )
    }

    /// One spine segment per authorized signal. Width weight is the real item
    /// count with a floor of one so a live area with no countable item stays
    /// legible instead of collapsing to nothing.
    private var loadSegments: [CommandLoadSegment] {
        prioritizedSignals.map { signal in
            CommandLoadSegment(
                id: signal.id,
                weight: Double(max(signal.count, 1)),
                accent: signal.tier.tone.accent
            )
        }
    }

    private var tierGroups: [CommandTierGroup] {
        var order: [AdminCommandPriorityTier] = []
        var totals: [AdminCommandPriorityTier: Int] = [:]
        for signal in prioritizedSignals {
            if totals[signal.tier] == nil {
                order.append(signal.tier)
                totals[signal.tier] = 0
            }
            totals[signal.tier, default: 0] += max(signal.count, 0)
        }
        return order.map { tier in
            let total = totals[tier] ?? 0
            return CommandTierGroup(
                id: tier.rawValue,
                label: tier.localizedLabel,
                countText: total > 0 ? formattedCount(total) : nil,
                accent: tier.tone.accent
            )
        }
    }

    /// Severity class for the operational-state ledger line. It reports the
    /// class of the highest-priority authorized signal instead of repeating the
    /// headline sentence, and stays absent while no class can be established.
    private var stateClassLabel: String? {
        switch phase {
        case .connecting, .loading, .denied:
            return nil
        case .ready:
            return (primarySignal?.tier ?? .ready).localizedLabel
        case .allClear:
            return AdminCommandPriorityTier.ready.localizedLabel
        case .degradedEmpty:
            return AdminCommandPriorityTier.elevated.localizedLabel
        }
    }

    private var loadAccessibilityValue: String {
        let currentSituation = situation
        if currentSituation.showsProgress || (store.snapshot.signals.isEmpty && currentSituation.tone != .stable) {
            return currentSituation.title
        }
        return String(format: L10n("AdminCommandCenter_Count_Format"), formattedCount(totalAttentionCount))
    }

    private var distributionAccessibilityValue: String {
        let groups = tierGroups
        guard !groups.isEmpty else { return situation.title }
        let template = L10n("AdminCommandCenter_TierCount_Format")
        let parts = groups.map { group -> String in
            guard let countText = group.countText else { return group.label }
            return String(format: template, group.label, countText)
        }
        return localizedList(parts)
    }

    private func primaryActionTitle(for signal: AdminCommandOrbitSignal) -> String {
        let module = signal.moduleTitle.isEmpty ? signal.title : signal.moduleTitle
        return String(format: L10n("AdminCommandCenter_PrimaryAction_Format"), module)
    }

    private var totalAttentionCount: Int {
        let attentionSignals = store.snapshot.signals.filter(\.isAttentionBearing)
        let count = attentionSignals.reduce(0) { $0 + max($1.count, 0) }
        return max(count, attentionSignals.isEmpty ? 0 : 1)
    }

    private var highestTone: AdminCommandTone {
        primarySignal?.tier.tone ?? .stable
    }

    private var readinessTone: AdminCommandTone {
        if !store.readiness.failedAreas.isEmpty { return .elevated }
        if !store.readiness.loadingAreas.isEmpty || !store.snapshot.isInitialized { return .info }
        return .stable
    }

    private var runwayTitle: String {
        totalAttentionCount > 0 ? L10n("CommandCenter_Needs_Attention") : L10n("CommandCenter_Command_Spine")
    }

    private var runwayDetail: String {
        totalAttentionCount > 0 ? L10n("CommandCenter_Needs_Attention_Detail") : L10n("CommandCenter_Command_Spine_Detail")
    }

    private var roleDisplayName: String {
        store.snapshot.roleName.isEmpty ? L10n("pp_role_admin") : store.snapshot.roleName
    }

    private var capabilityText: String {
        String(format: L10n("AdminCommand_ModuleCount_Format"), store.snapshot.capabilityCount)
    }

    private var languageToggleTitle: String {
        L10n(store.localeCode == "ar" ? "Language_English_Code" : "Language_Arabic_Code")
    }

    private var compactReadinessText: String {
        if !store.readiness.failedAreas.isEmpty { return L10n("AdminCommandCenter_SourceIssue_Title") }
        if !store.readiness.loadingAreas.isEmpty { return L10n("AdminCommandCenter_LoadingSources") }
        if !store.snapshot.isInitialized { return L10n("AdminCommandCenter_Connecting") }
        return L10n("AdminCommandCenter_Ready_Detail")
    }

    private var confirmingDetail: String {
        let areas = localizedAreaNames(store.readiness.loadingAreas)
        guard !areas.isEmpty else {
            return L10n("AdminCommandCenter_Confirming_Detail")
        }
        return String(format: L10n("AdminCommandCenter_Confirming_Format"), localizedList(areas))
    }

    private var failedDetail: String {
        let areas = localizedAreaNames(store.readiness.failedAreas)
        guard !areas.isEmpty else {
            return L10n("AdminCommandCenter_Offline_Detail")
        }
        return String(format: L10n("AdminCommandCenter_Degraded_Format"), localizedList(areas))
    }

    private var updatedText: String {
        guard let updatedAt = store.readiness.updatedAt else {
            return L10n("AdminCommandCenter_NotConfirmed")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: updatedAt, relativeTo: Date())
        return String(format: L10n("AdminCommandCenter_LastConfirmed_Format"), relative)
    }

    private func localizedAreaNames(_ areas: [String]) -> [String] {
        areas.map { area in
            let orbitKey = "AdminCommandOrbit_Area_\(area)"
            let commandKey = "CommandCenter_Area_\(area)"
            let orbitValue = Language.get(orbitKey, alter: nil)
            if orbitValue != orbitKey { return orbitValue }
            let commandValue = Language.get(commandKey, alter: nil)
            return commandValue == commandKey ? area : commandValue
        }
    }

    private func localizedList(_ values: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    private func L10n(_ key: String) -> String {
        Language.get(key, alter: nil)
    }

    private func route(_ tag: String) {
        guard !tag.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.onRoute?(tag)
    }

    private func refresh() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.onRefresh?()
    }

}

// MARK: - Workplace Header Backgrounds

/// Sovereign Living Aurora & Specular Glass Cockpit Surface for the Command Center Top Bar.
/// Category-defining animated background with telemetry-tuned living resonance,
/// sapphire-crystal specular caustics, and light-sculpted physical bezel strokes.
private struct CommandCenterCockpitBackground: View {
    let readinessTone: AdminCommandTone
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var breatheBrand: Bool = false
    @State private var breatheTelemetry: Bool = false
    @State private var sheenSweep: Bool = false

    private var isRTL: Bool {
        layoutDirection == .rightToLeft
    }

    private var primaryAuraColor: Color {
        Color(uiColor: .ppPrimary)
    }

    private var telemetryAuraColor: Color {
        readinessTone.accent
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [AdminSurface.surface, AdminSurface.surface.opacity(0.96)]
                        : [Color(uiColor: .ppSurface), Color(uiColor: .ppSurface).opacity(0.98)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let w = proxy.size.width
                        let h = proxy.size.height

                        let brandCenter = isRTL
                            ? CGPoint(x: w * 0.78, y: h * 0.32)
                            : CGPoint(x: w * 0.22, y: h * 0.32)
                        let telemetryCenter = isRTL
                            ? CGPoint(x: w * 0.26, y: h * 0.72)
                            : CGPoint(x: w * 0.74, y: h * 0.72)

                        ZStack {
                            // Orb 1: Signature Brand Radiance (soft ruby & rose gold orbit)
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            primaryAuraColor.opacity(colorScheme == .dark ? 0.20 : 0.10),
                                            Color(uiColor: .ppSoftRose).opacity(colorScheme == .dark ? 0.12 : 0.05),
                                            .clear
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: max(w, h) * 0.42
                                    )
                                )
                                .frame(width: max(w, h) * 0.84, height: max(w, h) * 0.84)
                                .position(
                                    x: brandCenter.x + (breatheBrand ? 12 : -8),
                                    y: brandCenter.y + (breatheBrand ? -5 : 7)
                                )
                                .scaleEffect(breatheBrand ? 1.14 : 0.90)
                                .blur(radius: 22)
                                .allowsHitTesting(false)

                            // Orb 2: Operational Health Resonance (breathes in sync with readiness tone)
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            telemetryAuraColor.opacity(colorScheme == .dark ? 0.22 : 0.11),
                                            telemetryAuraColor.opacity(colorScheme == .dark ? 0.08 : 0.03),
                                            .clear
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: max(w, h) * 0.38
                                    )
                                )
                                .frame(width: max(w, h) * 0.76, height: max(w, h) * 0.76)
                                .position(
                                    x: telemetryCenter.x + (breatheTelemetry ? -10 : 10),
                                    y: telemetryCenter.y + (breatheTelemetry ? 5 : -5)
                                )
                                .scaleEffect(breatheTelemetry ? 1.16 : 0.88)
                                .blur(radius: 20)
                                .allowsHitTesting(false)

                            // 3. Specular Prismatic Sheen (Sapphire Crystal Light Ray)
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: Color.white.opacity(0.0), location: 0.38),
                                    .init(color: Color.white.opacity(colorScheme == .dark ? 0.12 : 0.28), location: 0.50),
                                    .init(color: Color.white.opacity(0.0), location: 0.62),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(width: w * 1.8, height: h * 2.4)
                            .rotationEffect(.degrees(22))
                            .offset(x: sheenSweep ? (w * 0.85) : -(w * 0.85))
                            .blendMode(colorScheme == .dark ? .plusLighter : .overlay)
                            .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                } else {
                    // Tranquil static studio lighting for Reduce Motion
                    LinearGradient(
                        stops: [
                            .init(color: primaryAuraColor.opacity(colorScheme == .dark ? 0.08 : 0.04), location: isRTL ? 0.85 : 0.15),
                            .init(color: telemetryAuraColor.opacity(colorScheme == .dark ? 0.08 : 0.04), location: isRTL ? 0.15 : 0.85),
                            .init(color: .clear, location: 0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false)
            .overlay {
                // 4. Ultra-Thin Frosted Glass Depth
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.20 : 0.30))
                    .allowsHitTesting(false)
            }
            .allowsHitTesting(false)
            .overlay {
                // 5. Precision Sculpted Multi-Stop Bezel Rim
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.24 : 0.72), location: 0.0),
                                .init(color: AdminSurface.hairline.opacity(0.85), location: 0.45),
                                .init(color: telemetryAuraColor.opacity(colorScheme == .dark ? 0.30 : 0.18), location: 0.80),
                                .init(color: AdminSurface.hairline.opacity(0.70), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: contrast == .increased ? 1.25 : AdminStroke.hairline
                    )
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: AdminShadow.card.color,
                radius: AdminShadow.card.radius,
                y: AdminShadow.card.y
            )
            .shadow(
                color: telemetryAuraColor.opacity(colorScheme == .dark ? 0.16 : 0.08),
                radius: 14,
                y: 5
            )
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 7.2).repeatForever(autoreverses: true)) {
                    breatheBrand = true
                }
                withAnimation(.easeInOut(duration: 5.8).repeatForever(autoreverses: true)) {
                    breatheTelemetry = true
                }
                withAnimation(.easeInOut(duration: 9.5).repeatForever(autoreverses: true)) {
                    sheenSweep = true
                }
            }
    }
}

/// Fluid Recessed Optic Chamber for the Working Branch Selector inside the top bar.
private struct CommandCenterChamberBackground: View {
    let readinessTone: AdminCommandTone
    let cornerRadius: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        AdminSurface.control.opacity(colorScheme == .dark ? 0.85 : 0.72),
                        AdminSurface.control.opacity(colorScheme == .dark ? 0.60 : 0.46)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                // Ultra-thin material allowing subtle ambient aurora pass-through
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.15 : 0.25))
                    .allowsHitTesting(false)
            }
            .overlay {
                // Precision micro-bevel border: top catches ambient light, bottom grounds it
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.20 : 0.65), location: 0.0),
                                .init(color: AdminSurface.hairline.opacity(0.85), location: 0.50),
                                .init(color: readinessTone.accent.opacity(colorScheme == .dark ? 0.22 : 0.14), location: 0.80),
                                .init(color: AdminSurface.hairline.opacity(0.60), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: contrast == .increased ? 1.0 : 0.75
                    )
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
    }
}

// MARK: - Workplace Header

/// Presentation only. Snapshot, staff scope, branch selection and routes stay
/// with their existing owners; every visible action is a sibling native control.
private struct CommandCenterChrome: View {
    let displayName: String
    let avatarURL: String
    let roleName: String
    let capabilityText: String
    let readinessText: String
    let readinessTone: AdminCommandTone
    let onReadinessTap: (() -> Void)?
    let languageTitle: String
    let onAccount: () -> Void
    let onRefresh: () -> Void
    let onLanguage: () -> Void
    let onLogout: () -> Void
    let onSelectBranch: () -> Void
    var isRegular: Bool = false
    var containerWidth: CGFloat = 0

    @ObservedObject private var branchContextStore = BranchContextStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var pulseBeacon: Bool = false
    @ScaledMetric(relativeTo: .body) private var avatarSide: CGFloat = 36

    private var secondaryInk: Color {
        contrast == .increased ? AdminSurface.primaryText : AdminSurface.secondaryText
    }

    private var actionInk: Color {
        contrast == .increased ? AdminSurface.primaryText : Color(uiColor: .ppAccentText)
    }

    var body: some View {
        Group {
            if isRegular {
                ipadCommandBar
            } else {
                iphoneCommandCockpit
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("admin.command.header")
    }

    // MARK: - iPhone working-context signature

    private var iphoneCommandCockpit: some View {
        VStack(alignment: .leading, spacing: 0) {
            let signatureLayout = dynamicTypeSize >= .xxxLarge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            signatureLayout {
                operatorIdentityPodiPhone
                    .frame(maxWidth: .infinity, alignment: .leading)
                flightUtilityClusteriPhone
            }

            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.75)
                .padding(.top, 6)
                .padding(.bottom, 6)
                .accessibilityHidden(true)

            workingBranchChamberiPhone
            readinessControliPhone
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(AdminSurface.surface,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: contrast == .increased ? 1.5 : 0.75)
                .allowsHitTesting(false)
        }
        .shadow(color: AdminSurface.primaryText.opacity(0.035), radius: 14, x: 0, y: 5)
        .zIndex(1)
    }

    private var operatorIdentityPodiPhone: some View {
        Button(action: onAccount) {
            HStack(alignment: .center, spacing: 9) {
                let imageSide = min(avatarSide, 52)
                AdminRemoteImage(
                    url: resolvedAvatarURL,
                    contentMode: .fill,
                    targetSize: CGSize(width: imageSide, height: imageSide)
                ) {
                    Text(monogram)
                        .font(PPBrandFont.bold(size: 14, relativeTo: .subheadline))
                        .foregroundStyle(actionInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AdminSurface.primary.opacity(0.08))
                }
                .frame(width: imageSide, height: imageSide)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(resolvedDisplayName)
                        .font(PPBrandFont.bold(size: 14, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    let roleLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 5))
                    roleLayout {
                        Text(Language.get("AdminCommandCenter_Header_Admin", alter: nil))
                            .font(PPBrandFont.bold(size: 10, relativeTo: .caption2))
                            .foregroundStyle(actionInk)
                        Text(roleName)
                            .font(PPBrandFont.medium(size: 11, relativeTo: .caption2))
                            .foregroundStyle(secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandHeaderPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resolvedDisplayName)
        .accessibilityValue("\(roleName), \(capabilityText)")
        .accessibilityHint(Language.get("EditMyAccount_Title", alter: nil))
        .accessibilityIdentifier("admin.command.header.account")
    }

    private var flightUtilityClusteriPhone: some View {
        HStack(spacing: 4) {
            Button(action: onLanguage) {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .medium))
                        .accessibilityHidden(true)
                    Text(languageTitle)
                        .font(PPBrandFont.bold(size: 12, relativeTo: .caption))
                        .environment(\.layoutDirection, .leftToRight)
                }
                .foregroundStyle(AdminSurface.primaryText)
                .padding(.horizontal, 9)
                .frame(minWidth: 52, minHeight: 44)
                .background(AdminSurface.control, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(CommandHeaderPressStyle())
            .accessibilityLabel(Language.get("Confirm_LanguageChange_Title", alter: nil))
            .accessibilityValue(languageTitle)
            .accessibilityIdentifier("admin.command.header.language")

            moreActionsMenu(size: 44)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var workingBranchChamberiPhone: some View {
        Button(action: triggerBranchSwitch) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Label(Language.get("AdminCommandCenter_Header_BranchScope", alter: nil),
                          systemImage: "storefront")
                        .font(PPBrandFont.medium(size: 11, relativeTo: .caption))
                        .foregroundStyle(actionInk)

                    Text(currentBranchDisplayName)
                        .font(PPBrandFont.bold(size: 26, relativeTo: .title2))
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if canSwitchBranch {
                    VStack(spacing: 1) {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                        Text(Language.get("AdminCommandCenter_Header_Switch", alter: nil))
                            .font(PPBrandFont.bold(size: 10, relativeTo: .caption2))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(actionInk)
                    .padding(.horizontal, 9)
                    .frame(minWidth: 48, minHeight: 44)
                    .background(AdminSurface.primary.opacity(contrast == .increased ? 0.12 : 0.06),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)
                } else if !branchContextStore.availableBranches.isEmpty {
                    Image(systemName: "lock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondaryInk)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandHeaderPressStyle())
        .disabled(!canSwitchBranch)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get(
            canSwitchBranch ? "BranchContext_Switcher_Title" : "AdminCommandCenter_Header_WorkingBranch",
            alter: nil
        ))
        .accessibilityValue(currentBranchDisplayName)
        .accessibilityIdentifier("admin.command.header.branch")
    }

    // This sibling owns source details; branch switching never encloses its tap.
    private var readinessControliPhone: some View {
        Group {
            if let onReadinessTap {
                Button(action: onReadinessTap) {
                    branchStatsBadge
                        .contentShape(Rectangle())
                }
                .buttonStyle(CommandHeaderPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(readinessText)
                .accessibilityHint(Language.get("AdminCommandCenter_SourceIssue_TapHint", alter: nil))
            } else {
                branchStatsBadge
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(readinessText)
            }
        }
        .accessibilityIdentifier("admin.command.header.readiness")
    }

    private var branchStatsBadge: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: readinessTone.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(readinessTone.accent)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(readinessText)
                .font(PPBrandFont.medium(size: 12, relativeTo: .caption))
                .foregroundStyle(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if onReadinessTap != nil {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(readinessTone.accent)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: onReadinessTap == nil ? 24 : 44, alignment: .leading)
    }

    private var isLandscapeIPad: Bool {
        containerWidth >= 950
    }

    // MARK: - iPad Aerospace Command Bar
    private var ipadCommandBar: some View {
        HStack(alignment: .center, spacing: isLandscapeIPad ? 16 : 10) {
            // Wing 1: Working Branch Control Station
            workingBranchIPadStation

            Spacer(minLength: isLandscapeIPad ? 12 : 6)

            // Wing 2: Real-Time Telemetry & Readiness Radar
            readinessControlIPad

            Spacer(minLength: isLandscapeIPad ? 12 : 6)

            // Wing 3: Utility Flight Tools + Operator Identity Capsule
            HStack(spacing: isLandscapeIPad ? 10 : 8) {
                utilityActionsIPad

                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(width: 1, height: 24)
                    .accessibilityHidden(true)

                accountSignatureIPad
                moreActionsMenu(size: 36)
            }
        }
        .padding(.horizontal, isLandscapeIPad ? 18 : 14)
        .padding(.vertical, 10)
        .background(
            CommandCenterCockpitBackground(readinessTone: readinessTone, cornerRadius: 24)
                .allowsHitTesting(false)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .zIndex(1)
    }

    private var workingBranchIPadStation: some View {
        Button(action: triggerBranchSwitch) {
            HStack(alignment: .center, spacing: isLandscapeIPad ? 12 : 8) {
                // Branch Storefront Glyphed Squircle with gradient
                ZStack {
                    LinearGradient(
                        colors: canSwitchBranch
                            ? [Color(uiColor: .ppPrimary), Color(uiColor: .ppPrimary).opacity(0.82)]
                            : [AdminSurface.control, AdminSurface.hairline],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "storefront.fill")
                        .font(.system(size: isLandscapeIPad ? 16 : 14, weight: .bold))
                        .foregroundStyle(canSwitchBranch ? Color.white : secondaryInk)
                }
                .frame(width: isLandscapeIPad ? 42 : 36, height: isLandscapeIPad ? 42 : 36)
                .clipShape(RoundedRectangle(cornerRadius: isLandscapeIPad ? 13 : 10, style: .continuous))
                .shadow(
                    color: canSwitchBranch ? Color(uiColor: .ppPrimary).opacity(0.24) : Color.clear,
                    radius: 6,
                    y: 2
                )

                VStack(alignment: .leading, spacing: 1) {
                    if isLandscapeIPad {
                        HStack(spacing: 5) {
                            Text(Language.get("AdminCommandCenter_Header_WorkingBranch", alter: "فرع العمل والتشغيل"))
                                .font(PPBrandFont.medium(size: 11.5, relativeTo: .caption2))
                                .foregroundStyle(secondaryInk)

                            Circle()
                                .fill(Color(uiColor: .ppSuccess))
                                .frame(width: 5.5, height: 5.5)
                        }
                    }

                    Text(currentBranchDisplayName)
                        .font(PPBrandFont.bold(size: isLandscapeIPad ? 18 : 15, relativeTo: .title3))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if canSwitchBranch {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                        if isLandscapeIPad {
                            Text(Language.get("AdminCommandCenter_Header_Switch", alter: "تبديل"))
                                .font(PPBrandFont.bold(size: 11.5, relativeTo: .caption))
                        }
                    }
                    .foregroundStyle(Color(uiColor: .ppPrimary))
                    .padding(.horizontal, isLandscapeIPad ? 9 : 6)
                    .padding(.vertical, 5)
                    .background(
                        Color(uiColor: .ppPrimary).opacity(0.10),
                        in: Capsule(style: .continuous)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(uiColor: .ppPrimary).opacity(0.25), lineWidth: 0.75)
                    )
                } else if !branchContextStore.availableBranches.isEmpty {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondaryInk)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandHeaderPressStyle())
        .disabled(!canSwitchBranch)
        .accessibilityLabel(Language.get(
            canSwitchBranch ? "BranchContext_Switcher_Title" : "AdminCommandCenter_Header_WorkingBranch",
            alter: nil
        ))
        .accessibilityValue(currentBranchDisplayName)
        .accessibilityIdentifier("admin.command.header.branch.ipad")
    }

    private var readinessControlIPad: some View {
        Group {
            if let onReadinessTap {
                Button(action: onReadinessTap) {
                    readinessContentIPad
                        .contentShape(Rectangle())
                }
                .buttonStyle(CommandHeaderPressStyle())
                .accessibilityLabel(readinessText)
                .accessibilityHint(Language.get("AdminCommandCenter_SourceIssue_TapHint", alter: nil))
                .accessibilityIdentifier("admin.command.header.readiness.ipad")
            } else {
                readinessContentIPad
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(readinessText)
                    .accessibilityIdentifier("admin.command.header.readiness.ipad")
            }
        }
    }

    private var readinessContentIPad: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(readinessTone.accent.opacity(0.20))
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulseBeacon ? 1.25 : 0.95)
                    .opacity(pulseBeacon ? 0.7 : 1.0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulseBeacon)

                Circle()
                    .fill(readinessTone.accent)
                    .frame(width: 7.5, height: 7.5)
            }
            .frame(width: 18, height: 18)

            Text(readinessText)
                .font(PPBrandFont.bold(size: 13, relativeTo: .footnote))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)

            if onReadinessTap != nil {
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(readinessTone.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            AdminSurface.control,
            in: Capsule(style: .continuous)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(readinessTone.accent.opacity(0.25), lineWidth: 0.75)
        )
        .onAppear {
            pulseBeacon = true
        }
    }

    private var utilityActionsIPad: some View {
        // Language Matrix Switcher
        Button(action: onLanguage) {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .semibold))
                Text(languageTitle)
                    .font(PPBrandFont.bold(size: 13, relativeTo: .footnote))
                    .environment(\.layoutDirection, .leftToRight)
            }
            .foregroundStyle(AdminSurface.primaryText)
            .padding(.horizontal, isLandscapeIPad ? 14 : 10)
            .frame(height: 36)
            .background(
                AdminSurface.control,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandHeaderPressStyle())
        .accessibilityLabel(Language.get("Confirm_LanguageChange_Title", alter: nil))
        .accessibilityValue(languageTitle)
        .accessibilityIdentifier("admin.command.header.language.ipad")
    }

    private var accountSignatureIPad: some View {
        Button(action: onAccount) {
            HStack(spacing: 9) {
                AdminRemoteImage(
                    url: resolvedAvatarURL,
                    contentMode: .fill,
                    targetSize: CGSize(width: 36, height: 36)
                ) {
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(uiColor: .ppPrimary).opacity(0.16),
                                Color(uiColor: .ppSoftRose).opacity(0.40)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(monogram)
                            .font(PPBrandFont.bold(size: 14, relativeTo: .subheadline))
                            .foregroundStyle(actionInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                )

                if isLandscapeIPad {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(resolvedDisplayName)
                            .font(PPBrandFont.bold(size: 14, relativeTo: .footnote))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        HStack(spacing: 4) {
                            Text(roleName)
                                .font(PPBrandFont.medium(size: 11, relativeTo: .caption2))
                                .foregroundStyle(secondaryInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(secondaryInk.opacity(0.5))

                            Text("ADMIN")
                                .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(actionInk)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandHeaderPressStyle())
        .accessibilityLabel(resolvedDisplayName)
        .accessibilityValue("\(roleName), \(capabilityText)")
        .accessibilityIdentifier("admin.command.header.account.ipad")
    }


    // MARK: - Actions Menu (Beiruti Brand Font)

    private var moreActionsMenu: some View {
        moreActionsMenu(size: 38)
    }

    private func moreActionsMenu(size: CGFloat) -> some View {
        Menu {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onRefresh()
            } label: {
                Label(Language.get("AdminCommandCenter_Refresh", alter: nil), systemImage: "arrow.clockwise")
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onAccount()
            } label: {
                Label(Language.get("EditMyAccount_Title", alter: nil), systemImage: "person.crop.circle")
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onLanguage()
            } label: {
                Label(String(format: Language.get("AdminCommandCenter_Header_Language_Format", alter: nil), languageTitle), systemImage: "globe")
            }

            Button(role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onLogout()
            } label: {
                Label(Language.get("Logout", alter: nil), systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AdminSurface.primaryText)
                .frame(width: size, height: size)
                .background(
                    AdminSurface.control,
                    in: RoundedRectangle(cornerRadius: isRegular ? 11 : size / 2, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isRegular ? 11 : size / 2, style: .continuous)
                        .strokeBorder(isRegular ? AdminSurface.hairline : .clear, lineWidth: 0.75)
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Language.get("CommandCenter_Tab_More", alter: nil))
        .accessibilityIdentifier("admin.command.header.more")
    }

    // MARK: - Existing Context and Identity Resolution

    private var currentBranchDisplayName: String {
        let name = branchContextStore.currentBranchDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Language.get("BranchContext_SelectBranch_Prompt", alter: nil) : name
    }

    private var canSwitchBranch: Bool {
        branchContextStore.availableBranches.count > 1
    }

    private func triggerBranchSwitch() {
        guard canSwitchBranch else { return }
        let feedback = UIImpactFeedbackGenerator(style: .soft)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.82)
        onSelectBranch()
    }

    private var resolvedDisplayName: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? roleName : trimmedName
    }

    private var resolvedAvatarURL: URL? {
        let trimmedURL = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty, let url = URL(string: trimmedURL) {
            return url
        }
        if let user = UserManager.shared().currentUser {
            if let photo = user.photoURL, let url = URL(string: photo), !photo.isEmpty {
                return url
            }
            if let imgUrl = user.userImageUrl {
                return imgUrl
            }
            if let name = user.userImageName, let url = URL(string: name), !name.isEmpty {
                return url
            }
        }
        if let staffPhoto = PPStaffAuth.shared().cachedCurrentStaff?.photoURL, let url = URL(string: staffPhoto), !staffPhoto.isEmpty {
            return url
        }
        if let authPhoto = Auth.auth().currentUser?.photoURL {
            return authPhoto
        }
        return nil
    }

    private var monogram: String {
        let parts = resolvedDisplayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "PP" : letters.uppercased()
    }
}

/// Ultra-premium, tactile, and minimal press interaction for Command Center cards.
/// Delivers high-precision spatial depth, micro-depression (scale ~0.982),
/// subtle atmospheric opacity adjustment (0.94), and high-frequency spring physics.
private struct CommandCardPressStyle: ButtonStyle {
    var scale: CGFloat = 0.982
    var pressedOpacity: CGFloat = 0.94
    var cornerRadius: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        let animatesScale = UIDevice.current.userInterfaceIdiom != .pad
        return configuration.label
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed && animatesScale ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(animatesScale ? (configuration.isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.28, dampingFraction: 0.72)) : nil, value: configuration.isPressed)
    }
}

/// Immediate press acknowledgement, with no extra motion or request state.
/// Native Menu/sheet presentations keep their system accessibility behavior.
private struct CommandHeaderPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .transaction { transaction in
                transaction.animation = nil
            }
    }
}

private struct CommandStatusLine: View {
    let text: String
    let tone: AdminCommandTone
    let action: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) {
                statusContent
                    .frame(minHeight: AdminTouchTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CommandPressStyle())
            .accessibilityHint(Language.get("AdminCommandCenter_SourceIssue_TapHint", alter: nil))
        } else {
            statusContent
                .frame(minHeight: 24)
        }
    }

    private var statusContent: some View {
        HStack(spacing: 8) {
            Image(systemName: tone.symbol)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tone.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(AdminType.captionBold)
                .foregroundStyle(tone.color)
                .lineLimit(2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CommandSourceIssueSheet: View {
    let sourceNames: [String]
    let detail: String
    let updatedText: String
    let onRetry: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                header

                Text(Language.get("AdminCommandCenter_SourceIssue_SheetDetail", alter: nil))
                    .font(AdminType.callout)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: AdminSpacing.md) {
                    Text(Language.get("AdminCommandCenter_SourceIssue_AffectedSources", alter: nil))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminCommandInk.secondary)

                    ForEach(sourceNames, id: \.self) { sourceName in
                        HStack(spacing: AdminSpacing.md) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AdminCommandTone.elevated.accent)
                                .accessibilityHidden(true)
                            Text(sourceName)
                                .font(AdminType.headline)
                                .foregroundStyle(AdminSurface.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: AdminTouchTarget.minimum)
                    }

                    Divider()

                    Text(detail)
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(updatedText)
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminCommandInk.tertiary)
                }
                .padding(AdminSpacing.base)
                .background(
                    RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                        .fill(AdminSurface.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                )

                Button {
                    dismiss()
                    onRetry()
                } label: {
                    Label(
                        Language.get("AdminCommandCenter_Retry", alter: nil),
                        systemImage: "arrow.clockwise"
                    )
                    .font(AdminType.headline)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable)
                    .background(
                        RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                            .fill(AdminSurface.primary)
                    )
                }
                .buttonStyle(CommandPressStyle())
                .accessibilityHint(Language.get("AdminCommandOrbit_Refresh_Hint", alter: nil))
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, AdminSpacing.lg)
            .padding(.bottom, AdminSpacing.xl)
        }
        .background(AdminSurface.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AdminSpacing.md) {
            ZStack {
                Circle()
                    .fill(AdminCommandTone.elevated.softFill)
                Image(systemName: AdminCommandTone.elevated.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AdminCommandTone.elevated.accent)
                    .accessibilityHidden(true)
            }
            .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)

            Text(Language.get("AdminCommandCenter_SourceIssue_SheetTitle", alter: nil))
                .font(AdminType.title3)
                .foregroundStyle(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    .background(AdminSurface.control, in: Circle())
            }
            .buttonStyle(CommandPressStyle())
            .accessibilityLabel(Language.get("Close", alter: nil))
        }
    }
}

// MARK: - Escalation Hero

/// One proportional slice of the escalation spine. `weight` is the real item
/// count reported for an authorized area, floored at one so an area that is
/// flagged without a countable item still occupies legible width.
private struct CommandLoadSegment: Identifiable, Equatable {
    let id: String
    let weight: Double
    let accent: Color
}

/// Aggregate load for one priority class, used by the spine legend.
/// `countText` is absent when the class carries no countable item.
private struct CommandTierGroup: Identifiable, Equatable {
    let id: Int
    let label: String
    let countText: String?
    let accent: Color
}

/// Every value the hero renders. All of it is derived by the owning screen from
/// the live store, so the hero never computes, invents, or caches operational
/// figures and never decides routing on its own.
private struct CommandHeroModel: Equatable {
    let situation: AdminCommandSituation
    let totalCountText: String
    let usesNumericLoad: Bool
    let segments: [CommandLoadSegment]
    let tierGroups: [CommandTierGroup]
    let stateClassLabel: String?
    let capabilityText: String
    let updatedText: String
    let primarySignal: AdminCommandOrbitSignal?
    let primaryActionTitle: String
    let primaryCountText: String?
    let hasLiveSignal: Bool
    let loadAccessibilityValue: String
    let distributionAccessibilityValue: String
}

/// The dominant operational anchor of the command surface.
/// Reimagined as the Sovereign Command Nucleus: high-density, low-vertical-footprint,
/// multi-spectrum telemetry cockpit with integrated escalation catalyst.
private struct CommandEscalationHero: View {
    let model: CommandHeroModel
    let isRegular: Bool
    let onPrimary: (AdminCommandOrbitSignal) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var livePulse = false

    private var isAccessibilityMode: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        if let primary = model.primarySignal {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onPrimary(primary)
            } label: {
                heroCardBody
            }
            .buttonStyle(CommandCardPressStyle(scale: 0.985, pressedOpacity: 0.95, cornerRadius: 20))
            .accessibilityElement(children: .contain)
        } else {
            heroCardBody
                .accessibilityElement(children: .contain)
        }
    }

    private var heroCardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            telemetryHorizon

            if isRegular && !isAccessibilityMode {
                panoramicIntelligenceDeck
            } else {
                compactIntelligenceCluster
            }

            if model.primarySignal != nil {
                actionCatalyst
            } else if model.situation.tone == .stable {
                stableStatusRibbon
            }
        }
        .padding(14)
        .background(heroAtmosphere)
        .overlay(heroGlassBorder)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Atmospheric Canvas

    private var heroAtmosphere: some View {
        ZStack {
            AdminSurface.control

            // Directional chromatic bloom matching tone
            RadialGradient(
                colors: [
                    model.situation.tone.accent.opacity(colorScheme == .dark ? 0.20 : 0.08),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 220
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.05), radius: 14, x: 0, y: 5)
    }

    private var heroGlassBorder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        model.situation.tone.accent.opacity(0.42),
                        Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.60 : 0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.0
            )
    }

    // MARK: - Telemetry Horizon (Top Filament)

    @ViewBuilder
    private var telemetryHorizon: some View {
        if isAccessibilityMode {
            telemetryHorizonVertical
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        liveStatusBadge
                        if let stateClass = model.stateClassLabel {
                            stateClassTag(stateClass)
                        }
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 6) {
                        freshnessTag
                        scopeTag
                    }
                }

                telemetryHorizonVertical
            }
        }
    }

    private var telemetryHorizonVertical: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                liveStatusBadge
                if let stateClass = model.stateClassLabel {
                    stateClassTag(stateClass)
                }
            }
            HStack(spacing: 6) {
                freshnessTag
                scopeTag
            }
        }
    }

    private var liveStatusBadge: some View {
        HStack(spacing: 5) {
            liveIndicator
            Text(model.situation.badge)
                .font(AdminType.captionBold)
                .foregroundStyle(model.situation.tone.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(model.situation.tone.softFill, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(model.situation.tone.accent.opacity(0.28), lineWidth: 0.75)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.situation.badge)
    }

    private func stateClassTag(_ stateClass: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.situation.tone.accent)
                .frame(width: 5, height: 5)
                .shadow(color: model.situation.tone.accent.opacity(0.6), radius: 2, x: 0, y: 0)
            Text(stateClass)
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.30 : 0.15), in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("CommandCenter_Operational_State", alter: "Operational state"))
        .accessibilityValue(stateClass)
    }

    private var freshnessTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AdminCommandInk.tertiary)
            Text(model.updatedText)
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.20 : 0.10), in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("CommandCenter_Last_Updated", alter: nil))
        .accessibilityValue(model.updatedText)
    }

    private var scopeTag: some View {
        HStack(spacing: 3) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AdminCommandInk.tertiary)
            Text(model.capabilityText)
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.20 : 0.10), in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("AdminCommandCenter_AccessScope", alter: nil))
        .accessibilityValue(model.capabilityText)
    }

    @ViewBuilder
    private var liveIndicator: some View {
        if model.hasLiveSignal {
            ZStack {
                Circle()
                    .stroke(model.situation.tone.accent.opacity(0.4), lineWidth: 1.2)
                    .frame(width: 12, height: 12)
                    .scaleEffect(livePulse ? 1.4 : 1.0)
                    .opacity(livePulse ? 0.0 : 1.0)

                Circle()
                    .fill(model.situation.tone.accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: model.situation.tone.accent.opacity(0.7), radius: 2.5, x: 0, y: 0)
            }
            .frame(width: 12, height: 12)
            .onAppear(perform: startLivePulse)
            .onChange(of: reduceMotion) { isReduced in
                if isReduced { stopLivePulse() } else { startLivePulse() }
            }
            .accessibilityHidden(true)
        } else {
            Image(systemName: model.situation.symbol)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.situation.tone.accent)
                .accessibilityHidden(true)
        }
    }

    private func startLivePulse() {
        guard !reduceMotion, !livePulse else { return }
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
            livePulse = true
        }
    }

    private func stopLivePulse() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            livePulse = false
        }
    }

    // MARK: - Compact Intelligence Cluster (iPhone)

    private var compactIntelligenceCluster: some View {
        HStack(alignment: .center, spacing: 12) {
            workloadPod
                .frame(width: 80)

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.situation.title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(model.situation.detail)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                CommandLoadSpine(
                    segments: model.segments,
                    trackAccent: model.situation.tone.accent,
                    showsPlaceholder: model.situation.showsProgress,
                    reduceMotion: reduceMotion
                )

                tierLegendRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Panoramic Intelligence Deck (iPad)

    private var panoramicIntelligenceDeck: some View {
        HStack(alignment: .center, spacing: 18) {
            workloadPod
                .frame(width: 100)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.situation.title)
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                Text(model.situation.detail)
                    .font(AdminType.caption)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(2)

                CommandLoadSpine(
                    segments: model.segments,
                    trackAccent: model.situation.tone.accent,
                    showsPlaceholder: model.situation.showsProgress,
                    reduceMotion: reduceMotion
                )

                tierLegendRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Workload Quantum Pod

    private var workloadPod: some View {
        VStack(spacing: 2) {
            Text(Language.get("AdminCommandCenter_ActiveLoad", alter: "Active Workload"))
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if model.situation.showsProgress {
                ProgressView()
                    .tint(model.situation.tone.color)
                    .scaleEffect(0.9)
                    .frame(height: 34)
            } else if model.usesNumericLoad {
                Text(model.totalCountText)
                    .font(Font.custom("Beiruti-Bold", size: 30, relativeTo: .title))
                    .foregroundStyle(AdminSurface.primaryText)
                    .monospacedDigit()
                    .commandNumericTransition()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: model.situation.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(model.situation.tone.accent)
                    .frame(height: 34)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            model.situation.tone.accent.opacity(colorScheme == .dark ? 0.16 : 0.07),
                            AdminSurface.control.opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(model.situation.tone.accent.opacity(0.24), lineWidth: 0.8)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("AdminCommandCenter_ActiveLoad", alter: nil))
        .accessibilityValue(model.loadAccessibilityValue)
    }

    // MARK: - Tier Legend Row

    @ViewBuilder
    private var tierLegendRow: some View {
        if !model.tierGroups.isEmpty {
            HStack(spacing: 8) {
                ForEach(model.tierGroups) { group in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(group.accent)
                            .frame(width: 5, height: 5)
                            .shadow(color: group.accent.opacity(0.5), radius: 1.5, x: 0, y: 0)
                        Text(group.label)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                            .lineLimit(1)
                        if let countText = group.countText {
                            Text(countText)
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(group.label)
                    .commandAccessibilityValue(group.countText.map {
                        String(format: Language.get("AdminCommandCenter_Count_Format", alter: nil), $0)
                    })
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Sovereign Action Catalyst

    private func actionCatalyst(for signal: AdminCommandOrbitSignal) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.20))
                Image(systemName: signal.symbolName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(model.primaryActionTitle)
                    .font(AdminType.subheadlineBold)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Language.get("AdminCommandCenter_Act", alter: "Act now"))
                    .font(AdminType.caption2)
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            if let countText = model.primaryCountText {
                Text(countText)
                    .font(AdminType.captionBold)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.22), in: Capsule(style: .continuous))
                    .accessibilityHidden(true)
            }

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 22, height: 22)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            signal.tier.tone.accent,
                            signal.tier.tone.accent.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: signal.tier.tone.accent.opacity(0.32), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.75)
        )
        .accessibilityLabel(model.primaryActionTitle)
        .commandAccessibilityValue(model.primaryCountText.map {
            String(format: Language.get("AdminCommandCenter_Count_Format", alter: nil), $0)
        })
        .accessibilityHint(Language.get("AdminCommandCenter_OpenHint", alter: nil))
    }

    @ViewBuilder
    private var actionCatalyst: some View {
        if let primary = model.primarySignal {
            actionCatalyst(for: primary)
        }
    }

    private var stableStatusRibbon: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(uiColor: .ppSuccess))

            Text(model.situation.detail)
                .font(AdminType.captionBold)
                .foregroundStyle(Color(uiColor: .ppSuccess))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .ppSuccess).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.25), lineWidth: 0.75)
        )
    }
}

// MARK: - Escalation Spine

private struct CommandLoadSpine: View {
    let segments: [CommandLoadSegment]
    let trackAccent: Color
    let showsPlaceholder: Bool
    let reduceMotion: Bool

    private let gap: CGFloat = 2.5
    private let minimumSegment: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(in: proxy.size.width)
            HStack(spacing: gap) {
                if showsPlaceholder || segments.isEmpty {
                    Capsule(style: .continuous)
                        .fill(trackAccent.opacity(0.24))
                } else {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        Capsule(style: .continuous)
                            .fill(segment.accent)
                            .frame(width: index < widths.count ? widths[index] : 0)
                            .shadow(color: segment.accent.opacity(0.35), radius: 1.5, x: 0, y: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.88), value: layoutSignature)
        }
        .frame(height: 5)
        .background(AdminSurface.control.opacity(0.5), in: Capsule(style: .continuous))
    }

    private var layoutSignature: String {
        let base = segments.map { "\($0.id):\(Int($0.weight))" }.joined(separator: "|")
        return showsPlaceholder ? base + "#pending" : base
    }

    /// Each segment receives a small fixed floor so no authorized area can
    /// disappear, and the remaining width is distributed by true weight.
    private func segmentWidths(in totalWidth: CGFloat) -> [CGFloat] {
        guard !segments.isEmpty, totalWidth > 0 else { return [] }
        let gaps = gap * CGFloat(max(segments.count - 1, 0))
        let available = max(totalWidth - gaps, 0)
        guard available > 0 else { return segments.map { _ in 0 } }
        let floorWidth = min(minimumSegment, available / CGFloat(segments.count))
        let proportional = max(available - floorWidth * CGFloat(segments.count), 0)
        let totalWeight = max(segments.reduce(0) { $0 + $1.weight }, 1)
        return segments.map { floorWidth + proportional * CGFloat($0.weight / totalWeight) }
    }
}

private extension View {
    @ViewBuilder
    func commandNumericTransition() -> some View {
        if #available(iOS 16.0, *) {
            contentTransition(.numericText())
        } else {
            self
        }
    }

    @ViewBuilder
    func commandAccessibilityValue(_ value: String?) -> some View {
        if let value = value {
            accessibilityValue(value)
        } else {
            self
        }
    }
}

// MARK: - POS Sovereign Command Console & Real-time Telemetry (Deck 1)

@MainActor
final class CommandPOSShiftTelemetryStore: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case zero
        case error(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var todayReceiptsCount: Int = 0
    @Published private(set) var todaySalesTotal: Double = 0.0
    @Published private(set) var cashSalesTotal: Double = 0.0
    @Published private(set) var cardSalesTotal: Double = 0.0
    @Published private(set) var refundsCount: Int = 0
    @Published private(set) var lastFetchDate: Date? = nil
    @Published private(set) var isRefreshing: Bool = false

    private(set) var activeBranchID: String = ""
    private var activeFetchID: UUID?

    var averageOrderValue: Double {
        todayReceiptsCount > 0 ? (todaySalesTotal / Double(todayReceiptsCount)) : 0.0
    }

    var cashRatio: CGFloat {
        guard todaySalesTotal > 0 else { return 0.0 }
        return CGFloat(min(max(cashSalesTotal / todaySalesTotal, 0.0), 1.0))
    }

    var cardRatio: CGFloat {
        guard todaySalesTotal > 0 else { return 0.0 }
        return CGFloat(min(max(cardSalesTotal / todaySalesTotal, 0.0), 1.0))
    }

    var currencySymbol: String {
        Language.isRTL() ? "ر.ق" : "QAR"
    }

    var formattedTodaySales: String {
        String(format: "%.2f %@", todaySalesTotal, currencySymbol)
    }

    var formattedCashSales: String {
        String(format: "%.2f %@", cashSalesTotal, currencySymbol)
    }

    var formattedCardSales: String {
        String(format: "%.2f %@", cardSalesTotal, currencySymbol)
    }

    var formattedAverageOrderValue: String {
        String(format: "%.2f %@", averageOrderValue, currencySymbol)
    }

    var relativeTimeString: String {
        guard let last = lastFetchDate else { return "" }
        let seconds = Int(Date().timeIntervalSince(last))
        if seconds < 60 {
            return Language.isRTL() ? "مُحدّث للتو" : "Updated just now"
        } else if seconds < 3600 {
            let mins = max(1, seconds / 60)
            return Language.isRTL() ? "منذ \(mins) د" : "\(mins)m ago"
        } else {
            let hours = seconds / 3600
            return Language.isRTL() ? "منذ \(hours) س" : "\(hours)h ago"
        }
    }

    var canSell: Bool {
        guard let staff = BranchContextStore.shared.currentStaff else { return false }
        if !activeBranchID.isEmpty {
            return staff.hasPermission("pos.sell", inBranch: activeBranchID)
        }
        return staff.hasPermission("pos.sell")
    }

    var canView: Bool {
        guard let staff = BranchContextStore.shared.currentStaff else { return false }
        if !activeBranchID.isEmpty {
            return staff.hasPermission("pos.view", inBranch: activeBranchID)
        }
        return staff.hasPermission("pos.view")
    }

    var canViewHistory: Bool {
        guard let staff = BranchContextStore.shared.currentStaff else { return false }
        if !activeBranchID.isEmpty {
            return staff.hasPermission("pos.history", inBranch: activeBranchID)
        }
        return staff.hasPermission("pos.history")
    }

    var activeStaffName: String {
        let name = BranchContextStore.shared.currentStaff?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return Language.get("AdminPOS_ActiveCashier", alter: Language.isRTL() ? "الكاشير" : "Cashier")
    }

    func updateBranch(branchID: String) {
        let trimmed = branchID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != activeBranchID || state == .loading else { return }
        if trimmed != activeBranchID {
            // Invalidate the previous branch before accepting a new request. The service
            // completion may still arrive, but it no longer owns this readback.
            activeFetchID = nil
            isRefreshing = false
            activeBranchID = trimmed
            clearTelemetry()
            state = trimmed.isEmpty ? .ready : .loading
        }
        fetchShiftTelemetry()
    }

    func retry() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        fetchShiftTelemetry()
    }

    private func clearTelemetry() {
        todayReceiptsCount = 0
        todaySalesTotal = 0.0
        cashSalesTotal = 0.0
        cardSalesTotal = 0.0
        refundsCount = 0
        lastFetchDate = nil
    }

    func fetchShiftTelemetry() {
        guard !activeBranchID.isEmpty else {
            activeFetchID = nil
            isRefreshing = false
            clearTelemetry()
            state = .ready
            return
        }

        guard activeFetchID == nil else { return }
        let requestID = UUID()
        let requestedBranchID = activeBranchID
        activeFetchID = requestID
        isRefreshing = true
        if lastFetchDate == nil {
            state = .loading
        }

        PPPOSService.shared().fetchPOSHistory(branchID: requestedBranchID) { [weak self] receipts, error in
            Task { @MainActor in
                guard let self = self,
                      self.activeFetchID == requestID,
                      self.activeBranchID == requestedBranchID else { return }
                self.activeFetchID = nil
                self.isRefreshing = false

                if let error = error {
                    // Retain a successful snapshot without presenting a failed refresh
                    // as fresh or hiding the recovery action.
                    self.state = .error(error.localizedDescription)
                    return
                }

                self.lastFetchDate = Date()
                guard let receipts = receipts else {
                    self.state = .zero
                    self.todayReceiptsCount = 0
                    self.todaySalesTotal = 0.0
                    self.cashSalesTotal = 0.0
                    self.cardSalesTotal = 0.0
                    self.refundsCount = 0
                    return
                }

                let calendar = Calendar.current
                var count = 0
                var total: Double = 0.0
                var cash: Double = 0.0
                var card: Double = 0.0
                var refunds = 0

                for receipt in receipts {
                    let isToday: Bool
                    if let created = receipt.createdAt {
                        isToday = calendar.isDateInToday(created)
                    } else {
                        isToday = false
                    }

                    if isToday {
                        count += 1
                        total += receipt.total
                        let method = receipt.paymentMethod.lowercased()
                        if method.contains("cash") {
                            cash += receipt.total
                        } else {
                            card += receipt.total
                        }
                        if receipt.refundedAmount > 0 {
                            refunds += 1
                        }
                    }
                }

                self.todayReceiptsCount = count
                self.todaySalesTotal = total
                self.cashSalesTotal = cash
                self.cardSalesTotal = card
                self.refundsCount = refunds

                if count == 0 {
                    self.state = .zero
                } else {
                    self.state = .ready
                }
            }
        }
    }
}

// MARK: - Home POS: one register, one set of operational actions

private enum CommandPOSHomeCopy {
    static func text(_ suffix: String) -> String {
        Language.get("AdminPOS_Home_" + suffix, alter: "")
    }
}

private struct CommandPOSHomePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(AdminSurface.primaryText.opacity(configuration.isPressed ? 0.055 : 0),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CommandPOSSectionWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CommandPOSDeck: View {
    var isRegular: Bool = false
    var isLandscape: Bool = false
    var containerWidth: CGFloat = 0
    let canOpenWantedPets: Bool
    let onRoute: (String) -> Void

    @ObservedObject private var branchStore = BranchContextStore.shared
    @StateObject private var telemetryStore = CommandPOSShiftTelemetryStore()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var measuredWidth: CGFloat = 0
    @State private var isTelemetryExpanded: Bool? = nil
    @State private var showsQuickExpenseSheet = false

    private var currentBranchName: String {
        let name = branchStore.currentBranchDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Language.get("Branch_Scope_Active", alter: "") : name
    }

    private var usesColumns: Bool {
        isRegular && !dynamicTypeSize.isAccessibilitySize &&
            (measuredWidth > 0 ? measuredWidth : containerWidth) >= 740
    }

    private var showsDetails: Bool { isTelemetryExpanded ?? isRegular }
    private var hasBranch: Bool { !telemetryStore.activeBranchID.isEmpty }
    private var hasFigures: Bool { hasBranch && telemetryStore.lastFetchDate != nil }
    private var arrow: String { Language.isRTL() ? "arrow.left" : "arrow.right" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(CommandPOSHomeCopy.text("Title"))
                .font(AdminType.title2)
                .foregroundStyle(AdminSurface.primaryText)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 20) {
                operatorHeader
                rule
                if usesColumns {
                    HStack(alignment: .top, spacing: 24) {
                        registerActions.frame(maxWidth: .infinity, alignment: .leading)
                        supportingActions.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    registerActions
                    supportingActions
                }
                rule
                shiftSummary
            }
            .padding(isRegular ? 24 : 16)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: contrast == .increased ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: Language.isRTL() ? "ar" : "en"))
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: CommandPOSSectionWidthKey.self, value: geometry.size.width)
            }
        }
        .onPreferenceChange(CommandPOSSectionWidthKey.self) { width in
            if abs(measuredWidth - width) > 0.5 { measuredWidth = width }
        }
        .onAppear {
            telemetryStore.updateBranch(branchID: branchStore.activeBranch?.branchID ?? "")
        }
        .onReceive(branchStore.$activeBranch) { branch in
            telemetryStore.updateBranch(branchID: branch?.branchID ?? "")
        }
        .fullScreenCover(isPresented: $showsQuickExpenseSheet) {
            CommandPOSQuickExpenseSheet(currentBranchName: currentBranchName, onRoute: onRoute)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.pos.section")
    }

    private var operatorHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(currentBranchName, systemImage: "building.2")
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Label(telemetryStore.activeStaffName, systemImage: "person.crop.circle")
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { telemetryStore.retry() } label: {
                ZStack {
                    if telemetryStore.isRefreshing {
                        ProgressView().tint(AdminSurface.primaryText)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(width: 48, height: 48)
                .foregroundStyle(AdminSurface.primaryText)
                .background(AdminSurface.control, in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(CommandPOSHomePressStyle())
            .disabled(telemetryStore.isRefreshing || !hasBranch)
            .accessibilityLabel(CommandPOSHomeCopy.text("Refresh"))
            .accessibilityIdentifier("home.pos.refresh")
        }
    }

    private var registerActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onRoute("pos")
            } label: {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 12) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 27, weight: .medium))
                                .foregroundStyle(AdminSurface.primaryText)
                                .frame(width: 52, height: 52)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .accessibilityHidden(true)
                        }
                        Label(accessTitle, systemImage: telemetryStore.canSell ? "checkmark.circle" : "eye")
                            .font(AdminType.footnoteBold)
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: arrow)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(AdminSurface.primaryText)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(CommandPOSHomeCopy.text(telemetryStore.canSell ? "StartSale" : "Browse"))
                            .font(AdminType.title)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(CommandPOSHomeCopy.text(telemetryStore.canSell ? "SaleDetail" : "BrowseDetail"))
                            .font(AdminType.callout)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.primary.opacity(colorScheme == .dark ? 0.14 : 0.065),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(CommandPOSHomePressStyle())
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel(CommandPOSHomeCopy.text(telemetryStore.canSell ? "StartSale" : "Browse"))
            .accessibilityValue(accessTitle)
            .accessibilityHint(CommandPOSHomeCopy.text("StartHint"))
            .accessibilityIdentifier(isRegular ? "admin.command.pos.card" : "home.pos.startSale")

            if isRegular {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRoute("pos")
                } label: {
                    Label(CommandPOSHomeCopy.text("QuickScan"), systemImage: "viewfinder")
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CommandPOSHomePressStyle())
                .keyboardShortcut("b", modifiers: .command)
                .accessibilityIdentifier("home.pos.quickScan")
            }
        }
    }

    private var accessTitle: String {
        if telemetryStore.canSell { return CommandPOSHomeCopy.text("Ready") }
        if telemetryStore.canView { return CommandPOSHomeCopy.text("ViewOnly") }
        return CommandPOSHomeCopy.text("Restricted")
    }

    private var supportingActions: some View {
        VStack(spacing: 0) {
            CommandPOSHomeAction(title: CommandPOSHomeCopy.text("Receipts"),
                                 detail: CommandPOSHomeCopy.text("ReceiptsDetail"),
                                 symbol: "doc.text.magnifyingglass", identifier: "home.pos.receipts",
                                 showsDetail: isRegular) {
                onRoute("posHistory")
            }
            .keyboardShortcut("h", modifiers: .command)
            rule
            CommandPOSHomeAction(title: CommandPOSHomeCopy.text("Expense"),
                                 detail: CommandPOSHomeCopy.text("ExpenseDetail"),
                                 symbol: "plus.circle", identifier: "home.pos.expense",
                                 showsDetail: isRegular) {
                showsQuickExpenseSheet = true
            }
            .keyboardShortcut("e", modifiers: .command)
            if canOpenWantedPets {
                rule
                CommandPOSHomeAction(title: CommandPOSHomeCopy.text("Wanted"),
                                     detail: CommandPOSHomeCopy.text("WantedDetail"),
                                     symbol: "pawprint", identifier: "pos.wantedPets.entry") {
                    onRoute("wantedPets")
                }
                .accessibilityHint(Language.get("WantedPets_POS_Entry_Hint", alter: ""))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var shiftSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isTelemetryExpanded = !showsDetails
                }
            } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) {
                        shiftHeading.fixedSize(horizontal: true, vertical: true)
                        Spacer(minLength: 0)
                        shiftTotal.fixedSize(horizontal: true, vertical: true)
                        disclosureIcon
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            shiftHeading
                            Spacer(minLength: 8)
                            disclosureIcon
                        }
                        shiftTotal
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(CommandPOSHomePressStyle())
            .accessibilityLabel(CommandPOSHomeCopy.text(showsDetails ? "HideDetails" : "Details"))
            .accessibilityValue(CommandPOSHomeCopy.text(showsDetails ? "ExpandValue" : "CollapseValue") +
                                (hasFigures ? ", " + telemetryStore.formattedTodaySales : ""))
            .accessibilityIdentifier("home.pos.salesDisclosure")

            sourceStatus
            if showsDetails && hasFigures {
                CommandPOSHomeFigures(telemetryStore: telemetryStore, usesColumns: usesColumns)
                    .transition(.opacity)
            }
        }
    }

    private var shiftHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(CommandPOSHomeCopy.text("Shift"))
                .font(AdminType.subheadlineBold)
                .foregroundStyle(AdminSurface.primaryText)
            Text(Language.get("AdminPOS_TodaySales_Title", alter: ""))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var shiftTotal: some View {
        if hasFigures {
            Text(telemetryStore.formattedTodaySales)
                .font(AdminType.title2)
                .foregroundStyle(AdminSurface.primaryText)
                .monospacedDigit()
                .environment(\.layoutDirection, .leftToRight)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disclosureIcon: some View {
        Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AdminSurface.secondaryText)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var sourceStatus: some View {
        if !hasBranch {
            statusText(CommandPOSHomeCopy.text("BranchMissing"), symbol: "building.2", isError: false)
        } else if telemetryStore.isRefreshing {
            statusText(CommandPOSHomeCopy.text("Loading"), symbol: "arrow.clockwise", isError: false)
        } else if case .error = telemetryStore.state {
            statusText(CommandPOSHomeCopy.text("Error"), symbol: "exclamationmark.circle", isError: true)
            if hasFigures {
                Text(CommandPOSHomeCopy.text("Retained"))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { telemetryStore.retry() } label: {
                Label(CommandPOSHomeCopy.text("Refresh"), systemImage: "arrow.clockwise")
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CommandPOSHomePressStyle())
            .accessibilityIdentifier("home.pos.retry")
        } else if telemetryStore.state == .zero {
            statusText(CommandPOSHomeCopy.text("Empty"), symbol: "tray", isError: false)
        }
        if let updatedAt = telemetryStore.lastFetchDate {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    updatedLabel.fixedSize()
                    updatedTime(updatedAt).fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) { updatedLabel; updatedTime(updatedAt) }
            }
            .font(AdminType.caption)
            .foregroundStyle(AdminSurface.secondaryText)
            .accessibilityElement(children: .combine)
        }
    }

    private var updatedLabel: some View { Text(CommandPOSHomeCopy.text("Updated")) }
    private func updatedTime(_ date: Date) -> some View {
        Text(date, style: .time).monospacedDigit().environment(\.layoutDirection, .leftToRight)
    }

    private func statusText(_ text: String, symbol: String, isError: Bool) -> some View {
        Label(text, systemImage: symbol)
            .font(AdminType.footnote)
            .foregroundStyle(isError ? AdminSurface.crimson : AdminSurface.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rule: some View {
        Rectangle().fill(AdminSurface.hairline).frame(height: 1).accessibilityHidden(true)
    }
}

private struct CommandPOSHomeAction: View {
    let title: String
    let detail: String
    let symbol: String
    let identifier: String
    var showsDetail: Bool = true
    let action: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(AdminType.headline).foregroundStyle(AdminSurface.primaryText)
                    if showsDetail {
                        Text(detail).font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandPOSHomePressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityIdentifier(identifier)
    }
}

private struct CommandPOSHomeFigures: View {
    @ObservedObject var telemetryStore: CommandPOSShiftTelemetryStore
    let usesColumns: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if usesColumns {
                HStack(alignment: .top, spacing: 32) {
                    receiptFigures.frame(maxWidth: .infinity)
                    tenderFigures.frame(maxWidth: .infinity)
                }
            } else {
                receiptFigures
                tenderFigures
            }
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var receiptFigures: some View {
        VStack(spacing: 12) {
            figure("AdminPOS_Metric_Receipts", value: String(telemetryStore.todayReceiptsCount))
            figure("AdminPOS_Metric_AOV", value: telemetryStore.formattedAverageOrderValue)
            figure("AdminPOS_Metric_Refunds", value: String(telemetryStore.refundsCount))
        }
    }

    private var tenderFigures: some View {
        VStack(spacing: 12) {
            figure("AdminPOS_Tender_Cash", value: telemetryStore.formattedCashSales)
            figure("AdminPOS_Tender_Card", value: telemetryStore.formattedCardSales)
            if telemetryStore.todaySalesTotal > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        AdminSurface.primary.frame(width: geometry.size.width * telemetryStore.cashRatio)
                        AdminSurface.secondaryText.opacity(0.35)
                    }
                }
                .frame(height: 5)
                .clipShape(Capsule())
                .accessibilityHidden(true)
            }
        }
    }

    private func figure(_ key: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                figureLabel(key).fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 0)
                figureValue(value).fixedSize(horizontal: true, vertical: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                figureLabel(key)
                figureValue(value)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get(key, alter: ""))
        .accessibilityValue(value)
    }

    private func figureLabel(_ key: String) -> some View {
        Text(Language.get(key, alter: ""))
            .font(AdminType.subheadline)
            .foregroundStyle(AdminSurface.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func figureValue(_ value: String) -> some View {
        Text(value)
            .font(AdminType.headline)
            .foregroundStyle(AdminSurface.primaryText)
            .monospacedDigit()
            .environment(\.layoutDirection, .leftToRight)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Category-Defining POS Shift Expense Studio (Dedicated iPhone & iPad Architectures)

@MainActor
private final class CommandPOSQuickExpensePresenter: ObservableObject {
    @Published var amountText: String = ""
    @Published var selectedCategory: String = "supplies"
    @Published var descriptionText: String = ""
    @Published var isSubmitting: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showSuccessBanner: Bool = false
    @Published var recentVouchers: [PPAccountingExpense] = []
    @Published var todayExpenseTotal: Double = 0.0
    @Published var todayExpenseCount: Int = 0

    struct ReasonTagItem: Hashable {
        let key: String
        let fallback: String
        var localizedText: String {
            Language.get(key, alter: fallback)
        }
    }

    struct CategoryItem: Identifiable, Hashable {
        let id: String
        let titleKey: String
        let fallback: String
        let icon: String
        let iconTintColor: Color
        let iconBgColor: Color
        let tags: [ReasonTagItem]

        var localizedTitle: String {
            Language.get(titleKey, alter: fallback)
        }

        var reasonTags: [String] {
            tags.map { $0.localizedText }
        }
    }

    let categories: [CategoryItem] = [
        CategoryItem(
            id: "salary",
            titleKey: "AdminPOS_Category_Salary",
            fallback: "راتب",
            icon: "person.2.fill",
            iconTintColor: .white,
            iconBgColor: Color(red: 0.65, green: 0.48, blue: 0.96),
            tags: [
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_SalaryAdvance", fallback: "سلفة موظف"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Bonus", fallback: "مكافأة فورية"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Transport", fallback: "بدل انتقال")
            ]
        ),
        CategoryItem(
            id: "rent",
            titleKey: "AdminPOS_Category_Rent",
            fallback: "إيجار",
            icon: "building.2.fill",
            iconTintColor: .white,
            iconBgColor: Color(red: 0.96, green: 0.56, blue: 0.24),
            tags: [
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_StoreRent", fallback: "دفعة إيجار فرع"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_HousingRent", fallback: "إيجار سكن موظفين"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_WarehouseRent", fallback: "إيجار مستودع")
            ]
        ),
        CategoryItem(
            id: "supplies",
            titleKey: "AdminPOS_Category_Supplies",
            fallback: "لوازم",
            icon: "shippingbox.fill",
            iconTintColor: .white,
            iconBgColor: Color(red: 0.18, green: 0.56, blue: 0.98),
            tags: [
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Bags", fallback: "أكياس ومواد تغليف"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Cleaning", fallback: "منظفات ومطهرات فرع"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Water", fallback: "مياه وضيافة عملاء"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Supplies", fallback: "أدوات ومستلزمات متجر")
            ]
        ),
        CategoryItem(
            id: "bills",
            titleKey: "AdminPOS_Category_Bills",
            fallback: "فواتير",
            icon: "bolt.fill",
            iconTintColor: Color(red: 0.92, green: 0.62, blue: 0.05),
            iconBgColor: Color(red: 0.99, green: 0.93, blue: 0.76),
            tags: [
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Electricity", fallback: "فاتورة كهرباء وماء"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Telecom", fallback: "فاتورة إنترنت واتصالات"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Municipal", fallback: "رسوم بلدية وتراخيص")
            ]
        ),
        CategoryItem(
            id: "marketing",
            titleKey: "AdminPOS_Category_Marketing",
            fallback: "تسويق",
            icon: "megaphone.fill",
            iconTintColor: Color(red: 0.95, green: 0.28, blue: 0.50),
            iconBgColor: Color(red: 0.99, green: 0.88, blue: 0.92),
            tags: [
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_LocalAds", fallback: "إعلانات وترويج محلي"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_PrintAds", fallback: "مطبوعات وبنرات فرع"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_PromoGifts", fallback: "عينات وهدايا ترويجية")
            ]
        ),
        CategoryItem(
            id: "logistics",
            titleKey: "AdminPOS_Category_Logistics",
            fallback: "اللوجستيات والتوصيل",
            icon: "truck.box.fill",
            iconTintColor: Color(red: 0.32, green: 0.44, blue: 0.94),
            iconBgColor: Color(red: 0.89, green: 0.92, blue: 0.99),
            tags: [
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Delivery", fallback: "أجرة توصيل طارئة"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_ExpressShipping", fallback: "شحن وتوصيل مستعجل"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_DriverTip", fallback: "إكرامية سائق معتمدة"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_VehicleFuel", fallback: "وقود مركبة التوصيل")
            ]
        ),
        CategoryItem(
            id: "clinic",
            titleKey: "AdminPOS_Category_Clinic",
            fallback: "العيادة واللوازم الطبية",
            icon: "cross.case.fill",
            iconTintColor: Color(red: 0.12, green: 0.72, blue: 0.46),
            iconBgColor: Color(red: 0.88, green: 0.97, blue: 0.92),
            tags: [
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_MedicalGauze", fallback: "شاش ومطهرات طبية"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Medicines", fallback: "أدوية وإسعافات أولية"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_VetConsumables", fallback: "مستهلكات عيادة بيطرية")
            ]
        ),
        CategoryItem(
            id: "tech_maintenance",
            titleKey: "AdminPOS_Category_TechMaintenance",
            fallback: "التقنية والصيانة",
            icon: "wrench.and.screwdriver.fill",
            iconTintColor: Color(red: 0.14, green: 0.68, blue: 0.80),
            iconBgColor: Color(red: 0.88, green: 0.96, blue: 0.98),
            tags: [
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Maintenance", fallback: "صيانة عاجلة وأدوات"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Printer", fallback: "صيانة طابعة وفواتير"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Lighting", fallback: "إضاءة وكهرباء فرع"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Plumbing", fallback: "سباكة ومغاسل")
            ]
        ),
        CategoryItem(
            id: "inventory",
            titleKey: "AdminPOS_Category_Inventory",
            fallback: "المخزون والتوريد",
            icon: "cube.box.fill",
            iconTintColor: Color(red: 0.28, green: 0.58, blue: 0.92),
            iconBgColor: Color(red: 0.90, green: 0.95, blue: 1.0),
            tags: [
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_UrgentStock", fallback: "شراء بضاعة عاجلة"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_FreightFee", fallback: "رسوم تفريغ ونقل بضاعة"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_ShippingCartons", fallback: "تغليف وكراتين شحن")
            ]
        ),
        CategoryItem(
            id: "other",
            titleKey: "AdminPOS_Category_Other",
            fallback: "أخرى",
            icon: "ellipsis",
            iconTintColor: Color(red: 0.48, green: 0.50, blue: 0.55),
            iconBgColor: Color(red: 0.91, green: 0.92, blue: 0.94),
            tags: [
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Sundry", fallback: "نثريات تشغيلية"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_BranchPurchases", fallback: "مشتريات عاجلة للفرع"),
                ReasonTagItem(key: "AdminPOS_QuickExpense_Reason_Utilities", fallback: "رسوم خدمات عامة")
            ]
        )
    ]

    var currentCategoryItem: CategoryItem {
        categories.first(where: { $0.id == selectedCategory }) ?? categories[0]
    }

    var parsedAmount: Double? {
        let clean = amountText.normalizedEnglishDigits(allowsDecimal: true)
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let val = Double(clean), val > 0, val.isFinite else { return nil }
        return val
    }

    var formattedAmountDisplay: String {
        let text = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "0.00" : text
    }

    func addPreset(delta: Double) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let current = parsedAmount ?? 0.0
        let newTotal = current + delta
        if newTotal == floor(newTotal) {
            amountText = String(format: "%.2f", newTotal)
        } else {
            amountText = String(format: "%.2f", newTotal)
        }
        errorMessage = nil
    }

    func clearAmount() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        amountText = ""
        errorMessage = nil
    }

    func selectCategory(_ categoryId: String) {
        UISelectionFeedbackGenerator().selectionChanged()
        selectedCategory = categoryId
    }

    func applyReasonTag(_ tag: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        descriptionText = tag
    }

    func loadShiftTelemetry() {
        let allExpenses = PPAccountingService.shared().expenses ?? []
        let calendar = Calendar.current
        let todayExpenses = allExpenses.filter { expense in
            guard let created = expense.createdAt else { return false }
            return calendar.isDateInToday(created)
        }
        recentVouchers = Array(todayExpenses.prefix(8))
        todayExpenseCount = todayExpenses.count
        todayExpenseTotal = todayExpenses.reduce(0.0) { $0 + $1.amount }
    }

    private var onExpenseSuccess: (@MainActor @Sendable () -> Void)? = nil

    func submitExpense(onSuccess: (@MainActor @Sendable () -> Void)? = nil) {
        if let onSuccess {
            self.onExpenseSuccess = onSuccess
        }
        guard let amount = parsedAmount else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            errorMessage = Language.get("AdminPOS_QuickExpense_ValidationAmount", alter: "يرجى إدخال مبلغ صالح أكبر من صفر")
            return
        }

        errorMessage = nil
        isSubmitting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        PPAccountingService.shared().addExpense(
            amount,
            category: selectedCategory,
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        ) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isSubmitting = false
                if let error = error {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    self.errorMessage = error.localizedDescription
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        self.showSuccessBanner = true
                    }
                    self.loadShiftTelemetry()
                    try? await Task.sleep(nanoseconds: 850_000_000)
                    guard !Task.isCancelled else { return }
                    self.onExpenseSuccess?()
                }
            }
        }
    }
}

// MARK: - Dedicated Button Press Style with Haptic Spring

private struct CommandQuickExpensePressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? (reduceMotion ? 0.98 : 0.96) : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(configuration.isPressed ? (reduceMotion ? nil : .easeOut(duration: 0.08)) : (reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72)), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - iPhone Dedicated Architecture: Thumb-Zone Express Cashier Studio

private struct CommandPOSQuickExpenseView_iPhone: View {
    @ObservedObject var presenter: CommandPOSQuickExpensePresenter
    let currentBranchName: String
    let onRoute: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let coral = Color(red: 0.96, green: 0.44, blue: 0.30)

    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.97))
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 1. Active Shift Status Filament
                        activeShiftFilament

                        // 2. Tactile Cash Voucher Slip (Hero Chamber)
                        digitalVoucherSlip

                        // 3. Rapid Denomination Preset Bubbles
                        denominationBubblesRow

                        // 4. Category Selector (2-Column Grid matching media_1789251697960.png)
                        categoryCarouselDeck

                        // 5. Smart Contextual Auto-Fill Reason Tags
                        quickReasonTagsDeck

                        // 6. Reason & Notes Field
                        notesInputCard

                        // 7. Micro Shift Footprint Summary
                        shiftFootprintPill

                        // 8. Security & Immutable Audit Notice
                        auditAssuranceFilament

                        // 9. Error Banner (if present)
                        if let error = presenter.errorMessage {
                            errorBanner(message: error)
                        }

                        // 10. Success Confirmation Seal
                        if presenter.showSuccessBanner {
                            successBanner
                        }

                        // 11. Primary Sticky Commit Action Button
                        submitActionButton

                        // 12. General Accounting Deep Link
                        viewAccountingLink
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(Language.get("Cancel", alter: "إلغاء"))
                            .font(PPBeirutiFont.bold(15, relativeTo: .body))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(Language.get("AdminPOS_QuickExpense_SheetTitle", alter: "تسجيل مصروف وردية"))
                            .font(PPBeirutiFont.bold(16, relativeTo: .headline))
                            .foregroundStyle(AdminSurface.primaryText)
                            .multilineTextAlignment(.center)

                        Text(currentBranchName)
                            .font(PPBeirutiFont.regular(12, relativeTo: .caption))
                            .foregroundStyle(AdminCommandInk.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            presenter.loadShiftTelemetry()
        }
    }

    private var activeShiftFilament: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 0.10, green: 0.74, blue: 0.54))
                .frame(width: 7, height: 7)
                .shadow(color: Color(red: 0.10, green: 0.74, blue: 0.54).opacity(0.6), radius: 3)

            Text(Language.get("AdminPOS_QuickExpense_ActiveShiftPill", alter: "الوردية نشطة • صرف مباشر"))
                .font(PPBeirutiFont.bold(11.5, relativeTo: .caption))
                .foregroundStyle(Color(red: 0.10, green: 0.74, blue: 0.54))
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            Text(currentBranchName)
                .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                .foregroundStyle(AdminCommandInk.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.35 : 0.15), lineWidth: 0.75)
        )
    }

    private var digitalVoucherSlip: some View {
        VStack(spacing: 8) {
            HStack {
                Text(Language.get("AdminPOS_QuickExpense_Amount", alter: "مبلغ المصروف (ر.ق)"))
                    .font(PPBeirutiFont.bold(12.5, relativeTo: .subheadline))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .multilineTextAlignment(.leading)

                Spacer()

                if !presenter.amountText.isEmpty {
                    Button {
                        presenter.clearAmount()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(Language.get("AdminPOS_QuickExpense_Clear", alter: "تفريغ"))
                                .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                        }
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0.00", text: $presenter.amountText)
                    .font(PPBeirutiFont.bold(42, relativeTo: .largeTitle))
                    .foregroundStyle(coral)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .onChange(of: presenter.amountText) { val in
                        let clean = val.normalizedEnglishDigits(allowsDecimal: true)
                        if clean != val { presenter.amountText = clean }
                        if presenter.errorMessage != nil { presenter.errorMessage = nil }
                    }

                Text(Language.get("Currency_QAR", alter: Language.isRTL() ? "ر.ق" : "QAR"))
                    .font(PPBeirutiFont.bold(16, relativeTo: .headline))
                    .foregroundStyle(coral)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        coral.opacity(colorScheme == .dark ? 0.22 : 0.12),
                        in: Capsule()
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(coral.opacity(colorScheme == .dark ? 0.35 : 0.20), lineWidth: 1.2)
        )
        .shadow(color: coral.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 8, y: 3)
    }

    private var denominationBubblesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Language.get("AdminPOS_QuickExpense_QuickPresets", alter: "فئات الإضافة السريعة"))
                .font(PPBeirutiFont.bold(11.5, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let presets: [Double] = [10, 25, 50, 100, 500]
                    ForEach(presets, id: \.self) { val in
                        Button {
                            presenter.addPreset(delta: val)
                        } label: {
                            HStack(spacing: 2.5) {
                                Text("+")
                                    .font(PPBeirutiFont.bold(11, relativeTo: .caption2))
                                Text(String(format: "%.0f", val))
                                    .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                                Text(Language.get("Currency_QAR", alter: Language.isRTL() ? "ر.ق" : "QAR"))
                                    .font(PPBeirutiFont.medium(9.5, relativeTo: .caption2))
                            }
                            .foregroundStyle(AdminSurface.primaryText)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.40 : 0.22), lineWidth: 0.8)
                            )
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03), radius: 3, y: 1.5)
                        }
                        .buttonStyle(CommandQuickExpensePressStyle(reduceMotion: reduceMotion))
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
    }

    private var categoryCarouselDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("AdminPOS_QuickExpense_Category", alter: "التصنيف"))
                .font(PPBeirutiFont.bold(13, relativeTo: .headline))
                .foregroundStyle(AdminCommandInk.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 2)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(presenter.categories) { cat in
                    let isSelected = presenter.selectedCategory == cat.id
                    Button {
                        presenter.selectCategory(cat.id)
                    } label: {
                        HStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(cat.iconBgColor)
                                    .frame(width: 30, height: 30)

                                Image(systemName: cat.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(cat.iconTintColor)
                            }

                            Text(cat.localizedTitle)
                                .font(PPBeirutiFont.bold(11.5, relativeTo: .caption))
                                .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.primaryText.opacity(0.90))
                                .lineLimit(2)
                                .minimumScaleFactor(0.70)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color(red: 0.85, green: 0.15, blue: 0.35))
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.blue.opacity(0.18) : Color(red: 0.94, green: 0.97, blue: 1.0))
                                        : (colorScheme == .dark ? Color(white: 0.12) : Color.white)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isSelected
                                        ? Color(red: 0.20, green: 0.60, blue: 1.0)
                                        : (colorScheme == .dark ? Color.white.opacity(0.12) : Color(red: 0.91, green: 0.91, blue: 0.93)),
                                    lineWidth: isSelected ? 1.6 : 0.8
                                )
                        )
                        .shadow(color: isSelected ? Color(red: 0.20, green: 0.60, blue: 1.0).opacity(colorScheme == .dark ? 0.25 : 0.10) : Color.clear, radius: 4, y: 1.5)
                    }
                    .buttonStyle(CommandQuickExpensePressStyle(reduceMotion: reduceMotion))
                }
            }
        }
    }

    private var quickReasonTagsDeck: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Language.get("AdminPOS_QuickExpense_QuickReasons", alter: "أسباب شائعة للتحديد الفوري"))
                .font(PPBeirutiFont.bold(11.5, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presenter.currentCategoryItem.reasonTags, id: \.self) { tag in
                        let isApplied = presenter.descriptionText == tag
                        Button {
                            presenter.applyReasonTag(tag)
                        } label: {
                            Text(tag)
                                .font(PPBeirutiFont.medium(11.5, relativeTo: .caption))
                                .foregroundStyle(
                                    isApplied ? Color(red: 0.18, green: 0.56, blue: 0.98) : AdminSurface.primaryText
                                )
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(
                                            isApplied
                                                ? Color(red: 0.18, green: 0.56, blue: 0.98).opacity(0.12)
                                                : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(
                                            isApplied ? Color(red: 0.18, green: 0.56, blue: 0.98).opacity(0.5) : Color(uiColor: .ppSurfaceBorder).opacity(0.25),
                                            lineWidth: 0.8
                                        )
                                )
                        }
                        .buttonStyle(CommandQuickExpensePressStyle(reduceMotion: reduceMotion))
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
    }

    private var notesInputCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Language.get("AdminPOS_QuickExpense_Notes", alter: "بيان وسبب الصرف"))
                .font(PPBeirutiFont.bold(12, relativeTo: .subheadline))
                .foregroundStyle(AdminCommandInk.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.18, green: 0.56, blue: 0.98))

                TextField(
                    Language.get("AdminPOS_QuickExpense_NotesPlaceholder", alter: "مثال: أدوات نظافة، أكياس، عهدة نثرية، صيانة سريعة..."),
                    text: $presenter.descriptionText
                )
                .font(PPBeirutiFont.regular(13.5, relativeTo: .body))
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.leading)

                if !presenter.descriptionText.isEmpty {
                    Button {
                        presenter.descriptionText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.35), lineWidth: 0.8)
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.35 : 0.15), lineWidth: 0.75)
        )
    }

    private var shiftFootprintPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(coral)

            Text(Language.get("AdminPOS_QuickExpense_ShiftTotalLabel", alter: "إجمالي مصروفات اليوم") + ":")
                .font(PPBeirutiFont.regular(11.5, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .multilineTextAlignment(.leading)

            Text(String(format: "%.2f %@", presenter.todayExpenseTotal, Language.get("Currency_QAR", alter: Language.isRTL() ? "ر.ق" : "QAR")))
                .font(PPBeirutiFont.bold(12, relativeTo: .subheadline))
                .foregroundStyle(coral)

            Spacer()

            Text("(\(presenter.todayExpenseCount) " + Language.get("AdminPOS_QuickExpense_ShiftCountLabel", alter: "سند") + ")")
                .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                .foregroundStyle(AdminSurface.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(coral.opacity(colorScheme == .dark ? 0.12 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(coral.opacity(0.20), lineWidth: 0.75)
        )
    }

    private var auditAssuranceFilament: some View {
        HStack(spacing: 7) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(red: 0.10, green: 0.74, blue: 0.54))

            Text(Language.get("AdminPOS_QuickExpense_VoucherAuditNotice", alter: "سند قيد فوري موثق بالرقم السري وهويتك الإدارية في السحابة"))
                .font(PPBeirutiFont.regular(11.5, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 8)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(uiColor: .ppError))
            Text(message)
                .font(PPBeirutiFont.medium(12.5, relativeTo: .caption))
                .foregroundStyle(Color(uiColor: .ppError))
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(Color(uiColor: .ppError).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .transition(.opacity)
    }

    private var successBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))
            Text(Language.get("AdminPOS_QuickExpense_Success", alter: "تم تسجيل المصروف وتوثيقه بنجاح"))
                .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(Color(red: 0.06, green: 0.78, blue: 0.56).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .transition(.scale.combined(with: .opacity))
    }

    private var submitActionButton: some View {
        Button {
            presenter.submitExpense {
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if presenter.isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                }

                Text(Language.get("AdminPOS_QuickExpense_Confirm", alter: "اعتماد الصرف وتوثيق السند"))
                    .font(PPBeirutiFont.bold(15, relativeTo: .headline))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(coral)
            )
            .shadow(color: coral.opacity(0.35), radius: 8, y: 3)
        }
        .buttonStyle(CommandQuickExpensePressStyle(reduceMotion: reduceMotion))
        .disabled(presenter.isSubmitting)
        .opacity(presenter.isSubmitting ? 0.72 : 1.0)
    }

    private var viewAccountingLink: some View {
        Button {
            dismiss()
            onRoute("accounting")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                Text(Language.get("AdminPOS_QuickExpense_ViewAccounting", alter: "فتح سجل الحسابات العام"))
                    .font(PPBeirutiFont.bold(12.5, relativeTo: .subheadline))
            }
            .foregroundStyle(AdminCommandInk.secondary)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - iPad Dedicated Architecture: Widescreen Countertop Financial Studio

private struct CommandPOSQuickExpenseView_iPad: View {
    @ObservedObject var presenter: CommandPOSQuickExpensePresenter
    let currentBranchName: String
    let onRoute: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let coral = Color(red: 0.96, green: 0.44, blue: 0.30)

    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
                    .ignoresSafeArea()

                HStack(alignment: .top, spacing: 20) {
                    // Left Column (58%): Active Voucher Creation Forge
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Studio Header with Active Station Pulse
                            stationHeaderCard

                            // Large Express Amount Deck with Keypad & Presets
                            amountExpressDeck

                            // 2-Column Rich Category Matrix matching media_1789251697960.png
                            categoryMatrixDeck

                            // Smart Auto-Fill Reason Grid
                            quickReasonChipsDeck

                            // Multi-Line Description Editor
                            notesEditorDeck

                            // Error Banner
                            if let error = presenter.errorMessage {
                                errorBanner(message: error)
                            }

                            // Success Confirmation
                            if presenter.showSuccessBanner {
                                successBanner
                            }

                            // Primary Authorization Action Button (⌘+Return)
                            submitActionButton
                        }
                        .padding(.vertical, 16)
                        .padding(.leading, 20)
                        .padding(.trailing, 8)
                    }
                    .frame(maxWidth: .infinity)

                    // Right Column (42%): Shift Financial Telemetry & Live Vouchers Deck
                    VStack(spacing: 14) {
                        // Live Shift Telemetry Card
                        shiftTelemetryCard

                        // Live Recent Vouchers Feed for this shift
                        recentVouchersDeck

                        // Audit & Security Seal
                        auditSealCard

                        // Full Accounting Portal Link
                        accountingWorkspacePortalButton
                    }
                    .padding(.vertical, 16)
                    .padding(.trailing, 20)
                    .padding(.leading, 8)
                    .frame(width: 350)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                            Text(Language.get("Cancel", alter: "إلغاء"))
                                .font(PPBeirutiFont.bold(14, relativeTo: .headline))
                        }
                        .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "creditcard.and.123")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(coral)

                        Text(Language.get("AdminPOS_QuickExpense_SheetTitle", alter: "تسجيل مصروف وردية"))
                            .font(PPBeirutiFont.bold(17, relativeTo: .title3))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text("•")
                            .foregroundStyle(AdminSurface.secondaryText)

                        Text(currentBranchName)
                            .font(PPBeirutiFont.medium(13.5, relativeTo: .subheadline))
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Text(Language.get("AdminPOS_QuickExpense_KeyboardHint", alter: "اختصار الاعتماد: ⌘ + Return"))
                        .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                }
            }
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            presenter.loadShiftTelemetry()
        }
    }

    private var stationHeaderCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(coral.opacity(colorScheme == .dark ? 0.25 : 0.12))
                    .frame(width: 42, height: 42)

                Image(systemName: "banknote.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(coral)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.10, green: 0.74, blue: 0.54))
                        .frame(width: 7, height: 7)

                    Text(Language.get("AdminPOS_QuickExpense_ActiveShiftPill", alter: "الوردية نشطة • صرف مباشر"))
                        .font(PPBeirutiFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(Color(red: 0.10, green: 0.74, blue: 0.54))
                        .multilineTextAlignment(.leading)
                }

                Text(Language.get("AdminPOS_QuickExpense_SheetSubtitle", alter: "تسجيل عملية صرف فوري من صندوق الكاشير وتوثيقها تلقائياً"))
                    .font(PPBeirutiFont.regular(11.5, relativeTo: .caption))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(currentBranchName)
                    .font(PPBeirutiFont.bold(12.5, relativeTo: .subheadline))
                    .foregroundStyle(AdminSurface.primaryText)

                Text(Date(), style: .time)
                    .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.35 : 0.15), lineWidth: 0.8)
        )
    }

    private var amountExpressDeck: some View {
        VStack(spacing: 12) {
            HStack {
                Text(Language.get("AdminPOS_QuickExpense_Amount", alter: "مبلغ المصروف (ر.ق)"))
                    .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .multilineTextAlignment(.leading)

                Spacer()

                if !presenter.amountText.isEmpty {
                    Button {
                        presenter.clearAmount()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(Language.get("AdminPOS_QuickExpense_Clear", alter: "تفريغ"))
                                .font(PPBeirutiFont.bold(12, relativeTo: .subheadline))
                        }
                        .foregroundStyle(coral)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(coral.opacity(0.10), in: Capsule())
                    }
                    .hoverEffect(.highlight)
                }
            }

            // Hero Typographic Numeric Input Display
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("0.00", text: $presenter.amountText)
                    .font(PPBeirutiFont.bold(48, relativeTo: .largeTitle))
                    .foregroundStyle(coral)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .onChange(of: presenter.amountText) { val in
                        let clean = val.normalizedEnglishDigits(allowsDecimal: true)
                        if clean != val { presenter.amountText = clean }
                        if presenter.errorMessage != nil { presenter.errorMessage = nil }
                    }

                Text(Language.get("Currency_QAR", alter: Language.isRTL() ? "ر.ق" : "QAR"))
                    .font(PPBeirutiFont.bold(18, relativeTo: .headline))
                    .foregroundStyle(coral)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        coral.opacity(colorScheme == .dark ? 0.22 : 0.12),
                        in: Capsule()
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            // Rapid Denomination Presets Bar
            HStack(spacing: 8) {
                let presets: [Double] = [10, 25, 50, 100, 200, 500]
                ForEach(presets, id: \.self) { val in
                    Button {
                        presenter.addPreset(delta: val)
                    } label: {
                        HStack(spacing: 3) {
                            Text("+")
                                .font(PPBeirutiFont.bold(11, relativeTo: .caption))
                            Text(String(format: "%.0f", val))
                                .font(PPBeirutiFont.bold(13.5, relativeTo: .subheadline))
                            Text(Language.get("Currency_QAR", alter: Language.isRTL() ? "ر.ق" : "QAR"))
                                .font(PPBeirutiFont.medium(10, relativeTo: .caption2))
                        }
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.40 : 0.20), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(CommandQuickExpensePressStyle(reduceMotion: reduceMotion))
                    .hoverEffect(.highlight)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.13) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(coral.opacity(colorScheme == .dark ? 0.40 : 0.22), lineWidth: 1.2)
        )
        .shadow(color: coral.opacity(colorScheme == .dark ? 0.20 : 0.06), radius: 10, y: 4)
    }

    private var categoryMatrixDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("AdminPOS_QuickExpense_Category", alter: "التصنيف"))
                .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                .foregroundStyle(AdminCommandInk.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(presenter.categories) { cat in
                    let isSelected = presenter.selectedCategory == cat.id
                    Button {
                        presenter.selectCategory(cat.id)
                    } label: {
                        HStack(spacing: 7) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(cat.iconBgColor)
                                    .frame(width: 32, height: 32)

                                Image(systemName: cat.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(cat.iconTintColor)
                            }

                            Text(cat.localizedTitle)
                                .font(PPBeirutiFont.bold(12, relativeTo: .subheadline))
                                .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.primaryText.opacity(0.90))
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color(red: 0.85, green: 0.15, blue: 0.35))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.blue.opacity(0.18) : Color(red: 0.94, green: 0.97, blue: 1.0))
                                        : (colorScheme == .dark ? Color(white: 0.12) : Color.white)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isSelected
                                        ? Color(red: 0.20, green: 0.60, blue: 1.0)
                                        : (colorScheme == .dark ? Color.white.opacity(0.12) : Color(red: 0.91, green: 0.91, blue: 0.93)),
                                    lineWidth: isSelected ? 1.6 : 0.8
                                )
                        )
                        .shadow(color: isSelected ? Color(red: 0.20, green: 0.60, blue: 1.0).opacity(colorScheme == .dark ? 0.25 : 0.10) : Color.clear, radius: 4, y: 1.5)
                    }
                    .buttonStyle(CommandQuickExpensePressStyle(reduceMotion: reduceMotion))
                    .hoverEffect(.lift)
                }
            }
        }
    }

    private var quickReasonChipsDeck: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("AdminPOS_QuickExpense_QuickReasons", alter: "أسباب شائعة للتحديد الفوري"))
                .font(PPBeirutiFont.bold(12, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presenter.currentCategoryItem.reasonTags, id: \.self) { tag in
                        let isApplied = presenter.descriptionText == tag
                        Button {
                            presenter.applyReasonTag(tag)
                        } label: {
                            Text(tag)
                                .font(PPBeirutiFont.medium(12, relativeTo: .caption))
                                .foregroundStyle(
                                    isApplied ? Color(red: 0.18, green: 0.56, blue: 0.98) : AdminSurface.primaryText
                                )
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(
                                            isApplied
                                                ? Color(red: 0.18, green: 0.56, blue: 0.98).opacity(0.14)
                                                : (colorScheme == .dark ? Color.white.opacity(0.07) : Color.white)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(
                                            isApplied ? Color(red: 0.18, green: 0.56, blue: 0.98).opacity(0.6) : Color(uiColor: .ppSurfaceBorder).opacity(0.25),
                                            lineWidth: 0.8
                                        )
                                )
                        }
                        .buttonStyle(CommandQuickExpensePressStyle(reduceMotion: reduceMotion))
                        .hoverEffect(.highlight)
                    }
                }
            }
        }
    }

    private var notesEditorDeck: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Language.get("AdminPOS_QuickExpense_Notes", alter: "بيان وسبب الصرف"))
                    .font(PPBeirutiFont.bold(12.5, relativeTo: .subheadline))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .multilineTextAlignment(.leading)

                Spacer()

                Text("\(presenter.descriptionText.count) / 250")
                    .font(PPBeirutiFont.regular(11, relativeTo: .caption2))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.18, green: 0.56, blue: 0.98))

                TextField(
                    Language.get("AdminPOS_QuickExpense_NotesPlaceholder", alter: "مثال: أدوات نظافة، أكياس، عهدة نثرية، صيانة سريعة..."),
                    text: $presenter.descriptionText
                )
                .font(PPBeirutiFont.regular(14, relativeTo: .body))
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.leading)

                if !presenter.descriptionText.isEmpty {
                    Button {
                        presenter.descriptionText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.35), lineWidth: 0.8)
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.13) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.35 : 0.15), lineWidth: 0.8)
        )
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(uiColor: .ppError))
            Text(message)
                .font(PPBeirutiFont.medium(13, relativeTo: .caption))
                .foregroundStyle(Color(uiColor: .ppError))
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .background(Color(uiColor: .ppError).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .transition(.opacity)
    }

    private var successBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))
            Text(Language.get("AdminPOS_QuickExpense_Success", alter: "تم تسجيل المصروف وتوثيقه بنجاح"))
                .font(PPBeirutiFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(Color(red: 0.06, green: 0.78, blue: 0.56))
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .background(Color(red: 0.06, green: 0.78, blue: 0.56).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .transition(.scale.combined(with: .opacity))
    }

    private var submitActionButton: some View {
        Button {
            presenter.submitExpense {
                dismiss()
            }
        } label: {
            HStack(spacing: 10) {
                if presenter.isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.0)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                }

                Text(Language.get("AdminPOS_QuickExpense_Confirm", alter: "اعتماد الصرف وتوثيق السند"))
                    .font(PPBeirutiFont.bold(16, relativeTo: .headline))

                Spacer()

                Text("⌘ ↵")
                    .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.20), in: Capsule())
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(coral)
            )
            .shadow(color: coral.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(CommandQuickExpensePressStyle(reduceMotion: reduceMotion))
        .hoverEffect(.lift)
        .keyboardShortcut(.defaultAction)
        .disabled(presenter.isSubmitting)
        .opacity(presenter.isSubmitting ? 0.72 : 1.0)
    }

    // MARK: - Right Column: Shift Telemetry & Live Vouchers Deck

    private var shiftTelemetryCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(coral)

                    Text(Language.get("AdminPOS_QuickExpense_ShiftTelemetry_Title", alter: "مؤشرات مصروفات الوردية"))
                        .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Text(Language.isRTL() ? "اليوم" : "Today")
                    .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("AdminPOS_QuickExpense_ShiftTotalLabel", alter: "إجمالي مصروفات اليوم"))
                        .font(PPBeirutiFont.regular(11, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .multilineTextAlignment(.leading)

                    Text(String(format: "%.2f %@", presenter.todayExpenseTotal, Language.get("Currency_QAR", alter: Language.isRTL() ? "ر.ق" : "QAR")))
                        .font(PPBeirutiFont.bold(22, relativeTo: .title2))
                        .foregroundStyle(coral)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(Language.get("AdminPOS_QuickExpense_ShiftCountLabel", alter: "عدد السندات"))
                        .font(PPBeirutiFont.regular(11, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text("\(presenter.todayExpenseCount)")
                        .font(PPBeirutiFont.bold(22, relativeTo: .title2))
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            .padding(.top, 4)

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.98, green: 0.60, blue: 0.18))

                Text(Language.get("AdminPOS_QuickExpense_EstimatedDrawer", alter: "الصرف يخفّض رصيد الخزينة النقدية فوراً"))
                    .font(PPBeirutiFont.regular(11, relativeTo: .caption))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.35 : 0.15), lineWidth: 0.8)
        )
    }

    private var recentVouchersDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Language.get("AdminPOS_QuickExpense_RecentVouchers", alter: "آخر سندات مصروف مسجلة بالفرع"))
                    .font(PPBeirutiFont.bold(12.5, relativeTo: .subheadline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            if presenter.recentVouchers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                        .padding(.top, 8)

                    Text(Language.get("AdminPOS_QuickExpense_NoRecentVouchers", alter: "لم تُسجل مصروفات في وردية اليوم حتى الآن"))
                        .font(PPBeirutiFont.regular(11.5, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(presenter.recentVouchers, id: \.expenseID) { voucher in
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(coral.opacity(0.12))
                                        .frame(width: 28, height: 28)

                                    Image(systemName: "arrow.down.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(coral)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voucher.desc.isEmpty ? voucher.category : voucher.desc)
                                        .font(PPBeirutiFont.bold(12, relativeTo: .caption))
                                        .foregroundStyle(AdminSurface.primaryText)
                                        .lineLimit(1)
                                        .multilineTextAlignment(.leading)

                                    if let created = voucher.createdAt {
                                        Text(created, style: .time)
                                            .font(PPBeirutiFont.regular(10.5, relativeTo: .caption2))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                    }
                                }

                                Spacer()

                                Text(String(format: "%.2f %@", voucher.amount, Language.get("Currency_QAR", alter: Language.isRTL() ? "ر.ق" : "QAR")))
                                    .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                                    .foregroundStyle(coral)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.25), lineWidth: 0.6)
                            )
                        }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.35 : 0.15), lineWidth: 0.8)
        )
    }

    private var auditSealCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.10, green: 0.74, blue: 0.54))

            Text(Language.get("AdminPOS_QuickExpense_VoucherAuditNotice", alter: "سند قيد فوري موثق بالرقم السري وهويتك الإدارية في السحابة"))
                .font(PPBeirutiFont.regular(11, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.10, green: 0.74, blue: 0.54).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 0.10, green: 0.74, blue: 0.54).opacity(0.20), lineWidth: 0.8)
        )
    }

    private var accountingWorkspacePortalButton: some View {
        Button {
            dismiss()
            onRoute("accounting")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.system(size: 13))

                Text(Language.get("AdminPOS_QuickExpense_ViewAccounting", alter: "فتح سجل الحسابات العام"))
                    .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))

                Spacer()

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(AdminSurface.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.35), lineWidth: 0.8)
            )
        }
        .buttonStyle(CommandQuickExpensePressStyle(reduceMotion: reduceMotion))
        .hoverEffect(.highlight)
    }
}

// MARK: - Adaptive Studio Container Dispatcher

private struct CommandPOSQuickExpenseSheet: View {
    let currentBranchName: String
    let onRoute: (String) -> Void

    @StateObject private var presenter = CommandPOSQuickExpensePresenter()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad {
                CommandPOSQuickExpenseView_iPad(
                    presenter: presenter,
                    currentBranchName: currentBranchName,
                    onRoute: onRoute
                )
            } else {
                CommandPOSQuickExpenseView_iPhone(
                    presenter: presenter,
                    currentBranchName: currentBranchName,
                    onRoute: onRoute
                )
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Station 2 (iPad): Dedicated Add New Expense Console (Companion Card 2)

// MARK: - Stock Deck Preference Keys

private struct CommandStockStackedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct CommandStockSectionWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

// MARK: - Stock Sovereign Horizon Deck (Deck 2)

private struct CommandStockDeck: View {
    let signals: [AdminCommandOrbitSignal]
    var isRegular: Bool = false
    var isLandscape: Bool = false
    var containerWidth: CGFloat = 0
    let onRoute: (String) -> Void

    @ObservedObject private var branchStore = BranchContextStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var arrowNudge: CGFloat = 0
    @State private var stackedCardsHeight: CGFloat = 0
    @State private var measuredSectionWidth: CGFloat = 0

    private var effectiveWidth: CGFloat {
        if containerWidth > 0 { return containerWidth }
        if measuredSectionWidth > 0 { return measuredSectionWidth }
        return 0
    }

    private var isLandscapeIPad: Bool {
        isLandscape && effectiveWidth >= 950
    }

    private func columnWidths(spacing: CGFloat) -> (livePets: CGFloat?, stacked: CGFloat?) {
        guard effectiveWidth > 0 else { return (nil, nil) }
        let availableWidth = max(0, effectiveWidth - spacing)
        let livePetsRatio: CGFloat = isLandscapeIPad ? 0.35 : 0.38
        let livePets = floor(availableWidth * livePetsRatio)
        let stacked = max(0, availableWidth - livePets)
        return (livePets, stacked)
    }

    private var accessoriesSignal: AdminCommandOrbitSignal? {
        signals.first { $0.id.contains("accessor") || $0.id.contains("stock") }
    }

    private var foodSignal: AdminCommandOrbitSignal? {
        signals.first { $0.id.contains("food") || $0.id.contains("nutrition") }
    }

    private var livePetsSignal: AdminCommandOrbitSignal? {
        signals.first { $0.id.contains("pet") || $0.id.contains("live") || $0.id.contains("animal") }
    }

    private var stockAlertCount: Int {
        let acc = accessoriesSignal?.count ?? 0
        let food = foodSignal?.count ?? 0
        let pets = livePetsSignal?.count ?? 0
        return acc + food + pets
    }

    private var currentBranchName: String {
        let name = branchStore.currentBranchDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty ? name : Language.get("Branch_Scope_Active", alter: "الفرع الحالي")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSectionSpacing.headerToContent(isRegular: isRegular)) {
            AdminSectionHeader(
                title: Language.get("Stock_Section_Title", alter: "قطاع المخزون والمنتجات"),
                subtitle: Language.get("Stock_Section_Subtitle", alter: "كتالوج المنتجات، الأغذية، والحيوانات الحية مع تتبع الكميات"),
                eyebrow: Language.get("Stock_SectionEyebrow", alter: "المخزون والكتالوج"),
                symbol: "shippingbox.fill",
                themeColor: Color(red: 0.55, green: 0.36, blue: 0.96),
                state: .normal,
                isRegular: isRegular
            ) {
                stockTelemetryPill
            }

            if isRegular {
                ipadStockView
            } else {
                iphoneStockView
            }
        }
        .frame(maxWidth: .infinity)
        .onPreferenceChange(CommandStockStackedHeightKey.self) { newHeight in
            if newHeight > 0 && abs(stackedCardsHeight - newHeight) > 0.5 {
                stackedCardsHeight = newHeight
            }
        }
        .onPreferenceChange(CommandStockSectionWidthKey.self) { newWidth in
            if newWidth > 0 && abs(measuredSectionWidth - newWidth) > 0.5 {
                measuredSectionWidth = newWidth
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var stockTelemetryPill: some View {
        Group {
            if stockAlertCount > 0 {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(uiColor: .ppWarning))
                        .frame(width: 6, height: 6)
                    Text(String(format: Language.get("Stock_Alerts_Count_Format", alter: "%d تنبيهات بالمخزون"), stockAlertCount))
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(Color(uiColor: .ppWarning))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(uiColor: .ppWarning).opacity(colorScheme == .dark ? 0.18 : 0.08), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color(uiColor: .ppWarning).opacity(0.20), lineWidth: 0.5)
                )
            } else {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(red: 0.55, green: 0.36, blue: 0.96))
                        .frame(width: 6, height: 6)
                    Text(Language.get("Stock_Live_Sync_Active", alter: "مزامنة المخزون نشطة"))
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(Color(red: 0.55, green: 0.36, blue: 0.96))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(red: 0.55, green: 0.36, blue: 0.96).opacity(colorScheme == .dark ? 0.16 : 0.08), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.18), lineWidth: 0.5)
                )
            }
        }
    }

    // Stock & Products Horizon: Left column has Live Pets (tall card); Right column has Accessories + Food stacked
    private var iphoneStockView: some View {
        let spacing: CGFloat = 9
        let widths = columnWidths(spacing: spacing)

        return HStack(alignment: .top, spacing: spacing) {
            CommandStockVaultCardTallLivePets(
                title: Language.get("Stock_LivePets_Title", alter: "الحيوانات الحية"),
                subtitle: Language.get("Stock_LivePets_Subtitle", alter: "الطيور، القطط، الكلاب، السجلات والشرائح"),
                iconName: "pawprint.fill",
                accent: AdminSurface.primary,
                badgeCount: livePetsSignal?.count,
                arrowNudge: arrowNudge,
                targetHeight: stackedCardsHeight > 0 ? stackedCardsHeight : nil,
                action: { onRoute("stockSector:livePets") }
            )
            .frame(width: widths.livePets)
            .frame(maxWidth: widths.livePets == nil ? .infinity : nil)
            .frame(height: stackedCardsHeight > 0 ? stackedCardsHeight : nil)

            VStack(spacing: spacing) {
                CommandStockVaultCardCompactiPhone(
                    title: Language.get("Stock_Accessories_Title", alter: "المخزون والإكسسوارات"),
                    subtitle: Language.get("Stock_Accessories_Subtitle", alter: "الأطواق، الألعاب، ومستلزمات العناية والرعاية"),
                    iconName: "archivebox.fill",
                    accent: Color(red: 0.55, green: 0.36, blue: 0.96),
                    badgeCount: accessoriesSignal?.count ?? (stockAlertCount > 0 ? stockAlertCount : nil),
                    arrowNudge: arrowNudge,
                    action: { onRoute("stockSector:accessories") }
                )
                .frame(maxWidth: .infinity)

                CommandStockVaultCardCompactiPhone(
                    title: Language.get("Stock_Food_Title", alter: "الأغذية والتغذية"),
                    subtitle: Language.get("Stock_Food_Subtitle", alter: "الأغذية الجافة، الرطبة، المكملات والمكافآت"),
                    iconName: "bag.fill",
                    accent: Color(red: 0.96, green: 0.55, blue: 0.12),
                    badgeCount: foodSignal?.count,
                    arrowNudge: arrowNudge,
                    action: { onRoute("stockSector:food") }
                )
                .frame(maxWidth: .infinity)
            }
            .frame(width: widths.stacked)
            .frame(maxWidth: widths.stacked == nil ? .infinity : nil)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: CommandStockStackedHeightKey.self,
                        value: geo.size.height
                    )
                }
            )
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CommandStockSectionWidthKey.self,
                    value: geo.size.width
                )
            }
        )
    }

    // iPad: Panoramic Horizon Pavilion (Matching 2-Column Blueprint)
    private var ipadStockView: some View {
        let spacing: CGFloat = 14
        let widths = columnWidths(spacing: spacing)

        return HStack(alignment: .top, spacing: spacing) {
            CommandStockVaultCardTallLivePets(
                title: Language.get("Stock_LivePets_Title", alter: "الحيوانات الحية"),
                subtitle: Language.get("Stock_LivePets_Subtitle", alter: "الطيور، القطط، الكلاب، السجلات والشرائح"),
                iconName: "pawprint.fill",
                accent: AdminSurface.primary,
                badgeCount: livePetsSignal?.count,
                arrowNudge: arrowNudge,
                targetHeight: stackedCardsHeight > 0 ? stackedCardsHeight : nil,
                action: { onRoute("stockSector:livePets") }
            )
            .frame(width: widths.livePets)
            .frame(maxWidth: widths.livePets == nil ? .infinity : nil)
            .frame(height: stackedCardsHeight > 0 ? stackedCardsHeight : nil)

            VStack(spacing: spacing) {
                CommandStockVaultCardCompactiPhone(
                    title: Language.get("Stock_Accessories_Title", alter: "المخزون والإكسسوارات"),
                    subtitle: Language.get("Stock_Accessories_Subtitle", alter: "الأطواق، الألعاب، ومستلزمات العناية والرعاية"),
                    iconName: "archivebox.fill",
                    accent: Color(red: 0.55, green: 0.36, blue: 0.96),
                    badgeCount: accessoriesSignal?.count ?? (stockAlertCount > 0 ? stockAlertCount : nil),
                    arrowNudge: arrowNudge,
                    action: { onRoute("stockSector:accessories") }
                )
                .frame(maxWidth: .infinity)

                CommandStockVaultCardCompactiPhone(
                    title: Language.get("Stock_Food_Title", alter: "الأغذية والتغذية"),
                    subtitle: Language.get("Stock_Food_Subtitle", alter: "الأغذية الجافة، الرطبة، المكملات والمكافآت"),
                    iconName: "bag.fill",
                    accent: Color(red: 0.96, green: 0.55, blue: 0.12),
                    badgeCount: foodSignal?.count,
                    arrowNudge: arrowNudge,
                    action: { onRoute("stockSector:food") }
                )
                .frame(maxWidth: .infinity)
            }
            .frame(width: widths.stacked)
            .frame(maxWidth: widths.stacked == nil ? .infinity : nil)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: CommandStockStackedHeightKey.self,
                        value: geo.size.height
                    )
                }
            )
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CommandStockSectionWidthKey.self,
                    value: geo.size.width
                )
            }
        )
    }
}

// MARK: - Stock Vault Card Tall (Live Pets Column)

private struct CommandStockVaultCardTallLivePets: View {
    let title: String
    let subtitle: String
    let iconName: String
    let accent: Color
    let badgeCount: Int?
    let arrowNudge: CGFloat
    var targetHeight: CGFloat? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var chevronPill: some View {
        HStack(spacing: 2) {
            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
                .offset(x: (Language.isRTL() ? -1 : 1) * arrowNudge * 0.5)
        }
        .frame(width: 26, height: 26)
        .background(accent.opacity(colorScheme == .dark ? 0.12 : 0.06), in: Circle())
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 4) {
            Spacer(minLength: 4)

            if let count = badgeCount, count > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(uiColor: .ppWarning))
                        .frame(width: 4.5, height: 4.5)
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color(uiColor: .ppWarning), in: Capsule())
            }

            chevronPill
        }
    }

    /// Lottie cat animation loaded from Firebase Storage ("Loader cat.json") on a borderless circular plate.
    /// Plate is circular, borderless, decreased by 30%, elevated to top, and faded from bottom.
    /// Lottie size is preserved at full dimensions with slower animation speed (0.70x).
    private var lottieCatSection: some View {
        GeometryReader { proxy in
            let availW = proxy.size.width
            let availH = proxy.size.height
            // Sizing: base plate calculation
            let maxFromH = availH > 0 ? (availH / 1.3) : 75
            let maxFromW = availW > 0 ? (availW / 1.3) : 75
            let cap: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 105 : 82
            let baseSize = max(44, min(min(maxFromH, maxFromW), cap))
            // Base Lottie view size
            let baseLottieSize = (baseSize * 1.3) * 2.0
            // Lottie size increased by +30% with bottom anchor preserved
            let lottieSize = baseLottieSize * 1.30
            // Plate size preserved ((baseSize * 2.0) * 0.70)
            let plateSize = (baseSize * 2.0) * 0.70

            ZStack(alignment: .center) {
                // Borderless circular plate: decreased by 30%, moved to top little, faded from bottom
                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: accent.opacity(colorScheme == .dark ? 0.24 : 0.16), location: 0.0),
                                .init(color: accent.opacity(colorScheme == .dark ? 0.13 : 0.08), location: 0.45),
                                .init(color: accent.opacity(colorScheme == .dark ? 0.04 : 0.02), location: 0.78),
                                .init(color: accent.opacity(0.0), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.40),
                                .init(color: .black.opacity(0.40), location: 0.75),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: plateSize, height: plateSize)
                    .offset(y: -12)

                // Lottie cat animation anchored at bottom, increased by +30%, calm slow animation speed
                PPLottieFirebaseView(
                    fileName: "Loader cat",
                    loop: true,
                    speed: 0.35,
                    contentMode: .scaleAspectFit
                )
                .frame(width: lottieSize, height: lottieSize)
                .offset(y: -((lottieSize - baseLottieSize) / 2.0))
                .allowsHitTesting(false)
            }
            .position(
                x: availW / 2,
                y: (availH / 2) + (UIDevice.current.userInterfaceIdiom == .pad ? -8 : -2)
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(minHeight: 50, maxHeight: .infinity)
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                Text(Language.get("Stock_Category_LivePets", alter: "حيوانات حية"))
                    .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(accent.opacity(colorScheme == .dark ? 0.16 : 0.08), in: Capsule())

            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(subtitle)
                .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(2)
                .lineSpacing(1.1)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                Spacer(minLength: 4)
                lottieCatSection
                Spacer(minLength: 6)
                contentSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accent.opacity(colorScheme == .dark ? 0.28 : 0.14), lineWidth: 0.75)
            )
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.14 : 0.04), radius: 5, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CommandStockCardPressStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity)
        .frame(height: targetHeight)
        .frame(maxHeight: targetHeight == nil ? .infinity : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

// MARK: - Stock Vault Card Compact (iPhone 2-Column Row)

private struct CommandStockVaultCardCompactiPhone: View {
    let title: String
    let subtitle: String
    let iconName: String
    let accent: Color
    let badgeCount: Int?
    let arrowNudge: CGFloat
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var iconGradient: LinearGradient {
        let topOpacity: Double = colorScheme == .dark ? 0.25 : 0.14
        let bottomOpacity: Double = colorScheme == .dark ? 0.08 : 0.04
        return LinearGradient(
            colors: [
                accent.opacity(topOpacity),
                accent.opacity(bottomOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconSquircle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(iconGradient)

            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
        }
        .frame(width: 38, height: 38)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.32 : 0.18), lineWidth: 0.75)
        )
    }

    private var chevronPill: some View {
        HStack(spacing: 2) {
            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
                .offset(x: (Language.isRTL() ? -1 : 1) * arrowNudge * 0.5)
        }
        .frame(width: 26, height: 26)
        .background(accent.opacity(colorScheme == .dark ? 0.12 : 0.06), in: Circle())
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 4) {
            iconSquircle

            Spacer(minLength: 4)

            if let count = badgeCount, count > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(uiColor: .ppWarning))
                        .frame(width: 4.5, height: 4.5)
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color(uiColor: .ppWarning), in: Capsule())
            }

            chevronPill
        }
    }

    private var titleAndSubtitle: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .subheadline))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(subtitle)
                .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(2)
                .lineSpacing(1.2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 9) {
                topBar
                titleAndSubtitle
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accent.opacity(colorScheme == .dark ? 0.28 : 0.14), lineWidth: 0.75)
            )
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.14 : 0.04), radius: 5, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CommandStockCardPressStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

// MARK: - Stock Vault Card (iPhone)

private struct CommandStockVaultCardiPhone: View {
    let title: String
    let subtitle: String
    let iconName: String
    let accent: Color
    let badgeCount: Int?
    let arrowNudge: CGFloat
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var iconGradient: LinearGradient {
        let topOpacity: Double = colorScheme == .dark ? 0.25 : 0.14
        let bottomOpacity: Double = colorScheme == .dark ? 0.08 : 0.04
        return LinearGradient(
            colors: [
                accent.opacity(topOpacity),
                accent.opacity(bottomOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconSquircle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(iconGradient)

            Image(systemName: iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
        }
        .frame(width: 44, height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.32 : 0.18), lineWidth: 0.75)
        )
    }

    private var titleAndDescription: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                if let count = badgeCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color(uiColor: .ppWarning), in: Capsule())
                }
            }

            Text(subtitle)
                .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chevronPill: some View {
        HStack(spacing: 3) {
            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)
                .offset(x: (Language.isRTL() ? -1 : 1) * arrowNudge * 0.6)
        }
        .frame(width: 28, height: 28)
        .background(accent.opacity(colorScheme == .dark ? 0.12 : 0.06), in: Circle())
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: 12) {
                iconSquircle
                titleAndDescription
                Spacer(minLength: 4)
                chevronPill
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accent.opacity(colorScheme == .dark ? 0.28 : 0.14), lineWidth: 0.75)
            )
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.14 : 0.04), radius: 5, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CommandStockCardPressStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

// MARK: - Stock Vault Card (iPad)

private struct CommandStockVaultCardiPad: View {
    let title: String
    let subtitle: String
    let categoryBadge: String
    let iconName: String
    let accent: Color
    let badgeCount: Int?
    let arrowNudge: CGFloat
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var iconGradient: LinearGradient {
        let topOpacity: Double = colorScheme == .dark ? 0.24 : 0.14
        let bottomOpacity: Double = colorScheme == .dark ? 0.08 : 0.04
        return LinearGradient(
            colors: [
                accent.opacity(topOpacity),
                accent.opacity(bottomOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var topTagBar: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(categoryBadge)
                .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption2))
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(accent.opacity(colorScheme == .dark ? 0.20 : 0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(accent.opacity(colorScheme == .dark ? 0.28 : 0.16), lineWidth: 0.6)
                )

            Spacer(minLength: 4)

            if let count = badgeCount, count > 0 {
                HStack(spacing: 3.5) {
                    Circle()
                        .fill(Color(uiColor: .ppWarning))
                        .frame(width: 5, height: 5)
                    Text(count == 1 ? Language.get("Stock_Status_Alert_Singular", alter: "تنبيه نقص") : String(format: Language.get("Stock_Status_Alert_Plural", alter: "%d تنبيهات"), count))
                        .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
                        .foregroundStyle(Color(uiColor: .ppWarning))
                }
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .ppWarning).opacity(colorScheme == .dark ? 0.20 : 0.10))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color(uiColor: .ppWarning).opacity(0.24), lineWidth: 0.6)
                )
            } else {
                HStack(spacing: 3.5) {
                    Circle()
                        .fill(accent)
                        .frame(width: 4.5, height: 4.5)
                    Text(Language.get("Stock_Status_Active", alter: "متزامن"))
                        .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(accent.opacity(colorScheme == .dark ? 0.15 : 0.07))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(accent.opacity(colorScheme == .dark ? 0.22 : 0.12), lineWidth: 0.5)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var iconSquircle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(iconGradient)

            Image(systemName: iconName)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.40 : 0.18), radius: 4, y: 1.5)
        }
        .frame(width: 50, height: 50)
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.32 : 0.18), lineWidth: 0.8)
        )
    }

    private var titlesView: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(subtitle)
                .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(2)
                .lineSpacing(1.5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contentRow: some View {
        HStack(alignment: .center, spacing: 12) {
            iconSquircle
            titlesView
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionPill: some View {
        HStack(spacing: 5) {
            Text(Language.get("Stock_Open_Catalog", alter: "فتح الكتالوج"))
                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : AdminSurface.primaryText)

            Spacer()

            Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(accent)
                .offset(x: (Language.isRTL() ? -1 : 1) * arrowNudge * 0.7)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 33)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 0.7)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.03), radius: 2.5, y: 1)
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 11) {
                topTagBar
                contentRow
                Spacer(minLength: 2)
                actionPill
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 154)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(colorScheme == .dark ? Color(white: 0.13) : Color.white)

                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(colorScheme == .dark ? 0.06 : 0.025),
                                    accent.opacity(colorScheme == .dark ? 0.01 : 0.003)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(accent.opacity(colorScheme == .dark ? 0.26 : 0.14), lineWidth: 0.8)
            )
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.18 : 0.05), radius: 6, y: 2.5)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(CommandStockCardPressStyle())
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct CommandStockCardPressStyle: ButtonStyle {
    var scale: CGFloat = 0.982
    var pressedOpacity: CGFloat = 0.94
    var cornerRadius: CGFloat = 16
    func makeBody(configuration: Configuration) -> some View {
        let animatesScale = UIDevice.current.userInterfaceIdiom != .pad
        return configuration.label
            .scaleEffect(configuration.isPressed && animatesScale ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(animatesScale ? (configuration.isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.28, dampingFraction: 0.72)) : nil, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Operations Launchpad (Deck 3)

private struct CommandQuickActionItem: Identifiable, Hashable {
    let id: String
    let tag: String
    let title: String
    let subtitle: String
    let symbolName: String
    let accent: Color
    let badgeCount: Int?
    let isLive: Bool
    var isCustomAsset: Bool = false

    init(
        id: String,
        tag: String,
        title: String,
        subtitle: String,
        symbolName: String,
        accent: Color,
        badgeCount: Int?,
        isLive: Bool,
        isCustomAsset: Bool = false
    ) {
        self.id = id
        self.tag = tag
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.accent = accent
        self.badgeCount = badgeCount
        self.isLive = isLive
        self.isCustomAsset = isCustomAsset
    }
}

private struct CommandQuickActionIcon: View {
    let symbolName: String
    let accent: Color
    let size: CGFloat
    var isCustomAsset: Bool = false
    var weight: Font.Weight = .semibold

    init(symbolName: String, accent: Color, size: CGFloat, isCustomAsset: Bool = false, weight: Font.Weight = .semibold) {
        self.symbolName = symbolName
        self.accent = accent
        self.size = size
        self.isCustomAsset = isCustomAsset
        self.weight = weight
    }

    init(item: CommandQuickActionItem, size: CGFloat, weight: Font.Weight = .semibold) {
        self.symbolName = item.symbolName
        self.accent = item.accent
        self.size = size
        self.isCustomAsset = item.isCustomAsset
        self.weight = weight
    }

    var body: some View {
        let cleanName = symbolName.replacingOccurrences(of: ".png", with: "")
        if isCustomAsset || UIImage(named: cleanName) != nil || UIImage(named: symbolName) != nil {
            Image(cleanName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(accent)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: size, weight: weight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
        }
    }
}

private struct CommandQuickActionsDeck: View {
    let signals: [AdminCommandOrbitSignal]
    var isRegular: Bool = false
    var isLandscape: Bool = false
    var containerWidth: CGFloat = 0
    let onRoute: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded: Bool = false

    private var spacing: CGFloat { 10 }

    private var allDeckItems: [CommandQuickActionItem] {
        let fulfillmentSignal = signals.first { $0.id.contains("fulfillment") }
        let deliverySignal = signals.first { $0.id.contains("delivery") }
        let userSignal = signals.first { $0.id.contains("user") }

        return [
            // 1. Fulfillment Orders
            CommandQuickActionItem(
                id: "fulfillment",
                tag: "fulfillment",
                title: Language.get("AdminQuickActions_Fulfillment", alter: "التنفيذ"),
                subtitle: Language.get("AdminQuickActions_Fulfillment_Subtitle", alter: "معالجة وتحضير"),
                symbolName: "shippingbox.fill",
                accent: Color(red: 0.96, green: 0.55, blue: 0.12),
                badgeCount: (fulfillmentSignal?.count ?? 0) > 0 ? fulfillmentSignal?.count : nil,
                isLive: fulfillmentSignal?.isLive ?? false
            ),
            // 2. Delivery Fleet
            CommandQuickActionItem(
                id: "delivery",
                tag: "delivery",
                title: Language.get("AdminQuickActions_Delivery", alter: "التوصيل"),
                subtitle: Language.get("AdminQuickActions_Delivery_Subtitle", alter: "إسناد ومتابعة"),
                symbolName: "truck.box.fill",
                accent: Color(red: 0.14, green: 0.54, blue: 0.98),
                badgeCount: (deliverySignal?.count ?? 0) > 0 ? deliverySignal?.count : nil,
                isLive: deliverySignal?.isLive ?? false
            ),
            // 3. Customers Directory
            CommandQuickActionItem(
                id: "usersList",
                tag: "usersList",
                title: Language.get("AdminQuickActions_Users", alter: "المستخدمون"),
                subtitle: Language.get("AdminQuickActions_Users_Subtitle", alter: "الحسابات والصلاحيات"),
                symbolName: "person.2.fill",
                accent: Color(red: 0.05, green: 0.60, blue: 0.56),
                badgeCount: (userSignal?.count ?? 0) > 0 ? userSignal?.count : nil,
                isLive: userSignal?.isLive ?? false
            ),
            // 4. Security & Audit Trail
            CommandQuickActionItem(
                id: "audit",
                tag: "audit",
                title: Language.get("AdminQuickActions_Audit", alter: "سجل التدقيق"),
                subtitle: Language.get("AdminQuickActions_Audit_Subtitle", alter: "الرقابة وتتبع الأمان"),
                symbolName: "lock.shield.fill",
                accent: Color(red: 0.35, green: 0.40, blue: 0.52),
                badgeCount: nil,
                isLive: false
            )
        ]
    }

    private var activeSignalsCount: Int {
        signals.reduce(0) { $0 + ($1.count > 0 ? 1 : 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSectionSpacing.headerToContent(isRegular: isRegular)) {
            AdminSectionHeader(
                title: Language.get("AdminQuickActions_SectionTitle", alter: "إجراءات سريعة"),
                subtitle: Language.get("AdminQuickActions_SectionDetail", alter: "منصة إطلاق فورية للعمليات الميدانية"),
                eyebrow: Language.get("AdminQuickActions_SectionEyebrow", alter: "العمليات الميدانية"),
                symbol: "bolt.fill",
                themeColor: AdminSurface.primary,
                state: .normal,
                isRegular: isRegular
            ) {
                quickActionsTelemetryPill
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: spacing) {
                    ForEach(allDeckItems) { item in
                        CommandQuickActionCard(item: item, isRegular: true) {
                            onRoute(item.tag)
                        }
                    }
                }
            } else if isRegular {
                ipadOperationsMatrixView
            } else {
                iphoneOperationsMatrixView
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var quickActionsTelemetryPill: some View {
        Group {
            if activeSignalsCount > 0 {
                HStack(spacing: 5) {
                    Circle()
                        .fill(AdminSurface.primary)
                        .frame(width: 6, height: 6)
                    Text(String(format: Language.get("AdminQuickActions_SignalsCount_Format", alter: "%d إشارات نشطة"), activeSignalsCount))
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(AdminSurface.primary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AdminSurface.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AdminSurface.primary.opacity(0.18), lineWidth: 0.5)
                )
            }
        }
    }

    // iPhone Operations Line (All 4 actions in 1 line)
    private var iphoneOperationsMatrixView: some View {
        HStack(spacing: spacing) {
            ForEach(allDeckItems) { item in
                CommandQuickActionCard(item: item, isRegular: false) {
                    onRoute(item.tag)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var isLandscapeIPad: Bool {
        isLandscape && containerWidth >= 950
    }

    // iPad Operations Line (Panoramic Horizon in Landscape, 2x2 Balanced Matrix in Portrait)
    private var ipadOperationsMatrixView: some View {
        Group {
            if isLandscapeIPad {
                HStack(spacing: spacing) {
                    ForEach(allDeckItems) { item in
                        CommandQuickActionCard(item: item, isRegular: true) {
                            onRoute(item.tag)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    let pairs = stride(from: 0, to: allDeckItems.count, by: 2).map {
                        Array(allDeckItems[$0 ..< min($0 + 2, allDeckItems.count)])
                    }
                    ForEach(pairs.indices, id: \.self) { pairIndex in
                        HStack(spacing: 10) {
                            ForEach(pairs[pairIndex]) { item in
                                CommandQuickActionCard(item: item, isRegular: true) {
                                    onRoute(item.tag)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Sovereign Quick Action Card (Adaptive Ergonomic Single-Line Tile)

private struct CommandQuickActionCard: View {
    let item: CommandQuickActionItem
    var isRegular: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Group {
                if isRegular {
                    regularContent
                } else {
                    compactSingleLineContent
                }
            }
        }
        .buttonStyle(CommandQuickActionCardStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            if item.badgeCount != nil || item.isLive {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title)، \(item.subtitle)")
        .accessibilityHint(Language.get("AdminCommandCenter_OpenHint", alter: "يفتح القسم"))
    }

    // MARK: - iPhone Single-Line Compact Content (Vertical Ergonomic Tile)
    private var compactSingleLineContent: some View {
        VStack(spacing: 5) {
            // Icon squircle with attached micro-badge
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? item.accent.opacity(0.24)
                                : Color.white.opacity(0.95)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(item.accent.opacity(colorScheme == .dark ? 0.25 : 0.16), lineWidth: 0.75)
                        )
                        .shadow(color: item.accent.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 3, y: 1)

                    CommandQuickActionIcon(item: item, size: 17)
                }
                .frame(width: 36, height: 36)

                // Micro-badge badge overlay
                if let count = item.badgeCount, count > 0 {
                    Text("\(count)")
                        .font(Font.custom("Beiruti-Bold", size: 10))
                        .foregroundStyle(Color.white)
                        .monospacedDigit()
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(item.accent, in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(colorScheme == .dark ? Color.black : Color.white, lineWidth: 1.2)
                        )
                        .offset(x: Language.isRTL() ? -4 : 4, y: -4)
                } else if item.isLive {
                    Circle()
                        .fill(item.accent)
                        .frame(width: 6.5, height: 6.5)
                        .scaleEffect(isPulsing ? 1.25 : 0.85)
                        .overlay(
                            Circle()
                                .strokeBorder(colorScheme == .dark ? Color.black : Color.white, lineWidth: 1)
                        )
                        .offset(x: Language.isRTL() ? -2 : 2, y: -2)
                }
            }
            .accessibilityHidden(true)

            // Text Stack (Title + Subtitle)
            VStack(spacing: 1.5) {
                Text(item.title)
                    .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .subheadline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)

                Text(item.subtitle)
                    .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 98)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)

                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                item.accent.opacity(colorScheme == .dark ? 0.05 : 0.025),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(item.accent.opacity(colorScheme == .dark ? 0.20 : 0.12), lineWidth: 0.75)
        )
        .shadow(
            color: item.accent.opacity(colorScheme == .dark ? 0.14 : 0.04),
            radius: 4,
            y: 1.5
        )
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    // MARK: - iPad Panoramic Single-Line Content (Horizontal Executive Card)
    private var regularContent: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? item.accent.opacity(0.24)
                                : Color.white.opacity(0.95)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(item.accent.opacity(colorScheme == .dark ? 0.25 : 0.16), lineWidth: 0.75)
                        )
                        .shadow(color: item.accent.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 3, y: 1)

                    CommandQuickActionIcon(item: item, size: 18)
                }
                .frame(width: 38, height: 38)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .subheadline))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(item.subtitle)
                    .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 4)

            // Trailing Telemetry Pill / Arrow Affordance
            if let count = item.badgeCount, count > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(item.accent)
                        .frame(width: 5, height: 5)
                        .scaleEffect(isPulsing ? 1.25 : 0.85)
                    Text("\(count)")
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(item.accent)
                        .monospacedDigit()
                }
                .padding(.horizontal, 6.5)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(colorScheme == .dark ? item.accent.opacity(0.22) : Color.white.opacity(0.92))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(item.accent.opacity(0.18), lineWidth: 0.75)
                )
            } else if item.isLive {
                HStack(spacing: 3) {
                    Circle()
                        .fill(item.accent)
                        .frame(width: 4.5, height: 4.5)
                        .scaleEffect(isPulsing ? 1.25 : 0.85)
                    Text(Language.get("AdminQuickActions_Live", alter: "مباشر"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(item.accent)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(item.accent.opacity(colorScheme == .dark ? 0.18 : 0.08), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(item.accent.opacity(0.18), lineWidth: 0.75)
                )
            } else {
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(item.accent.opacity(0.55))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 76)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                item.accent.opacity(colorScheme == .dark ? 0.03 : 0.012),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(item.accent.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 0.75)
        )
        .shadow(
            color: item.accent.opacity(colorScheme == .dark ? 0.14 : 0.04),
            radius: 4,
            y: 1.5
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CommandQuickActionCardStyle: ButtonStyle {
    var scale: CGFloat = 0.968
    var pressedOpacity: CGFloat = 0.92
    func makeBody(configuration: Configuration) -> some View {
        let animatesScale = UIDevice.current.userInterfaceIdiom != .pad
        return configuration.label
            .scaleEffect(configuration.isPressed && animatesScale ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(
                animatesScale ? (configuration.isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.28, dampingFraction: 0.72)) : nil,
                value: configuration.isPressed
            )
    }
}

// MARK: - Priority Runway

private struct CommandPriorityRunway: View {
    let title: String
    let detail: String
    let signals: [AdminCommandOrbitSignal]
    let locale: Locale
    var isRegular: Bool = false
    let action: (AdminCommandOrbitSignal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSectionSpacing.headerToContent(isRegular: isRegular)) {
            AdminSectionHeader(
                title: title,
                subtitle: detail,
                eyebrow: Language.get("AdminRunway_SectionEyebrow", alter: "التدخل السريع"),
                symbol: "exclamationmark.triangle.fill",
                themeColor: Color(uiColor: .ppWarning),
                state: signals.isEmpty ? .empty(Language.get("AdminCommandCenter_AllClear_Title", alter: "لا توجد إشارات معلقة")) : .normal,
                isRegular: isRegular
            ) {
                if !signals.isEmpty {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(uiColor: .ppWarning))
                            .frame(width: 6, height: 6)
                        Text(signals.count == 1 ? Language.get("AdminSectionHeader_ActiveSignalsSingular", alter: "إشارة نشطة واحدة") : String(format: Language.get("AdminCommandCenter_SignalsCount_Format", alter: "%d إشارات"), signals.count))
                            .font(Font.custom("Beiruti-Bold", size: 11))
                            .foregroundStyle(Color(uiColor: .ppWarning))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(uiColor: .ppWarning).opacity(0.12), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(uiColor: .ppWarning).opacity(0.18), lineWidth: 0.5)
                    )
                }
            }

            if signals.isEmpty {
                CommandCenterStatePanel(
                    tone: .stable,
                    title: Language.get("AdminCommandCenter_AllClear_Title", alter: nil),
                    detail: Language.get("AdminCommandCenter_AllClear_Detail", alter: nil),
                    showsProgress: false,
                    actionTitle: nil,
                    action: nil
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(signals.enumerated()), id: \.element.id) { index, signal in
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            action(signal)
                        } label: {
                            CommandPriorityRow(
                                signal: signal,
                                locale: locale,
                                position: index + 1,
                                isLast: index == signals.count - 1
                            )
                        }
                        .buttonStyle(CommandCardPressStyle(scale: 0.985, pressedOpacity: 0.95, cornerRadius: 18))
                    }
                }
            }
        }
    }
}

private struct CommandPriorityRow: View {
    let signal: AdminCommandOrbitSignal
    let locale: Locale
    let position: Int
    let isLast: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Priority Leading Indicator Bar
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(signal.tier.tone.accent)
                .frame(width: 4, height: 44)
                .shadow(color: signal.tier.tone.accent.opacity(0.40), radius: 2, x: 0, y: 0)

            // Specimen Icon Container
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(signal.tier.tone.softFill)
                Image(systemName: signal.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(signal.tier.tone.accent)
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(signal.tier.tone.accent.opacity(0.25), lineWidth: 0.75)
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(priorityLabel)
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(signal.tier.tone.color)
                            .lineLimit(1)

                        if !signal.moduleTitle.isEmpty {
                            Text("•")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(AdminCommandInk.tertiary)
                            Text(signal.moduleTitle)
                                .font(AdminType.caption2)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if signal.count > 0 {
                        Text(signal.count.formatted(.number.locale(locale)))
                            .font(AdminType.captionBold)
                            .foregroundStyle(signal.tier.tone.color)
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(signal.tier.tone.softFill, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(signal.tier.tone.accent.opacity(0.25), lineWidth: 0.5)
                            )
                            .accessibilityLabel(countAccessibilityText)
                    }
                }

                Text(signal.title)
                    .font(position == 1 ? AdminType.headline : AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !signal.detail.isEmpty {
                    Text(signal.detail)
                        .font(AdminType.callout)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(3)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text(Language.get("AdminCommandCenter_Act", alter: "Act now"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(signal.tier.tone.color)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(signal.tier.tone.accent)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.03), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.60 : 0.35), lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Language.get("AdminCommandCenter_OpenHint", alter: nil))
    }

    private var priorityLabel: String {
        signal.tier.localizedLabel
    }

    private var countAccessibilityText: String {
        String(format: Language.get("AdminCommandCenter_Count_Format", alter: nil), signal.count.formatted(.number.locale(locale)))
    }

    private var accessibilityLabel: String {
        String(
            format: Language.get("AdminCommandCenter_Priority_A11y_Format", alter: nil),
            priorityLabel,
            signal.title,
            signal.count.formatted(.number.locale(locale))
        )
    }
}

// MARK: - Source and Recovery

private struct CommandSourceLedger: View {
    let title: String
    let detail: String
    let loadingSources: [String]
    let failedSources: [String]
    let updatedText: String
    var isRegular: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var rows: [CommandSourceRow] {
        var result: [CommandSourceRow] = []
        result.append(.init(title: Language.get("CommandCenter_Last_Updated", alter: "Last confirmed"), value: updatedText, tone: .stable, symbol: "clock.badge.checkmark"))
        if loadingSources.isEmpty && failedSources.isEmpty {
            result.append(.init(title: Language.get("AdminCommandCenter_SourceReady", alter: "All sources verified"), value: Language.get("AdminCommandCenter_Ready_Detail", alter: "Real-time sync active"), tone: .stable, symbol: "checkmark.seal.fill"))
        }
        if !loadingSources.isEmpty {
            result.append(.init(title: Language.get("AdminCommandCenter_LoadingSources", alter: "Confirming sources"), value: localizedList(loadingSources), tone: .info, symbol: "arrow.triangle.2.circlepath"))
        }
        if !failedSources.isEmpty {
            result.append(.init(title: Language.get("AdminCommandCenter_SourceIssue_Title", alter: "Source issue"), value: localizedList(failedSources), tone: .elevated, symbol: "wifi.exclamationmark"))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSectionSpacing.headerToContent(isRegular: isRegular)) {
            AdminSectionHeader(
                title: title,
                subtitle: detail,
                eyebrow: Language.get("AdminLedger_SectionEyebrow", alter: "بيانات المنظومة"),
                symbol: "network",
                themeColor: Color(red: 0.20, green: 0.60, blue: 0.86),
                state: failedSources.isEmpty ? .normal : .error(Language.get("AdminCommandCenter_SourceIssue_Title", alter: "مشكلة بمصدر")),
                isRegular: isRegular
            ) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(failedSources.isEmpty ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                        .frame(width: 6, height: 6)
                    Text(failedSources.isEmpty ? Language.get("AdminSectionHeader_AllOptimal", alter: "الحالة ممتازة ومطابقة") : String(format: Language.get("AdminCommandCenter_FailedSources_Format", alter: "%d مصادر متعثرة"), failedSources.count))
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(failedSources.isEmpty ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background((failedSources.isEmpty ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.12), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder((failedSources.isEmpty ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.18), lineWidth: 0.5)
                )
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(row.tone.softFill)
                            Image(systemName: row.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(row.tone.accent)
                        }
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(row.tone.accent.opacity(0.25), lineWidth: 0.75)
                        )
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .lineLimit(1)
                            Text(row.value)
                                .font(AdminType.callout)
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(2)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .accessibilityElement(children: .combine)

                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 70)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AdminSurface.control)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.03), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.60 : 0.35), lineWidth: 0.75)
            )
        }
    }

    private func localizedList(_ values: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = Locale(identifier: Language.currentLanguageCode())
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }
}

private struct CommandSourceRow: Identifiable {
    let title: String
    let value: String
    let tone: AdminCommandTone
    let symbol: String

    var id: String { "\(title)-\(value)" }
}

private struct CommandRecoveryStrip: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .ppWarning))
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .ppWarning).opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(AdminType.callout)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(3)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: action) {
                HStack(spacing: 8) {
                    Text(actionTitle)
                        .font(AdminType.calloutBold)
                        .lineLimit(1)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(CommandPressStyle())
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppWarning).opacity(0.35), lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct CommandCenterSourcePanel: View {
    let tone: AdminCommandTone
    let title: String
    let detail: String
    let sourceNames: [String]
    let showsProgress: Bool
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        CommandCenterStatePanel(
            tone: tone,
            title: title,
            detail: detail,
            showsProgress: showsProgress,
            actionTitle: actionTitle,
            action: action
        ) {
            if !sourceNames.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sourceNames, id: \.self) { source in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(tone.accent)
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                            Text(source)
                                .font(AdminType.callout)
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(nil)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

private struct CommandCenterStatePanel<Extra: View>: View {
    let tone: AdminCommandTone
    let title: String
    let detail: String
    let showsProgress: Bool
    let actionTitle: String?
    let action: (() -> Void)?
    let extra: Extra

    @Environment(\.colorScheme) private var colorScheme

    init(
        tone: AdminCommandTone,
        title: String,
        detail: String,
        showsProgress: Bool,
        actionTitle: String?,
        action: (() -> Void)?,
        @ViewBuilder extra: () -> Extra
    ) {
        self.tone = tone
        self.title = title
        self.detail = detail
        self.showsProgress = showsProgress
        self.actionTitle = actionTitle
        self.action = action
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(tone.softFill)
                    .frame(width: 64, height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(tone.accent.opacity(0.30), lineWidth: 1.0)
                    )

                if showsProgress {
                    ProgressView().tint(tone.color)
                } else {
                    Image(systemName: tone.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tone.accent)
                }
            }
            .frame(width: 64, height: 64)
            .shadow(color: tone.accent.opacity(0.25), radius: 8, x: 0, y: 3)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(AdminType.callout)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            extra

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AdminType.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(tone.actionFill)
                                .shadow(color: tone.accent.opacity(0.35), radius: 8, x: 0, y: 3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
                        )
                }
                .buttonStyle(CommandPressStyle())
                .accessibilityHint(Language.get("AdminCommandOrbit_Refresh_Hint", alter: nil))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(colorScheme == .dark ? 0.60 : 0.35), lineWidth: 0.75)
        )
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}

private extension CommandCenterStatePanel where Extra == EmptyView {
    init(
        tone: AdminCommandTone,
        title: String,
        detail: String,
        showsProgress: Bool,
        actionTitle: String?,
        action: (() -> Void)?
    ) {
        self.init(
            tone: tone,
            title: title,
            detail: detail,
            showsProgress: showsProgress,
            actionTitle: actionTitle,
            action: action
        ) {
            EmptyView()
        }
    }
}

// MARK: - Category-Defining Section Header Architecture & Spacing Tokens

enum AdminSectionSpacing {
    /// Vertical space between distinct functional sections on the home command center
    /// Enhanced vertical spacing for category-defining architectural separation
    static func interSection(isRegular: Bool) -> CGFloat {
        isRegular ? 44 : 34
    }

    /// Inner vertical spacing between the section header and the section's content cards/grid
    static func headerToContent(isRegular: Bool) -> CGFloat {
        isRegular ? 14 : 11
    }

    /// Vertical space between header/navbar bottom and the first section (POS) header top
    static func navBarToFirstSection(isRegular: Bool) -> CGFloat {
        isRegular ? 32 : 26
    }
}

enum AdminSectionHeaderState: Equatable {
    case normal
    case loading
    case empty(String)
    case error(String)
}

struct AdminSectionHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let eyebrow: String?
    let symbol: String?
    let themeColor: Color
    let state: AdminSectionHeaderState
    let isRegular: Bool
    let onTapHeader: (() -> Void)?
    @ViewBuilder let accessory: () -> Accessory

    init(
        title: String,
        subtitle: String? = nil,
        eyebrow: String? = nil,
        symbol: String? = nil,
        themeColor: Color = AdminSurface.primary,
        state: AdminSectionHeaderState = .normal,
        isRegular: Bool = false,
        onTapHeader: (() -> Void)? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.eyebrow = eyebrow
        self.symbol = symbol
        self.themeColor = themeColor
        self.state = state
        self.isRegular = isRegular
        self.onTapHeader = onTapHeader
        self.accessory = accessory
    }

    var body: some View {
        if isRegular {
            AdminSectionHeader_iPad(
                title: title,
                subtitle: subtitle,
                eyebrow: eyebrow,
                symbol: symbol,
                themeColor: themeColor,
                state: state,
                onTapHeader: onTapHeader,
                accessory: accessory
            )
        } else {
            AdminSectionHeader_iPhone(
                title: title,
                subtitle: subtitle,
                eyebrow: eyebrow,
                symbol: symbol,
                themeColor: themeColor,
                state: state,
                onTapHeader: onTapHeader,
                accessory: accessory
            )
        }
    }
}

// MARK: - iPhone Dedicated Architecture (Mobile Thumb-Zone & High Density)

private struct AdminSectionHeader_iPhone<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let eyebrow: String?
    let symbol: String?
    let themeColor: Color
    let state: AdminSectionHeaderState
    let onTapHeader: (() -> Void)?
    @ViewBuilder let accessory: () -> Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Leading Badge / Emblem
            if let symbol = symbol {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(themeColor.opacity(0.12))
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(themeColor)
                        .flipsForRightToLeftLayoutDirection(true)
                }
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(themeColor.opacity(0.18), lineWidth: 0.5)
                )
                .accessibilityHidden(true)
            }

            // Title & Subtitle Stack
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow = eyebrow, !eyebrow.isEmpty {
                    Text(eyebrow)
                        .font(Font.custom("Beiruti-Bold", size: 10.5))
                        .foregroundStyle(themeColor)
                        .lineLimit(1)
                }

                if case .loading = state {
                    shimmerPlaceholder(width: 140, height: 18)
                    if subtitle != nil {
                        shimmerPlaceholder(width: 200, height: 12)
                            .padding(.top, 2)
                    }
                } else {
                    Text(title)
                        .font(Font.custom("Beiruti-Bold", size: 19))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Font.custom("Beiruti-Regular", size: 12.5))
                            .foregroundStyle(AdminCommandInk.secondary)
                            .lineLimit(2)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Error state message inline
                if case .error(let message) = state {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(uiColor: .ppWarning))
                        Text(message)
                            .font(Font.custom("Beiruti-Bold", size: 11.5))
                            .foregroundStyle(Color(uiColor: .ppWarning))
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing Accessory
            if case .loading = state {
                shimmerPlaceholder(width: 58, height: 26, isCapsule: true)
            } else {
                accessory()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let onTapHeader = onTapHeader {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTapHeader()
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var text = title
        if let subtitle = subtitle {
            text += ", " + subtitle
        }
        return text
    }

    @ViewBuilder
    private func shimmerPlaceholder(width: CGFloat, height: CGFloat, isCapsule: Bool = false) -> some View {
        ZStack {
            if isCapsule {
                Capsule(style: .continuous)
                    .fill(AdminSurface.control)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AdminSurface.control)
            }

            if !reduceMotion {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: (shimmerPhase * 2 - 1) * width)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

// MARK: - iPad Dedicated Architecture (Panoramic Flight-Deck & Pointer Intelligence)

private struct AdminSectionHeader_iPad<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let eyebrow: String?
    let symbol: String?
    let themeColor: Color
    let state: AdminSectionHeaderState
    let onTapHeader: (() -> Void)?
    @ViewBuilder let accessory: () -> Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Prominent Section Emblem Container
            if let symbol = symbol {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeColor.opacity(0.18),
                                    themeColor.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: symbol)
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundStyle(themeColor)
                        .flipsForRightToLeftLayoutDirection(true)
                }
                .frame(width: 42, height: 42)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(themeColor.opacity(0.24), lineWidth: 0.75)
                )
                .shadow(color: themeColor.opacity(isHovered ? 0.28 : 0.10), radius: isHovered ? 6 : 3, x: 0, y: 1)
                .accessibilityHidden(true)
            }

            // Title & Subtitle Stack
            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow = eyebrow, !eyebrow.isEmpty {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(themeColor)
                            .frame(width: 4.5, height: 4.5)
                        Text(eyebrow)
                            .font(Font.custom("Beiruti-Bold", size: 11.5))
                            .foregroundStyle(themeColor)
                            .lineLimit(1)
                    }
                }

                if case .loading = state {
                    shimmerPlaceholder(width: 200, height: 22)
                    if subtitle != nil {
                        shimmerPlaceholder(width: 320, height: 14)
                            .padding(.top, 2)
                    }
                } else {
                    Text(title)
                        .font(Font.custom("Beiruti-Bold", size: 22))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Font.custom("Beiruti-Regular", size: 14))
                            .foregroundStyle(AdminCommandInk.secondary)
                            .lineLimit(2)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if case .error(let message) = state {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(uiColor: .ppWarning))
                        Text(message)
                            .font(Font.custom("Beiruti-Bold", size: 12.5))
                            .foregroundStyle(Color(uiColor: .ppWarning))
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing Accessory Deck with Pointer Hover
            if case .loading = state {
                shimmerPlaceholder(width: 80, height: 32, isCapsule: true)
            } else {
                accessory()
                    .hoverEffect(.highlight)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var text = title
        if let subtitle = subtitle {
            text += ", " + subtitle
        }
        return text
    }

    @ViewBuilder
    private func shimmerPlaceholder(width: CGFloat, height: CGFloat, isCapsule: Bool = false) -> some View {
        ZStack {
            if isCapsule {
                Capsule(style: .continuous)
                    .fill(AdminSurface.control)
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(AdminSurface.control)
            }

            if !reduceMotion {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: (shimmerPhase * 2 - 1) * width)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

// MARK: - Legacy Compatibility Seam

struct SectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        AdminSectionHeader(
            title: title,
            subtitle: detail,
            themeColor: AdminSurface.primary
        )
    }
}

struct CommandPressStyle: ButtonStyle {
    var scale: CGFloat = 0.985
    var pressedOpacity: CGFloat = 0.92
    func makeBody(configuration: Configuration) -> some View {
        let animatesScale = UIDevice.current.userInterfaceIdiom != .pad
        return configuration.label
            .scaleEffect(configuration.isPressed && animatesScale ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .contentShape(Rectangle())
            .animation(
                animatesScale ? (configuration.isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.28, dampingFraction: 0.72)) : nil,
                value: configuration.isPressed
            )
    }
}

// MARK: - Category-Defining Flagship Accounting Sovereign Entry Card

@MainActor
private final class CommandAccountingCardViewModel: ObservableObject {
    @Published private(set) var grossRevenue: Double = 0.0
    @Published private(set) var totalExpenses: Double = 0.0
    @Published private(set) var paidOrderCount: Int = 0
    @Published private(set) var expenseCount: Int = 0
    @Published private(set) var isLoading: Bool = true

    private nonisolated(unsafe) var notificationToken: (any NSObjectProtocol)? = nil
    private nonisolated(unsafe) var branchNotificationToken: (any NSObjectProtocol)? = nil

    private let service: PPAccountingService
    private nonisolated(unsafe) var listeners: [any ListenerRegistration] = []

    init(service: PPAccountingService = .shared()) {
        self.service = service
        self.notificationToken = NotificationCenter.default.addObserver(
            forName: Notification.Name("PPAccountingDataDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sync()
            }
        }
        self.branchNotificationToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.PPActiveBranchDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.grossRevenue = 0
                self?.totalExpenses = 0
                self?.paidOrderCount = 0
                self?.expenseCount = 0
                self?.subscribe()
            }
        }
        subscribe()
    }

    deinit {
        listeners.forEach { $0.remove() }
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = branchNotificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func subscribe() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        isLoading = true

        let filter = "month"
        let wsReg = service.subscribeAccountingWorkspace(withFilter: filter) { [weak self] _ in
            Task { @MainActor in
                self?.sync()
            }
        }
        let orderReg = service.subscribeOrderRevenue(withFilter: filter) { [weak self] in
            Task { @MainActor in
                self?.sync()
            }
        }
        let expenseReg = service.subscribeExpenses(withFilter: filter) { [weak self] in
            Task { @MainActor in
                self?.sync()
            }
        }
        let txnReg = service.subscribeTransactions(withFilter: filter) { [weak self] in
            Task { @MainActor in
                self?.sync()
            }
        }
        listeners = [wsReg, orderReg, expenseReg, txnReg]
        sync()
    }

    private func sync() {
        let workspace = service.currentWorkspace
        let dashboard = workspace?.primaryDashboard

        // Multi-tier revenue derivation
        if let dashboard, dashboard.income > 0 {
            grossRevenue = dashboard.income
            paidOrderCount = workspace?.incomeCount ?? 0
        } else if let docs = workspace?.documents, !docs.isEmpty {
            let docIncome = docs.filter { $0.kind == "income" }.reduce(0.0) { $0 + $1.total }
            let docCount = docs.filter { $0.kind == "income" }.count
            if docIncome > 0 || docCount > 0 {
                grossRevenue = docIncome
                paidOrderCount = docCount
            } else if service.orderRevenue > 0 || service.orderCount > 0 {
                grossRevenue = service.orderRevenue
                paidOrderCount = service.orderCount
            } else if service.liveTransactionRevenue > 0 || service.liveTransactionCount > 0 {
                grossRevenue = service.liveTransactionRevenue
                paidOrderCount = service.liveTransactionCount
            } else {
                grossRevenue = 0
                paidOrderCount = 0
            }
        } else if service.orderRevenue > 0 || service.orderCount > 0 {
            grossRevenue = service.orderRevenue
            paidOrderCount = service.orderCount
        } else if service.liveTransactionRevenue > 0 || service.liveTransactionCount > 0 {
            grossRevenue = service.liveTransactionRevenue
            paidOrderCount = service.liveTransactionCount
        } else {
            grossRevenue = 0
            paidOrderCount = 0
        }

        // Multi-tier expense derivation
        if let dashboard, dashboard.expenses > 0 {
            totalExpenses = dashboard.expenses
            expenseCount = workspace?.expenseCount ?? 0
        } else if let docs = workspace?.documents, !docs.isEmpty {
            let docExpenses = docs.filter { $0.kind == "expense" }.reduce(0.0) { $0 + $1.total }
            let docCount = docs.filter { $0.kind == "expense" }.count
            if docExpenses > 0 || docCount > 0 {
                totalExpenses = docExpenses
                expenseCount = docCount
            } else if service.liveTotalExpenses > 0 || service.liveExpenseCount > 0 {
                totalExpenses = service.liveTotalExpenses
                expenseCount = service.liveExpenseCount
            } else {
                totalExpenses = 0
                expenseCount = 0
            }
        } else if service.liveTotalExpenses > 0 || service.liveExpenseCount > 0 {
            totalExpenses = service.liveTotalExpenses
            expenseCount = service.liveExpenseCount
        } else {
            totalExpenses = 0
            expenseCount = 0
        }

        isLoading = false
    }

    var netProfit: Double {
        grossRevenue - totalExpenses
    }

    var isProfitable: Bool {
        netProfit >= 0
    }

    var profitMarginPercent: Double {
        guard grossRevenue > 0 else { return 0.0 }
        return (netProfit / grossRevenue) * 100.0
    }

    var expenseRatio: Double {
        guard grossRevenue > 0 else { return totalExpenses > 0 ? 1.0 : 0.0 }
        return min(max(totalExpenses / grossRevenue, 0.0), 1.0)
    }
}

private struct CommandAccountingSovereignCard: View {
    let onRoute: () -> Void

    @StateObject private var viewModel = CommandAccountingCardViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onRoute()
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // Header Flight Deck: Live Beacon + Section Identity + Quick Route Pill
                headerDeck

                // Primary Hologram: Net Operating Profit
                netProfitHero

                // Secondary Telemetry Twin-Pillars: Inflow (Revenue) vs Outflow (Expenses)
                twinPillars

                // Micro Financial Efficiency Progress Gauge
                efficiencyGauge
            }
            .padding(18)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(cardBorder)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06),
                radius: 12,
                x: 0,
                y: 5
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .buttonStyle(CommandCardPressStyle(scale: 0.985, pressedOpacity: 0.95, cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Language.isRTL() ? "اضغط لفتح الخزينة والتقارير المالية الكاملة" : "Tap to open complete financial command center")
    }

    private var headerDeck: some View {
        HStack(alignment: .center, spacing: 8) {
            // Glowing Symbol Squircle
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.72, blue: 0.44).opacity(colorScheme == .dark ? 0.30 : 0.16),
                                Color(red: 0.10, green: 0.55, blue: 0.85).opacity(colorScheme == .dark ? 0.22 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.40), lineWidth: 0.75)
                    )

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Language.get("Accounting_Title", alter: "الخزينة والمالية"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    // Live Telemetry Pulse Dot
                    HStack(spacing: 3.5) {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.78, blue: 0.48))
                            .frame(width: 5, height: 5)
                            .scaleEffect(isPulsing ? 1.3 : 0.8)
                        Text(Language.get("LiveSync", alter: "مباشر"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.12), in: Capsule())
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                }

                Text(Language.isRTL() ? "الأداء التشغيلي والخزينة • هذا الشهر" : "Operational Performance & Treasury • This Month")
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }

            Spacer(minLength: 4)

            // Tactile Entry Pill
            HStack(spacing: 4) {
                Text(Language.isRTL() ? "استعراض" : "Open")
                    .font(AdminType.caption2Bold)
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(AdminSurface.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AdminSurface.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), in: Capsule())
            .overlay(
                Capsule().strokeBorder(AdminSurface.primary.opacity(0.24), lineWidth: 0.5)
            )
        }
    }

    private var netProfitHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Language.isRTL() ? "صافي الربح التشغيلي" : "Net Operating Profit")
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)

                Spacer()

                // Margin Percentage Chip
                HStack(spacing: 3) {
                    Image(systemName: viewModel.isProfitable ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%@%.1f%%", viewModel.isProfitable ? "+" : "", viewModel.profitMarginPercent))
                        .font(AdminType.caption2Bold)
                        .monospacedDigit()
                }
                .foregroundStyle(viewModel.isProfitable ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.95, green: 0.35, blue: 0.40))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    (viewModel.isProfitable ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.95, green: 0.35, blue: 0.40))
                        .opacity(colorScheme == .dark ? 0.20 : 0.10),
                    in: Capsule()
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(formatCurrency(viewModel.netProfit))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(viewModel.isProfitable ? AdminSurface.primaryText : Color(red: 0.95, green: 0.35, blue: 0.40))
                    .monospacedDigit()

                Text(Language.isRTL() ? "ر.ق" : "QAR")
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminCommandInk.secondary)
            }
        }
    }

    private var twinPillars: some View {
        HStack(spacing: 10) {
            // Revenue Pillar
            pillarCell(
                title: Language.isRTL() ? "الإيرادات" : "Revenue",
                amount: viewModel.grossRevenue,
                subtitle: Language.isRTL() ? "\(viewModel.paidOrderCount) عملية دخل" : "\(viewModel.paidOrderCount) income entries",
                symbol: "arrow.up.forward.circle.fill",
                tint: Color(red: 0.16, green: 0.78, blue: 0.48)
            )

            // Expenses Pillar
            pillarCell(
                title: Language.isRTL() ? "المصروفات" : "Expenses",
                amount: viewModel.totalExpenses,
                subtitle: Language.isRTL() ? "\(viewModel.expenseCount) سند صرف" : "\(viewModel.expenseCount) vouchers",
                symbol: "arrow.down.forward.circle.fill",
                tint: Color(red: 0.95, green: 0.40, blue: 0.35)
            )
        }
    }

    private func pillarCell(title: String, amount: Double, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)

                HStack(spacing: 3) {
                    Text(formatCurrency(amount))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(Language.isRTL() ? "ر.ق" : "QAR")
                        .font(AdminType.caption2Medium)
                        .foregroundStyle(AdminCommandInk.secondary)
                }

                Text(subtitle)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(tint.opacity(colorScheme == .dark ? 0.20 : 0.12), lineWidth: 0.5)
        )
    }

    private var efficiencyGauge: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let w = proxy.size.width
                let expenseRatio = CGFloat(viewModel.expenseRatio)
                let revenueRatio = max(1.0 - expenseRatio, 0.0)

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))

                    // Dynamic multi-segment
                    HStack(spacing: 2) {
                        if revenueRatio > 0 {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.16, green: 0.78, blue: 0.48), Color(red: 0.10, green: 0.65, blue: 0.70)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(w * revenueRatio - 1, 4))
                        }

                        if expenseRatio > 0 {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.95, green: 0.45, blue: 0.35), Color(red: 0.90, green: 0.25, blue: 0.35)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(w * expenseRatio - 1, 4))
                        }
                    }
                }
            }
            .frame(height: 6)

            HStack {
                Text(Language.isRTL() ? "كفاءة التشغيل المالي" : "Capital Efficiency")
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
                Spacer()
                Text(Language.isRTL() ? "انقر لفتح الخزينة والتحليلات ←" : "Tap for full ledger & analytics →")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)
            }
        }
        .padding(.top, 2)
    }

    private var cardBackground: some View {
        ZStack {
            AdminSurface.control

            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.78, blue: 0.48).opacity(colorScheme == .dark ? 0.08 : 0.04),
                    Color(red: 0.10, green: 0.55, blue: 0.85).opacity(colorScheme == .dark ? 0.06 : 0.02),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.78, blue: 0.48).opacity(colorScheme == .dark ? 0.40 : 0.25),
                        AdminSurface.primary.opacity(colorScheme == .dark ? 0.25 : 0.15),
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.85
            )
    }

    private var accessibilityLabel: String {
        let title = Language.isRTL() ? "الخزينة والمالية" : "Treasury and Finance"
        let profit = formatCurrency(viewModel.netProfit)
        let curr = Language.isRTL() ? "ريال قطري" : "QAR"
        return "\(title), \(profit) \(curr)"
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

// MARK: - Command Hotel Sovereign Card

private struct CommandHotelSovereignCard: View {
    let onRoute: () -> Void
    var onOpenArrivals: (() -> Void)? = nil
    var onOpenDepartures: (() -> Void)? = nil

    @ObservedObject private var viewModel = AdminPetsHotelViewModel.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerDeck
            occupancyHero
            operationalPillars
            wingHorizonBar
        }
        .padding(18)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardBorder)
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06),
            radius: 12,
            x: 0,
            y: 5
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onRoute()
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Language.isRTL() ? "اضغط لفتح عمليات فندق ورعاية الحيوانات" : "Tap to open pets hotel operations hub")
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header Deck
    private var headerDeck: some View {
        HStack(alignment: .center, spacing: 8) {
            // Glowing Symbol Squircle
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.58, green: 0.35, blue: 0.95).opacity(colorScheme == .dark ? 0.30 : 0.16),
                                Color(red: 0.20, green: 0.65, blue: 0.95).opacity(colorScheme == .dark ? 0.22 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color(red: 0.58, green: 0.35, blue: 0.95).opacity(0.40), lineWidth: 0.75)
                    )

                Image(systemName: "bed.double.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.68, green: 0.45, blue: 1.0))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Language.get("Hotel_Title", alter: "فندق ورعاية الحيوانات"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)

                    // Live Telemetry Pulse Dot
                    HStack(spacing: 3.5) {
                        Circle()
                            .fill(Color(red: 0.35, green: 0.80, blue: 0.55))
                            .frame(width: 5, height: 5)
                            .scaleEffect(isPulsing ? 1.3 : 0.8)
                        Text(Language.get("LiveSync", alter: "مباشر"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(red: 0.35, green: 0.80, blue: 0.55))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.35, green: 0.80, blue: 0.55).opacity(0.12), in: Capsule())
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                }

                Text(Language.isRTL() ? "الإشغال والنزلاء • الغرف والرعاية الفندقية" : "Occupancy & In-House Guests • Boarding & Care")
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            Spacer(minLength: 4)

            // Tactile Entry Pill
            HStack(spacing: 4) {
                Text(Language.isRTL() ? "استعراض" : "Open")
                    .font(AdminType.caption2Bold)
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Color(red: 0.58, green: 0.35, blue: 0.95))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(red: 0.58, green: 0.35, blue: 0.95).opacity(colorScheme == .dark ? 0.18 : 0.08), in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color(red: 0.58, green: 0.35, blue: 0.95).opacity(0.26), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Occupancy Hero
    private var occupancyHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Language.isRTL() ? "معدل إشغال الغرف والأجنحة" : "Room & Suite Occupancy Rate")
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)

                Spacer()

                // Active Capacity Chip
                HStack(spacing: 4) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(Language.isRTL() ? "\(viewModel.inHouseGuestsCount) نزيل مقيم" : "\(viewModel.inHouseGuestsCount) In-House")
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(Color(red: 0.58, green: 0.35, blue: 0.95))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Color(red: 0.58, green: 0.35, blue: 0.95).opacity(colorScheme == .dark ? 0.20 : 0.10),
                    in: Capsule()
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(viewModel.occupancyPercentageString)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(AdminSurface.primaryText)
                    .monospacedDigit()

                Text(Language.isRTL() ? "(\(viewModel.occupiedRoomsCount) من \(viewModel.totalRoomsCount) غرفة)" : "(\(viewModel.occupiedRoomsCount) of \(viewModel.totalRoomsCount) suites)")
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminCommandInk.secondary)

                if viewModel.attentionGuestsCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(Language.isRTL() ? "\(viewModel.attentionGuestsCount) عناية خاصة" : "\(viewModel.attentionGuestsCount) clinical")
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    // MARK: - Operational Twin Pillars
    private var operationalPillars: some View {
        HStack(spacing: 10) {
            // Arrivals Pillar
            pillarCell(
                title: Language.isRTL() ? "وصول اليوم" : "Arrivals Today",
                count: viewModel.arrivalsTodayCount,
                subtitle: Language.isRTL() ? "حجوزات مؤكدة" : "Confirmed bookings",
                symbol: "arrow.down.right.and.arrow.up.left",
                tint: Color(red: 0.20, green: 0.70, blue: 0.50),
                onTap: onOpenArrivals
            )

            // Departures Pillar
            pillarCell(
                title: Language.isRTL() ? "مغادرة اليوم" : "Departures Today",
                count: viewModel.departuresTodayCount,
                subtitle: Language.isRTL() ? "تسليم لأصحابها" : "Discharge & handover",
                symbol: "arrow.up.left.and.arrow.down.right",
                tint: Color(red: 0.30, green: 0.60, blue: 0.95),
                onTap: onOpenDepartures
            )
        }
    }

    private func pillarCell(
        title: String,
        count: Int,
        subtitle: String,
        symbol: String,
        tint: Color,
        onTap: (() -> Void)? = nil
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if let onTap {
                onTap()
            } else {
                onRoute()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)

                    HStack(spacing: 4) {
                        Text("\(count)")
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                            .monospacedDigit()
                        Text(Language.isRTL() ? "حالات" : "items")
                            .font(AdminType.caption2Medium)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }

                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(tint.opacity(colorScheme == .dark ? 0.20 : 0.12), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(CommandCardPressStyle(scale: 0.97, pressedOpacity: 0.92, cornerRadius: 13))
    }

    // MARK: - Multi-Wing Horizon Bar
    private var wingHorizonBar: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let w = proxy.size.width
                let total = max(viewModel.totalRoomsCount, 1)
                let occupiedW = w * CGFloat(viewModel.occupiedRoomsCount) / CGFloat(total)
                let availableW = w * CGFloat(viewModel.availableRoomsCount) / CGFloat(total)
                let cleaningW = w * CGFloat(viewModel.cleaningRoomsCount) / CGFloat(total)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))

                    HStack(spacing: 2) {
                        if occupiedW > 3 {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.58, green: 0.35, blue: 0.95), Color(red: 0.45, green: 0.25, blue: 0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(occupiedW - 2, 4))
                        }
                        if availableW > 3 {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.20, green: 0.75, blue: 0.50), Color(red: 0.15, green: 0.65, blue: 0.45)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(availableW - 2, 4))
                        }
                        if cleaningW > 3 {
                            Capsule()
                                .fill(Color.orange.opacity(0.85))
                                .frame(width: max(cleaningW - 2, 4))
                        }
                    }
                }
            }
            .frame(height: 6)

            HStack {
                HStack(spacing: 12) {
                    legendDot(color: Color(red: 0.58, green: 0.35, blue: 0.95), label: Language.isRTL() ? "مشغول (\(viewModel.occupiedRoomsCount))" : "Occupied (\(viewModel.occupiedRoomsCount))")
                    legendDot(color: Color(red: 0.20, green: 0.75, blue: 0.50), label: Language.isRTL() ? "متاح (\(viewModel.availableRoomsCount))" : "Available (\(viewModel.availableRoomsCount))")
                    if viewModel.cleaningRoomsCount > 0 {
                        legendDot(color: Color.orange, label: Language.isRTL() ? "تعقيم (\(viewModel.cleaningRoomsCount))" : "Cleaning (\(viewModel.cleaningRoomsCount))")
                    }
                }
                Spacer()
                Text(Language.isRTL() ? "إدارة الفندق والنزلاء ←" : "Manage Hotel & Guests →")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color(red: 0.58, green: 0.35, blue: 0.95))
            }
        }
        .padding(.top, 2)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
        }
    }

    // MARK: - Visual Enclosure
    private var cardBackground: some View {
        ZStack {
            AdminSurface.control

            LinearGradient(
                colors: [
                    Color(red: 0.58, green: 0.35, blue: 0.95).opacity(colorScheme == .dark ? 0.08 : 0.04),
                    Color(red: 0.20, green: 0.65, blue: 0.95).opacity(colorScheme == .dark ? 0.06 : 0.02),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color(red: 0.58, green: 0.35, blue: 0.95).opacity(colorScheme == .dark ? 0.40 : 0.25),
                        Color(red: 0.20, green: 0.65, blue: 0.95).opacity(colorScheme == .dark ? 0.25 : 0.15),
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.85
            )
    }

    private var accessibilityLabel: String {
        let title = Language.isRTL() ? "فندق ورعاية الحيوانات" : "Pets Hotel and Boarding"
        let rate = viewModel.occupancyPercentageString
        let guests = "\(viewModel.inHouseGuestsCount)"
        return "\(title), \(rate), \(guests)"
    }
}

// MARK: - Command Hotel Deck

private struct CommandHotelDeck: View {
    let isRegular: Bool
    let onRoute: (String) -> Void
    let onOpenArrivals: () -> Void
    let onOpenDepartures: () -> Void

    @ObservedObject private var viewModel = AdminPetsHotelViewModel.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSectionSpacing.headerToContent(isRegular: isRegular)) {
            // Dedicated Section Header
            AdminSectionHeader(
                title: Language.get("AdminHotel_SectionTitle", alter: "فندق ورعاية الحيوانات"),
                subtitle: Language.get("AdminHotel_SectionDetail", alter: "الإشغال والنزلاء، الغرف، وعمليات الوصول والمغادرة اليومية"),
                eyebrow: Language.get("AdminHotel_SectionEyebrow", alter: "الضيافة والرعاية الفندقية"),
                symbol: "bed.double.fill",
                themeColor: Color(red: 0.58, green: 0.35, blue: 0.95),
                state: .normal,
                isRegular: isRegular
            )

            VStack(spacing: 12) {
                // Primary Sovereign Radar Card
                CommandHotelSovereignCard(
                    onRoute: { onRoute("hotel") },
                    onOpenArrivals: onOpenArrivals,
                    onOpenDepartures: onOpenDepartures
                )

                // Dedicated Quick Actions Below Card
                HStack(spacing: isRegular ? 14 : 10) {
                    // Quick Action 1: Arrived Today
                    CommandHotelQuickActionCard(
                        title: Language.get("AdminHotel_ArrivalsQuickAction", alter: "وصول اليوم"),
                        subtitle: Language.get("AdminHotel_ArrivalsQuickAction_Subtitle", alter: "تسجيل الدخول والتسكين"),
                        count: viewModel.arrivalsTodayCount,
                        countUnit: Language.isRTL() ? "حالات" : "guests",
                        actionTitle: Language.get("AdminHotel_ArrivalsQuickAction_Action", alter: "تسجيل الدخول"),
                        symbol: "arrow.down.left.circle.fill",
                        accent: Color(red: 0.16, green: 0.78, blue: 0.48),
                        isRegular: isRegular,
                        onTap: onOpenArrivals
                    )

                    // Quick Action 2: Leaves Today
                    CommandHotelQuickActionCard(
                        title: Language.get("AdminHotel_DeparturesQuickAction", alter: "مغادرة اليوم"),
                        subtitle: Language.get("AdminHotel_DeparturesQuickAction_Subtitle", alter: "تسليم وإتمام الإقامة"),
                        count: viewModel.departuresTodayCount,
                        countUnit: Language.isRTL() ? "حالات" : "guests",
                        actionTitle: Language.get("AdminHotel_DeparturesQuickAction_Action", alter: "إتمام المغادرة"),
                        symbol: "arrow.up.right.circle.fill",
                        accent: Color(red: 0.95, green: 0.55, blue: 0.20),
                        isRegular: isRegular,
                        onTap: onOpenDepartures
                    )
                }
            }
        }
    }
}

// MARK: - Command Hotel Quick Action Card

private struct CommandHotelQuickActionCard: View {
    let title: String
    let subtitle: String
    let count: Int
    let countUnit: String
    let actionTitle: String
    let symbol: String
    let accent: Color
    let isRegular: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isPulsing: Bool = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header: Symbol Squircle + Counter Telemetry Pill
                HStack(alignment: .center) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(accent.opacity(colorScheme == .dark ? 0.22 : 0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(
                                        accent.opacity(contrast == .increased ? 0.60 : (colorScheme == .dark ? 0.35 : 0.20)),
                                        lineWidth: 0.75
                                    )
                            )

                        Image(systemName: symbol)
                            .font(.system(size: isRegular ? 16 : 14, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: isRegular ? 34 : 30, height: isRegular ? 34 : 30)

                    Spacer(minLength: 4)

                    // Live Counter Badge
                    HStack(spacing: 3.5) {
                        if count > 0 {
                            Circle()
                                .fill(accent)
                                .frame(width: 5, height: 5)
                                .scaleEffect(isPulsing ? 1.25 : 0.8)
                        }

                        Text("\(count)")
                            .font(AdminType.calloutBold)
                            .foregroundStyle(accent)
                            .monospacedDigit()

                        Text(countUnit)
                            .font(AdminType.caption2Medium)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        accent.opacity(colorScheme == .dark ? 0.16 : 0.08),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder(accent.opacity(contrast == .increased ? 0.50 : 0.22), lineWidth: 0.5)
                    )
                }

                // Title & Subtitle Stack
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                // Bottom Action Strip with Directional Arrow
                HStack(spacing: 4) {
                    Text(actionTitle)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(accent)

                    Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accent)
                }
                .padding(.top, 2)
            }
            .padding(isRegular ? 14 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: isRegular ? 116 : 106)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(cardBorder)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04),
                radius: 8,
                x: 0,
                y: 3
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(CommandCardPressStyle(scale: 0.98, pressedOpacity: 0.94, cornerRadius: 18))
        .onAppear {
            if count > 0 {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) \(countUnit), \(subtitle)")
        .accessibilityHint(Language.isRTL() ? "اضغط لفتح \(title)" : "Tap to open \(title)")
    }

    private var cardBackground: some View {
        ZStack {
            AdminSurface.control

            LinearGradient(
                colors: [
                    accent.opacity(colorScheme == .dark ? 0.08 : 0.035),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        accent.opacity(contrast == .increased ? 0.60 : (colorScheme == .dark ? 0.35 : 0.20)),
                        accent.opacity(contrast == .increased ? 0.40 : (colorScheme == .dark ? 0.15 : 0.08))
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: contrast == .increased ? 1.2 : 0.8
            )
    }
}
