//
//  HomeControlView.swift
//  PurePetsAdmin
//
//  NextGen V10 Category-Defining Home Feed Choreographer & Sovereign Studio.
//  Reinvented from absolute first principles:
//  - Sovereign Uncrowded Header: Flawless Arabic typography with zero truncation,
//    breathing live status beacon, and preset layout orchestrator.
//  - Ergonomic Floating Action Dock: Save & Revert controls live in an elevated,
//    tactile glass dock that emerges with spring physics when dirty changes exist,
//    liberating prime navigation real estate.
//  - NextGen V10 Feed Card: Generous layout without text truncation, monospaced
//    numeric rank HUD (#01-#20), ergonomic 44pt step triggers, radiant identity
//    glyphs, and a bespoke tactile visibility capsule replacing clunky generic toggles.
//  - Living Telemetry & Feed Balance Radar: Live visual gauge showing feed density,
//    core safety compliance, and category distribution (Gateway, Commerce, Care, Discovery).
//  - Smart Layout Presets: Instant 1-tap switching between Standard, Commerce Focus,
//    Care & Adoption Focus, and Ultra-Lightweight minimal modes.
//  - Hyper-Realistic iPhone 16 Pro Canvas: Live scrolling simulator rendering all
//    active sections with high-fidelity micro-components in real-time sequence.
//  - Full Backend Contract Parity: 100% compliant with AppConfigCol/HomeConfig,
//    publishHomeConfig callable, expectedVersion conflict protection, and audit logs.
//

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Category Taxonomy

public enum HomeSectionCategory: String, CaseIterable, Sendable {
    case gateway
    case commerce
    case care
    case discovery

    public var title: String {
        switch self {
        case .gateway: return Language.get("HomeControl_Category_Gateway", alter: "البوابة والاستكشاف")
        case .commerce: return Language.get("HomeControl_Category_Commerce", alter: "التجارة والتسوق")
        case .care: return Language.get("HomeControl_Category_Care", alter: "الرعاية والبيطرة")
        case .discovery: return Language.get("HomeControl_Category_Discovery", alter: "التوصيات والمجتمع")
        }
    }

