//
//  PPAddBannerEditorView.swift
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 02/09/2026.
//  First-Principles Category-Defining Banner Creative Studio & Campaign Command Center.
//

import SwiftUI
import PhotosUI
import Firebase
import FirebaseAuth
import FirebaseStorage

// MARK: - Brand Gradient Presets

public struct PPBannerBrandGradient: Identifiable, Sendable {
    public let id: Int
    public let nameAr: String
    public let nameEn: String
    public let colors: [Color]

    public static let presets: [PPBannerBrandGradient] = [
        PPBannerBrandGradient(
            id: 0,
            nameAr: "زمردي ملكي",
            nameEn: "Royal Emerald",
            colors: [Color(red: 0.05, green: 0.42, blue: 0.32), Color(red: 0.02, green: 0.24, blue: 0.18)]
        ),
        PPBannerBrandGradient(
            id: 1,
            nameAr: "كهرمان الغروب",
            nameEn: "Sunset Amber",
            colors: [Color(red: 0.95, green: 0.52, blue: 0.12), Color(red: 0.82, green: 0.26, blue: 0.08)]
        ),
        PPBannerBrandGradient(
            id: 2,
            nameAr: "نيلي ليلي",
            nameEn: "Midnight Indigo",
            colors: [Color(red: 0.12, green: 0.18, blue: 0.42), Color(red: 0.05, green: 0.08, blue: 0.22)]
        ),
        PPBannerBrandGradient(
            id: 3,
            nameAr: "وردي ياقوتي",
            nameEn: "Rose Quartz",
            colors: [Color(red: 0.88, green: 0.28, blue: 0.48), Color(red: 0.58, green: 0.12, blue: 0.32)]
        ),
        PPBannerBrandGradient(
            id: 4,
            nameAr: "فخامة داكنة",
            nameEn: "Obsidian Velvet",
            colors: [Color(red: 0.14, green: 0.16, blue: 0.22), Color(red: 0.07, green: 0.08, blue: 0.11)]
        )
    ]
}

// MARK: - Spatial Stages

public enum PPBannerEditorStage: String, CaseIterable, Identifiable {
    case media
    case copywriting
    case action
    case groupSettings

    public var id: String { rawValue }

    public func localizedTitle(isGroupOnly: Bool) -> String {
        switch self {
        case .media:
            return Language.get("Stage_BannerMedia", alter: "الوسائط والمظهر")
        case .copywriting:
            return Language.get("Stage_BannerCopy", alter: "النصوص والمحتوى")
        case .action:
            return Language.get("Stage_BannerAction", alter: "الإجراء والجدولة")
        case .groupSettings:
            return Language.get("Stage_BannerGroup", alter: "المجموعة والظهور")
        }
    }

    public var iconName: String {
        switch self {
        case .media: return "photo.on.rectangle.angled"
        case .copywriting: return "character.book.closed"
        case .action: return "cursorarrow.rays"
        case .groupSettings: return "slider.horizontal.3"
        }
    }
}

// MARK: - View Model

@MainActor
public final class PPAddBannerEditorViewModel: ObservableObject {
    public let editMode: Int // PPEditMode: 0: NewGroup, 1: GroupAndBanner, 2: GroupOnly, 3: BannerOnly, 4: AddBannerToGroup
    public let originalGroup: MainBannerModel?
    public let originalBanner: PPBannerViewModel?
    public let onDismiss: @Sendable () -> Void

    // Content - English & Arabic
    @Published public var titleEn: String = ""
    @Published public var titleAr: String = ""
    @Published public var descEn: String = ""
    @Published public var descAr: String = ""
    @Published public var textStyle: PPBannerTextStyle = .white

    // On Tap Action
    @Published public var onTapAction: PPBannerOnTapAction = .viewAccessory
    @Published public var onTapValue: String = ""

    // Scheduling & Validity
    @Published public var postDate: Date = Date()
    @Published public var hasValidityDuration: Bool = false
    @Published public var validDays: Int = 0
    @Published public var validHours: Int = 0
    @Published public var validMins: Int = 0
    @Published public var expirationDate: Date? = nil

    // Media
    @Published public var sampleImage: UIImage? = nil
    @Published public var existingSampleImageURL: URL? = nil
    @Published public var bgImage: UIImage? = nil
    @Published public var existingBgImageURL: URL? = nil
    @Published public var selectedGradientPresetIndex: Int = 0 // default to preset 0 if no custom bg

    // Group Metadata
    @Published public var groupID: String = ""
    @Published public var groupVisible: Bool = true
    @Published public var groupHolder: PPBannerHolder = .mainView
    @Published public var groupPosition: PPBannerPosition = .top
    @Published public var groupTransaction: PPBannerTransaction = .scroll

    // Active Spatial Stage
    @Published public var activeStage: PPBannerEditorStage = .media

    // Digital Twin Live Preview Switch
    @Published public var previewInArabic: Bool = true

    // State & Feedback
    @Published public var isSubmitting: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showSuccessToast: Bool = false

    // Image Picker Triggers
    @Published public var showSamplePicker: Bool = false
    @Published public var showBgPicker: Bool = false

