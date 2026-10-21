//
//  HomeControlView.swift
//  PurePetsAdmin
//
//  PurePets Sovereign Home Studio — Category-Defining Native SwiftUI Home Screen Control.
//  Preserves all Firestore AppConfigCol/HomeConfig contracts, legacy mirrors,
//  section catalog, global settings, audit logs, and features a live Apple-grade
//  interactive reordering engine, live iPhone feed simulator, and platform engine studio.
//

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Section Catalog Metadata

public struct HomeSectionCatalogItem: Identifiable, Hashable, Sendable {
    public let sectionID: Int
    public let type: String
    public let labelKey: String
    public let descKey: String
    public let defaultVisible: Bool
    public let critical: Bool
    public let conditional: Bool
    public let symbol: String
    public let accentColor: Color

    public var id: Int { sectionID }

    public var label: String { Language.get(labelKey, alter: nil) }
    public var desc: String { Language.get(descKey, alter: nil) }
}

public struct HomeSectionStateItem: Identifiable, Hashable, Equatable, Sendable {
    public let sectionID: Int
    public let type: String
    public var visible: Bool

    public var id: Int { sectionID }
}

// MARK: - Catalog Definition (20 Canonical Sections)

private let kHomeCatalog: [HomeSectionCatalogItem] = [
    HomeSectionCatalogItem(sectionID: 20, type: "PPHomeSectionPureLens", labelKey: "HomeControl_Section_PureLens_Label", descKey: "HomeControl_Section_PureLens_Description", defaultVisible: true, critical: false, conditional: false, symbol: "viewfinder.circle.fill", accentColor: .purple),
    HomeSectionCatalogItem(sectionID: 15, type: "PPHomeSectionPremiumSearch", labelKey: "HomeControl_Section_PremiumSearch_Label", descKey: "HomeControl_Section_PremiumSearch_Description", defaultVisible: true, critical: false, conditional: false, symbol: "magnifyingglass", accentColor: .blue),
    HomeSectionCatalogItem(sectionID: 17, type: "PPHomeSectionMarketplaceHero", labelKey: "HomeControl_Section_MarketplaceHero_Label", descKey: "HomeControl_Section_MarketplaceHero_Description", defaultVisible: false, critical: false, conditional: false, symbol: "bag.fill", accentColor: .orange),
    HomeSectionCatalogItem(sectionID: 16, type: "PPHomeSectionProviderCategoryNav", labelKey: "HomeControl_Section_ProviderCategoryNav_Label", descKey: "HomeControl_Section_ProviderCategoryNav_Description", defaultVisible: false, critical: false, conditional: false, symbol: "rectangle.grid.1x2.fill", accentColor: .indigo),
    HomeSectionCatalogItem(sectionID: 0, type: "PPHomeSectionHero", labelKey: "HomeControl_Section_Hero_Label", descKey: "HomeControl_Section_Hero_Description", defaultVisible: true, critical: true, conditional: false, symbol: "photo.stack.fill", accentColor: .pink),
    HomeSectionCatalogItem(sectionID: 5, type: "PPHomeSectionMainKinds", labelKey: "HomeControl_Section_MainKinds_Label", descKey: "HomeControl_Section_MainKinds_Description", defaultVisible: true, critical: true, conditional: false, symbol: "pawprint.fill", accentColor: .teal),
    HomeSectionCatalogItem(sectionID: 9, type: "PPHomeSectionPremiumCare", labelKey: "HomeControl_Section_PremiumCare_Label", descKey: "HomeControl_Section_PremiumCare_Description", defaultVisible: true, critical: false, conditional: false, symbol: "cross.case.fill", accentColor: .red),
    HomeSectionCatalogItem(sectionID: 1, type: "PPHomeSectionQuickActions", labelKey: "HomeControl_Section_QuickActions_Label", descKey: "HomeControl_Section_QuickActions_Description", defaultVisible: true, critical: false, conditional: false, symbol: "square.grid.3x3.fill", accentColor: .cyan),
    HomeSectionCatalogItem(sectionID: 2, type: "PPHomeSectionCurrentOrders", labelKey: "HomeControl_Section_CurrentOrders_Label", descKey: "HomeControl_Section_CurrentOrders_Description", defaultVisible: true, critical: false, conditional: false, symbol: "truck.box.fill", accentColor: .green),
    HomeSectionCatalogItem(sectionID: 7, type: "PPHomeSectionAccessories", labelKey: "HomeControl_Section_Accessories_Label", descKey: "HomeControl_Section_Accessories_Description", defaultVisible: true, critical: false, conditional: false, symbol: "shippingbox.fill", accentColor: .brown),
    HomeSectionCatalogItem(sectionID: 18, type: "PPHomeSectionSuggestionAds", labelKey: "HomeControl_Section_SuggestionAds_Label", descKey: "HomeControl_Section_SuggestionAds_Description", defaultVisible: true, critical: false, conditional: false, symbol: "megaphone.fill", accentColor: .indigo),
    HomeSectionCatalogItem(sectionID: 19, type: "PPHomeSectionSuggestionAccessories", labelKey: "HomeControl_Section_SuggestionAccessories_Label", descKey: "HomeControl_Section_SuggestionAccessories_Description", defaultVisible: true, critical: false, conditional: false, symbol: "sparkle.magnifyingglass", accentColor: .orange),
    HomeSectionCatalogItem(sectionID: 6, type: "PPHomeSectionSuggestions", labelKey: "HomeControl_Section_Suggestions_Label", descKey: "HomeControl_Section_Suggestions_Description", defaultVisible: true, critical: false, conditional: false, symbol: "lightbulb.fill", accentColor: .yellow),
    HomeSectionCatalogItem(sectionID: 4, type: "PPHomeSectionCarousel", labelKey: "HomeControl_Section_Carousel_Label", descKey: "HomeControl_Section_Carousel_Description", defaultVisible: true, critical: true, conditional: false, symbol: "play.rectangle.fill", accentColor: .mint),
    HomeSectionCatalogItem(sectionID: 10, type: "PPHomeSectionLastFood", labelKey: "HomeControl_Section_LastFood_Label", descKey: "HomeControl_Section_LastFood_Description", defaultVisible: true, critical: false, conditional: false, symbol: "takeoutbag.and.cup.and.straw.fill", accentColor: .orange),
    HomeSectionCatalogItem(sectionID: 12, type: "PPHomeSectionAdsNearBy", labelKey: "HomeControl_Section_AdsNearBy_Label", descKey: "HomeControl_Section_AdsNearBy_Description", defaultVisible: true, critical: false, conditional: false, symbol: "mappin.and.ellipse", accentColor: .blue),
    HomeSectionCatalogItem(sectionID: 11, type: "PPHomeSectionNearbyServices", labelKey: "HomeControl_Section_NearbyServices_Label", descKey: "HomeControl_Section_NearbyServices_Description", defaultVisible: true, critical: false, conditional: false, symbol: "cross.fill", accentColor: .red),
    HomeSectionCatalogItem(sectionID: 13, type: "PPHomeSectionAdopt", labelKey: "HomeControl_Section_Adopt_Label", descKey: "HomeControl_Section_Adopt_Description", defaultVisible: true, critical: false, conditional: false, symbol: "heart.fill", accentColor: .pink),
    HomeSectionCatalogItem(sectionID: 14, type: "PPHomeSectionBuyAgain", labelKey: "HomeControl_Section_BuyAgain_Label", descKey: "HomeControl_Section_BuyAgain_Description", defaultVisible: true, critical: false, conditional: true, symbol: "arrow.triangle.2.circlepath", accentColor: .teal),
    HomeSectionCatalogItem(sectionID: 8, type: "PPHomeSectionPetProfile", labelKey: "HomeControl_Section_PetProfile_Label", descKey: "HomeControl_Section_PetProfile_Description", defaultVisible: true, critical: false, conditional: false, symbol: "person.crop.circle.badge.plus", accentColor: .purple)
]

