//
//  HomeControlView.swift
//  PurePetsAdmin
//
//  NextGen V6 Native SwiftUI Home Screen Control.
//  Preserves all Firestore AppConfigCol/HomeConfig contracts, legacy mirrors,
//  section ordering catalog, global settings toggles, and live layout preview.
//

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth

// MARK: - Section Metadata

struct HomeSectionCatalogItem: Identifiable, Hashable {
    let sectionID: Int
    let type: String
    let labelKey: String
    let descKey: String
    let defaultVisible: Bool
    let critical: Bool
    let conditional: Bool
    let symbol: String

    var id: Int { sectionID }

    var label: String { Language.get(labelKey, alter: nil) }
    var desc: String { Language.get(descKey, alter: nil) }
}

struct HomeSectionStateItem: Identifiable, Hashable {
    let sectionID: Int
    let type: String
    var visible: Bool

    var id: Int { sectionID }
}

// MARK: - Catalog Definition

private let kHomeCatalog: [HomeSectionCatalogItem] = [
    HomeSectionCatalogItem(sectionID: 20, type: "PPHomeSectionPureLens", labelKey: "HomeControl_Section_PureLens_Label", descKey: "HomeControl_Section_PureLens_Description", defaultVisible: true, critical: false, conditional: false, symbol: "viewfinder.circle.fill"),
    HomeSectionCatalogItem(sectionID: 15, type: "PPHomeSectionPremiumSearch", labelKey: "HomeControl_Section_PremiumSearch_Label", descKey: "HomeControl_Section_PremiumSearch_Description", defaultVisible: true, critical: false, conditional: false, symbol: "magnifyingglass"),
    HomeSectionCatalogItem(sectionID: 17, type: "PPHomeSectionMarketplaceHero", labelKey: "HomeControl_Section_MarketplaceHero_Label", descKey: "HomeControl_Section_MarketplaceHero_Description", defaultVisible: false, critical: false, conditional: false, symbol: "bag.fill"),
    HomeSectionCatalogItem(sectionID: 16, type: "PPHomeSectionProviderCategoryNav", labelKey: "HomeControl_Section_ProviderCategoryNav_Label", descKey: "HomeControl_Section_ProviderCategoryNav_Description", defaultVisible: false, critical: false, conditional: false, symbol: "rectangle.grid.1x2.fill"),
    HomeSectionCatalogItem(sectionID: 0, type: "PPHomeSectionHero", labelKey: "HomeControl_Section_Hero_Label", descKey: "HomeControl_Section_Hero_Description", defaultVisible: true, critical: true, conditional: false, symbol: "photo.stack.fill"),
    HomeSectionCatalogItem(sectionID: 5, type: "PPHomeSectionMainKinds", labelKey: "HomeControl_Section_MainKinds_Label", descKey: "HomeControl_Section_MainKinds_Description", defaultVisible: true, critical: true, conditional: false, symbol: "pawprint.fill"),
    HomeSectionCatalogItem(sectionID: 9, type: "PPHomeSectionPremiumCare", labelKey: "HomeControl_Section_PremiumCare_Label", descKey: "HomeControl_Section_PremiumCare_Description", defaultVisible: true, critical: false, conditional: false, symbol: "cross.case.fill"),
    HomeSectionCatalogItem(sectionID: 1, type: "PPHomeSectionQuickActions", labelKey: "HomeControl_Section_QuickActions_Label", descKey: "HomeControl_Section_QuickActions_Description", defaultVisible: true, critical: false, conditional: false, symbol: "square.grid.3x3.fill"),
    HomeSectionCatalogItem(sectionID: 2, type: "PPHomeSectionCurrentOrders", labelKey: "HomeControl_Section_CurrentOrders_Label", descKey: "HomeControl_Section_CurrentOrders_Description", defaultVisible: true, critical: false, conditional: false, symbol: "truck.box.fill"),
    HomeSectionCatalogItem(sectionID: 7, type: "PPHomeSectionAccessories", labelKey: "HomeControl_Section_Accessories_Label", descKey: "HomeControl_Section_Accessories_Description", defaultVisible: true, critical: false, conditional: false, symbol: "shippingbox.fill"),
    HomeSectionCatalogItem(sectionID: 18, type: "PPHomeSectionSuggestionAds", labelKey: "HomeControl_Section_SuggestionAds_Label", descKey: "HomeControl_Section_SuggestionAds_Description", defaultVisible: true, critical: false, conditional: false, symbol: "megaphone.fill"),
    HomeSectionCatalogItem(sectionID: 19, type: "PPHomeSectionSuggestionAccessories", labelKey: "HomeControl_Section_SuggestionAccessories_Label", descKey: "HomeControl_Section_SuggestionAccessories_Description", defaultVisible: true, critical: false, conditional: false, symbol: "sparkle.magnifyingglass"),
    HomeSectionCatalogItem(sectionID: 6, type: "PPHomeSectionSuggestions", labelKey: "HomeControl_Section_Suggestions_Label", descKey: "HomeControl_Section_Suggestions_Description", defaultVisible: true, critical: false, conditional: false, symbol: "lightbulb.fill"),
    HomeSectionCatalogItem(sectionID: 4, type: "PPHomeSectionCarousel", labelKey: "HomeControl_Section_Carousel_Label", descKey: "HomeControl_Section_Carousel_Description", defaultVisible: true, critical: true, conditional: false, symbol: "play.rectangle.fill"),
    HomeSectionCatalogItem(sectionID: 10, type: "PPHomeSectionLastFood", labelKey: "HomeControl_Section_LastFood_Label", descKey: "HomeControl_Section_LastFood_Description", defaultVisible: true, critical: false, conditional: false, symbol: "takeoutbag.and.cup.and.straw.fill"),
    HomeSectionCatalogItem(sectionID: 12, type: "PPHomeSectionAdsNearBy", labelKey: "HomeControl_Section_AdsNearBy_Label", descKey: "HomeControl_Section_AdsNearBy_Description", defaultVisible: true, critical: false, conditional: false, symbol: "mappin.and.ellipse"),
    HomeSectionCatalogItem(sectionID: 11, type: "PPHomeSectionNearbyServices", labelKey: "HomeControl_Section_NearbyServices_Label", descKey: "HomeControl_Section_NearbyServices_Description", defaultVisible: true, critical: false, conditional: false, symbol: "cross.fill"),
    HomeSectionCatalogItem(sectionID: 13, type: "PPHomeSectionAdopt", labelKey: "HomeControl_Section_Adopt_Label", descKey: "HomeControl_Section_Adopt_Description", defaultVisible: true, critical: false, conditional: false, symbol: "heart.fill"),
    HomeSectionCatalogItem(sectionID: 14, type: "PPHomeSectionBuyAgain", labelKey: "HomeControl_Section_BuyAgain_Label", descKey: "HomeControl_Section_BuyAgain_Description", defaultVisible: true, critical: false, conditional: true, symbol: "arrow.triangle.2.circlepath"),
    HomeSectionCatalogItem(sectionID: 8, type: "PPHomeSectionPetProfile", labelKey: "HomeControl_Section_PetProfile_Label", descKey: "HomeControl_Section_PetProfile_Description", defaultVisible: true, critical: false, conditional: false, symbol: "person.crop.circle.badge.plus")
]