    public init(
        editMode: Int,
        group: MainBannerModel?,
        banner: PPBannerViewModel?,
        onDismiss: @escaping @Sendable () -> Void
    ) {
        self.editMode = editMode
        self.originalGroup = group
        self.originalBanner = banner
        self.onDismiss = onDismiss

        // Load existing Group
        if let g = group {
            self.groupID = g.bannerViewID ?? ""
            self.groupVisible = g.bannerViewVisible
            self.groupHolder = g.bannerViewHolder
            self.groupPosition = g.bannerViewPosition
            self.groupTransaction = g.bannerViewTransaction
        }

        // Load existing Banner
        if let b = banner {
            self.titleEn = b.titleTextEn ?? ""
            self.titleAr = b.titleTextAr ?? ""
            self.descEn = b.descTextEn ?? ""
            self.descAr = b.descTextAr ?? ""
            self.postDate = b.postDate ?? Date()
            self.textStyle = b.pannerTextStyle
            self.onTapAction = b.onTapAction
            self.onTapValue = b.onTapValue ?? ""
            self.existingSampleImageURL = b.sampleImageURL
            self.existingBgImageURL = b.backgroundImageURL
            self.expirationDate = b.expirationDate

            if let duration = b.validityDuration {
                self.validDays = duration.day ?? 0
                self.validHours = duration.hour ?? 0
                self.validMins = duration.minute ?? 0
                self.hasValidityDuration = (validDays > 0 || validHours > 0 || validMins > 0)
            }
        }

        // Set initial stage based on mode
        if editMode == 2 { // PPEditModeGroupOnly
            self.activeStage = .groupSettings
        } else {
            self.activeStage = .media
        }
    }

    public var isGroupOnly: Bool {
        return editMode == 2
    }

    public var allowsGroupSettings: Bool {
        return editMode != 3 // Not BannerOnly
    }

    public var availableStages: [PPBannerEditorStage] {
        if isGroupOnly {
            return [.groupSettings]
        }
        var stages: [PPBannerEditorStage] = [.media, .copywriting, .action]
        if allowsGroupSettings {
            stages.append(.groupSettings)
        }
        return stages
    }

    // Dynamic Title Readout
    public var navTitle: String {
        switch editMode {
        case 2:
            return Language.get("EditBannerGroup", alter: "تعديل إعدادات المجموعة")
        case 3:
            return Language.get("EditBanner", alter: "تعديل البنر التسويقي")
        case 4:
            return Language.get("AddBannerToGroup", alter: "إضافة بنر إلى المجموعة")
        default:
            return Language.get("CreateNewBanner", alter: "تصميم بنر جديد")
        }
    }

    // Dynamic Status Pill
    public var statusBadgeText: String {
        if isGroupOnly {
            return groupVisible ? "● " + Language.get("GroupActive", alter: "المجموعة معروضة") : "○ " + Language.get("GroupHidden", alter: "المجموعة مخفية")
        }
        return "● " + Language.get("LiveTwinPreview", alter: "معاينة حية متزامنة")
    }

    // Missing Requirement Radar
    public var missingRequirementHint: String? {
        if !isGroupOnly {
            if titleAr.trimmingCharacters(in: .whitespaces).isEmpty && titleEn.trimmingCharacters(in: .whitespaces).isEmpty {
                return Language.get("BannerTitleRequiredHint", alter: "أدخل عنوان البنر (عربي أو إنجليزي) للاعتماد")
            }
        }
        if allowsGroupSettings && groupID.trimmingCharacters(in: .whitespaces).isEmpty && editMode == 0 {
            return Language.get("BannerGroupIDHint", alter: "حدد معرّف المجموعة أو سيتم إنشاؤه تلقائياً")
        }
        return nil
    }

    public var canSave: Bool {
        if isGroupOnly { return true }
        return !titleAr.trimmingCharacters(in: .whitespaces).isEmpty || !titleEn.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Live Expiration Calculation
    public var computedExpirationString: String? {
        guard hasValidityDuration else { return nil }
        let calendar = Calendar.current
        var components = DateComponents()
        components.day = validDays
        components.hour = validHours
        components.minute = validMins

        if let expire = calendar.date(byAdding: components, to: postDate) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
            return formatter.string(from: expire)
        }
        return nil
    }

    // MARK: - Save Action Flow

    public func saveBanner() {
        guard canSave else {
            errorMessage = Language.get("PleaseEnterBannerTitle", alter: "يرجى كتابة عنوان البنر قبل الحفظ")
            return
        }

        isSubmitting = true
        errorMessage = nil

        // Step 1: Upload Images to Firebase Storage if any picked
        uploadImagesIfNeeded { [weak self] bgURL, sampleURL, uploadError in
            guard let self = self else { return }
            if let err = uploadError {
                self.isSubmitting = false
                self.errorMessage = err.localizedDescription
                return
            }

            // Step 2: Assemble Models
            self.persistModels(bgURL: bgURL, sampleURL: sampleURL)
        }
    }