    public var symbol: String {
        switch self {
        case .gateway: return "sparkles.rectangle.stack"
        case .commerce: return "cart.fill"
        case .care: return "heart.text.square.fill"
        case .discovery: return "bubble.left.and.exclamationmark.bubble.right.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .gateway: return .purple
        case .commerce: return .orange
        case .care: return .red
        case .discovery: return .blue
        }
    }
}

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
    public let category: HomeSectionCategory

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
    HomeSectionCatalogItem(sectionID: 20, type: "PPHomeSectionPureLens", labelKey: "HomeControl_Section_PureLens_Label", descKey: "HomeControl_Section_PureLens_Description", defaultVisible: true, critical: false, conditional: false, symbol: "viewfinder.circle.fill", accentColor: .purple, category: .gateway),
    HomeSectionCatalogItem(sectionID: 15, type: "PPHomeSectionPremiumSearch", labelKey: "HomeControl_Section_PremiumSearch_Label", descKey: "HomeControl_Section_PremiumSearch_Description", defaultVisible: true, critical: false, conditional: false, symbol: "magnifyingglass", accentColor: .blue, category: .gateway),
    HomeSectionCatalogItem(sectionID: 17, type: "PPHomeSectionMarketplaceHero", labelKey: "HomeControl_Section_MarketplaceHero_Label", descKey: "HomeControl_Section_MarketplaceHero_Description", defaultVisible: false, critical: false, conditional: false, symbol: "bag.fill", accentColor: .orange, category: .commerce),
    HomeSectionCatalogItem(sectionID: 16, type: "PPHomeSectionProviderCategoryNav", labelKey: "HomeControl_Section_ProviderCategoryNav_Label", descKey: "HomeControl_Section_ProviderCategoryNav_Description", defaultVisible: false, critical: false, conditional: false, symbol: "rectangle.grid.1x2.fill", accentColor: .indigo, category: .gateway),
    HomeSectionCatalogItem(sectionID: 0, type: "PPHomeSectionHero", labelKey: "HomeControl_Section_Hero_Label", descKey: "HomeControl_Section_Hero_Description", defaultVisible: true, critical: true, conditional: false, symbol: "photo.stack.fill", accentColor: .pink, category: .gateway),
    HomeSectionCatalogItem(sectionID: 5, type: "PPHomeSectionMainKinds", labelKey: "HomeControl_Section_MainKinds_Label", descKey: "HomeControl_Section_MainKinds_Description", defaultVisible: true, critical: true, conditional: false, symbol: "pawprint.fill", accentColor: .teal, category: .gateway),
    HomeSectionCatalogItem(sectionID: 9, type: "PPHomeSectionPremiumCare", labelKey: "HomeControl_Section_PremiumCare_Label", descKey: "HomeControl_Section_PremiumCare_Description", defaultVisible: true, critical: false, conditional: false, symbol: "cross.case.fill", accentColor: .red, category: .care),
    HomeSectionCatalogItem(sectionID: 1, type: "PPHomeSectionQuickActions", labelKey: "HomeControl_Section_QuickActions_Label", descKey: "HomeControl_Section_QuickActions_Description", defaultVisible: true, critical: false, conditional: false, symbol: "square.grid.3x3.fill", accentColor: .cyan, category: .gateway),
    HomeSectionCatalogItem(sectionID: 2, type: "PPHomeSectionCurrentOrders", labelKey: "HomeControl_Section_CurrentOrders_Label", descKey: "HomeControl_Section_CurrentOrders_Description", defaultVisible: true, critical: false, conditional: false, symbol: "truck.box.fill", accentColor: .green, category: .discovery),
    HomeSectionCatalogItem(sectionID: 7, type: "PPHomeSectionAccessories", labelKey: "HomeControl_Section_Accessories_Label", descKey: "HomeControl_Section_Accessories_Description", defaultVisible: true, critical: false, conditional: false, symbol: "shippingbox.fill", accentColor: .brown, category: .commerce),
    HomeSectionCatalogItem(sectionID: 18, type: "PPHomeSectionSuggestionAds", labelKey: "HomeControl_Section_SuggestionAds_Label", descKey: "HomeControl_Section_SuggestionAds_Description", defaultVisible: true, critical: false, conditional: false, symbol: "megaphone.fill", accentColor: .indigo, category: .discovery),
    HomeSectionCatalogItem(sectionID: 19, type: "PPHomeSectionSuggestionAccessories", labelKey: "HomeControl_Section_SuggestionAccessories_Label", descKey: "HomeControl_Section_SuggestionAccessories_Description", defaultVisible: true, critical: false, conditional: false, symbol: "sparkle.magnifyingglass", accentColor: .orange, category: .commerce),
    HomeSectionCatalogItem(sectionID: 6, type: "PPHomeSectionSuggestions", labelKey: "HomeControl_Section_Suggestions_Label", descKey: "HomeControl_Section_Suggestions_Description", defaultVisible: true, critical: false, conditional: false, symbol: "lightbulb.fill", accentColor: .yellow, category: .commerce),
    HomeSectionCatalogItem(sectionID: 4, type: "PPHomeSectionCarousel", labelKey: "HomeControl_Section_Carousel_Label", descKey: "HomeControl_Section_Carousel_Description", defaultVisible: true, critical: true, conditional: false, symbol: "play.rectangle.fill", accentColor: .mint, category: .commerce),
    HomeSectionCatalogItem(sectionID: 10, type: "PPHomeSectionLastFood", labelKey: "HomeControl_Section_LastFood_Label", descKey: "HomeControl_Section_LastFood_Description", defaultVisible: true, critical: false, conditional: false, symbol: "takeoutbag.and.cup.and.straw.fill", accentColor: .orange, category: .commerce),
    HomeSectionCatalogItem(sectionID: 21, type: "PPHomeSectionMedicines", labelKey: "HomeControl_Section_Medicines_Label", descKey: "HomeControl_Section_Medicines_Description", defaultVisible: true, critical: false, conditional: false, symbol: "cross.case.circle.fill", accentColor: .red, category: .care),
    HomeSectionCatalogItem(sectionID: 12, type: "PPHomeSectionAdsNearBy", labelKey: "HomeControl_Section_AdsNearBy_Label", descKey: "HomeControl_Section_AdsNearBy_Description", defaultVisible: true, critical: false, conditional: false, symbol: "mappin.and.ellipse", accentColor: .blue, category: .discovery),
    HomeSectionCatalogItem(sectionID: 11, type: "PPHomeSectionNearbyServices", labelKey: "HomeControl_Section_NearbyServices_Label", descKey: "HomeControl_Section_NearbyServices_Description", defaultVisible: true, critical: false, conditional: false, symbol: "cross.fill", accentColor: .red, category: .care),
    HomeSectionCatalogItem(sectionID: 13, type: "PPHomeSectionAdopt", labelKey: "HomeControl_Section_Adopt_Label", descKey: "HomeControl_Section_Adopt_Description", defaultVisible: true, critical: false, conditional: false, symbol: "heart.fill", accentColor: .pink, category: .care),
    HomeSectionCatalogItem(sectionID: 14, type: "PPHomeSectionBuyAgain", labelKey: "HomeControl_Section_BuyAgain_Label", descKey: "HomeControl_Section_BuyAgain_Description", defaultVisible: true, critical: false, conditional: true, symbol: "arrow.triangle.2.circlepath", accentColor: .teal, category: .commerce),
    HomeSectionCatalogItem(sectionID: 8, type: "PPHomeSectionPetProfile", labelKey: "HomeControl_Section_PetProfile_Label", descKey: "HomeControl_Section_PetProfile_Description", defaultVisible: true, critical: false, conditional: false, symbol: "person.crop.circle.badge.plus", accentColor: .purple, category: .care)
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