// MARK: - Global Settings Model

public struct HomeGlobalSettings: Equatable, Sendable {
    public var titleViewMode: String = "location"
    public var novaFloatingVisible: Bool = true
    public var pureLensVisible: Bool = true
    public var backgroundGlowsFaded: Bool = true
    public var usedAccessoriesAllowed: Bool = false
    public var reusableVideoEnabled: Bool = true
    public var ultraCareActivated: Bool = true
    public var useLegacyBar: Bool = false
    public var universalCellsSwiftUI: Bool = true
}

// MARK: - Workspace Studio Modes & Filter Tabs

public enum HomeStudioTab: String, CaseIterable, Identifiable {
    case layout
    case simulator
    case engine

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .layout: return Language.get("HomeControl_Tab_Sections", alter: "ترتيب الأقسام")
        case .simulator: return Language.get("HomeControl_Tab_Preview", alter: "المعاينة التفاعلية")
        case .engine: return Language.get("HomeControl_Tab_Engine", alter: "محرك المنصة")
        }
    }

    public var symbol: String {
        switch self {
        case .layout: return "rectangle.3.group.fill"
        case .simulator: return "iphone"
        case .engine: return "slider.horizontal.2.square"
        }
    }
}

public enum HomeSectionFilter: String, CaseIterable, Identifiable {
    case all
    case visible
    case hidden
    case critical

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return Language.get("HomeControl_Filter_All", alter: "الكل")
        case .visible: return Language.get("HomeControl_Filter_Visible", alter: "الظاهرة")
        case .hidden: return Language.get("HomeControl_Filter_Hidden", alter: "المخفية")
        case .critical: return Language.get("HomeControl_Filter_Critical", alter: "الأساسية")
        }
    }
}

// MARK: - ViewModel

@MainActor
public final class AdminHomeControlViewModel: ObservableObject {
    @Published public var sections: [HomeSectionStateItem] = []
    @Published public var globalSettings = HomeGlobalSettings()
    @Published public var selectedTab: HomeStudioTab = .layout
    @Published public var selectedFilter: HomeSectionFilter = .all
    @Published public var searchText: String = ""
    @Published public private(set) var isLoading: Bool = true
    @Published public private(set) var isSaving: Bool = false
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var isDirty: Bool = false
    @Published public var draggedSectionID: Int? = nil

    private var savedSections: [HomeSectionStateItem] = []
    private var savedGlobalSettings = HomeGlobalSettings()
    private var loadedConfigVersion = 0
    private let configRef = Firestore.firestore().collection("AppConfigCol").document("HomeConfig")

    public var enabledSectionsCount: Int {
        sections.filter { $0.visible }.count
    }

    public var hiddenSectionsCount: Int {
        sections.filter { !$0.visible }.count
    }

    public var totalSectionsCount: Int {
        sections.count
    }

    public var unsavedChangesCount: Int {
        var count = 0
        for (idx, item) in sections.enumerated() {
            if idx >= savedSections.count || savedSections[idx] != item {
                count += 1
            }
        }
        if globalSettings != savedGlobalSettings {
            count += 1
        }
        return count
    }

    public var visibleSectionsInOrder: [HomeSectionCatalogItem] {
        sections.filter { $0.visible }.compactMap { item in
            kHomeCatalog.first(where: { $0.sectionID == item.sectionID })
        }
    }

    public var filteredSections: [HomeSectionStateItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sections.filter { item in
            guard let meta = metaFor(sectionID: item.sectionID) else { return false }

            // Filter by Category
            switch selectedFilter {
            case .all: break
            case .visible: if !item.visible { return false }
            case .hidden: if item.visible { return false }
            case .critical: if !meta.critical { return false }
            }

            // Filter by Query
            guard !query.isEmpty else { return true }
            return meta.label.lowercased().contains(query) ||
                   meta.desc.lowercased().contains(query) ||
                   meta.type.lowercased().contains(query)
        }
    }

    public init() {
        resetToDefaultState()
    }

    public func resetToDefaultState() {
        sections = kHomeCatalog.map { HomeSectionStateItem(sectionID: $0.sectionID, type: $0.type, visible: $0.defaultVisible) }
        globalSettings = HomeGlobalSettings()
    }

    public func markDirty() {
        isDirty = (sections != savedSections) || (globalSettings != savedGlobalSettings)
    }