    private func uploadImagesIfNeeded(completion: @escaping (URL?, URL?, Error?) -> Void) {
        let needsBgUpload = (bgImage != nil)
        let needsSampleUpload = (sampleImage != nil)

        guard needsBgUpload || needsSampleUpload else {
            completion(existingBgImageURL, existingSampleImageURL, nil)
            return
        }

        let storage = Storage.storage().reference()
        let group = DispatchGroup()
        var finalBgURL: URL? = existingBgImageURL
        var finalSampleURL: URL? = existingSampleImageURL
        var firstError: Error? = nil

        if let bg = bgImage, let data = bg.pngData() {
            group.enter()
            let ref = storage.child("banners/bg/\(UUID().uuidString).png")
            let meta = StorageMetadata()
            meta.contentType = "image/png"
            ref.putData(data, metadata: meta) { _, err in
                if let err = err {
                    if firstError == nil { firstError = err }
                    group.leave()
                } else {
                    ref.downloadURL { url, uErr in
                        if let uErr = uErr, firstError == nil { firstError = uErr }
                        finalBgURL = url
                        group.leave()
                    }
                }
            }
        }

        if let sample = sampleImage, let data = sample.pngData() {
            group.enter()
            let ref = storage.child("banners/sample/\(UUID().uuidString).png")
            let meta = StorageMetadata()
            meta.contentType = "image/png"
            ref.putData(data, metadata: meta) { _, err in
                if let err = err {
                    if firstError == nil { firstError = err }
                    group.leave()
                } else {
                    ref.downloadURL { url, uErr in
                        if let uErr = uErr, firstError == nil { firstError = uErr }
                        finalSampleURL = url
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            completion(finalBgURL, finalSampleURL, firstError)
        }
    }

    private func persistModels(bgURL: URL?, sampleURL: URL?) {
        // Resolve or generate group
        let resolvedGroupID: String
        let trimmedGID = groupID.trimmingCharacters(in: .whitespaces)
        if !trimmedGID.isEmpty {
            resolvedGroupID = trimmedGID
        } else if let origID = originalGroup?.bannerViewID, !origID.isEmpty {
            resolvedGroupID = origID
        } else if groupHolder == .mainView && groupPosition == .top {
            resolvedGroupID = "HOME_MAIN_TOP_CAROUSEL"
        } else {
            resolvedGroupID = "GROUP_\(UUID().uuidString.prefix(8))"
        }

        let groupModel: MainBannerModel
        if let orig = originalGroup {
            groupModel = orig
        } else {
            groupModel = MainBannerModel()
        }

        groupModel.bannerViewID = resolvedGroupID
        groupModel.docID = originalGroup?.docID ?? resolvedGroupID
        if allowsGroupSettings {
            groupModel.bannerViewVisible = groupVisible
            groupModel.bannerViewHolder = groupHolder
            groupModel.bannerViewPosition = groupPosition
            groupModel.bannerViewTransaction = groupTransaction
        }

        // Group Only Mode
        if isGroupOnly {
            PPBannersManager.shared().updateBannerGroup(groupModel) { [weak self] error in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isSubmitting = false
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.showSuccessToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            self.onDismiss()
                        }
                    }
                }
            }
            return
        }

        // Build Child Banner
        let bannerID = originalBanner?.bannerID ?? "BANNER_\(UUID().uuidString.prefix(8))"
        let child = PPBannerViewModel(
            titleEn: titleEn,
            titleAr: titleAr,
            descTextEn: descEn,
            descTextAr: descAr,
            post: postDate,
            backgroundImageURL: bgURL,
            sampleImageURL: sampleURL,
            badgeImageURL: originalBanner?.badgeImageURL,
            onTapAction: onTapAction,
            textStyle: textStyle,
            onTapValue: onTapValue,
            bannerID: bannerID
        )

        if hasValidityDuration {
            let dc = DateComponents()
            var comp = dc
            comp.day = validDays
            comp.hour = validHours
            comp.minute = validMins
            child.validityDuration = comp

            if let exp = Calendar.current.date(byAdding: comp, to: postDate) {
                child.expirationDate = exp
            }
        } else {
            child.validityDuration = nil
            child.expirationDate = nil
        }

        if let orig = originalBanner {
            child.tapCount = orig.tapCount
        }

        // Save through PPBannersManager
        if editMode == 4 { // Add to existing group
            PPBannersManager.shared().addChildBanner(child, toGroup: groupModel.bannerViewID ?? groupModel.docID) { [weak self] error in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isSubmitting = false
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.showSuccessToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            self.onDismiss()
                        }
                    }
                }
            }
        } else {
            // Update group with child array
            var updatedChildren = (groupModel.childBanners as? [PPBannerViewModel]) ?? []
            if let orig = originalBanner {
                if let idx = updatedChildren.firstIndex(where: { $0.bannerID == orig.bannerID }) {
                    updatedChildren[idx] = child
                } else {
                    updatedChildren.append(child)
                }
            } else {
                updatedChildren.append(child)
            }
            groupModel.childBanners = updatedChildren

            PPBannersManager.shared().updateBannerGroup(groupModel) { [weak self] error in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isSubmitting = false
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.showSuccessToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            self.onDismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Screen View

public struct PPAddBannerEditorScreen: View {
    @StateObject public var viewModel: PPAddBannerEditorViewModel
    @Environment(\.layoutDirection) private var layoutDirection

    public init(viewModel: PPAddBannerEditorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Background Canvas
            AdminSurface.background
                .ignoresSafeArea()

            // Main Scrollable Stage Area
            ScrollView {
                VStack(spacing: 16) {
                    // Safe Area Offset for Sovereign Navigation Bar
                    Spacer().frame(height: 72)

                    // Error Banner if needed
                    if let err = viewModel.errorMessage {
                        AdminErrorBanner(message: err) {
                            viewModel.errorMessage = nil
                        }
                        .padding(.horizontal, AdminSpacing.screenMargin)
                    }

                    // 1. Digital Twin Live Hologram (Consumer App Preview)
                    if !viewModel.isGroupOnly {
                        bannerDigitalTwinHologram
                            .padding(.horizontal, AdminSpacing.screenMargin)
                    }

                    // 2. Spatial Stage Radar Navigation
                    if viewModel.availableStages.count > 1 {
                        stageRadarDeck
                            .padding(.horizontal, AdminSpacing.screenMargin)
                    }

                    // 3. Stage Viewport
                    switch viewModel.activeStage {
                    case .media:
                        mediaCanvasStage
                            .padding(.horizontal, AdminSpacing.screenMargin)
                    case .copywriting:
                        copywritingStudioStage
                            .padding(.horizontal, AdminSpacing.screenMargin)
                    case .action:
                        actionHubScheduleStage
                            .padding(.horizontal, AdminSpacing.screenMargin)
                    case .groupSettings:
                        groupSettingsStage
                            .padding(.horizontal, AdminSpacing.screenMargin)
                    }

                    // Bottom clearance for floating save dock
                    Spacer().frame(height: 120)
                }
            }

            // Sovereign Glassmorphic Navigation Bar
            sovereignNavigationBar

            // Tactical Floating Save Dock
            VStack {
                Spacer()
                tacticalSaveDock
            }
        }
        .sheet(isPresented: $viewModel.showSamplePicker) {
            PPBannerImagePickerSheet { picked in
                viewModel.sampleImage = picked
            }
        }
        .sheet(isPresented: $viewModel.showBgPicker) {
            PPBannerImagePickerSheet { picked in
                viewModel.bgImage = picked
                viewModel.selectedGradientPresetIndex = -1 // custom photo used
            }
        }
    }

    // MARK: - Sovereign Glassmorphic Navigation Bar

    private var sovereignNavigationBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Back Button (Luxury Glass Squircle)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.onDismiss()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AdminSurface.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                            )
                        Image(systemName: Language.isRTL() ? "arrow.right" : "arrow.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                // Title & Status Stack
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.navTitle)
                        .font(AdminType.title3)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 6, height: 6)
                        Text(viewModel.statusBadgeText)
                            .font(AdminType.caption2)
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                    }
                }

                Spacer()

                // Top Bar Quick Save Trigger
                Button {
                    viewModel.saveBanner()
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isSubmitting {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .heavy))
                            Text(Language.get("Save", alter: "حفظ"))
                                .font(AdminType.calloutBold)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(AdminSurface.primary, in: Capsule())
                    .shadow(color: AdminSurface.primary.opacity(0.35), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSubmitting)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(
                Color.clear
                    .ignoresSafeArea(edges: .top)
            )
        }
    }

    // MARK: - Interactive Digital Twin Hologram

    private var bannerDigitalTwinHologram: some View {
        VStack(spacing: 10) {
            // Live Simulation Top Bar
            HStack {
                Label(Language.get("DigitalTwinBannerPreview", alter: "المعاينة الحية لمتجر التطبيقات"), systemImage: "sparkles.tv")
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)

                Spacer()

                // Language Flip Switch (AR vs EN)
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        viewModel.previewInArabic.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                        Text(viewModel.previewInArabic ? "العربية (RTL)" : "English (LTR)")
                            .font(AdminType.caption2Bold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    .foregroundStyle(AdminSurface.primary)
                }
                .buttonStyle(.plain)

                // Text Contrast Toggle
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        viewModel.textStyle = (viewModel.textStyle == .white) ? .black : .white
                    }
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(viewModel.textStyle == .white ? Color.white : Color.black)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Color.gray, lineWidth: 0.5))
                        Text(viewModel.textStyle == .white ? "أبيض" : "أسود")
                            .font(AdminType.caption2Bold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.control, in: Capsule())
                    .foregroundStyle(AdminSurface.primaryText)
                }
                .buttonStyle(.plain)
            }

            // The Rendered Banner Card (2.2:1 Flagship Ratio)
            ZStack {
                // Background Layer: Custom Image or Brand Gradient
                if let bg = viewModel.bgImage {
                    Image(uiImage: bg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let bgURL = viewModel.existingBgImageURL {
                    AdminRemoteImage(url: bgURL, contentMode: .fill) {
                        presetGradientView(viewModel.selectedGradientPresetIndex)
                    }
                } else {
                    presetGradientView(viewModel.selectedGradientPresetIndex)
                }

                // Ambient Shadow Overlay for Typographic Contrast
                LinearGradient(
                    colors: [
                        Color.black.opacity(viewModel.textStyle == .white ? 0.45 : 0.05),
                        Color.clear
                    ],
                    startPoint: viewModel.previewInArabic ? .trailing : .leading,
                    endPoint: viewModel.previewInArabic ? .leading : .trailing
                )

                // Content Composition
                HStack(alignment: .center, spacing: 14) {
                    if viewModel.previewInArabic {
                        // Text Left / Sample Right
                        bannerTextReadout
                        Spacer()
                        floatingSampleHero
                    } else {
                        // Text Left / Sample Right for LTR
                        bannerTextReadout
                        Spacer()
                        floatingSampleHero
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                // Top-Corner Placement / Countdown Badge
                VStack {
                    HStack {
                        if let exp = viewModel.computedExpirationString {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                    .font(.system(size: 9))
                                Text(exp)
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.85), in: Capsule())
                            .padding(8)
                        }

                        Spacer()

                        // Placement Tag Badge
                        Text(placementBadgeString)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                    }
                    Spacer()
                }
            }
            .frame(height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 7)
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
        )
    }

    private var bannerTextReadout: some View {
        let isWhite = viewModel.textStyle == .white
        let textColor = isWhite ? Color.white : Color.black
        let title = viewModel.previewInArabic
            ? (viewModel.titleAr.isEmpty ? Language.get("PreviewTitleArPlaceholder", alter: "عنوان البنر الترويجي") : viewModel.titleAr)
            : (viewModel.titleEn.isEmpty ? "Promotional Banner Title" : viewModel.titleEn)
        let desc = viewModel.previewInArabic
            ? (viewModel.descAr.isEmpty ? Language.get("PreviewDescArPlaceholder", alter: "وصف العرض المميز والخصومات") : viewModel.descAr)
            : (viewModel.descEn.isEmpty ? "Special discount and exclusive offer description" : viewModel.descEn)

        return VStack(alignment: viewModel.previewInArabic ? .trailing : .leading, spacing: 5) {
            Text(title)
                .font(AdminType.title3)
                .foregroundStyle(textColor)
                .lineLimit(2)
                .multilineTextAlignment(viewModel.previewInArabic ? .trailing : .leading)
                .shadow(color: isWhite ? Color.black.opacity(0.3) : Color.clear, radius: 2, x: 0, y: 1)

            Text(desc)
                .font(AdminType.caption1)
                .foregroundStyle(textColor.opacity(0.88))
                .lineLimit(2)
                .multilineTextAlignment(viewModel.previewInArabic ? .trailing : .leading)
                .shadow(color: isWhite ? Color.black.opacity(0.25) : Color.clear, radius: 2, x: 0, y: 1)

            // Action Pill Indicator
            HStack(spacing: 4) {
                Text(actionButtonPreviewText)
                    .font(.system(size: 11, weight: .bold))
                Image(systemName: viewModel.previewInArabic ? "chevron.left" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(isWhite ? .white : AdminSurface.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isWhite ? Color.white.opacity(0.25) : AdminSurface.primary.opacity(0.12), in: Capsule())
            .padding(.top, 4)
        }
        .frame(maxWidth: 190, alignment: viewModel.previewInArabic ? .trailing : .leading)
    }

    private var floatingSampleHero: some View {
        ZStack {
            if let sample = viewModel.sampleImage {
                Image(uiImage: sample)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 95, height: 95)
                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
            } else if let sampleURL = viewModel.existingSampleImageURL {
                AdminRemoteImage(url: sampleURL, contentMode: .fit, targetSize: CGSize(width: 95, height: 95)) {
                    samplePlaceholderIcon
                }
                .frame(width: 95, height: 95)
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
            } else {
                samplePlaceholderIcon
            }
        }
    }

    private var samplePlaceholderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .frame(width: 82, height: 82)
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 26))
                .foregroundStyle(Color.white.opacity(0.75))
        }
    }

    private func presetGradientView(_ index: Int) -> some View {
        let safeIndex = max(0, min(index, PPBannerBrandGradient.presets.count - 1))
        let gradient = PPBannerBrandGradient.presets[safeIndex]
        return LinearGradient(
            colors: gradient.colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var placementBadgeString: String {
        switch viewModel.groupHolder {
        case .mainView: return "الرئيسية"
        case .accessoriesView: return "المستلزمات"
        case .adsView: return "الإعلانات"
        case .foodView: return "الأغذية"
        case .vetsView: return "البيطرة"
        @unknown default: return ""
        }
    }

    private var actionButtonPreviewText: String {
        switch viewModel.onTapAction {
        case .viewAccessory: return "تسوق الآن"
        case .viewAd: return "عرض الإعلان"
        case .openUrl: return "زيارة الرابط"
        case .callPhoneNumber: return "اتصل بنا"
        case .whatsApp: return "واتساب"
        @unknown default: return ""
        }
    }

    // MARK: - Spatial Stage Radar Navigation

    private var stageRadarDeck: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.availableStages, id: \.id) { stage in
                let isActive = viewModel.activeStage == stage

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        viewModel.activeStage = stage
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: stage.iconName)
                            .font(.system(size: 13, weight: isActive ? .bold : .medium))

                        Text(stage.localizedTitle(isGroupOnly: viewModel.isGroupOnly))
                            .font(AdminType.caption1Bold)
                    }
                    .foregroundColor(isActive ? .white : AdminCommandInk.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(
                        isActive
                            ? AnyView(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AdminSurface.primary)
                                    .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, x: 0, y: 2)
                            )
                            : AnyView(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AdminSurface.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Stage 1: Media Canvas & Brand Gradients

    private var mediaCanvasStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section Header
            stageHeader(
                title: Language.get("MediaCanvasTitle", alter: "الأصول البصرية وصور البنر"),
                subtitle: Language.get("MediaCanvasSub", alter: "اختر صورة العرض المفرغة (Sample) وصورة أو تدرج الخلفية")
            )

            // Dual Image Vault
            HStack(spacing: 12) {
                // 1. Hero Sample Product Cutout Slot
                sampleCutoutSlot

                // 2. Backdrop Canvas Slot
                backdropCanvasSlot
            }

            // Brand Gradient Preset Carousel
            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("BrandGradientsTitle", alter: "تدرجات ألوان بيوريتس المعتمدة للبنرات"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(PPBannerBrandGradient.presets) { preset in
                            let isSelected = viewModel.selectedGradientPresetIndex == preset.id && viewModel.bgImage == nil && viewModel.existingBgImageURL == nil

                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    viewModel.selectedGradientPresetIndex = preset.id
                                    viewModel.bgImage = nil
                                    viewModel.existingBgImageURL = nil
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 60, height: 42)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(isSelected ? AdminSurface.primary : Color.white.opacity(0.2), lineWidth: isSelected ? 2.5 : 0.8)
                                        )
                                        .shadow(color: preset.colors.first?.opacity(0.3) ?? Color.clear, radius: 4, x: 0, y: 2)

                                    Text(Language.isRTL() ? preset.nameAr : preset.nameEn)
                                        .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                                        .foregroundStyle(isSelected ? AdminSurface.primary : AdminCommandInk.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.8)
        )
    }

    private var sampleCutoutSlot: some View {
        VStack(spacing: 8) {
            Text(Language.get("SampleImageSlot", alter: "صورة المنتج المفرغة"))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminSurface.primaryText)

            ZStack {
                if let sample = viewModel.sampleImage {
                    Image(uiImage: sample)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 90, height: 90)
                } else if let sampleURL = viewModel.existingSampleImageURL {
                    AdminRemoteImage(url: sampleURL, contentMode: .fit, targetSize: CGSize(width: 90, height: 90)) {
                        Image(systemName: "photo").font(.system(size: 28))
                    }
                    .frame(width: 90, height: 90)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "plus.viewfinder")
                            .font(.system(size: 26))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("UploadCutout", alter: "إضافة صورة مفرغة"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4]))
                    .foregroundColor(AdminSurface.primary.opacity(0.45))
            )
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.showSamplePicker = true
            }

            // Replace or Remove
            if viewModel.sampleImage != nil || viewModel.existingSampleImageURL != nil {
                HStack(spacing: 8) {
                    Button(Language.get("Change", alter: "تغيير")) {
                        viewModel.showSamplePicker = true
                    }
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)

                    Button(Language.get("Remove", alter: "حذف")) {
                        viewModel.sampleImage = nil
                        viewModel.existingSampleImageURL = nil
                    }
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color.red)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var backdropCanvasSlot: some View {
        VStack(spacing: 8) {
            Text(Language.get("BackdropImageSlot", alter: "صورة الخلفية الكاملة"))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminSurface.primaryText)

            ZStack {
                if let bg = viewModel.bgImage {
                    Image(uiImage: bg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if let bgURL = viewModel.existingBgImageURL {
                    AdminRemoteImage(url: bgURL, contentMode: .fill) {
                        Image(systemName: "photo").font(.system(size: 28))
                    }
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 26))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("UploadBackdrop", alter: "رفع صورة خلفية"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4]))
                    .foregroundColor(AdminSurface.primary.opacity(0.45))
            )
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.showBgPicker = true
            }

            // Replace or Remove
            if viewModel.bgImage != nil || viewModel.existingBgImageURL != nil {
                HStack(spacing: 8) {
                    Button(Language.get("Change", alter: "تغيير")) {
                        viewModel.showBgPicker = true
                    }
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)

                    Button(Language.get("Remove", alter: "استخدام التدرج")) {
                        viewModel.bgImage = nil
                        viewModel.existingBgImageURL = nil
                        viewModel.selectedGradientPresetIndex = 0
                    }
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color.red)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stage 2: Bilingual Copywriting Studio

    private var copywritingStudioStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            stageHeader(
                title: Language.get("CopywritingTitle", alter: "صياغة النصوص والحملة التسويقية"),
                subtitle: Language.get("CopywritingSub", alter: "النصوص بالعربية والإنجليزية مع ضبط التنسيق ونمط الألوان")
            )

            // Arabic Copywriting Deck (Primary)
            VStack(alignment: .leading, spacing: 10) {
                Label("اللغة العربية (الأساسية)", systemImage: "textformat.size.ar")
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("TitleArLabel", alter: "عنوان البنر (عربي)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    TextField(Language.get("TitleArPlaceholder", alter: "مثال: ترقبوا الجديد من بيوريتس"), text: $viewModel.titleAr)
                        .font(AdminType.callout)
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("DescArLabel", alter: "وصف البنر (عربي)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    TextEditor(text: $viewModel.descAr)
                        .frame(minHeight: 64)
                        .font(AdminType.callout)
                        .padding(8)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(14)
            .background(AdminSurface.control.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // English Copywriting Deck (Secondary)
            VStack(alignment: .leading, spacing: 10) {
                Label("English (Secondary Language)", systemImage: "textformat.size")
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("TitleEnLabel", alter: "Title (English)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    TextField("e.g. New Arrivals from PurePets", text: $viewModel.titleEn)
                        .font(AdminType.callout)
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .environment(\.layoutDirection, .leftToRight)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("DescEnLabel", alter: "Description (English)"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    TextEditor(text: $viewModel.descEn)
                        .frame(minHeight: 64)
                        .font(AdminType.callout)
                        .padding(8)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .padding(14)
            .background(AdminSurface.control.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Text Contrast Selector
            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("TextColorChoice", alter: "تباين لون خط البنر"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                HStack(spacing: 12) {
                    textColorChoicePill(
                        title: Language.get("TextColorWhite", alter: "أبيض ناصع (للخلفيات الداكنة)"),
                        style: .white,
                        circleColor: Color.white
                    )

                    textColorChoicePill(
                        title: Language.get("TextColorBlack", alter: "أسود داكن (للخلفيات الفاتحة)"),
                        style: .black,
                        circleColor: Color.black
                    )
                }
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.8)
        )
    }

    private func textColorChoicePill(title: String, style: PPBannerTextStyle, circleColor: Color) -> some View {
        let isSelected = viewModel.textStyle == style
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.textStyle = style
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(circleColor)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.gray, lineWidth: 1))
                Text(title)
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.primaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? AdminSurface.primary.opacity(0.12) : AdminSurface.control,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? AdminSurface.primary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stage 3: Action Hub & Temporal Schedule

    private var actionHubScheduleStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            stageHeader(
                title: Language.get("ActionAndScheduleTitle", alter: "إجراء النقر والجدولة الزمنية"),
                subtitle: Language.get("ActionAndScheduleSub", alter: "حدد الوجهة التفاعلية عند ضغط العميل وفترة صلاحية البنر")
            )

            // Action Selection Cards
            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("OnTapActionLabel", alter: "الإجراء عند النقر على البنر"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                VStack(spacing: 8) {
                    actionCard(
                        title: Language.get("ActionViewAccessory", alter: "عرض صنف / منتج من المتجر"),
                        action: .viewAccessory,
                        icon: "bag.fill",
                        placeholder: Language.get("AccessoryIDPlaceholder", alter: "أدخل معرّف الصنف أو المنتج")
                    )

                    actionCard(
                        title: Language.get("ActionViewAd", alter: "عرض إعلان مخصص"),
                        action: .viewAd,
                        icon: "megaphone.fill",
                        placeholder: Language.get("AdIDPlaceholder", alter: "أدخل معرّف الإعلان")
                    )

                    actionCard(
                        title: Language.get("ActionOpenURL", alter: "فتح رابط موقع خارجي"),
                        action: .openUrl,
                        icon: "safari.fill",
                        placeholder: "https://pure-pets.net"
                    )

                    actionCard(
                        title: Language.get("ActionCall", alter: "اتصال هاتفي مباشر"),
                        action: .callPhoneNumber,
                        icon: "phone.fill",
                        placeholder: "+974 5512 3456"
                    )

                    actionCard(
                        title: Language.get("ActionWhatsApp", alter: "محادثة فورية عبر واتساب"),
                        action: .whatsApp,
                        icon: "message.fill",
                        placeholder: "+974 5512 3456"
                    )
                }
            }

            Divider().padding(.vertical, 4)

            // Scheduling & Validity Engine
            VStack(alignment: .leading, spacing: 12) {
                Label(Language.get("SchedulingTitle", alter: "جدولة وصلاحية البنر الترويجي"), systemImage: "calendar.badge.clock")
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)

                // Publish Date
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("PublishDateLabel", alter: "تاريخ ووقت بدء النشر"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminCommandInk.secondary)
                    DatePicker("", selection: $viewModel.postDate)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Validity Duration Toggle
                Toggle(isOn: $viewModel.hasValidityDuration) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("AutoExpireToggle", alter: "تفعيل مدة انتهاء صلاحية تلقائية"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(Language.get("AutoExpireSub", alter: "يتم إخفاء البنر تلقائياً بعد انقضاء المهلة"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
                .tint(AdminSurface.primary)
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Validity Steppers
                if viewModel.hasValidityDuration {
                    HStack(spacing: 8) {
                        durationStepper(title: Language.get("Days", alter: "أيام"), value: $viewModel.validDays)
                        durationStepper(title: Language.get("Hours", alter: "ساعات"), value: $viewModel.validHours)
                        durationStepper(title: Language.get("Minutes", alter: "دقائق"), value: $viewModel.validMins)
                    }

                    if let expString = viewModel.computedExpirationString {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color(uiColor: .ppSuccess))
                            Text(Language.get("ComputedExpiration", alter: "موعد الإخفاء التلقائي: ") + expString)
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                        .padding(10)
                        .background(Color(uiColor: .ppSuccess).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.8)
        )
    }

    private func actionCard(title: String, action: PPBannerOnTapAction, icon: String, placeholder: String) -> some View {
        let isSelected = viewModel.onTapAction == action
        return VStack(spacing: 8) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewModel.onTapAction = action
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? AdminSurface.primary : AdminSurface.control)
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(isSelected ? .white : AdminSurface.primary)
                    }

                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                }
                .padding(12)
                .background(
                    isSelected ? AdminSurface.primary.opacity(0.08) : AdminSurface.control,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? AdminSurface.primary : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            // Inline Value Input when selected
            if isSelected {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 13))
                        .foregroundStyle(AdminSurface.primary)
                    TextField(placeholder, text: $viewModel.onTapValue)
                        .font(AdminType.callout)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func durationStepper(title: String, value: Binding<Int>) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
            HStack(spacing: 6) {
                Button {
                    if value.wrappedValue > 0 { value.wrappedValue -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(AdminSurface.surface, in: Circle())
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue)")
                    .font(AdminType.calloutBold)
                    .frame(minWidth: 26)

                Button {
                    value.wrappedValue += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(AdminSurface.surface, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(6)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stage 4: Group Settings (Placement, Position, Transition)

    private var groupSettingsStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            stageHeader(
                title: Language.get("GroupSettingsTitle", alter: "إعدادات المجموعة وموقع الظهور"),
                subtitle: Language.get("GroupSettingsSub", alter: "حدد القسم، موضع العرض، تأثير الحركة، وحالة العرض في التطبيق")
            )

            // Group ID
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("GroupIDLabel", alter: "معرّف المجموعة (Group ID)"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                TextField("HOME_MAIN_TOP_CAROUSEL", text: $viewModel.groupID)
                    .font(AdminType.callout)
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .environment(\.layoutDirection, .leftToRight)
            }

            // Visible Switch
            Toggle(isOn: $viewModel.groupVisible) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("GroupVisibleToggle", alter: "عرض المجموعة في التطبيق"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("GroupVisibleSub", alter: "إذا تم التعطيل، ستختفي المجموعة بجميع بنراتها مؤقتاً"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                }
            }
            .tint(AdminSurface.primary)
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Placement / Holder Deck
            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("PlacementHolderLabel", alter: "القسم الحاضن للبنر (Placement)"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                VStack(spacing: 6) {
                    placementRow(title: Language.get("HolderMain", alter: "الصفحة الرئيسية (Main Home)"), holder: .mainView, icon: "house.fill")
                    placementRow(title: Language.get("HolderAccessories", alter: "قسم المستلزمات (Accessories)"), holder: .accessoriesView, icon: "bag.fill")
                    placementRow(title: Language.get("HolderAds", alter: "قسم الإعلانات (Ads)"), holder: .adsView, icon: "megaphone.fill")
                    placementRow(title: Language.get("HolderFood", alter: "قسم الأغذية (Pet Food)"), holder: .foodView, icon: "fork.knife")
                    placementRow(title: Language.get("HolderVets", alter: "قسم العيادات البيطرية (Vets)"), holder: .vetsView, icon: "cross.case.fill")
                }
            }

            // Position (Top, Center, Bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("PositionLabel", alter: "الموضع في الصفحة (Position)"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                HStack(spacing: 8) {
                    positionPill(title: Language.get("PosTop", alter: "أعلى الصفحة"), pos: .top)
                    positionPill(title: Language.get("PosCenter", alter: "وسط الصفحة"), pos: .center)
                    positionPill(title: Language.get("PosBottom", alter: "أسفل الصفحة"), pos: .bottom)
                }
            }

            // Transition (Scroll, Fade, Replace)
            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("TransitionLabel", alter: "تأثير الانتقال الحركي (Animation)"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminCommandInk.secondary)

                HStack(spacing: 8) {
                    transitionPill(title: Language.get("TransScroll", alter: "تمرير (Scroll)"), trans: .scroll)
                    transitionPill(title: Language.get("TransFade", alter: "تلاشي (Fade)"), trans: .fade)
                    transitionPill(title: Language.get("TransReplace", alter: "استبدال"), trans: .replace)
                }
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.8)
        )
    }

    private func placementRow(title: String, holder: PPBannerHolder, icon: String) -> some View {
        let isSelected = viewModel.groupHolder == holder
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.groupHolder = holder
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? AdminSurface.primary : AdminCommandInk.secondary)
                Text(title)
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AdminSurface.primary)
                }
            }
            .padding(12)
            .background(
                isSelected ? AdminSurface.primary.opacity(0.08) : AdminSurface.control,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func positionPill(title: String, pos: PPBannerPosition) -> some View {
        let isSelected = viewModel.groupPosition == pos
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.groupPosition = pos
            }
        } label: {
            Text(title)
                .font(AdminType.caption1Bold)
                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    isSelected ? AdminSurface.primary : AdminSurface.control,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func transitionPill(title: String, trans: PPBannerTransaction) -> some View {
        let isSelected = viewModel.groupTransaction == trans
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.groupTransaction = trans
            }
        } label: {
            Text(title)
                .font(AdminType.caption1Bold)
                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    isSelected ? AdminSurface.primary : AdminSurface.control,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tactical Floating Save Dock

    private var tacticalSaveDock: some View {
        VStack(spacing: 6) {
            // Live Requirement Radar Hint
            if let hint = viewModel.missingRequirementHint {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(uiColor: .ppWarning))
                    Text(hint)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(uiColor: .ppWarning).opacity(0.14), in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            Button {
                viewModel.saveBanner()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 17, weight: .bold))
                        Text(Language.get("SaveAndPublishBanner", alter: "حفظ ونشر البنر الترويجي"))
                            .font(AdminType.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: AdminSurface.primary.opacity(0.35), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(BannerPressStyle())
            .disabled(viewModel.isSubmitting)
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    Divider().background(Color(uiColor: .ppSurfaceBorder).opacity(0.7))
                }
        )
    }

    // MARK: - Subviews & Helpers

    private func stageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
            Text(subtitle)
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.secondary)
        }
    }
}

// MARK: - Button Press Style

private struct BannerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Single Image Picker Sheet

private struct PPBannerImagePickerSheet: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PPBannerImagePickerSheet

        init(_ parent: PPBannerImagePickerSheet) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let first = results.first else { return }

            if first.itemProvider.canLoadObject(ofClass: UIImage.self) {
                first.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let img = object as? UIImage {
                        DispatchQueue.main.async {
                            self.parent.onPicked(img)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Objective-C Hosting Bridge

@objc @MainActor public final class PPAddBannerEditorHostingBridge: NSObject {
    @objc public static func makeViewController(
        editMode: NSInteger,
        group: MainBannerModel?,
        banner: PPBannerViewModel?,
        onDismiss: @escaping @Sendable () -> Void
    ) -> UIViewController {
        let viewModel = PPAddBannerEditorViewModel(
            editMode: editMode,
            group: group,
            banner: banner,
            onDismiss: onDismiss
        )
        let host = UIHostingController(rootView: PPAddBannerEditorScreen(viewModel: viewModel))
        host.view.backgroundColor = .clear
        return host
    }
}