// MARK: - Global Home Settings Model

struct HomeGlobalSettings: Equatable {
    var titleViewMode: String = "location"
    var novaFloatingVisible: Bool = true
    var pureLensVisible: Bool = true
    var backgroundGlowsFaded: Bool = true
    var usedAccessoriesAllowed: Bool = false
    var reusableVideoEnabled: Bool = true
    var ultraCareActivated: Bool = true
    var useLegacyBar: Bool = false
    var universalCellsSwiftUI: Bool = true
}

// MARK: - Home Control ViewModel

@MainActor
final class AdminHomeControlViewModel: ObservableObject {
    @Published var sections: [HomeSectionStateItem] = []
    @Published var globalSettings = HomeGlobalSettings()
    @Published var searchText: String = ""
    @Published var isSettingsExpanded: Bool = false
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var isDirty: Bool = false

    private var savedSections: [HomeSectionStateItem] = []
    private var savedGlobalSettings = HomeGlobalSettings()
    private let configRef = Firestore.firestore().collection("AppConfigCol").document("HomeConfig")

    var enabledSectionsCount: Int {
        sections.filter { $0.visible }.count
    }

    var totalSectionsCount: Int {
        sections.count
    }

    var visibleSectionsInOrder: [HomeSectionCatalogItem] {
        sections.filter { $0.visible }.compactMap { item in
            kHomeCatalog.first(where: { $0.sectionID == item.sectionID })
        }
    }