    // MARK: - Reordering Logic (100% Reliable & Touch-Optimized)

    public func rankFor(sectionID: Int) -> Int {
        (sections.firstIndex(where: { $0.sectionID == sectionID }) ?? 0) + 1
    }

    public func isFirst(sectionID: Int) -> Bool {
        sections.first?.sectionID == sectionID
    }

    public func isLast(sectionID: Int) -> Bool {
        sections.last?.sectionID == sectionID
    }

    public func moveUp(sectionID: Int) {
        guard let index = sections.firstIndex(where: { $0.sectionID == sectionID }), index > 0 else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            sections.swapAt(index, index - 1)
        }
        markDirty()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    public func moveDown(sectionID: Int) {
        guard let index = sections.firstIndex(where: { $0.sectionID == sectionID }), index < sections.count - 1 else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            sections.swapAt(index, index + 1)
        }
        markDirty()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    public func moveToTop(sectionID: Int) {
        guard let index = sections.firstIndex(where: { $0.sectionID == sectionID }), index > 0 else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            let item = sections.remove(at: index)
            sections.insert(item, at: 0)
        }
        markDirty()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    public func moveToBottom(sectionID: Int) {
        guard let index = sections.firstIndex(where: { $0.sectionID == sectionID }), index < sections.count - 1 else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            let item = sections.remove(at: index)
            sections.append(item)
        }
        markDirty()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    public func toggleVisibility(for sectionID: Int) {
        if let idx = sections.firstIndex(where: { $0.sectionID == sectionID }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                sections[idx].visible.toggle()
            }
            markDirty()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    public func moveSections(fromOffsets source: IndexSet, toOffset destination: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            sections.move(fromOffsets: source, toOffset: destination)
        }
        markDirty()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    public func resetToDefaults() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            resetToDefaultState()
            markDirty()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    public func revertChanges() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            sections = savedSections
            globalSettings = savedGlobalSettings
            isDirty = false
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Firestore Sync

    public func loadConfig() {
        isLoading = true
        errorMessage = nil

        configRef.getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                    self.loadedConfigVersion = 0
                    self.resetToDefaultState()
                    self.savedSections = self.sections
                    self.savedGlobalSettings = self.globalSettings
                    self.isDirty = false
                    return
                }

                self.loadedConfigVersion = (data["configVersion"] as? NSNumber)?.intValue ?? 0
                var loadedSections: [HomeSectionStateItem] = []
                var seenIDs = Set<Int>()

                if let rawSections = data["sections"] as? [[String: Any]] {
                    for raw in rawSections {
                        let sid = (raw["id"] as? Int) ?? (raw["id"] as? String).flatMap(Int.init)
                        let stype = raw["type"] as? String
                        guard let match = kHomeCatalog.first(where: { ($0.sectionID == sid) || ($0.type == stype) }) else { continue }
                        if seenIDs.contains(match.sectionID) { continue }
                        seenIDs.insert(match.sectionID)

                        let visible = (raw["visible"] as? Bool) ?? match.defaultVisible
                        loadedSections.append(HomeSectionStateItem(sectionID: match.sectionID, type: match.type, visible: visible))
                    }
                }

                for item in kHomeCatalog where !seenIDs.contains(item.sectionID) {
                    loadedSections.append(HomeSectionStateItem(sectionID: item.sectionID, type: item.type, visible: item.defaultVisible))
                }

                if !seenIDs.contains(9), let legacyPremiumCare = data["premiumCareVisible"] as? Bool {
                    if let idx = loadedSections.firstIndex(where: { $0.sectionID == 9 }) {
                        loadedSections[idx].visible = legacyPremiumCare
                    }
                }

                var loadedSettings = HomeGlobalSettings()
                if let mode = data["titleViewMode"] as? String, mode == "location" || mode == "search" {
                    loadedSettings.titleViewMode = mode
                }
                loadedSettings.novaFloatingVisible = (data["novaFloatingVisible"] as? Bool) ?? true
                loadedSettings.pureLensVisible = (data["pureLensVisible"] as? Bool) ?? true
                loadedSettings.backgroundGlowsFaded = (data["backgroundGlowsFaded"] as? Bool) ?? true
                loadedSettings.usedAccessoriesAllowed = (data["AllwedUsedAccessories"] as? Bool) ?? false
                loadedSettings.reusableVideoEnabled = (data["PP_REUSABLE_VIDEO_MEDIA_ENABLED"] as? Bool) ?? ((data["PPReusableVideoMediaEnabled"] as? Bool) ?? true)
                loadedSettings.ultraCareActivated = (data["PPULTRA_CARE_IS_ACTIVATED"] as? Bool) ?? true
                loadedSettings.useLegacyBar = (data["PPUSE_LEGACY_BAR"] as? Bool) ?? false
                loadedSettings.universalCellsSwiftUI = (data["BBUniversalCellUseSwiftUI"] as? Bool) ?? true

                self.sections = loadedSections
                self.globalSettings = loadedSettings
                self.savedSections = loadedSections
                self.savedGlobalSettings = loadedSettings
                self.isDirty = false
            }
        }
    }

    public func save(completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        isSaving = true

        let sectionsPayload = sections.map { item -> [String: Any] in
            [
                "id": item.sectionID,
                "type": item.type,
                "visible": item.visible
            ]
        }

        let premiumCareVisible = sections.first(where: { $0.sectionID == 9 })?.visible ?? true

        let payload: [String: Any] = [
            "sections": sectionsPayload,
            "titleViewMode": globalSettings.titleViewMode,
            "premiumCareVisible": premiumCareVisible,
            "novaFloatingVisible": globalSettings.novaFloatingVisible,
            "pureLensVisible": globalSettings.pureLensVisible,
            "backgroundGlowsFaded": globalSettings.backgroundGlowsFaded,
            "AllwedUsedAccessories": globalSettings.usedAccessoriesAllowed,
            "PP_REUSABLE_VIDEO_MEDIA_ENABLED": globalSettings.reusableVideoEnabled,
            "PPReusableVideoMediaEnabled": globalSettings.reusableVideoEnabled,
            "PPULTRA_CARE_IS_ACTIVATED": globalSettings.ultraCareActivated,
            "PPUSE_LEGACY_BAR": globalSettings.useLegacyBar,
            "BBUniversalCellUseSwiftUI": globalSettings.universalCellsSwiftUI
        ]

        // HomeConfig is server-owned: publish via the audited, version-checked callable.
        // Direct Firestore writes are intentionally rejected by production rules.
        let commandId = UUID().uuidString
        Functions.functions().httpsCallable("publishHomeConfig").call([
            "commandId": commandId,
            "expectedVersion": loadedConfigVersion,
            "config": payload
        ]) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSaving = false
                if let error {
                    completion(false, error.localizedDescription)
                    return
                }
                guard let response = result?.data as? [String: Any],
                      response["ok"] as? Bool == true,
                      let version = response["configVersion"] as? Int else {
                    completion(false, "Home configuration publish returned an invalid response.")
                    return
                }
                self.loadedConfigVersion = version
                self.savedSections = self.sections
                self.savedGlobalSettings = self.globalSettings
                self.isDirty = false
                completion(true, Language.get("HomeControl_Saved", alter: "تم حفظ إعدادات الصفحة الرئيسية بنجاح"))
            }
        }
    }

    public func metaFor(sectionID: Int) -> HomeSectionCatalogItem? {
        kHomeCatalog.first(where: { $0.sectionID == sectionID })
    }
}

