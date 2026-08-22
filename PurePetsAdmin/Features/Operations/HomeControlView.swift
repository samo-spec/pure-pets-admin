//
//  HomeControlView.swift
//  PurePetsAdmin
//
//  NextGen V6 Native SwiftUI Home Screen Control.
//  Preserves all Firestore AppConfigCol/HomeConfig contracts, legacy mirrors,
//  section ordering catalog, global settings toggles, and live layout preview.
//

import SwiftUI
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

        var payload: [String: Any] = [
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

// MARK: - Main Home Control View

@MainActor
struct AdminHomeControlView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminHomeControlViewModel()
    @State private var toastMessage: String? = nil
    @State private var isErrorToast = false
    @State private var showsAllHiddenWarning = false
    @State private var showsCoreHiddenWarning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AdminSpacing.sectionSpacing) {
                    dossierHeaderView
                    heroHeader
                    topSearchField
                    generalSettingsAccordion
                    sectionsOrderingCard
                    livePreviewCard
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, AdminSpacing.xs)
                .padding(.bottom, AdminSpacing.xxl)
            }
            .refreshable {
                viewModel.loadConfig()
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
        .alert(Language.get("HomeControl_AllSectionsHidden_Title", alter: nil), isPresented: $showsAllHiddenWarning) {
            Button(Language.get("HomeControl_Cancel", alter: nil), role: .cancel) {}
            Button(Language.get("HomeControl_Continue", alter: nil), role: .destructive) {
                commitSave()
            }
        } message: {
            Text(Language.get("HomeControl_AllSectionsHidden_Message", alter: nil))
        }
        .alert(Language.get("HomeControl_CoreSectionsHidden_Title", alter: nil), isPresented: $showsCoreHiddenWarning) {
            Button(Language.get("HomeControl_Cancel", alter: nil), role: .cancel) {}
            Button(Language.get("HomeControl_Continue", alter: nil), role: .destructive) {
                commitSave()
            }
        } message: {
            Text(Language.get("HomeControl_CoreSectionsHidden_Message", alter: nil))
        }
    }

    // MARK: - Dossier Header (PPAccessoryEditorView Pattern)

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack {
                Button(action: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(Language.get("Back", alter: "رجوع"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .frame(minHeight: 44)
                }

                Spacer()

                if viewModel.isLoading || viewModel.isSaving {
                    ProgressView().tint(AdminSurface.primary)
                } else {
                    Button(action: { viewModel.loadConfig() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AdminSurface.primary)
                            .frame(width: 36, height: 36)
                            .background(AdminSurface.primary.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                }
            }

            Text(Language.get("CommandCenter_Operations_Workspace", alter: "مساحة العمليات") + " / " + Language.get("HomeControl_Title", alter: "الرئيسية"))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(Language.get("HomeControl_Title", alter: "التحكم في الشاشة الرئيسية"))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) { viewModel.loadConfig() }
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(Language.get("HomeControl_Title", alter: nil))
                            .font(AdminType.title2)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("HomeControl_Subtitle", alter: nil))
                            .font(AdminType.subheadline)
                            .foregroundColor(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ZStack {
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(AdminSurface.primary)
                    }
                    .accessibilityHidden(true)
                }

                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        let format = Language.get("HomeControl_EnabledCount_Format", alter: "%@ / %@ enabled")
                        Text(String(format: format, "\(viewModel.enabledSectionsCount)", "\(viewModel.totalSectionsCount)"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AdminSurface.primary.opacity(0.08), in: Capsule())

                    Spacer()

                    actionButtonsBar
                }
            }
            .padding(AdminSpacing.cardPadding)
        }
    }

    // MARK: - Action Buttons Bar

    private var actionButtonsBar: some View {
        HStack(spacing: 8) {
            if viewModel.isDirty {
                Button {
                    viewModel.revertChanges()
                } label: {
                    Text(Language.get("HomeControl_Revert", alter: nil))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(AdminSurface.control, in: Capsule())
                }
            }

            Button {
                validateAndSave()
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(Language.get("Save", alter: nil))
                        .font(AdminType.captionBold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(viewModel.isDirty ? AdminSurface.primary : AdminSurface.primary.opacity(0.60), in: Capsule())
            }
            .disabled(viewModel.isSaving || viewModel.isLoading)
        }
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
            showsAllHiddenWarning = true
            return
        }

        let criticalSections = kHomeCatalog.filter { $0.critical }
        let hiddenCriticalCount = viewModel.sections.filter { item in
            guard let meta = viewModel.metaFor(sectionID: item.sectionID) else { return false }
            return meta.critical && !item.visible
        }.count

        if criticalSections.count > 0 && hiddenCriticalCount == criticalSections.count {
            showsCoreHiddenWarning = true
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
}