// MARK: - Smart Layout Presets

public enum HomeLayoutPreset: String, CaseIterable, Identifiable {
    case standard
    case commerceFocus
    case careFocus
    case minimalLight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return Language.get("HomeControl_Preset_Standard", alter: "الوضع المتوازن القياسي")
        case .commerceFocus: return Language.get("HomeControl_Preset_Commerce", alter: "تركيز المتجر والتسوق")
        case .careFocus: return Language.get("HomeControl_Preset_Care", alter: "تركيز الرعاية والتبني")
        case .minimalLight: return Language.get("HomeControl_Preset_Minimal", alter: "الوضع الخفيف السريع")
        }
    }

    public var subtitle: String {
        switch self {
        case .standard: return Language.get("HomeControl_Preset_Standard_Desc", alter: "التوزيع الافتراضي المعتمد للخدمات والتجارة")
        case .commerceFocus: return Language.get("HomeControl_Preset_Commerce_Desc", alter: "تقديم العروض والمنتجات وإعادة الطلب في صدارة الصفحة")
        case .careFocus: return Language.get("HomeControl_Preset_Care_Desc", alter: "إبراز العيادات البيطرية والخدمات وبطاقات التبني")
        case .minimalLight: return Language.get("HomeControl_Preset_Minimal_Desc", alter: "إبقاء الأقسام الأساسية فقط لتجربة خفيفة وسريعة")
        }
    }

    public var symbol: String {
        switch self {
        case .standard: return "slider.horizontal.3"
        case .commerceFocus: return "bag.badge.plus"
        case .careFocus: return "heart.circle.fill"
        case .minimalLight: return "bolt.shield.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .standard: return AdminSurface.primary
        case .commerceFocus: return .orange
        case .careFocus: return .red
        case .minimalLight: return .teal
        }
    }
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
    @Published public var selectedCategory: HomeSectionCategory? = nil
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

            // Filter by Status Tab
            switch selectedFilter {
            case .all: break
            case .visible: if !item.visible { return false }
            case .hidden: if item.visible { return false }
            case .critical: if !meta.critical { return false }
            }

            // Filter by Category if selected
            if let cat = selectedCategory, meta.category != cat {
                return false
            }

            // Filter by Search Query
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

    // MARK: - Smart Presets Application

    public func applyPreset(_ preset: HomeLayoutPreset) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            switch preset {
            case .standard:
                resetToDefaultState()

            case .commerceFocus:
                // Priority: Hero (0), Carousel (4), Marketplace (17), Food (10), Accessories (7), Buy Again (14), Suggestions (6)
                let commercePriorityIDs: [Int] = [0, 4, 17, 10, 7, 14, 6, 19, 1, 5, 20, 15, 9, 11, 13, 8, 2, 12, 18, 16]
                reorderSectionsBy(idOrder: commercePriorityIDs)
                // Ensure commerce sections are visibly turned on
                for cid in [0, 4, 17, 10, 7, 14, 6, 19] {
                    if let idx = sections.firstIndex(where: { $0.sectionID == cid }) {
                        sections[idx].visible = true
                    }
                }

            case .careFocus:
                // Priority: Hero (0), Premium Care (9), Services (11), Adopt (13), Pet Profile (8), MainKinds (5)
                let carePriorityIDs: [Int] = [0, 9, 11, 13, 8, 5, 20, 1, 15, 4, 17, 10, 7, 14, 6, 2, 12, 18, 19, 16]
                reorderSectionsBy(idOrder: carePriorityIDs)
                for cid in [0, 9, 11, 13, 8, 5] {
                    if let idx = sections.firstIndex(where: { $0.sectionID == cid }) {
                        sections[idx].visible = true
                    }
                }

            case .minimalLight:
                // Keep only critical core sections visible
                for idx in 0..<sections.count {
                    let sid = sections[idx].sectionID
                    let isCore = (sid == 0 || sid == 5 || sid == 4 || sid == 15)
                    sections[idx].visible = isCore
                }
            }
            markDirty()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func reorderSectionsBy(idOrder: [Int]) {
        var newOrder: [HomeSectionStateItem] = []
        var existingMap = Dictionary(uniqueKeysWithValues: sections.map { ($0.sectionID, $0) })

        for id in idOrder {
            if let item = existingMap.removeValue(forKey: id) {
                newOrder.append(item)
            }
        }
        // Append any remaining
        for item in sections where existingMap[item.sectionID] != nil {
            newOrder.append(item)
        }
        sections = newOrder
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

// MARK: - NextGen V10 Sovereign Home Studio View

@MainActor
public struct AdminHomeControlView: View {
    public var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminHomeControlViewModel()
    @State private var toastMessage: String? = nil
    @State private var isErrorToast = false
    @State private var showsPresetsSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Dynamic Atmosphere Background
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // NextGen V10 Uncrowded Sovereign Header
                sovereignOperationsHeader

                // Mode Horizon Switcher (Layout, Simulator, Engine)
                studioModeHorizon
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

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

            // Floating Sovereign Action Dock (Save, Revert & Sync Status)
            floatingActionDock
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.bottom, max(PPStatusBarHelper.safeAreaBottomInset, 16))

            // Toast Floating Capsule
            if let message = toastMessage {
                VStack {
                    toastFloatingCapsule(message: message, isError: isErrorToast)
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.top, max(PPStatusBarHelper.statusBarHeight, 44) + 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .animation(AdminAnimation.standard, value: toastMessage)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showsPresetsSheet) {
            presetsSelectionSheet
        }
        .onAppear {
            viewModel.loadConfig()
        }
    }

    // MARK: - 1. Sovereign Uncrowded Operations Header

    private var sovereignOperationsHeader: some View {
        VStack(spacing: 0) {
            // Safe Top Clearance
            Color.clear.frame(height: max(PPStatusBarHelper.statusBarHeight, 44))

            HStack(alignment: .center, spacing: 12) {
                // Leading (RTL Right): Tactile Back Button
                AdminSquircleBackButton {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }

                // Center-Leading: Uncut Headline & Operations Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("HomeControl_Title", alter: "التحكم في الصفحة الرئيسية"))
                        .font(AdminType.title3Bold)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .allowsTightening(true)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isDirty ? AdminSurface.amber : Color.green)
                            .frame(width: 6, height: 6)
                            .shadow(color: (viewModel.isDirty ? AdminSurface.amber : Color.green).opacity(0.6), radius: 3)

                        Text(Language.get("CommandCenter_Operations_Workspace", alter: "مساحة عمل العمليات"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                // Trailing (RTL Left): Live Telemetry Beacon, Presets, Refresh
                HStack(spacing: 8) {
                    // Live Status Capsule (Spacious Single-Line Never Squeezed)
                    liveStatusBeacon

                    // Presets Quick Menu Button
                    Button {
                        showsPresetsSheet = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AdminSurface.primary)
                            .frame(width: 36, height: 36)
                            .background(AdminSurface.surface, in: Circle())
                            .overlay(Circle().strokeBorder(AdminSurface.primary.opacity(0.2), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("HomeControl_Presets", alter: "القوالب الجاهزة"))

                    // Refresh Button
                    Button {
                        viewModel.loadConfig()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(width: 36, height: 36)
                            .background(AdminSurface.surface, in: Circle())
                            .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Reload", alter: "تحديث"))
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, 8)
        }
    }

    private var liveStatusBeacon: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(viewModel.isDirty ? AdminSurface.amber : Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: (viewModel.isDirty ? AdminSurface.amber : Color.green).opacity(0.7), radius: 4)

            Text(viewModel.isDirty
                 ? String(format: Language.get("HomeControl_Unsaved_Count", alter: "%d غير محفوظة"), viewModel.unsavedChangesCount)
                 : Language.get("HomeControl_LiveStatus_Synced", alter: "مباشر"))
                .font(AdminType.caption2Bold)
                .foregroundColor(viewModel.isDirty ? AdminSurface.amber : Color.green)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            (viewModel.isDirty ? AdminSurface.amber : Color.green).opacity(0.08),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder((viewModel.isDirty ? AdminSurface.amber : Color.green).opacity(0.25), lineWidth: 0.8)
        )
    }

    // MARK: - 2. Studio Mode Horizon Switcher (3 Tabs)

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
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))

                        Text(tab.title)
                            .font(isSelected ? .system(size: 11.5, weight: .bold) : .system(size: 11.5, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.72)
                            .fixedSize(horizontal: false, vertical: true)

                        if tab == .layout {
                            Text("\(viewModel.totalSectionsCount)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(isSelected ? Color.white.opacity(0.25) : AdminSurface.primary.opacity(0.12), in: Capsule())
                        } else if tab == .simulator {
                            Text("\(viewModel.enabledSectionsCount)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(isSelected ? Color.white.opacity(0.25) : Color.green.opacity(0.12), in: Capsule())
                        }
                    }
                    .foregroundColor(isSelected ? .white : AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .padding(.horizontal, 4)
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

    // MARK: - 3. WORKSPACE 1: Layout & Sequence Studio

    private var layoutStudioWorkspace: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                // Feed Health Telemetry Radar
                feedTelemetryRadarCard

                // Search & Category Shelf
                searchAndFilterShelf

                // Sequential Section Reorder Deck
                if viewModel.isLoading {
                    loadingDeck
                } else if viewModel.filteredSections.isEmpty {
                    emptySearchState
                } else {
                    reorderableSectionsList
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.bottom, viewModel.isDirty ? 110 : 60)
        }
        .refreshable {
            viewModel.loadConfig()
        }
    }

    // MARK: - Telemetry & Radar Card

    private var feedTelemetryRadarCard: some View {
        HStack(spacing: 12) {
            // Metric 1: Active Sections Gauge
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.green)
                        .font(.system(size: 13))
                    Text(Language.get("HomeControl_Telemetry_Active", alter: "الأقسام المفعلة"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(viewModel.enabledSectionsCount)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(AdminSurface.primaryText)
                    Text("/ \(viewModel.totalSectionsCount)")
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                // Mini Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AdminSurface.control).frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(colors: [Color.green, AdminSurface.primary], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(viewModel.enabledSectionsCount) / CGFloat(max(viewModel.totalSectionsCount, 1)), height: 4)
                    }
                }
                .frame(height: 4)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))

            // Metric 2: Core Safety Protection
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundColor(AdminSurface.amber)
                        .font(.system(size: 13))
                    Text(Language.get("HomeControl_CoreProtection", alter: "الأقسام الأساسية"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                let criticalCount = kHomeCatalog.filter { $0.critical }.count
                let activeCritical = viewModel.sections.filter { item in
                    guard let meta = viewModel.metaFor(sectionID: item.sectionID) else { return false }
                    return meta.critical && item.visible
                }.count

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(activeCritical)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(activeCritical == criticalCount ? AdminSurface.amber : Color.red)
                    Text("/ \(criticalCount) " + Language.get("HomeControl_Protected", alter: "محمية"))
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Text(activeCritical == criticalCount
                     ? Language.get("HomeControl_SafeState", alter: "التدفق الأساسي آمن")
                     : Language.get("HomeControl_WarningState", alter: "تنبيه: أرفف أساسية مخفية"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(activeCritical == criticalCount ? Color.green : Color.red)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
        }
    }

    // MARK: - Search & Category Shelf

    private var searchAndFilterShelf: some View {
        VStack(spacing: 8) {
            // Search Input Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AdminSurface.secondaryText)
                    .font(.system(size: 14, weight: .medium))

                TextField(Language.get("HomeControl_SearchPlaceholder", alter: "ابحث في الأقسام"), text: $viewModel.searchText)
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                    .environment(\.layoutDirection, .leftToRight)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AdminSurface.secondaryText)
                            .font(.system(size: 15))
                    }
                    .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))

            // Filter Status Chips (All, Visible, Hidden, Critical)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
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
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? AdminSurface.primary : AdminSurface.surface,
                                in: Capsule()
                            )
                            .overlay(Capsule().strokeBorder(isSelected ? Color.white.opacity(0.2) : AdminSurface.hairline, lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }

                    // Optional Category Clear Pill
                    if viewModel.selectedCategory != nil {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                viewModel.selectedCategory = nil
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text(viewModel.selectedCategory?.title ?? "")
                                    .font(AdminType.captionBold)
                            }
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(AdminSurface.primary.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Reorderable Sections Deck

    private var reorderableSectionsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.filteredSections) { item in
                HomeSectionCardV10(
                    item: item,
                    viewModel: viewModel
                )
            }
        }
    }

    private var loadingDeck: some View {
        VStack(spacing: 14) {
            ProgressView().tint(AdminSurface.primary).scaleEffect(1.2)
            Text(Language.get("Loading", alter: "جاري تحميل إعدادات الأقسام..."))
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
                .font(.system(size: 32))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
            Text(Language.get("HomeControl_NoMatchingSections", alter: "لا توجد أقسام تطابق معايير البحث أو التصفية."))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
            Button {
                viewModel.searchText = ""
                viewModel.selectedFilter = .all
                viewModel.selectedCategory = nil
            } label: {
                Text(Language.get("Clear", alter: "إعادة ضبط التصفية"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - 4. WORKSPACE 2: Live iPhone 16 Pro Feed Simulator

    private var liveSimulatorWorkspace: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AdminSpacing.md) {
                // Simulator Info Banner
                HStack(spacing: 10) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 18))
                        .foregroundColor(AdminSurface.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("HomeControl_Canvas_DeviceFrame", alter: "محاكي تدفق الصفحة الرئيسية المباشر"))
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("HomeControl_LivePreview_Subtitle", alter: "معاينة حية دقيقة لترتيب ونمط ظهور الأقسام كما يراها العميل."))
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    Spacer()
                }
                .padding(12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))

                // The Realistic Apple iPhone Viewport
                iPhone16ProSimulatorViewport

                Spacer(minLength: viewModel.isDirty ? 110 : 60)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
        }
    }

    private var iPhone16ProSimulatorViewport: some View {
        VStack(spacing: 0) {
            // Status Bar & Dynamic Island
            HStack {
                Text("9:41")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                // Dynamic Island Pill
                Capsule()
                    .fill(Color.black)
                    .frame(width: 84, height: 22)
                    .overlay(
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 4, height: 4)
                            Spacer()
                            Circle().fill(Color.green).frame(width: 4, height: 4)
                        }
                        .padding(.horizontal, 6)
                    )

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

            // Mobile App Header Mock
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "pawprint.circle.fill")
                        .foregroundColor(AdminSurface.primary)
                        .font(.system(size: 18))
                    Text("PurePets")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(AdminSurface.primary)

                    HStack(spacing: 3) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 9))
                        Text(viewModel.globalSettings.titleViewMode == "search" ? "الدوحة" : "موقعك الحالي")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AdminSurface.control, in: Capsule())
                }

                Spacer()

                Image(systemName: "bell.badge.fill")
                    .foregroundColor(AdminSurface.secondaryText)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 16)

            // Sequential Live Feed Items
            if viewModel.visibleSectionsInOrder.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash.circle.fill")
                        .font(.system(size: 38))
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
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(20)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(viewModel.visibleSectionsInOrder.enumerated()), id: \.element.sectionID) { idx, section in
                        miniFeedCard(section: section, rank: idx + 1)
                    }
                }
                .padding(14)
            }
        }
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.8), Color.gray.opacity(0.3), Color.black.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 10)
        .padding(.horizontal, 6)
    }

    private func miniFeedCard(section: HomeSectionCatalogItem, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("#\(rank)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(section.accentColor, in: Capsule())

                Image(systemName: section.symbol)
                    .font(.system(size: 11, weight: .bold))
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
                    .font(.system(size: 14))
                    .foregroundColor(.purple)
                Text("PureLens AI • ماسح ذكي للحيوانات الأليفة")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.purple)
                Spacer()
                Circle().fill(Color.purple.opacity(0.4)).frame(width: 6, height: 6)
            }
            .padding(8)
            .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case 15: // Premium Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(.gray)
                Text("ماذا تبحث عنه لحيوانك الأليف؟")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(8)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case 0: // Hero Banner
            ZStack(alignment: .leading) {
                LinearGradient(colors: [Color.pink.opacity(0.3), Color.orange.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("عالم الرعاية المتكامل للحيوانات الأليفة")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AdminSurface.primaryText)
                        Text("خصومات حصرية وخدمات بيطرية فورية")
                            .font(.system(size: 9))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "arrow.left.circle.fill")
                        .foregroundColor(.pink)
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 10)
            }

        case 5: // Main Kinds
            HStack(spacing: 10) {
                ForEach(["كلاب", "قطط", "طيور", "أسماك"], id: \.self) { pet in
                    VStack(spacing: 2) {
                        Circle().fill(Color.teal.opacity(0.18)).frame(width: 30, height: 30)
                            .overlay(Image(systemName: "pawprint.fill").font(.system(size: 11)).foregroundColor(.teal))
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
                    .frame(width: 32, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    RoundedRectangle(cornerRadius: 3).fill(AdminSurface.primaryText.opacity(0.2)).frame(width: 90, height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(AdminSurface.secondaryText.opacity(0.15)).frame(width: 50, height: 5)
                }
                Spacer()
            }
            .padding(6)
        }
    }

    // MARK: - 5. WORKSPACE 3: Platform Engine & Features Studio

    private var platformEngineWorkspace: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AdminSpacing.md) {
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
                            Text(Language.get("HomeControl_TitleViewSearch", alter: "حقل البحث المباشر")).tag("search")
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
                            desc: "زر نوفا الذكي العائم للمساعدة السريعة وتوجيه المستفيدين.",
                            symbol: "sparkle.magnifyingglass",
                            color: .purple,
                            binding: $viewModel.globalSettings.novaFloatingVisible
                        )

                        Divider()

                        engineToggleRow(
                            title: Language.get("HomeControl_PureLens", alter: "استكشاف PureLens"),
                            desc: "ماسح الرؤية الحاسوبية للتعرف على فصائل الحيوانات وأعراضها.",
                            symbol: "camera.viewfinder",
                            color: .indigo,
                            binding: $viewModel.globalSettings.pureLensVisible
                        )
                    }
                }

                // Section 3: Visual & Media Systems
                engineCategoryCard(
                    title: Language.get("HomeControl_Engine_Media", alter: "وسائط وتجربة العرض"),
                    symbol: "play.tv.fill",
                    color: .mint
                ) {
                    VStack(spacing: 12) {
                        engineToggleRow(
                            title: Language.get("HomeControl_BackgroundGlows", alter: "تخفيف توهجات الخلفية"),
                            desc: "إبقاء التوهجات الجوية ناعمة ومخففة لتقليل استهلاك البطارية والراحة البصرية.",
                            symbol: "sun.min.fill",
                            color: .yellow,
                            binding: $viewModel.globalSettings.backgroundGlowsFaded
                        )

                        Divider()

                        engineToggleRow(
                            title: Language.get("HomeControl_ReusableVideo", alter: "وسائط الفيديو القابلة لإعادة الاستخدام"),
                            desc: "تشغيل عروض الفيديو الترويجية وموجز المنتجات بسلاسة.",
                            symbol: "play.rectangle.fill",
                            color: .mint,
                            binding: $viewModel.globalSettings.reusableVideoEnabled
                        )

                        Divider()

                        engineToggleRow(
                            title: Language.get("HomeControl_UniversalCells", alter: "الخلايا العامة SwiftUI"),
                            desc: "استخدام الجيل الأحدث من خلايا العرض الأصلية فائقة الأداء.",
                            symbol: "cube.transparent.fill",
                            color: .cyan,
                            binding: $viewModel.globalSettings.universalCellsSwiftUI
                        )
                    }
                }

                // Section 4: Policies & Advanced Services
                engineCategoryCard(
                    title: Language.get("HomeControl_Engine_Policies", alter: "السياسات والخدمات المتقدمة"),
                    symbol: "lock.shield.fill",
                    color: .orange
                ) {
                    VStack(spacing: 12) {
                        engineToggleRow(
                            title: Language.get("HomeControl_UsedAccessories", alter: "الإكسسوارات المستعملة"),
                            desc: "إتاحة أقسام وفلاتر مستلزمات الحيوانات المستعملة في السوق.",
                            symbol: "arrow.3.trianglepath",
                            color: .orange,
                            binding: $viewModel.globalSettings.usedAccessoriesAllowed
                        )

                        Divider()

                        engineToggleRow(
                            title: Language.get("HomeControl_UltraCare", alter: "بوابة الرعاية الفائقة UltraCare"),
                            desc: "تفعيل اشتراكات وخدمات الرعاية البيطرية الطارئة والشاملة.",
                            symbol: "heart.text.square.fill",
                            color: .red,
                            binding: $viewModel.globalSettings.ultraCareActivated
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

                Spacer(minLength: viewModel.isDirty ? 110 : 60)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
        }
    }

    private func engineCategoryCard<Content: View>(
        title: String,
        symbol: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
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
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
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

    // MARK: - 6. Floating Sovereign Action Dock

    private var floatingActionDock: some View {
        Group {
            if viewModel.isDirty {
                HStack(spacing: 10) {
                    // Unsaved Badge Pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AdminSurface.amber)
                            .frame(width: 7, height: 7)
                            .shadow(color: AdminSurface.amber.opacity(0.8), radius: 4)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: Language.get("HomeControl_Unsaved_Count", alter: "%d تغييرات بانتظار الحفظ"), viewModel.unsavedChangesCount))
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.primaryText)
                            Text(Language.get("HomeControl_PendingSync", alter: "لم تُنشر على تطبيق العملاء بعد"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                    .padding(.leading, 6)

                    Spacer()

                    // Revert Button
                    Button {
                        viewModel.revertChanges()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("HomeControl_Revert", alter: "تراجع"))
                                .font(AdminType.captionBold)
                        }
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(AdminSurface.control, in: Capsule())
                        .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)

                    // Hero Save Button
                    Button {
                        validateAndSave()
                    } label: {
                        HStack(spacing: 6) {
                            if viewModel.isSaving {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .heavy))
                            }

                            Text(Language.get("Save", alter: "حفظ ونشر التعديلات"))
                                .font(AdminType.captionBold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(
                            LinearGradient(
                                colors: [AdminSurface.primary, AdminSurface.primaryPressed],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
                        .shadow(color: AdminSurface.primary.opacity(0.4), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSaving || viewModel.isLoading)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(AdminSurface.amber.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.14), radius: 16, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isDirty)
    }

    // MARK: - 7. Presets Selection Sheet

    private var presetsSelectionSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(Language.get("HomeControl_Presets_Headline", alter: "اختر قالب توزيع الصفحة الرئيسية"))
                    .font(AdminType.headlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 16)

                Text(Language.get("HomeControl_Presets_Subheadline", alter: "تطبيق فوري لترتيب مدروس مسبقاً يناسب أهداف المتجر أو الحملات الموسمية."))
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, AdminSpacing.screenMargin)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(HomeLayoutPreset.allCases) { preset in
                            Button {
                                viewModel.applyPreset(preset)
                                showsPresetsSheet = false
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(preset.tintColor.opacity(0.14))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: preset.symbol)
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(preset.tintColor)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preset.title)
                                            .font(AdminType.bodyBold)
                                            .foregroundColor(AdminSurface.primaryText)
                                        Text(preset.subtitle)
                                            .font(AdminType.caption1)
                                            .foregroundColor(AdminSurface.secondaryText)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                                }
                                .padding(14)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.bottom, 20)
                }
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("HomeControl_Presets_Title", alter: "قوالب الترتيب الذكية"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        showsPresetsSheet = false
                    }
                    .font(AdminType.bodyBold)
                    .foregroundColor(AdminSurface.primary)
                }
            }
        }
        .presentationDetents([.medium])
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
                .font(.system(size: 16))
            Text(message)
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    // MARK: - Safety Confirmations

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