// MARK: - Main Sovereign Home Studio View

@MainActor
public struct AdminHomeControlView: View {
    public var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminHomeControlViewModel()
    @State private var toastMessage: String? = nil
    @State private var isErrorToast = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Studio Dynamic Atmospheric Background
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Sovereign Header & Telemetry Island
                studioHeaderBar

                // Studio Mode Horizon Switcher (Layout, Simulator, Engine)
                studioModeHorizon
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Active Workspace Tab
                Group {
                    switch viewModel.selectedTab {
                    case .layout:
                        layoutStudioWorkspace
                    case .simulator:
                        liveSimulatorWorkspace
                    case .engine:
                        platformEngineWorkspace
                    }
                }
            }

            // Toast Floating Capsule
            if let message = toastMessage {
                VStack {
                    Spacer()
                    toastFloatingCapsule(message: message, isError: isErrorToast)
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.bottom, AdminSpacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(AdminAnimation.standard, value: toastMessage)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            viewModel.loadConfig()
        }
    }

    // MARK: - Sovereign Header Bar

    private var studioHeaderBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("HomeControl_Title", alter: "التحكم في الصفحة الرئيسية"),
            subtitle: Language.get("CommandCenter_Operations_Workspace", alter: "مساحة عمل العمليات"),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            HStack(spacing: 8) {
                // Live Status Beacon Capsule
                liveStatusBeacon

                // Revert Button (when dirty)
                if viewModel.isDirty {
                    Button {
                        viewModel.revertChanges()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.secondaryText)
                            .frame(width: 38, height: 38)
                            .background(AdminSurface.surface, in: Circle())
                            .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }

                // Primary Save Pill
                Button {
                    validateAndSave()
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isSaving {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                        }

                        Text(Language.get("Save", alter: "حفظ"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(
                        viewModel.isDirty ? AdminSurface.primary : AdminSurface.primary.opacity(0.6),
                        in: Capsule()
                    )
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75))
                    .shadow(
                        color: viewModel.isDirty ? AdminSurface.primary.opacity(0.35) : Color.clear,
                        radius: 8,
                        x: 0,
                        y: 3
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSaving || viewModel.isLoading)

                // Refresh Button
                Button {
                    viewModel.loadConfig()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(width: 38, height: 38)
                        .background(AdminSurface.surface, in: Circle())
                        .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var liveStatusBeacon: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isDirty ? AdminSurface.amber : Color.green)
                .frame(width: 7, height: 7)
                .shadow(color: (viewModel.isDirty ? AdminSurface.amber : Color.green).opacity(0.6), radius: 4)

            Text(viewModel.isDirty
                 ? String(format: Language.get("HomeControl_Unsaved_Count", alter: "%d غير محفوظة"), viewModel.unsavedChangesCount)
                 : Language.get("HomeControl_LiveStatus_Synced", alter: "مباشر"))
                .font(AdminType.caption2Bold)
                .foregroundColor(viewModel.isDirty ? AdminSurface.amber : Color.green)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background((viewModel.isDirty ? AdminSurface.amber : Color.green).opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder((viewModel.isDirty ? AdminSurface.amber : Color.green).opacity(0.25), lineWidth: 0.8))
    }

    // MARK: - Mode Horizon Switcher (3 Tabs)

    private var studioModeHorizon: some View {
        HStack(spacing: 6) {
            ForEach(HomeStudioTab.allCases) { tab in
                let isSelected = viewModel.selectedTab == tab
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.selectedTab = tab
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))

                        Text(tab.title)
                            .font(isSelected ? AdminType.subheadlineBold : AdminType.subheadline)
                            .lineLimit(1)

                        if tab == .layout {
                            Text("\(viewModel.totalSectionsCount)")
                                .font(AdminType.caption2Bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.white.opacity(0.25) : AdminSurface.primary.opacity(0.12), in: Capsule())
                        } else if tab == .simulator {
                            Text("\(viewModel.enabledSectionsCount)")
                                .font(AdminType.caption2Bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.white.opacity(0.25) : Color.green.opacity(0.12), in: Capsule())
                        }
                    }
                    .foregroundColor(isSelected ? .white : AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        isSelected ? AdminSurface.primary : AdminSurface.control,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? Color.white.opacity(0.2) : AdminSurface.hairline, lineWidth: 0.8)
                    )
                    .shadow(color: isSelected ? AdminSurface.primary.opacity(0.25) : Color.clear, radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
    }

    // MARK: - WORKSPACE 1: Layout & Sequence Studio

    private var layoutStudioWorkspace: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AdminSpacing.md) {
                // Command Toolbar: Search & Quick Actions
                commandToolbar

                // Section Filter Chips
                filterChipsRow

                // Reorder Guidance Pill & Reset to Defaults
                reorderGuidanceBanner

                // The Sequential Sections Reorder Deck
                if viewModel.isLoading {
                    loadingDeck
                } else if viewModel.filteredSections.isEmpty {
                    emptySearchState
                } else {
                    reorderableSectionsList
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.bottom, AdminSpacing.xxl)
        }
        .refreshable {
            viewModel.loadConfig()
        }
    }

    private var commandToolbar: some View {
        HStack(spacing: 10) {
            // Search Input Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AdminSurface.secondaryText)
                    .font(.system(size: 15, weight: .medium))

                TextField(Language.get("HomeControl_SearchPlaceholder", alter: "ابحث في الأقسام"), text: $viewModel.searchText)
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primaryText)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AdminSurface.secondaryText)
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))

            // Reset Defaults Button
            Button {
                promptResetDefaults()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .bold))
                    Text(Language.get("HomeControl_Defaults", alter: "الافتراضيات"))
                        .font(AdminType.captionBold)
                }
                .foregroundColor(AdminSurface.primary)
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.primary.opacity(0.2), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        }
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeSectionFilter.allCases) { filter in
                    let isSelected = viewModel.selectedFilter == filter
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            viewModel.selectedFilter = filter
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 5) {
                            Text(filter.title)
                                .font(isSelected ? AdminType.captionBold : AdminType.captionRegular)

                            // Dynamic Count
                            let count: Int = {
                                switch filter {
                                case .all: return viewModel.totalSectionsCount
                                case .visible: return viewModel.enabledSectionsCount
                                case .hidden: return viewModel.hiddenSectionsCount
                                case .critical: return kHomeCatalog.filter { $0.critical }.count
                                }
                            }()
                            Text("\(count)")
                                .font(AdminType.caption2Bold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.white.opacity(0.25) : AdminSurface.primary.opacity(0.12), in: Capsule())
                        }
                        .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? AdminSurface.primary : AdminSurface.surface,
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(isSelected ? Color.white.opacity(0.2) : AdminSurface.hairline, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var reorderGuidanceBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.and.down.circle.fill")
                .foregroundColor(AdminSurface.primary)
                .font(.system(size: 14))

            Text(viewModel.searchText.isEmpty
                 ? Language.get("HomeControl_Reorder_Hint", alter: "اسحب أو استخدم أزرار الأسهم لإعادة الترتيب التفاعلي")
                 : Language.get("HomeControl_Search_Active_Hint", alter: "البحث نشط — الترتيب التسلسلي الكامل متاح عند مسح البحث"))
                .font(AdminType.captionRegular)
                .foregroundColor(AdminSurface.secondaryText)
                .lineLimit(1)

            Spacer()

            // Active/Total Ratio
            Text("\(viewModel.enabledSectionsCount) / \(viewModel.totalSectionsCount) " + Language.get("HomeControl_Telemetry_Active", alter: "أقسام مفعلة"))
                .font(AdminType.caption2Bold)
                .foregroundColor(AdminSurface.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AdminSurface.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.primary.opacity(0.15), lineWidth: 0.8))
    }

    // MARK: - Reorderable Sections List

    private var reorderableSectionsList: some View {
        LazyVStack(spacing: 10) {
            ForEach(viewModel.filteredSections) { item in
                InteractiveSectionCard(
                    item: item,
                    viewModel: viewModel
                )
            }
        }
    }

    private var loadingDeck: some View {
        VStack(spacing: 14) {
            ProgressView().tint(AdminSurface.primary).scaleEffect(1.2)
            Text(Language.get("Loading", alter: "جاري التحميل..."))
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
            Text(Language.get("HomeControl_NoMatchingSections", alter: "لا توجد أقسام تطابق هذا البحث."))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
            Button {
                viewModel.searchText = ""
            } label: {
                Text(Language.get("Clear", alter: "مسح البحث"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - WORKSPACE 2: Live iPhone Feed Simulator

    private var liveSimulatorWorkspace: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AdminSpacing.lg) {
                // Simulator Info Banner
                HStack(spacing: 10) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 20))
                        .foregroundColor(AdminSurface.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("HomeControl_Canvas_DeviceFrame", alter: "محاكي تدفق الصفحة الرئيسية"))
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("HomeControl_LivePreview_Subtitle", alter: "ستعرض الصفحة الرئيسية للعميل الأقسام الظاهرة بهذا الترتيب."))
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    Spacer()
                }
                .padding(14)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))

                // The Realistic Apple iPhone Frame
                iPhoneSimulatorViewport

                // Reorder from simulator notice
                Text(Language.get("HomeControl_Reorder_Hint", alter: "عد إلى تبويب ترتيب الأقسام للتحكم بالترتيب والإخفاء"))
                    .font(AdminType.footnote)
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.bottom, AdminSpacing.xl)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
        }
    }

    private var iPhoneSimulatorViewport: some View {
        VStack(spacing: 0) {
            // iPhone Dynamic Island & Status Bar Mock
            HStack {
                Text("9:41")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                // Dynamic Island Pill
                Capsule()
                    .fill(Color.black)
                    .frame(width: 80, height: 20)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "cellularbars").font(.system(size: 10))
                    Image(systemName: "wifi").font(.system(size: 10))
                    Image(systemName: "battery.100").font(.system(size: 11))
                }
                .foregroundColor(AdminSurface.primaryText)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Mobile App Header Simulation
            HStack(spacing: 8) {
                // Mini Logo & Location
                HStack(spacing: 5) {
                    Image(systemName: "pawprint.circle.fill")
                        .foregroundColor(AdminSurface.primary)
                        .font(.system(size: 18))
                    Text("PurePets")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(AdminSurface.primary)

                    HStack(spacing: 3) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 10))
                        Text(viewModel.globalSettings.titleViewMode == "search" ? "الدوحة" : "موقعك الحالي")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AdminSurface.control, in: Capsule())
                }

                Spacer()

                // Notification Bell
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(AdminSurface.secondaryText)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 16)

            // Sequential Feed Items
            if viewModel.visibleSectionsInOrder.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color.red.opacity(0.6))
                    Text(Language.get("HomeControl_NoVisibleSections", alter: "لا توجد أقسام ظاهرة. ستظهر الصفحة الرئيسية للعميل فارغة."))
                        .font(AdminType.callout)
                        .foregroundColor(Color.red)
                        .multilineTextAlignment(.center)
                    Button {
                        viewModel.resetToDefaults()
                    } label: {
                        Text(Language.get("HomeControl_Reset_Confirm", alter: "استعادة الترتيب الافتراضي"))
                            .font(AdminType.captionBold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(AdminSurface.primary, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 240)
                .padding(20)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(viewModel.visibleSectionsInOrder.enumerated()), id: \.element.sectionID) { idx, section in
                        miniFeedCard(section: section, rank: idx + 1)
                    }
                }
                .padding(16)
            }
        }
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [Color.white.opacity(0.8), Color.gray.opacity(0.3), Color.black.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 3)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 10)
        .padding(.horizontal, 8)
    }

    private func miniFeedCard(section: HomeSectionCatalogItem, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with Rank & Symbol
            HStack(spacing: 6) {
                Text("#\(rank)")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(section.accentColor, in: Capsule())

                Image(systemName: section.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(section.accentColor)

                Text(section.label)
                    .font(AdminType.caption1Bold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                Spacer()

                if section.critical {
                    Text(Language.get("HomeControl_Critical", alter: "أساسي"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(uiColor: .ppWarning))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .ppWarning).opacity(0.12), in: Capsule())
                }
            }

            // Visual Skeleton Mimic
            feedVisualSkeleton(for: section)
        }
        .padding(10)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
    }

    @ViewBuilder
    private func feedVisualSkeleton(for section: HomeSectionCatalogItem) -> some View {
        switch section.sectionID {
        case 20: // PureLens
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 16))
                    .foregroundColor(.purple)
                Text("PureLens AI • مسح حيوانك المفضل")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.purple)
                Spacer()
                Circle().fill(Color.purple.opacity(0.3)).frame(width: 8, height: 8)
            }
            .padding(8)
            .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case 15: // Premium Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(.gray)
                Text("ماذا تبحث عنه لحيوانك الأليف؟")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(8)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case 0: // Hero Banner
            ZStack(alignment: .leading) {
                LinearGradient(colors: [Color.pink.opacity(0.3), Color.orange.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("عالم الرعاية المتكامل")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AdminSurface.primaryText)
                        Text("خصومات تصل إلى 40% على المستلزمات")
                            .font(.system(size: 9))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "arrow.left.circle.fill")
                        .foregroundColor(.pink)
                        .font(.system(size: 18))
                }
                .padding(.horizontal, 12)
            }

        case 5: // Main Kinds
            HStack(spacing: 12) {
                ForEach(["كلاب", "قطط", "طيور", "أسماك"], id: \.self) { pet in
                    VStack(spacing: 3) {
                        Circle().fill(Color.teal.opacity(0.18)).frame(width: 32, height: 32)
                            .overlay(Image(systemName: "pawprint.fill").font(.system(size: 12)).foregroundColor(.teal))
                        Text(pet).font(.system(size: 9, weight: .medium))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

        default:
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(section.accentColor.opacity(0.2))
                    .frame(width: 36, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    RoundedRectangle(cornerRadius: 3).fill(AdminSurface.primaryText.opacity(0.2)).frame(width: 100, height: 7)
                    RoundedRectangle(cornerRadius: 3).fill(AdminSurface.secondaryText.opacity(0.15)).frame(width: 60, height: 5)
                }
                Spacer()
            }
            .padding(6)
        }
    }

    // MARK: - WORKSPACE 3: Platform Engine & Features Studio

    private var platformEngineWorkspace: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AdminSpacing.lg) {
                // Section 1: Header & Search Mode
                engineCategoryCard(
                    title: Language.get("HomeControl_Engine_HeaderSearch", alter: "واجهة الرأس والبحث"),
                    symbol: "magnifyingglass.circle.fill",
                    color: .blue
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Language.get("HomeControl_TitleViewMode", alter: "وضع عرض العنوان"))
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primaryText)

                        Picker(Language.get("HomeControl_TitleViewMode", alter: "وضع عرض العنوان"), selection: $viewModel.globalSettings.titleViewMode) {
                            Text(Language.get("HomeControl_TitleViewLocation", alter: "الموقع الجغرافي")).tag("location")
                            Text(Language.get("HomeControl_TitleViewSearch", alter: "حقل البحث")).tag("search")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: viewModel.globalSettings.titleViewMode) { _ in
                            viewModel.markDirty()
                        }
                    }
                }

                // Section 2: AI & Intelligence Systems
                engineCategoryCard(
                    title: Language.get("HomeControl_Engine_AI", alter: "أنظمة الذكاء الاصطناعي"),
                    symbol: "sparkles",
                    color: .purple
                ) {
                    VStack(spacing: 12) {
                        engineToggleRow(
                            title: Language.get("HomeControl_NovaFloating", alter: "مساعد نوفا العائم"),
                            desc: "زر ذكاء اصطناعي تفاعلي عائم لمساعدة العملاء في كافة أقسام التطبيق.",
                            symbol: "sparkle",
                            color: .purple,
                            binding: $viewModel.globalSettings.novaFloatingVisible
                        )

                        Divider()

                        engineToggleRow(
                            title: Language.get("HomeControl_PureLens", alter: "استكشاف PureLens"),
                            desc: "ماسح كاميرا الذكاء الاصطناعي للتعرف الفوري على سلالات الحيوانات.",
                            symbol: "viewfinder",
                            color: .indigo,
                            binding: $viewModel.globalSettings.pureLensVisible
                        )
                    }
                }

                // Section 3: Media & Display Engine
                engineCategoryCard(
                    title: Language.get("HomeControl_Engine_Media", alter: "وسائط وتجربة العرض"),
                    symbol: "play.tv.fill",
                    color: .orange
                ) {
                    VStack(spacing: 12) {
                        engineToggleRow(
                            title: Language.get("HomeControl_ReusableVideo", alter: "وسائط الفيديو القابلة لإعادة الاستخدام"),
                            desc: "تشغيل سلس لفيديوهات الحيوانات ومقاطع المنتجات الترويجية.",
                            symbol: "video.fill",
                            color: .orange,
                            binding: $viewModel.globalSettings.reusableVideoEnabled
                        )

                        Divider()

                        engineToggleRow(
                            title: Language.get("HomeControl_BackgroundGlows", alter: "تخفيف توهجات الخلفية"),
                            desc: "تأثير هالة بصرية متكيفة ناعمة تمنح التطبيق عمقاً جمالياً دون تشتيت.",
                            symbol: "sun.haze.fill",
                            color: .yellow,
                            binding: $viewModel.globalSettings.backgroundGlowsFaded
                        )

                        Divider()

                        engineToggleRow(
                            title: Language.get("HomeControl_UniversalCells", alter: "الخلايا العامة SwiftUI"),
                            desc: "بنية بطاقات الجيل الجديد المبنية بالكامل بـ SwiftUI عالية السرعة.",
                            symbol: "cube.fill",
                            color: .teal,
                            binding: $viewModel.globalSettings.universalCellsSwiftUI
                        )
                    }
                }

                // Section 4: Advanced Policies & Services
                engineCategoryCard(
                    title: Language.get("HomeControl_Engine_Policies", alter: "السياسات والخدمات المتقدمة"),
                    symbol: "shield.checkerboard",
                    color: .green
                ) {
                    VStack(spacing: 12) {
                        engineToggleRow(
                            title: Language.get("HomeControl_UltraCare", alter: "بوابة الرعاية الفائقة"),
                            desc: "تفعيل خدمة الطوارئ البيطرية المباشرة والاستشارات الفورية.",
                            symbol: "cross.case.fill",
                            color: .red,
                            binding: $viewModel.globalSettings.ultraCareActivated
                        )

                        Divider()

                        engineToggleRow(
                            title: Language.get("HomeControl_UsedAccessories", alter: "سوق الإكسسوارات المستعملة"),
                            desc: "السماح بعرض مستلزمات الحيوانات الأليفة المستعملة في أرفف المتجر.",
                            symbol: "arrow.3.trianglepath",
                            color: .brown,
                            binding: $viewModel.globalSettings.usedAccessoriesAllowed
                        )

                        Divider()

                        engineToggleRow(
                            title: Language.get("HomeControl_LegacyBar", alter: "شريط الرئيسية القديم"),
                            desc: "الاحتفاظ بوضع التوافق القديم للتطبيقات السابقة إذا لزم الأمر.",
                            symbol: "clock.arrow.circlepath",
                            color: .gray,
                            binding: $viewModel.globalSettings.useLegacyBar
                        )
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.bottom, AdminSpacing.xxl)
        }
    }

    private func engineCategoryCard<Content: View>(
        title: String,
        symbol: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
            }

            content()
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
    }

    private func engineToggleRow(
        title: String,
        desc: String,
        symbol: String,
        color: Color,
        binding: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AdminType.bodyBold)
                    .foregroundColor(AdminSurface.primaryText)
                Text(desc)
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(AdminSurface.primary)
                .onChange(of: binding.wrappedValue) { _ in
                    viewModel.markDirty()
                }
        }
    }

    // MARK: - Save Validation & Execution

    private func validateAndSave() {
        let visibleCount = viewModel.enabledSectionsCount
        if visibleCount == 0 {
            promptAllHiddenWarning()
            return
        }

        let criticalSections = kHomeCatalog.filter { $0.critical }
        let hiddenCriticalCount = viewModel.sections.filter { item in
            guard let meta = viewModel.metaFor(sectionID: item.sectionID) else { return false }
            return meta.critical && !item.visible
        }.count

        if criticalSections.count > 0 && hiddenCriticalCount == criticalSections.count {
            promptCoreHiddenWarning()
            return
        }

        commitSave()
    }

    private func commitSave() {
        viewModel.save { success, message in
            showToast(message ?? "", isError: !success)
        }
    }

    private func showToast(_ message: String, isError: Bool) {
        guard !message.isEmpty else { return }
        toastMessage = message
        isErrorToast = isError
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    private func toastFloatingCapsule(message: String, isError: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
                .font(.system(size: 18))
            Text(message)
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    // MARK: - Safety Confirmations

    private func promptResetDefaults() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("HomeControl_Defaults", alter: "الافتراضيات"),
            subtitle: Language.get("HomeControl_Reset_Confirm", alter: "هل أنت متأكد من رغبتك في استعادة ترتيب وإعدادات الأقسام الافتراضية؟"),
            confirmButton: Language.get("HomeControl_Continue", alter: "استعادة الافتراضيات"),
            cancelButton: Language.get("HomeControl_Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "arrow.counterclockwise"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                viewModel.resetToDefaults()
            },
            cancelBlock: nil
        )
    }

    private func promptAllHiddenWarning() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("HomeControl_AllSectionsHidden_Title", alter: "إخفاء كافة الأقسام"),
            subtitle: Language.get("HomeControl_AllSectionsHidden_Message", alter: "هل أنت متأكد من رغبتك في إخفاء جميع أقسام الصفحة الرئيسية؟ لن يظهر للمستخدم أي محتوى."),
            confirmButton: Language.get("HomeControl_Continue", alter: "متابعة الحفظ"),
            cancelButton: Language.get("HomeControl_Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "exclamationmark.triangle.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                commitSave()
            },
            cancelBlock: nil
        )
    }

    private func promptCoreHiddenWarning() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("HomeControl_CoreSectionsHidden_Title", alter: "إخفاء الأقسام الأساسية"),
            subtitle: Language.get("HomeControl_CoreSectionsHidden_Message", alter: "سيؤدي ذلك إلى إخفاء الأقسام الحيوية في التطبيق. هل ترغب في المتابعة؟"),
            confirmButton: Language.get("HomeControl_Continue", alter: "متابعة الحفظ"),
            cancelButton: Language.get("HomeControl_Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "exclamationmark.triangle.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                commitSave()
            },
            cancelBlock: nil
        )
    }
}