    var filteredSections: [HomeSectionStateItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sections }
        return sections.filter { item in
            guard let meta = kHomeCatalog.first(where: { $0.sectionID == item.sectionID }) else { return false }
            return meta.label.lowercased().contains(query) ||
                   meta.desc.lowercased().contains(query) ||
                   meta.type.lowercased().contains(query)
        }
    }

    init() {
        resetToDefaultState()
    }

    func resetToDefaultState() {
        sections = kHomeCatalog.map { HomeSectionStateItem(sectionID: $0.sectionID, type: $0.type, visible: $0.defaultVisible) }
        globalSettings = HomeGlobalSettings()
    }

    func loadConfig() {
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
                    self.resetToDefaultState()
                    self.savedSections = self.sections
                    self.savedGlobalSettings = self.globalSettings
                    self.isDirty = false
                    return
                }

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

    func markDirty() {
        isDirty = (sections != savedSections) || (globalSettings != savedGlobalSettings)
    }

    func toggleVisibility(for sectionID: Int) {
        if let idx = sections.firstIndex(where: { $0.sectionID == sectionID }) {
            sections[idx].visible.toggle()
            markDirty()
        }
    }

    func moveSections(fromOffsets source: IndexSet, toOffset destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
        markDirty()
    }

    func resetToDefaults() {
        resetToDefaultState()
        markDirty()
    }

    func revertChanges() {
        sections = savedSections
        globalSettings = savedGlobalSettings
        isDirty = false
    }

    func save(completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
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
            "BBUniversalCellUseSwiftUI": globalSettings.universalCellsSwiftUI,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        configRef.setData(payload, merge: true) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSaving = false
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    self.savedSections = self.sections
                    self.savedGlobalSettings = self.globalSettings
                    self.isDirty = false
                    self.writeAuditLog()
                    completion(true, Language.get("HomeControl_Saved", alter: nil))
                }
            }
        }
    }

    private func writeAuditLog() {
        let uid = Auth.auth().currentUser?.uid ?? ""
        Firestore.firestore().collection("AdminAuditLogs").document().setData([
            "action": "update_home_config",
            "targetCollection": "AppConfigCol",
            "targetId": "HomeConfig",
            "adminUid": uid,
            "timestamp": FieldValue.serverTimestamp()
        ])
    }

    func metaFor(sectionID: Int) -> HomeSectionCatalogItem? {
        kHomeCatalog.first(where: { $0.sectionID == sectionID })
    }
}

// MARK: - Sovereign Top Deck (Command Background & Tactile Control)

@MainActor
struct PPSovereignHomeControlDeck: View {
    @ObservedObject var viewModel: AdminHomeControlViewModel
    let onSave: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beaconPulse: Bool = false

    private var isPad: Bool {
        horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        ZStack {
            // Tier 1: Living Multi-Layered Atmospheric Substrate
            deckAtmosphericBackground

            // Tier 2: Specular Chamfer Light Edge & State Sheen
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.75),
                            Color.white.opacity(0.20),
                            (viewModel.isDirty ? AdminSurface.amber : AdminSurface.primary).opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )

            // Tier 3: Inner Sovereign Chambers (Adaptive iPad vs iPhone)
            Group {
                if isPad {
                    iPadCockpitLayout
                } else {
                    iPhoneCompactLayout
                }
            }
            .padding(AdminSpacing.cardPadding + 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 4)
        .shadow(
            color: (viewModel.isDirty ? AdminSurface.amber : AdminSurface.primary).opacity(viewModel.isDirty ? 0.09 : 0.02),
            radius: 8,
            x: 0,
            y: 2
        )
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    beaconPulse = true
                }
            }
        }
    }

    // MARK: - Background Atmosphere

    private var deckAtmosphericBackground: some View {
        ZStack {
            // Base Surface Material
            AdminSurface.surface

            // Frosted Micro-Material
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.85))

            // Ambient Radiant Glow Mesh
            GeometryReader { geo in
                // Dynamic Aurora Bloom
                RadialGradient(
                    colors: [
                        (viewModel.isDirty ? AdminSurface.amber : AdminSurface.primary).opacity(viewModel.isDirty ? 0.12 : 0.08),
                        (viewModel.isDirty ? AdminSurface.amber.opacity(0.04) : AdminSurface.primarySoft.opacity(0.03)),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: geo.size.width * 0.75
                )

                // Secondary Warm Specular Reflection
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.25), location: 0.0),
                        .init(color: Color.white.opacity(0.05), location: 0.35),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneCompactLayout: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            // Zone 1: Identity Pod & Emblem
            HStack(alignment: .top, spacing: AdminSpacing.md) {
                // Typographic Identity & Live State Beacon
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(Language.get("HomeControl_Title", alter: "التحكم في الصفحة الرئيسية"))
                            .font(AdminType.title2)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)

                        liveStatusBadge
                    }

                    Text(Language.get("HomeControl_Subtitle", alter: "التحكم في أقسام الصفحة الرئيسية والرؤية وتبديل الميزات"))
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Sovereign Tactile Emblem Squircle
                tactileEmblemSquircle
            }

            // Zone 2: Telemetry Radar & Tactical Command Runway
            HStack(spacing: AdminSpacing.sm) {
                // Telemetry Capacity Meter
                telemetryMeterChip

                Spacer(minLength: 4)

                // Tactical Action Controls
                actionControlsCapsule
            }
        }
    }

    // MARK: - iPad Cockpit Layout

    private var iPadCockpitLayout: some View {
        HStack(alignment: .center, spacing: AdminSpacing.lg) {
            // Leading Identity & Status Pod
            HStack(alignment: .center, spacing: AdminSpacing.md) {
                tactileEmblemSquircle

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(Language.get("HomeControl_Title", alter: "التحكم في الصفحة الرئيسية"))
                            .font(AdminType.title)
                            .foregroundColor(AdminSurface.primaryText)

                        liveStatusBadge
                    }

                    Text(Language.get("HomeControl_Subtitle", alter: "التحكم في أقسام الصفحة الرئيسية والرؤية وتبديل الميزات"))
                        .font(AdminType.body)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing Cockpit Telemetry & Actions
            HStack(spacing: AdminSpacing.md) {
                telemetryMeterChip

                actionControlsCapsule
            }
        }
    }

    // MARK: - Subcomponents

    private var tactileEmblemSquircle: some View {
        ZStack {
            // Squircle Body with State Tint
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill((viewModel.isDirty ? AdminSurface.amber : AdminSurface.primary).opacity(0.12))
                .frame(width: 52, height: 52)

            // Specular Inner Border
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    (viewModel.isDirty ? AdminSurface.amber : AdminSurface.primary).opacity(0.25),
                    lineWidth: 0.8
                )
                .frame(width: 52, height: 52)

            // Icon Glyph
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(viewModel.isDirty ? AdminSurface.amber : AdminSurface.primary)
                .scaleEffect(viewModel.isDirty ? 1.05 : 1.0)
                .animation(reduceMotion ? nil : AdminAnimation.standard, value: viewModel.isDirty)
        }
        .accessibilityHidden(true)
    }

    private var liveStatusBadge: some View {
        HStack(spacing: 5) {
            ZStack {
                if !reduceMotion && beaconPulse {
                    Circle()
                        .stroke((viewModel.isDirty ? AdminSurface.amber : Color.green).opacity(0.4), lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                        .scaleEffect(1.4)
                }

                Circle()
                    .fill(viewModel.isDirty ? AdminSurface.amber : Color.green)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 14, height: 14)

            Text(viewModel.isDirty
                 ? Language.get("HomeControl_LiveStatus_Unsaved", alter: "تعديلات غير محفوظة")
                 : Language.get("HomeControl_LiveStatus_Synced", alter: "مباشر ومزامن"))
                .font(AdminType.caption2Bold)
                .foregroundColor(viewModel.isDirty ? AdminSurface.amber : Color.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((viewModel.isDirty ? AdminSurface.amber : Color.green).opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder((viewModel.isDirty ? AdminSurface.amber : Color.green).opacity(0.22), lineWidth: 0.75)
        )
    }

    private var telemetryMeterChip: some View {
        HStack(spacing: 7) {
            // Micro Circular Telemetry Gauge
            ZStack {
                Circle()
                    .stroke(AdminSurface.primary.opacity(0.15), lineWidth: 2.2)
                    .frame(width: 16, height: 16)

                let total = max(viewModel.totalSectionsCount, 1)
                let progress = Double(viewModel.enabledSectionsCount) / Double(total)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        AdminSurface.primary,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 16, height: 16)
            }

            let format = Language.get("HomeControl_EnabledCount_Format", alter: "%@ / %@ مفعّل")
            Text(String(format: format, "\(viewModel.enabledSectionsCount)", "\(viewModel.totalSectionsCount)"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AdminSurface.primary.opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(AdminSurface.primary.opacity(0.20), lineWidth: 0.75)
        )
    }

    private var actionControlsCapsule: some View {
        HStack(spacing: 8) {
            if viewModel.isDirty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(reduceMotion ? nil : AdminAnimation.standard) {
                        viewModel.revertChanges()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .bold))
                        Text(Language.get("HomeControl_Revert", alter: "تراجع"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(AdminSurface.control, in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSave()
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isSaving {
                        ProgressView().tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                    }

                    Text(Language.get("Save", alter: "حفظ"))
                        .font(AdminType.captionBold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 34)
                .background(
                    viewModel.isDirty ? AdminSurface.primary : AdminSurface.primary.opacity(0.55),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
                )
                .shadow(
                    color: viewModel.isDirty ? AdminSurface.primary.opacity(0.35) : Color.clear,
                    radius: 6,
                    x: 0,
                    y: 2
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSaving || viewModel.isLoading)
        }
    }
}

// MARK: - Precision Horizon Energy Separator

struct PPHomeControlEnergySeparator: View {
    let isDirty: Bool
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        VStack(spacing: 0) {
            // Micro-Chamber 1: Directional Occlusion Drop Shadow
            LinearGradient(
                colors: [
                    Color.black.opacity(0.04),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 6)

            // Micro-Chamber 2: Dual-Tone Luminous Hairline with Centered Architectural Gem
            ZStack {
                // Continuous Hairline with Reading-Flow Falloff
                GeometryReader { geo in
                    let isRTL = layoutDirection == .rightToLeft
                    let tint = isDirty ? AdminSurface.amber : AdminSurface.primary
                    LinearGradient(
                        stops: [
                            .init(color: tint.opacity(isRTL ? 0.35 : 0.08), location: 0.0),
                            .init(color: tint.opacity(0.45), location: 0.5),
                            .init(color: tint.opacity(isRTL ? 0.08 : 0.35), location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 0.85)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .frame(height: 18)

                // Micro-Chamber 3: Architectural Status Bridge Gem
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isDirty ? AdminSurface.amber : AdminSurface.primary)

                    Text(Language.get("HomeControl_LiveChannels", alter: "قنوات البث المباشر"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(AdminSurface.surface, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            (isDirty ? AdminSurface.amber : AdminSurface.primary).opacity(0.20),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
            }
        }
    }
}

// MARK: - Main Home Control View

@MainActor
struct AdminHomeControlView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminHomeControlViewModel()
    @State private var toastMessage: String? = nil
    @State private var isErrorToast = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        PPSovereignHomeControlDeck(
                            viewModel: viewModel,
                            onSave: { validateAndSave() }
                        )
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.top, AdminSpacing.xs)

                        PPHomeControlEnergySeparator(isDirty: viewModel.isDirty)
                            .padding(.horizontal, AdminSpacing.screenMargin)
                            .padding(.top, 14)
                            .padding(.bottom, 16)

                        VStack(spacing: AdminSpacing.sectionSpacing) {
                            topSearchField
                            generalSettingsAccordion
                            sectionsOrderingCard
                            livePreviewCard
                        }
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.bottom, AdminSpacing.xxl)
                    }
                }
                .refreshable {
                    viewModel.loadConfig()
                }
            }

            if let message = toastMessage {
                VStack {
                    Spacer()
                    toastBanner(message: message, isError: isErrorToast)
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

    // MARK: - Sovereign Navigation Bar

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            AdminSovereignNavigationBar(
                title: Language.get("HomeControl_Title", alter: "التحكم في الشاشة الرئيسية"),
                subtitle: Language.get("CommandCenter_Operations_Workspace", alter: "مساحة العمليات"),
                onBack: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
            ) {
                HStack(spacing: 8) {
                    if viewModel.isDirty {
                        AdminPrimaryPillButton(
                            title: Language.get("Save", alter: "حفظ"),
                            systemImage: "checkmark",
                            isLoading: viewModel.isSaving
                        ) {
                            viewModel.save { success, msg in
                                if success {
                                    showToast(msg ?? "", isError: false)
                                } else {
                                    showToast(msg ?? "", isError: true)
                                }
                            }
                        }
                    }

                    if viewModel.isLoading || viewModel.isSaving {
                        ProgressView().tint(AdminSurface.primary)
                    } else {
                        Button(action: { viewModel.loadConfig() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AdminSurface.primaryText)
                                .frame(width: 44, height: 44)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                                )
                                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                    }
                }
            }

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) { viewModel.loadConfig() }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Search Field

    private var topSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AdminSurface.secondaryText)
                .font(.system(size: 16, weight: .medium))

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
                .frame(minWidth: AdminTouchTarget.minimum, minHeight: AdminTouchTarget.minimum)
                .accessibilityLabel(Language.get("Clear", alter: nil))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - General Settings Accordion

    private var generalSettingsAccordion: some View {
        AdminCard {
            VStack(spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.isSettingsExpanded.toggle()
                    }
                } label: {
                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "gearshape.2.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AdminSurface.primary)
                            Text(Language.get("HomeControl_GlobalSettings", alter: "الإعدادات العامة"))
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)
                        }

                        Spacer()

                        Image(systemName: viewModel.isSettingsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(AdminSpacing.cardPadding)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if viewModel.isSettingsExpanded {
                    Divider().padding(.horizontal, AdminSpacing.cardPadding)

                    VStack(spacing: 16) {
                        // Title View Mode Picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Language.get("HomeControl_TitleViewMode", alter: "وضع عرض العنوان"))
                                .font(AdminType.caption1)
                                .foregroundColor(AdminSurface.secondaryText)

                            Picker(Language.get("HomeControl_TitleViewMode", alter: nil), selection: $viewModel.globalSettings.titleViewMode) {
                                Text(Language.get("HomeControl_TitleViewLocation", alter: "الموقع")).tag("location")
                                Text(Language.get("HomeControl_TitleViewSearch", alter: "البحث")).tag("search")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.globalSettings.titleViewMode) { _ in
                                viewModel.markDirty()
                            }
                        }

                        Divider()

                        // Global Feature Toggles
                        featureToggleRow(titleKey: "HomeControl_NovaFloating", binding: $viewModel.globalSettings.novaFloatingVisible)
                        featureToggleRow(titleKey: "HomeControl_PureLens", binding: $viewModel.globalSettings.pureLensVisible)
                        featureToggleRow(titleKey: "HomeControl_BackgroundGlows", binding: $viewModel.globalSettings.backgroundGlowsFaded)
                        featureToggleRow(titleKey: "HomeControl_UsedAccessories", binding: $viewModel.globalSettings.usedAccessoriesAllowed)
                        featureToggleRow(titleKey: "HomeControl_ReusableVideo", binding: $viewModel.globalSettings.reusableVideoEnabled)
                        featureToggleRow(titleKey: "HomeControl_UltraCare", binding: $viewModel.globalSettings.ultraCareActivated)
                        featureToggleRow(titleKey: "HomeControl_LegacyBar", binding: $viewModel.globalSettings.useLegacyBar)
                        featureToggleRow(titleKey: "HomeControl_UniversalCells", binding: $viewModel.globalSettings.universalCellsSwiftUI)
                    }
                    .padding(AdminSpacing.cardPadding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func featureToggleRow(titleKey: String, binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Text(Language.get(titleKey, alter: nil))
                .font(AdminType.body)
                .foregroundColor(AdminSurface.primaryText)
        }
        .tint(AdminSurface.primary)
        .onChange(of: binding.wrappedValue) { _ in
            viewModel.markDirty()
        }
    }

    // MARK: - Section Ordering & Visibility Card

    private var sectionsOrderingCard: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack {
                Text(Language.get("HomeControl_SectionOrder", alter: "ترتيب الأقسام والرؤية"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                Button {
                    viewModel.resetToDefaults()
                } label: {
                    Text(Language.get("HomeControl_Defaults", alter: "الافتراضيات"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primary)
                }
            }
            .padding(.horizontal, 4)

            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView().tint(AdminSurface.primary)
                    Text(Language.get("Loading", alter: nil))
                        .font(AdminType.callout)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(spacing: AdminSpacing.sm) {
                    ForEach(Array(viewModel.filteredSections.enumerated()), id: \.element.sectionID) { index, item in
                        sectionRowCard(item: item, index: index)
                    }
                }
            }
        }
    }

    // MARK: - Section Row Card

    private func sectionRowCard(item: HomeSectionStateItem, index: Int) -> some View {
        let meta = viewModel.metaFor(sectionID: item.sectionID)
        let isCritical = meta?.critical ?? false
        let isConditional = meta?.conditional ?? false
        let isVisible = item.visible

        return AdminCard {
            HStack(spacing: 12) {
                // Drag Reorder Handle
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.60))
                    .frame(width: 24, height: 24)
                    .accessibilityLabel(Language.get("Reorder", alter: "إعادة ترتيب"))

                // Switch Toggle
                Toggle("", isOn: Binding(
                    get: { item.visible },
                    set: { _ in viewModel.toggleVisibility(for: item.sectionID) }
                ))
                .labelsHidden()
                .tint(AdminSurface.primary)

                // Info Section
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(meta?.label ?? "")
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)

                        // Status Badge
                        badgeForSection(critical: isCritical, conditional: isConditional, visible: isVisible)
                    }

                    Text(meta?.desc ?? "")
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Trailing Symbol Tile
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(badgeTint(critical: isCritical, conditional: isConditional, visible: isVisible).opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: isCritical ? "exclamationmark.shield.fill" : (meta?.symbol ?? "rectangle.stack.fill"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(badgeTint(critical: isCritical, conditional: isConditional, visible: isVisible))
                }
                .accessibilityHidden(true)
            }
            .padding(14)
        }
    }

    private func badgeForSection(critical: Bool, conditional: Bool, visible: Bool) -> some View {
        let title: String
        let tint: Color

        if critical {
            title = Language.get("HomeControl_Critical", alter: "أساسي")
            tint = Color(uiColor: .ppWarning)
        } else if conditional {
            title = Language.get("HomeControl_Conditional", alter: "مشروط")
            tint = Color(uiColor: .ppInfo)
        } else if visible {
            title = Language.get("HomeControl_Visible", alter: "ظاهر")
            tint = AdminSurface.primary
        } else {
            title = Language.get("HomeControl_Hidden", alter: "مخفي")
            tint = AdminSurface.secondaryText
        }

        return Text(title)
            .font(AdminType.caption2Bold)
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10), in: Capsule())
    }

    private func badgeTint(critical: Bool, conditional: Bool, visible: Bool) -> Color {
        if critical { return Color(uiColor: .ppWarning) }
        if conditional { return Color(uiColor: .ppInfo) }
        if visible { return AdminSurface.primary }
        return AdminSurface.secondaryText
    }

    // MARK: - Live Preview Card

    private var livePreviewCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill")
                        .foregroundColor(AdminSurface.primary)
                    Text(Language.get("HomeControl_LivePreview", alter: "معاينة مباشرة"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                }

                Text(Language.get("HomeControl_LivePreview_Subtitle", alter: "ستعرض الصفحة الرئيسية للعميل الأقسام الظاهرة بهذا الترتيب."))
                    .font(AdminType.footnote)
                    .foregroundColor(AdminSurface.secondaryText)

                let visibleSections = viewModel.visibleSectionsInOrder

                if visibleSections.isEmpty {
                    Text(Language.get("HomeControl_NoVisibleSections", alter: "لا توجد أقسام ظاهرة."))
                        .font(AdminType.subheadline)
                        .foregroundColor(.red)
                        .padding(.vertical, 8)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(visibleSections.enumerated()), id: \.element.sectionID) { idx, section in
                            HStack(spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(AdminType.captionBold)
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(AdminSurface.primary, in: Circle())

                                Image(systemName: section.symbol)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AdminSurface.primary)
                                    .frame(width: 20)

                                Text(section.label)
                                    .font(AdminType.subheadlineBold)
                                    .foregroundColor(AdminSurface.primaryText)

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(AdminSpacing.cardPadding)
        }
    }

    // MARK: - Save Validation

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

    private func toastBanner(message: String, isError: Bool) -> some View {
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
                .stroke(isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3))
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    // MARK: - Save Warning Confirmations (PPAlertHelper)

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