// MARK: - NextGen V10 Section Card with Ergonomic Steppers & Tactile Toggle

@MainActor
private struct HomeSectionCardV10: View {
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
        HStack(spacing: 10) {
            // MARK: Zone 1 (Leading in RTL) - Precision Reorder HUD & Steppers
            VStack(spacing: 2) {
                // Stepper Up Trigger
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

                // Sequence Rank Badge (#01, #02...)
                Text(String(format: "%02d", rank))
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(item.visible ? (meta?.accentColor ?? AdminSurface.primary) : AdminSurface.secondaryText)
                    .frame(width: 28, height: 20)
                    .background(
                        (item.visible ? (meta?.accentColor ?? AdminSurface.primary) : AdminSurface.secondaryText).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                // Stepper Down Trigger
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
            .frame(width: 30)

            // MARK: Zone 2 - Visual Identity Glyph Orb
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((meta?.accentColor ?? AdminSurface.primary).opacity(item.visible ? 0.15 : 0.06))
                    .frame(width: 42, height: 42)

                Image(systemName: meta?.symbol ?? "square.stack.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(item.visible ? (meta?.accentColor ?? AdminSurface.primary) : AdminSurface.secondaryText)
            }

            // MARK: Zone 3 - Full Uncut Metadata & Category Badges
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(meta?.label ?? "")
                        .font(AdminType.bodyBold)
                        .foregroundColor(item.visible ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)

                    // Badges (Critical, Conditional, Category)
                    if meta?.critical == true {
                        badgeTag(title: Language.get("HomeControl_Critical", alter: "أساسي"), color: Color(uiColor: .ppWarning))
                    } else if meta?.conditional == true {
                        badgeTag(title: Language.get("HomeControl_Conditional", alter: "مشروط"), color: Color(uiColor: .ppInfo))
                    }
                }

                Text(meta?.desc ?? "")
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // MARK: Zone 4 (Trailing in RTL) - Tactile Visibility Capsule & Drag Handle
            HStack(spacing: 8) {
                // NextGen Bespoke Visibility Pill (Replaces clunky iOS switch)
                Button {
                    viewModel.toggleVisibility(for: item.sectionID)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.visible ? Color.green : AdminSurface.secondaryText.opacity(0.5))
                            .frame(width: 6, height: 6)

                        Text(item.visible ? Language.get("HomeControl_Visible", alter: "ظاهر") : Language.get("HomeControl_Hidden", alter: "مخفي"))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundColor(item.visible ? Color.green : AdminSurface.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        (item.visible ? Color.green : AdminSurface.secondaryText).opacity(0.1),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder((item.visible ? Color.green : AdminSurface.secondaryText).opacity(0.25), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)

                // Drag Handle
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isDragging ? AdminSurface.primary.opacity(0.18) : AdminSurface.control)
                        .frame(width: 28, height: 36)

                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isDragging ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.65))
                }
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                            dragOffset = value.translation.height

                            if dragOffset < -45 {
                                if !isFirstItem {
                                    viewModel.moveUp(sectionID: item.sectionID)
                                    dragOffset += 50
                                }
                            } else if dragOffset > 45 {
                                if !isLastItem {
                                    viewModel.moveDown(sectionID: item.sectionID)
                                    dragOffset -= 50
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
        }
        .padding(10)
        .background(
            item.visible ? AdminSurface.surface : AdminSurface.surface.opacity(0.7),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isDragging ? AdminSurface.primary : (item.visible ? AdminSurface.hairline : AdminSurface.hairline.opacity(0.5)),
                    lineWidth: isDragging ? 1.5 : 0.8
                )
        )
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .offset(y: dragOffset)
        .shadow(
            color: isDragging ? AdminSurface.primary.opacity(0.2) : Color.black.opacity(0.03),
            radius: isDragging ? 12 : 3,
            y: isDragging ? 5 : 1
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

    private func badgeTag(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