// MARK: - Interactive Section Card with Precision Reorder Steppers & Gestures

@MainActor
private struct InteractiveSectionCard: View {
    let item: HomeSectionStateItem
    @ObservedObject var viewModel: AdminHomeControlViewModel
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    private var meta: HomeSectionCatalogItem? {
        viewModel.metaFor(sectionID: item.sectionID)
    }

    private var rank: Int {
        viewModel.rankFor(sectionID: item.sectionID)
    }

    private var isFirstItem: Bool {
        viewModel.isFirst(sectionID: item.sectionID)
    }

    private var isLastItem: Bool {
        viewModel.isLast(sectionID: item.sectionID)
    }

    var body: some View {
        HStack(spacing: 12) {
            // MARK: Zone 1 - Precision Reorder HUD (Rank & Steppers)
            VStack(spacing: 3) {
                // Stepper Up Button
                Button {
                    viewModel.moveUp(sectionID: item.sectionID)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isFirstItem ? AdminSurface.secondaryText.opacity(0.3) : AdminSurface.primary)
                        .frame(width: 28, height: 20)
                        .background(
                            isFirstItem ? Color.clear : AdminSurface.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isFirstItem)

                // Sequence Rank Badge
                Text(String(format: "%02d", rank))
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(item.visible ? AdminSurface.primary : AdminSurface.secondaryText)
                    .frame(width: 28, height: 22)
                    .background(
                        (item.visible ? AdminSurface.primary : AdminSurface.secondaryText).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                // Stepper Down Button
                Button {
                    viewModel.moveDown(sectionID: item.sectionID)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isLastItem ? AdminSurface.secondaryText.opacity(0.3) : AdminSurface.primary)
                        .frame(width: 28, height: 20)
                        .background(
                            isLastItem ? Color.clear : AdminSurface.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isLastItem)
            }
            .frame(width: 32)

            // MARK: Zone 2 - Visual Identity Glyph
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill((meta?.accentColor ?? AdminSurface.primary).opacity(item.visible ? 0.14 : 0.06))
                    .frame(width: 44, height: 44)

                Image(systemName: meta?.symbol ?? "square.stack.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(item.visible ? (meta?.accentColor ?? AdminSurface.primary) : AdminSurface.secondaryText)
            }

            // MARK: Zone 3 - Metadata Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(meta?.label ?? "")
                        .font(AdminType.headline)
                        .foregroundColor(item.visible ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .lineLimit(1)

                    // Badges
                    if meta?.critical == true {
                        badgeView(title: Language.get("HomeControl_Critical", alter: "أساسي"), color: Color(uiColor: .ppWarning))
                    } else if meta?.conditional == true {
                        badgeView(title: Language.get("HomeControl_Conditional", alter: "مشروط"), color: Color(uiColor: .ppInfo))
                    }

                    badgeView(
                        title: item.visible ? Language.get("HomeControl_Visible", alter: "ظاهر") : Language.get("HomeControl_Hidden", alter: "مخفي"),
                        color: item.visible ? AdminSurface.primary : AdminSurface.secondaryText
                    )
                }

                Text(meta?.desc ?? "")
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // MARK: Zone 4 - Visibility Toggle Switch
            Toggle("", isOn: Binding(
                get: { item.visible },
                set: { _ in viewModel.toggleVisibility(for: item.sectionID) }
            ))
            .labelsHidden()
            .tint(AdminSurface.primary)

            // MARK: Zone 5 - Drag Handle with Fluid Drag Reorder Gesture
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDragging ? AdminSurface.primary.opacity(0.18) : AdminSurface.control)
                    .frame(width: 30, height: 38)

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isDragging ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.7))
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        dragOffset = value.translation.height

                        // Continuous index swapping during drag
                        if dragOffset < -50 {
                            if !isFirstItem {
                                viewModel.moveUp(sectionID: item.sectionID)
                                dragOffset += 60
                            }
                        } else if dragOffset > 50 {
                            if !isLastItem {
                                viewModel.moveDown(sectionID: item.sectionID)
                                dragOffset -= 60
                            }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isDragging = false
                            dragOffset = 0
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
        }
        .padding(12)
        .background(
            item.visible ? AdminSurface.surface : AdminSurface.surface.opacity(0.7),
            in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(
                    isDragging ? AdminSurface.primary : (item.visible ? AdminSurface.hairline : AdminSurface.hairline.opacity(0.5)),
                    lineWidth: isDragging ? 1.5 : 0.8
                )
        )
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .offset(y: dragOffset)
        .shadow(
            color: isDragging ? AdminSurface.primary.opacity(0.2) : Color.black.opacity(0.03),
            radius: isDragging ? 14 : 4,
            y: isDragging ? 6 : 1
        )
        .contextMenu {
            Button {
                viewModel.moveToTop(sectionID: item.sectionID)
            } label: {
                Label(Language.get("HomeControl_Action_MoveTop", alter: "نقل إلى القمة"), systemImage: "arrow.up.to.line")
            }

            Button {
                viewModel.moveUp(sectionID: item.sectionID)
            } label: {
                Label(Language.get("HomeControl_Action_MoveUp", alter: "رفع للأعلى"), systemImage: "chevron.up")
            }
            .disabled(isFirstItem)

            Button {
                viewModel.moveDown(sectionID: item.sectionID)
            } label: {
                Label(Language.get("HomeControl_Action_MoveDown", alter: "إنزال للأسفل"), systemImage: "chevron.down")
            }
            .disabled(isLastItem)

            Button {
                viewModel.moveToBottom(sectionID: item.sectionID)
            } label: {
                Label(Language.get("HomeControl_Action_MoveBottom", alter: "نقل إلى القاع"), systemImage: "arrow.down.to.line")
            }

            Divider()

            Button {
                viewModel.toggleVisibility(for: item.sectionID)
            } label: {
                Label(
                    item.visible ? Language.get("HomeControl_Hidden", alter: "إخفاء القسم") : Language.get("HomeControl_Visible", alter: "إظهار القسم"),
                    systemImage: item.visible ? "eye.slash" : "eye"
                )
            }
        }
    }

    private func badgeView(title: String, color: Color) -> some View {
        Text(title)
            .font(AdminType.caption2Bold)
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}