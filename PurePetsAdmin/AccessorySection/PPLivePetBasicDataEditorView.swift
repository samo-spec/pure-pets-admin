//
//  PPLivePetBasicDataEditorView.swift
//  Pure Pets Admin
//
//  Created for Pure Pets Platform.
//  Category-defining, sovereign live pet basic data editor.
//

import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Kingfisher

// MARK: - Editor Language Enum

private enum EditorLanguage: String, CaseIterable, Identifiable {
    case arabic = "ar"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arabic: return Language.get("Arabic", alter: "العربية")
        case .english: return Language.get("English", alter: "English")
        }
    }

    var flag: String {
        switch self {
        case .arabic: return "🇸🇦"
        case .english: return "🇬🇧"
        }
    }
}

// MARK: - Active Input Field Focus

private enum EditorField: Hashable {
    case arabicName
    case englishName
    case arabicDesc
    case englishDesc
}

// MARK: - Local Picked Specimen Image

private struct LocalSpecimenImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Main View

@available(iOS 16.0, *)
public struct PPLivePetBasicDataEditorView: View {
    // Parent references
    let item: PetAccessory
    let onSaved: ((PetAccessory) -> Void)?
    @Environment(\.dismiss) private var dismiss

    // MARK: - State: Specimen Imagery
    @State private var remoteImageURLs: [String] = []
    @State private var localImages: [LocalSpecimenImage] = []
    @State private var primaryImageIdentifier: String = "" // URL or UUID string
    @State private var showImagePicker: Bool = false
    @State private var activeImageIndex: Int = 0

    // MARK: - State: Bilingual Identity
    @State private var selectedLanguage: EditorLanguage = .arabic
    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var descAr: String = ""
    @State private var descEn: String = ""
    @FocusState private var activeField: EditorField?

    // MARK: - State: Taxonomy (Species & Breed)
    @State private var availableMainKinds: [MainKindsModel] = []
    @State private var selectedSpeciesID: Int = 0
    @State private var availableSubKinds: [SubKindModel] = []
    @State private var selectedSubKindID: Int = 0
    @State private var showBreedPickerSheet: Bool = false
    @State private var isLoadingKinds: Bool = false
    @State private var isLoadingSubKinds: Bool = false

    // MARK: - State: Symbiotic Care Ecosystem (Related Accessories)
    @State private var selectedRelatedAccessoryIDs: [String] = []
    @State private var loadedRelatedAccessories: [PetAccessory] = []
    @State private var isLoadingRelated: Bool = false
    @State private var showRelatedAccessoryPickerSheet: Bool = false

    // MARK: - State: Persistence & Execution
    @State private var isSaving: Bool = false
    @State private var saveProgressText: String = ""
    @State private var initialSnapshot: [String: Any] = [:]

    // Haptics
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    // MARK: - Init

    public init(item: PetAccessory, onSaved: ((PetAccessory) -> Void)? = nil) {
        self.item = item
        self.onSaved = onSaved
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Living Dark Canvas
                AdminSurface.background.ignoresSafeArea()

                // Dynamic Ambient Aura
                ambientAtmosphericAura

                // Scrollable Studio Canvas
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: AdminSpacing.xl) {
                            // Spacer for navigation bar
                            Color.clear.frame(height: 10)

                            // 1. Hero Specimen Stage (Photo Studio)
                            heroSpecimenStage
                                .id("section_photos")

                            // 2. Bilingual Identity Matrix (Name & Description)
                            bilingualIdentityMatrix
                                .id("section_identity")

                            // 3. Taxonomy & Lineage Studio (Species & Breed)
                            taxonomyLineageStudio
                                .id("section_taxonomy")

                            // 4. Symbiotic Care Ecosystem (Related Products)
                            symbioticCareEcosystem
                                .id("section_ecosystem")

                            // Bottom spacing for sticky dock
                            Color.clear.frame(height: 120)
                        }
                        .padding(.horizontal, AdminSpacing.md)
                        .padding(.top, AdminSpacing.sm)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: activeField) { field in
                        if let field {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    proxy.scrollTo(field, anchor: .center)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedLanguage) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            if let field = activeField {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    proxy.scrollTo(field, anchor: .center)
                                }
                            } else {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    proxy.scrollTo("section_identity", anchor: .center)
                                }
                            }
                        }
                    }
                }

                // Sticky Bottom Action Dock
                stickyActionDock
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    closeButton
                }
                ToolbarItem(placement: .principal) {
                    headerTitleView
                }
                ToolbarItem(placement: .topBarTrailing) {
                    quickSaveButton
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        impactFeedback.impactOccurred()
                        switchLanguage(to: selectedLanguage == .arabic ? .english : .arabic)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text(selectedLanguage == .arabic ? "English" : "العربية")
                        }
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primary)
                    }

                    Spacer()

                    Button(Language.get("Done", alter: "تم")) {
                        activeField = nil
                    }
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primary)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                PPImagePickerSheet(maxSelection: 8) { pickedImages in
                    for img in pickedImages {
                        let local = LocalSpecimenImage(image: img)
                        localImages.append(local)
                        if primaryImageIdentifier.isEmpty {
                            primaryImageIdentifier = local.id.uuidString
                        }
                    }
                }
            }
            .sheet(isPresented: $showBreedPickerSheet) {
                PPLivePetBreedPickerSheet(
                    subKinds: availableSubKinds,
                    selectedSubKindID: selectedSubKindID,
                    onSelect: { sub in
                        selectedSubKindID = sub.id
                        selectionFeedback.selectionChanged()
                    }
                )
            }
            .sheet(isPresented: $showRelatedAccessoryPickerSheet) {
                PPLivePetRelatedAccessoryPickerSheet(
                    currentItemId: item.accessoryID,
                    selectedIDs: selectedRelatedAccessoryIDs,
                    onSaveSelection: { updatedIDs in
                        selectedRelatedAccessoryIDs = updatedIDs
                        Task {
                            await loadHydratedRelatedAccessories()
                        }
                    }
                )
            }
            .task {
                setupInitialData()
                loadSpecies()
                await loadHydratedRelatedAccessories()
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    savingGlassOverlay
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: - Computed Properties & Diffs

    private var hasChanges: Bool {
        guard !initialSnapshot.isEmpty else { return false }
        if nameAr.trimmingCharacters(in: .whitespacesAndNewlines) != (initialSnapshot["name"] as? String ?? "") { return true }
        if nameEn.trimmingCharacters(in: .whitespacesAndNewlines) != (initialSnapshot["nameEn"] as? String ?? "") { return true }
        if descAr.trimmingCharacters(in: .whitespacesAndNewlines) != (initialSnapshot["desc"] as? String ?? "") { return true }
        if descEn.trimmingCharacters(in: .whitespacesAndNewlines) != (initialSnapshot["descEn"] as? String ?? "") { return true }
        if selectedSpeciesID != (initialSnapshot["petMainCategoryID"] as? Int ?? 0) { return true }
        if selectedSubKindID != (initialSnapshot["petSubCategoryID"] as? Int ?? 0) { return true }
        if !localImages.isEmpty { return true }
        if remoteImageURLs != (initialSnapshot["imageURLsArray"] as? [String] ?? []) { return true }
        if selectedRelatedAccessoryIDs.sorted() != (initialSnapshot["relatedAccessories"] as? [String] ?? []).sorted() { return true }
        return false
    }

    private var changeCount: Int {
        var count = 0
        if nameAr.trimmingCharacters(in: .whitespacesAndNewlines) != (initialSnapshot["name"] as? String ?? "") { count += 1 }
        if nameEn.trimmingCharacters(in: .whitespacesAndNewlines) != (initialSnapshot["nameEn"] as? String ?? "") { count += 1 }
        if descAr.trimmingCharacters(in: .whitespacesAndNewlines) != (initialSnapshot["desc"] as? String ?? "") { count += 1 }
        if descEn.trimmingCharacters(in: .whitespacesAndNewlines) != (initialSnapshot["descEn"] as? String ?? "") { count += 1 }
        if selectedSpeciesID != (initialSnapshot["petMainCategoryID"] as? Int ?? 0) { count += 1 }
        if selectedSubKindID != (initialSnapshot["petSubCategoryID"] as? Int ?? 0) { count += 1 }
        if !localImages.isEmpty { count += localImages.count }
        if remoteImageURLs != (initialSnapshot["imageURLsArray"] as? [String] ?? []) { count += 1 }
        if selectedRelatedAccessoryIDs.sorted() != (initialSnapshot["relatedAccessories"] as? [String] ?? []).sorted() { count += 1 }
        return count
    }

    // MARK: - Navigation Bar Items

    private var closeButton: some View {
        Button {
            impactFeedback.impactOccurred()
            if hasChanges {
                promptUnsavedChangesDiscard()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AdminSurface.primaryText)
                .padding(8)
                .background(AdminSurface.card.opacity(0.8), in: Circle())
                .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 0.5))
        }
    }

    private var headerTitleView: some View {
        VStack(spacing: 2) {
            Text(Language.get("LivePet_EditBasicData", alter: "تعديل البيانات الأساسية"))
                .font(Font.custom("Beiruti-Bold", size: 17))
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 4) {
                Circle()
                    .fill(hasChanges ? AdminSurface.amber : AdminSurface.emerald)
                    .frame(width: 6, height: 6)

                Text(hasChanges ? "\(changeCount) \(Language.get("ChangesPending", alter: "تعديلات غير محفوظة"))" : Language.get("Synced", alter: "متطابق مع السيرفر"))
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(hasChanges ? AdminSurface.amber : AdminSurface.secondaryText)
            }
        }
    }

    private var quickSaveButton: some View {
        Button {
            impactFeedback.impactOccurred()
            Task {
                await executeSave()
            }
        } label: {
            Text(Language.get("Save", alter: "حفظ"))
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(hasChanges ? Color.white : AdminSurface.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    hasChanges ? AdminSurface.primary : AdminSurface.card.opacity(0.6),
                    in: Capsule()
                )
                .shadow(color: hasChanges ? AdminSurface.primary.opacity(0.3) : Color.clear, radius: 6, y: 2)
        }
        .disabled(!hasChanges || isSaving)
    }

    // MARK: - Ambient Aura

    private var ambientAtmosphericAura: some View {
        VStack {
            RadialGradient(
                colors: [
                    AdminSurface.primary.opacity(0.12),
                    AdminSurface.amber.opacity(0.06),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 400
            )
            .frame(height: 380)
            .ignoresSafeArea()
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - 1. Hero Specimen Stage (Photo Studio)

    private var heroSpecimenStage: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            // Stage Header
            HStack {
                Label {
                    Text(Language.get("SpecimenGallery", alter: "معرض صور الكائن الحي"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                } icon: {
                    Image(systemName: "camera.aperture")
                        .foregroundStyle(AdminSurface.primary)
                }

                Spacer()

                let totalCount = remoteImageURLs.count + localImages.count
                Text("\(totalCount) \(Language.get("Photos", alter: "صور"))")
                    .font(Font.custom("Beiruti-Medium", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AdminSurface.control, in: Capsule())
            }

            // Primary Cover Viewport
            primaryCoverViewport

            // Multi-Angle Gallery Carousel
            galleryStripCarousel
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var primaryCoverViewport: some View {
        ZStack(alignment: .bottomLeading) {
            // Image Content
            if let local = localImages.first(where: { $0.id.uuidString == primaryImageIdentifier }) {
                Image(uiImage: local.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
            } else if let remoteURLString = remoteImageURLs.first(where: { $0 == primaryImageIdentifier }) ?? remoteImageURLs.first,
                      let url = URL(string: remoteURLString) {
                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 800, height: 800)) {
                    ZStack {
                        AdminSurface.control
                        ProgressView()
                            .tint(AdminSurface.primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipped()
            } else {
                // Empty State Placeholder
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(Language.get("AddPetPhotosPrompt", alter: "اضغط لإضافة صور لهذا الكائن الحي"))
                        .font(Font.custom("Beiruti-Medium", size: 14))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .background(AdminSurface.control)
                .onTapGesture {
                    showImagePicker = true
                }
            }

            // Gradient Shade Overlay
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 90)

            // Primary Cover Badge
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AdminSurface.amber)
                Text(Language.get("PrimaryCoverPhoto", alter: "الغلاف الرئيسي"))
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(AdminSurface.amber.opacity(0.6), lineWidth: 0.75))
            .padding(AdminSpacing.md)
        }
        .clipShape(RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.5)
        )
    }

    private var galleryStripCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AdminSpacing.sm) {
                // Add New Image Slot
                Button {
                    impactFeedback.impactOccurred()
                    showImagePicker = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("Add", alter: "إضافة"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .frame(width: 72, height: 72)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                            .stroke(AdminSurface.primary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    )
                }

                // Remote Gallery Images
                ForEach(remoteImageURLs, id: \.self) { urlString in
                    let isCover = (primaryImageIdentifier == urlString) || (primaryImageIdentifier.isEmpty && remoteImageURLs.first == urlString)
                    ZStack(alignment: .topTrailing) {
                        if let url = URL(string: urlString) {
                            AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 144, height: 144)) {
                                AdminSurface.control
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))
                        }

                        if isCover {
                            Circle()
                                .fill(AdminSurface.amber)
                                .frame(width: 16, height: 16)
                                .overlay(Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Color.black))
                                .padding(4)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                            .stroke(isCover ? AdminSurface.amber : AdminSurface.hairline, lineWidth: isCover ? 2 : 0.5)
                    )
                    .contextMenu {
                        Button {
                            primaryImageIdentifier = urlString
                            selectionFeedback.selectionChanged()
                        } label: {
                            Label(Language.get("SetAsCover", alter: "تعيين كغلاف رئيسي"), systemImage: "star")
                        }

                        Button(role: .destructive) {
                            promptDeleteRemoteImage(urlString)
                        } label: {
                            Label(Language.get("Delete", alter: "حذف الصورة"), systemImage: "trash")
                        }
                    }
                }

                // Local Picked Images
                ForEach(localImages) { local in
                    let isCover = (primaryImageIdentifier == local.id.uuidString)
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: local.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))

                        if isCover {
                            Circle()
                                .fill(AdminSurface.amber)
                                .frame(width: 16, height: 16)
                                .overlay(Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Color.black))
                                .padding(4)
                        } else {
                            Circle()
                                .fill(AdminSurface.primary)
                                .frame(width: 14, height: 14)
                                .overlay(Image(systemName: "arrow.up").font(.system(size: 7, weight: .bold)).foregroundStyle(Color.white))
                                .padding(4)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                            .stroke(isCover ? AdminSurface.amber : AdminSurface.primary.opacity(0.6), lineWidth: isCover ? 2 : 1)
                    )
                    .contextMenu {
                        Button {
                            primaryImageIdentifier = local.id.uuidString
                            selectionFeedback.selectionChanged()
                        } label: {
                            Label(Language.get("SetAsCover", alter: "تعيين كغلاف رئيسي"), systemImage: "star")
                        }

                        Button(role: .destructive) {
                            localImages.removeAll(where: { $0.id == local.id })
                            if primaryImageIdentifier == local.id.uuidString {
                                primaryImageIdentifier = remoteImageURLs.first ?? localImages.first?.id.uuidString ?? ""
                            }
                        } label: {
                            Label(Language.get("Delete", alter: "إلغاء الصورة"), systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func promptDeleteRemoteImage(_ urlString: String) {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("DeletePhotoTitle", alter: "حذف الصورة"),
            subtitle: Language.get("DeletePhotoMsg", alter: "هل أنت متأكد من رغبتك في إزالة هذه الصورة من المعرض؟"),
            confirmButton: Language.get("Delete", alter: "حذف"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "trash.fill"),
            confirmBlock: { _, confirmed in
                guard confirmed else { return }
                remoteImageURLs.removeAll(where: { $0 == urlString })
                if primaryImageIdentifier == urlString {
                    primaryImageIdentifier = remoteImageURLs.first ?? localImages.first?.id.uuidString ?? ""
                }
            },
            cancelBlock: nil
        )
    }

    // MARK: - 2. Bilingual Identity Matrix (Zero-Flicker Focus & Exact Alignment)

    private var bilingualIdentityMatrix: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            // Header & Language Capsule Toggle
            HStack {
                Label {
                    Text(Language.get("BilingualIdentity", alter: "البيانات وهوية الكائن الحي"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                } icon: {
                    Image(systemName: "character.book.closed")
                        .foregroundStyle(AdminSurface.primary)
                }

                Spacer()

                // Language Switcher Capsule with Zero-Flicker Focus Handoff
                HStack(spacing: 2) {
                    ForEach(EditorLanguage.allCases) { lang in
                        let isSel = (selectedLanguage == lang)
                        Button {
                            impactFeedback.impactOccurred()
                            switchLanguage(to: lang)
                        } label: {
                            HStack(spacing: 4) {
                                Text(lang.flag)
                                    .font(.system(size: 12))
                                Text(lang.title)
                                    .font(Font.custom("Beiruti-Bold", size: 13))
                            }
                            .foregroundStyle(isSel ? Color.white : AdminSurface.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                isSel ? AdminSurface.primary : Color.clear,
                                in: Capsule()
                            )
                        }
                    }
                }
                .padding(3)
                .background(AdminSurface.control, in: Capsule())
                .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.5))
            }

            // Specimen Name Input (Bilingual Dual-Surface)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(selectedLanguage == .arabic ? Language.get("NameArabicLabel", alter: "اسم الكائن الحي (بالعربية)") : Language.get("NameEnglishLabel", alter: "Live Pet Name (English)"))
                        .font(Font.custom("Beiruti-Medium", size: 14))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Spacer()

                    let currentText = (selectedLanguage == .arabic ? nameAr : nameEn)
                    Text("\(currentText.count)/80")
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(currentText.count > 80 ? AdminSurface.crimson : AdminSurface.secondaryText.opacity(0.7))
                }

                ZStack {
                    // Arabic Name Field (Aligned Right)
                    TextField(Language.get("EnterArabicName", alter: "مثال: زوج كروان هولندي أليف"), text: $nameAr)
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                        .focused($activeField, equals: .arabicName)
                        .environment(\.layoutDirection, .rightToLeft)
                        .multilineTextAlignment(.leading) // In RTL layout, leading is on the RIGHT
                        .padding(AdminSpacing.md)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                                .stroke(activeField == .arabicName ? AdminSurface.primary : AdminSurface.hairline, lineWidth: activeField == .arabicName ? 1.5 : 0.75)
                        )
                        .opacity(selectedLanguage == .arabic ? 1 : 0)
                        .allowsHitTesting(selectedLanguage == .arabic)
                        .zIndex(selectedLanguage == .arabic ? 1 : 0)
                        .accessibilityHidden(selectedLanguage != .arabic)
                        .id(EditorField.arabicName)

                    // English Name Field (Aligned Left)
                    TextField(Language.get("EnterEnglishName", alter: "e.g. Dutch Cockatiel Mated Pair"), text: $nameEn)
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                        .focused($activeField, equals: .englishName)
                        .environment(\.layoutDirection, .leftToRight)
                        .multilineTextAlignment(.leading) // In LTR layout, leading is on the LEFT
                        .padding(AdminSpacing.md)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                                .stroke(activeField == .englishName ? AdminSurface.primary : AdminSurface.hairline, lineWidth: activeField == .englishName ? 1.5 : 0.75)
                        )
                        .opacity(selectedLanguage == .english ? 1 : 0)
                        .allowsHitTesting(selectedLanguage == .english)
                        .zIndex(selectedLanguage == .english ? 1 : 0)
                        .accessibilityHidden(selectedLanguage != .english)
                        .id(EditorField.englishName)
                }
            }

            // Specimen Description Input (Bilingual Dual-Surface Multiline)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(selectedLanguage == .arabic ? Language.get("DescArabicLabel", alter: "الوصف والمواصفات (بالعربية)") : Language.get("DescEnglishLabel", alter: "Description & Specifications (English)"))
                        .font(Font.custom("Beiruti-Medium", size: 14))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Spacer()

                    let currentText = (selectedLanguage == .arabic ? descAr : descEn)
                    Text("\(currentText.count)/1000")
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(currentText.count > 1000 ? AdminSurface.crimson : AdminSurface.secondaryText.opacity(0.7))
                }

                ZStack {
                    // Arabic Description (Aligned Right)
                    ZStack(alignment: .topLeading) {
                        if descAr.isEmpty {
                            Text(Language.get("EnterArabicDescPrompt", alter: "اكتب وصفاً وافياً عن الحالة الصحية، التغذية، السلوك، وأي ملحقات مرفقة..."))
                                .font(Font.custom("Beiruti-Regular", size: 14))
                                .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, AdminSpacing.md)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $descAr)
                            .font(Font.custom("Beiruti-Regular", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                            .focused($activeField, equals: .arabicDesc)
                            .multilineTextAlignment(.leading) // In RTL, leading is on the RIGHT
                            .frame(minHeight: 110)
                            .padding(AdminSpacing.xs)
                            .scrollContentBackground(.hidden)
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(AdminSpacing.sm)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                            .stroke(activeField == .arabicDesc ? AdminSurface.primary : AdminSurface.hairline, lineWidth: activeField == .arabicDesc ? 1.5 : 0.75)
                    )
                    .opacity(selectedLanguage == .arabic ? 1 : 0)
                    .allowsHitTesting(selectedLanguage == .arabic)
                    .zIndex(selectedLanguage == .arabic ? 1 : 0)
                    .accessibilityHidden(selectedLanguage != .arabic)
                    .id(EditorField.arabicDesc)

                    // English Description (Aligned Left)
                    ZStack(alignment: .topLeading) {
                        if descEn.isEmpty {
                            Text(Language.get("EnterEnglishDescPrompt", alter: "Detailed description of health condition, diet, behavior, and any included accessories..."))
                                .font(Font.custom("Beiruti-Regular", size: 14))
                                .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, AdminSpacing.md)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $descEn)
                            .font(Font.custom("Beiruti-Regular", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                            .focused($activeField, equals: .englishDesc)
                            .multilineTextAlignment(.leading) // In LTR, leading is on the LEFT
                            .frame(minHeight: 110)
                            .padding(AdminSpacing.xs)
                            .scrollContentBackground(.hidden)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(AdminSpacing.sm)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                            .stroke(activeField == .englishDesc ? AdminSurface.primary : AdminSurface.hairline, lineWidth: activeField == .englishDesc ? 1.5 : 0.75)
                    )
                    .opacity(selectedLanguage == .english ? 1 : 0)
                    .allowsHitTesting(selectedLanguage == .english)
                    .zIndex(selectedLanguage == .english ? 1 : 0)
                    .accessibilityHidden(selectedLanguage != .english)
                    .id(EditorField.englishDesc)
                }
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    /// Zero-flicker language focus handoff: keeps the keyboard open smoothly
    private func switchLanguage(to newLang: EditorLanguage) {
        guard selectedLanguage != newLang else { return }
        let prevField = activeField
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            selectedLanguage = newLang
        }

        // Direct focus transfer without dropping to nil
        if prevField == .arabicName && newLang == .english {
            activeField = .englishName
        } else if prevField == .englishName && newLang == .arabic {
            activeField = .arabicName
        } else if prevField == .arabicDesc && newLang == .english {
            activeField = .englishDesc
        } else if prevField == .englishDesc && newLang == .arabic {
            activeField = .arabicDesc
        }
    }

    // MARK: - 3. Taxonomy & Lineage Studio (Species & Breed)

    private var taxonomyLineageStudio: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            // Header
            HStack {
                Label {
                    Text(Language.get("TaxonomyAndBreed", alter: "التصنيف والسلالة (الفصيلة والنوع)"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                } icon: {
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(AdminSurface.amber)
                }

                Spacer()

                if isLoadingKinds || isLoadingSubKinds {
                    ProgressView()
                        .tint(AdminSurface.primary)
                }
            }

            // Species Carousel (MainKinds)
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("SpeciesCategory", alter: "نوع الكائن الحي (الفصيلة الرئيسية)"))
                    .font(Font.custom("Beiruti-Medium", size: 14))
                    .foregroundStyle(AdminSurface.secondaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(availableMainKinds, id: \.id) { kind in
                            let isSel = (selectedSpeciesID == kind.id)
                            Button {
                                impactFeedback.impactOccurred()
                                selectSpecies(kind)
                            } label: {
                                VStack(spacing: 6) {
                                    if let urlString = kind.kindImageUrl, let url = URL(string: urlString) {
                                        AdminRemoteImage(url: url, contentMode: .fit, targetSize: CGSize(width: 80, height: 80)) {
                                            Circle().fill(AdminSurface.control)
                                        }
                                        .frame(width: 44, height: 44)
                                        .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(isSel ? AdminSurface.primary.opacity(0.2) : AdminSurface.control)
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Image(systemName: "pawprint")
                                                    .foregroundStyle(isSel ? AdminSurface.primary : AdminSurface.secondaryText)
                                            )
                                    }

                                    Text(Language.isRTL() ? kind.kindNameAr : (kind.kindNameEn.isEmpty ? kind.kindNameAr : kind.kindNameEn))
                                        .font(Font.custom(isSel ? "Beiruti-Bold" : "Beiruti-Medium", size: 13))
                                        .foregroundStyle(isSel ? AdminSurface.primaryText : AdminSurface.secondaryText)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    isSel ? AdminSurface.primary.opacity(0.12) : AdminSurface.control,
                                    in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                                        .stroke(isSel ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSel ? 1.5 : 0.5)
                                )
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Breed Selector Card (SubKinds)
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("SubKindBreedLabel", alter: "السلالة / النوع الفرعي"))
                    .font(Font.custom("Beiruti-Medium", size: 14))
                    .foregroundStyle(AdminSurface.secondaryText)

                Button {
                    impactFeedback.impactOccurred()
                    showBreedPickerSheet = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.amber.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: "seal.fill")
                                .foregroundStyle(AdminSurface.amber)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            let currentBreedName = currentSelectedBreedName
                            Text(currentBreedName.isEmpty ? Language.get("SelectBreedPlaceholder", alter: "اضغط لاختيار السلالة أو الفصيلة الفرعية") : currentBreedName)
                                .font(Font.custom("Beiruti-Bold", size: 15))
                                .foregroundStyle(currentBreedName.isEmpty ? AdminSurface.secondaryText : AdminSurface.primaryText)

                            Text(Language.get("BreedSelectorHint", alter: "تحديد السلالة يتيح للمشترين فلترة الكائنات بدقة"))
                                .font(Font.custom("Beiruti-Regular", size: 12))
                                .foregroundStyle(AdminSurface.secondaryText.opacity(0.8))
                        }

                        Spacer()

                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .padding(AdminSpacing.md)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 0.75)
                    )
                }
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var currentSelectedBreedName: String {
        if let sub = availableSubKinds.first(where: { $0.id == selectedSubKindID }) {
            return Language.isRTL() ? sub.subKindNameAr : (sub.subKindNameEn.isEmpty ? sub.subKindNameAr : sub.subKindNameEn)
        }
        return ""
    }

    private func selectSpecies(_ kind: MainKindsModel) {
        selectedSpeciesID = kind.id
        selectedSubKindID = 0
        fetchSubKindsForSpecies(kind)
    }

    // MARK: - 4. Symbiotic Care Ecosystem (Related Accessories)

    private var symbioticCareEcosystem: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            // Header
            HStack {
                Label {
                    Text(Language.get("RelatedCareEcosystem", alter: "المستلزمات والمنتجات المرتبطة"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                } icon: {
                    Image(systemName: "link.circle.fill")
                        .foregroundStyle(AdminSurface.primary)
                }

                Spacer()

                Button {
                    impactFeedback.impactOccurred()
                    showRelatedAccessoryPickerSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(Language.get("LinkAccessories", alter: "ربط منتجات"))
                    }
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                }
            }

            Text(Language.get("RelatedAccessoriesExplanation", alter: "اربط أطعمة وأقفاص وفيتامينات ومستلزمات رعاية متوافقة مع هذا الكائن الحي لتسهيل البيع المتقاطع."))
                .font(Font.custom("Beiruti-Regular", size: 13))
                .foregroundStyle(AdminSurface.secondaryText)

            if isLoadingRelated {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(AdminSurface.primary)
                    Spacer()
                }
                .padding(.vertical, AdminSpacing.md)
            } else if loadedRelatedAccessories.isEmpty {
                // Empty State
                VStack(spacing: 8) {
                    Image(systemName: "cart.badge.questionmark")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(Language.get("NoRelatedAccessoriesLinked", alter: "لا توجد مستلزمات مرتبطة بهذا الكائن حالياً"))
                        .font(Font.custom("Beiruti-Medium", size: 14))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AdminSpacing.lg)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            } else {
                // Linked Accessories Cards
                VStack(spacing: AdminSpacing.sm) {
                    ForEach(loadedRelatedAccessories, id: \.accessoryID) { accessory in
                        HStack(spacing: 12) {
                            // Thumbnail
                            if let firstImage = accessory.imageURLsArray.first, let url = URL(string: firstImage) {
                                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 96, height: 96)) {
                                    AdminSurface.control
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                                    .fill(AdminSurface.control)
                                    .frame(width: 48, height: 48)
                                    .overlay(Image(systemName: "bag").foregroundStyle(AdminSurface.secondaryText))
                            }

                            // Info
                            VStack(alignment: .leading, spacing: 2) {
                                Text(accessory.name)
                                    .font(Font.custom("Beiruti-Bold", size: 14))
                                    .foregroundStyle(AdminSurface.primaryText)
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    if accessory.price.doubleValue > 0 {
                                        Text("\(accessory.price.stringValue) QAR")
                                            .font(Font.custom("Beiruti-Medium", size: 12))
                                            .foregroundStyle(AdminSurface.emerald)
                                    }

                                    if let categoryName = accessory.category, !categoryName.isEmpty {
                                        Text("• \(categoryName)")
                                            .font(Font.custom("Beiruti-Regular", size: 12))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                    }
                                }
                            }

                            Spacer()

                            // Unlink Button
                            Button {
                                impactFeedback.impactOccurred()
                                unlinkAccessory(accessory.accessoryID)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                            }
                        }
                        .padding(AdminSpacing.sm)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    }
                }
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private func unlinkAccessory(_ id: String) {
        selectedRelatedAccessoryIDs.removeAll(where: { $0 == id })
        loadedRelatedAccessories.removeAll(where: { $0.accessoryID == id })
    }

    // MARK: - Sticky Bottom Action Dock

    private var stickyActionDock: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AdminSurface.hairline)

            HStack(spacing: 12) {
                // Change Indicator Pill
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasChanges ? "\(changeCount) \(Language.get("ChangesDetected", alter: "تعديلات جاهزة للحفظ"))" : Language.get("NoChangesMade", alter: "لا توجد تعديلات"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(hasChanges ? AdminSurface.amber : AdminSurface.secondaryText)

                    Text(Language.get("AuditRecordedOnSave", alter: "سيتم تدوين التغييرات في سجل التدقيق"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.7))
                }

                Spacer()

                // Primary Save Jewel
                Button {
                    impactFeedback.impactOccurred()
                    Task {
                        await executeSave()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(Language.get("SaveChanges", alter: "حفظ التعديلات"))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        hasChanges ? AdminSurface.primary : AdminSurface.card,
                        in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    )
                    .shadow(color: hasChanges ? AdminSurface.primary.opacity(0.35) : Color.clear, radius: 10, y: 4)
                }
                .disabled(!hasChanges || isSaving)
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.top, AdminSpacing.sm)
            .padding(.bottom, AdminSpacing.md)
            .background(
                .ultraThinMaterial,
                in: Rectangle()
            )
        }
    }

    // MARK: - Saving Glass Overlay

    private var savingGlassOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(AdminSurface.primary)
                    .scaleEffect(1.4)

                Text(saveProgressText.isEmpty ? Language.get("SavingChanges", alter: "جاري حفظ التعديلات...") : saveProgressText)
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(Color.white)
            }
            .padding(28)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 1)
            )
        }
    }

    // MARK: - Data Hydration & Initial Snapshot

    private func setupInitialData() {
        remoteImageURLs = item.imageURLsArray ?? []
        if let first = remoteImageURLs.first {
            primaryImageIdentifier = first
        }
        nameAr = item.name ?? ""
        nameEn = item.nameEn ?? ""
        descAr = item.desc ?? ""
        descEn = item.descEn ?? ""
        selectedSpeciesID = item.petMainCategoryID
        selectedSubKindID = item.petSubCategoryID
        selectedRelatedAccessoryIDs = item.relatedAccessories ?? []

        // Capture Initial Snapshot for Diffing
        initialSnapshot = [
            "name": nameAr,
            "nameEn": nameEn,
            "desc": descAr,
            "descEn": descEn,
            "petMainCategoryID": selectedSpeciesID,
            "petSubCategoryID": selectedSubKindID,
            "imageURLsArray": remoteImageURLs,
            "relatedAccessories": selectedRelatedAccessoryIDs
        ]
    }

    private func loadSpecies() {
        if let cached = AppManager.shared().mainKindsArray as? [MainKindsModel], !cached.isEmpty {
            self.availableMainKinds = cached
            if let initialMain = cached.first(where: { $0.id == selectedSpeciesID }) {
                fetchSubKindsForSpecies(initialMain)
            }
            return
        }

        isLoadingKinds = true
        Firestore.firestore().collection("MainKindsCollection").order(by: "sortingKey").getDocuments { snapshot, _ in
            DispatchQueue.main.async {
                self.isLoadingKinds = false
                guard let docs = snapshot?.documents else { return }
                var list: [MainKindsModel] = []
                for doc in docs {
                    list.append(MainKindsModel(snapshot: doc))
                }
                self.availableMainKinds = list
                AppManager.shared().mainKindsArray = NSMutableArray(array: list)
                if let initialMain = list.first(where: { $0.id == self.selectedSpeciesID }) {
                    self.fetchSubKindsForSpecies(initialMain)
                }
            }
        }
    }

    private func fetchSubKindsForSpecies(_ species: MainKindsModel) {
        let docID = species.documentID.isEmpty ? "\(species.id)" : species.documentID
        guard !docID.isEmpty else { return }

        isLoadingSubKinds = true
        Firestore.firestore().collection("MainKindsCollection").document(docID).collection("SubKinds").order(by: "ID").getDocuments { snapshot, _ in
            DispatchQueue.main.async {
                self.isLoadingSubKinds = false
                guard let docs = snapshot?.documents else { return }
                var items: [SubKindModel] = []
                for doc in docs {
                    let sub = SubKindModel(snapshot: doc)
                    sub.documentID = doc.documentID
                    items.append(sub)
                }
                self.availableSubKinds = items
            }
        }
    }

    private func loadHydratedRelatedAccessories() async {
        guard !selectedRelatedAccessoryIDs.isEmpty else {
            loadedRelatedAccessories = []
            return
        }

        isLoadingRelated = true
        let db = Firestore.firestore()
        var items: [PetAccessory] = []

        for id in selectedRelatedAccessoryIDs {
            do {
                let doc = try await db.collection("petAccessories").document(id).getDocument()
                if let data = doc.data() {
                    let accessory = PetAccessory(dictionary: data, documentID: doc.documentID)
                    items.append(accessory)
                }
            } catch {
                print("[PPLivePetBasicDataEditor] Error loading related accessory \(id): \(error)")
            }
        }

        DispatchQueue.main.async {
            self.loadedRelatedAccessories = items
            self.isLoadingRelated = false
        }
    }

    // MARK: - Photo Storage Upload Pipeline

    private func uploadSpecimenPhoto(data: Data, path: String, adminUid: String) async throws -> String {
        let storageRef = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = ["uploaded_by": adminUid]

        return try await withCheckedThrowingContinuation { continuation in
            storageRef.putData(data, metadata: metadata) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                storageRef.downloadURL { url, downloadError in
                    if let downloadError = downloadError {
                        continuation.resume(throwing: downloadError)
                    } else if let urlString = url?.absoluteString {
                        continuation.resume(returning: urlString)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "PPStorageError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to obtain uploaded image download URL"]
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Save Execution & Audit Ledger

    private func executeSave() async {
        guard hasChanges else { return }
        isSaving = true
        saveProgressText = Language.get("UploadingPhotosProgress", alter: "جاري رفع الصور الجديدة...")

        do {
            // 1. Upload Local Images to Firebase Storage
            var finalImageURLs = remoteImageURLs
            if !localImages.isEmpty {
                let adminUid = Auth.auth().currentUser?.uid ?? "system_admin"

                for (idx, local) in localImages.enumerated() {
                    saveProgressText = "\(Language.get("UploadingPhotoIndex", alter: "جاري رفع الصورة")) (\(idx + 1)/\(localImages.count))..."
                    guard let data = local.image.jpegData(compressionQuality: 0.82) else { continue }
                    let filename = "\(UUID().uuidString).jpg"
                    let path = "petAccessories/\(item.accessoryID)/\(filename)"
                    let urlString = try await uploadSpecimenPhoto(data: data, path: path, adminUid: adminUid)

                    if primaryImageIdentifier == local.id.uuidString {
                        // Promoted cover is this newly uploaded image
                        finalImageURLs.insert(urlString, at: 0)
                        primaryImageIdentifier = urlString
                    } else {
                        finalImageURLs.append(urlString)
                    }
                }
            }

            // Ensure primary cover is at index 0 if specified
            if !primaryImageIdentifier.isEmpty, let idx = finalImageURLs.firstIndex(of: primaryImageIdentifier), idx > 0 {
                let cover = finalImageURLs.remove(at: idx)
                finalImageURLs.insert(cover, at: 0)
            }

            saveProgressText = Language.get("PersistingData", alter: "جاري حفظ بيانات الصنف...")

            // 2. Prepare Firestore Updates
            let normalizedSearch = ArabicNormalizer.normalize(nameAr) ?? ""
            var updateData: [String: Any] = [
                "name": nameAr,
                "nameEn": nameEn,
                "name_en": nameEn,
                "searchTitle": normalizedSearch,
                "desc": descAr,
                "descEn": descEn,
                "desc_en": descEn,
                "petMainCategoryID": selectedSpeciesID,
                "petSubCategoryID": selectedSubKindID,
                "imageURLsArray": finalImageURLs,
                "relatedAccessories": selectedRelatedAccessoryIDs,
                "updatedAt": FieldValue.serverTimestamp()
            ]

            if let cover = finalImageURLs.first {
                updateData["image"] = cover
                updateData["imageUrl"] = cover
            }

            let db = Firestore.firestore()
            try await db.collection("petAccessories").document(item.accessoryID).updateData(updateData)

            // 3. Write Immutable Audit Log to AdminAuditLogs
            saveProgressText = Language.get("RecordingAuditLog", alter: "تدوين السجل الرقابي...")
            let adminUid = Auth.auth().currentUser?.uid ?? "system_admin"
            let adminEmail = Auth.auth().currentUser?.email ?? ""

            var changesSummary: [String: Any] = [:]
            if nameAr != (initialSnapshot["name"] as? String ?? "") {
                changesSummary["name"] = ["old": initialSnapshot["name"] as? String ?? "", "new": nameAr]
            }
            if nameEn != (initialSnapshot["nameEn"] as? String ?? "") {
                changesSummary["nameEn"] = ["old": initialSnapshot["nameEn"] as? String ?? "", "new": nameEn]
            }
            if descAr != (initialSnapshot["desc"] as? String ?? "") {
                changesSummary["desc"] = ["old": initialSnapshot["desc"] as? String ?? "", "new": descAr]
            }
            if descEn != (initialSnapshot["descEn"] as? String ?? "") {
                changesSummary["descEn"] = ["old": initialSnapshot["descEn"] as? String ?? "", "new": descEn]
            }
            if selectedSpeciesID != (initialSnapshot["petMainCategoryID"] as? Int ?? 0) {
                changesSummary["petMainCategoryID"] = ["old": initialSnapshot["petMainCategoryID"] as? Int ?? 0, "new": selectedSpeciesID]
            }
            if selectedSubKindID != (initialSnapshot["petSubCategoryID"] as? Int ?? 0) {
                changesSummary["petSubCategoryID"] = ["old": initialSnapshot["petSubCategoryID"] as? Int ?? 0, "new": selectedSubKindID]
            }
            if finalImageURLs != (initialSnapshot["imageURLsArray"] as? [String] ?? []) {
                changesSummary["imageURLsArray"] = ["old": initialSnapshot["imageURLsArray"] as? [String] ?? [], "new": finalImageURLs]
            }
            if selectedRelatedAccessoryIDs != (initialSnapshot["relatedAccessories"] as? [String] ?? []) {
                changesSummary["relatedAccessories"] = ["old": initialSnapshot["relatedAccessories"] as? [String] ?? [], "new": selectedRelatedAccessoryIDs]
            }

            let auditPayload: [String: Any] = [
                "action": "live_pet.edit_basic_data",
                "targetCollection": "petAccessories",
                "targetId": item.accessoryID,
                "adminUid": adminUid,
                "adminEmail": adminEmail,
                "changes": changesSummary,
                "before": initialSnapshot,
                "timestamp": FieldValue.serverTimestamp()
            ]
            try await db.collection("AdminAuditLogs").document().setData(auditPayload)

            // 4. Update local item model directly
            item.name = nameAr
            item.nameEn = nameEn
            item.desc = descAr
            item.descEn = descEn
            item.petMainCategoryID = selectedSpeciesID
            item.petSubCategoryID = selectedSubKindID
            item.imageURLsArray = finalImageURLs
            item.relatedAccessories = selectedRelatedAccessoryIDs

            onSaved?(item)
            isSaving = false

            // Success Alert via PPAlertHelper
            PPAlertHelper.showSuccess(
                in: nil,
                title: Language.get("SavedSuccessfully", alter: "تم الحفظ بنجاح"),
                subtitle: Language.get("LivePetBasicDataSavedSubtitle", alter: "تم تحديث البيانات الأساسية وسجل التدقيق بنجاح")
            )

            dismiss()
        } catch {
            isSaving = false
            await PPAlertHelper.showError(
                in: nil,
                title: Language.get("Error", alter: "خطأ في الحفظ"),
                subtitle: error.localizedDescription
            )
        }
    }

    private func promptUnsavedChangesDiscard() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("UnsavedChangesTitle", alter: "تعديلات غير محفوظة"),
            subtitle: Language.get("UnsavedChangesMsg", alter: "لديك تعديلات لم يتم حفظها بعد. هل تريد بالتأكيد إغلاق الشاشة وإلغاء هذه التعديلات؟"),
            confirmButton: Language.get("Discard", alter: "تجاهل وإغلاق"),
            cancelButton: Language.get("KeepEditing", alter: "متابعة التعديل"),
            icon: UIImage(systemName: "exclamationmark.triangle.fill"),
            confirmBlock: { _, confirmed in
                if confirmed {
                    dismiss()
                }
            },
            cancelBlock: nil
        )
    }
}

// MARK: - Breed / SubKind Selection Sheet

@available(iOS 16.0, *)
private struct PPLivePetBreedPickerSheet: View {
    let subKinds: [SubKindModel]
    let selectedSubKindID: Int
    let onSelect: (SubKindModel) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery: String = ""

    private var filteredSubKinds: [SubKindModel] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return subKinds }
        return subKinds.filter {
            $0.subKindNameAr.lowercased().contains(q) || $0.subKindNameEn.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: AdminSpacing.md) {
                    // Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AdminSurface.secondaryText)

                        TextField(Language.get("SearchBreedPlaceholder", alter: "بحث عن سلالة أو فصيلة فرعية..."), text: $searchQuery)
                            .font(Font.custom("Beiruti-Medium", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)

                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                        }
                    }
                    .padding(AdminSpacing.md)
                    .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.75))
                    .padding(.horizontal, AdminSpacing.md)
                    .padding(.top, AdminSpacing.sm)

                    // Breeds List
                    ScrollView {
                        LazyVStack(spacing: AdminSpacing.sm) {
                            ForEach(filteredSubKinds, id: \.id) { sub in
                                let isSel = (selectedSubKindID == sub.id)
                                Button {
                                    onSelect(sub)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        if !sub.subKindIconUrl.isEmpty, let url = URL(string: sub.subKindIconUrl) {
                                            AdminRemoteImage(url: url, contentMode: .fit, targetSize: CGSize(width: 80, height: 80)) {
                                                Circle().fill(AdminSurface.control)
                                            }
                                            .frame(width: 36, height: 36)
                                            .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(AdminSurface.control)
                                                .frame(width: 36, height: 36)
                                                .overlay(Image(systemName: "seal").foregroundStyle(AdminSurface.amber))
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(Language.isRTL() ? sub.subKindNameAr : (sub.subKindNameEn.isEmpty ? sub.subKindNameAr : sub.subKindNameEn))
                                                .font(Font.custom("Beiruti-Bold", size: 15))
                                                .foregroundStyle(AdminSurface.primaryText)

                                            if !sub.subKindNameEn.isEmpty && Language.isRTL() {
                                                Text(sub.subKindNameEn)
                                                    .font(Font.custom("Beiruti-Regular", size: 12))
                                                    .foregroundStyle(AdminSurface.secondaryText)
                                            }
                                        }

                                        Spacer()

                                        if isSel {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(AdminSurface.primary)
                                        }
                                    }
                                    .padding(AdminSpacing.md)
                                    .background(isSel ? AdminSurface.primary.opacity(0.1) : AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                                            .stroke(isSel ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSel ? 1.5 : 0.5)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, AdminSpacing.md)
                        .padding(.bottom, AdminSpacing.xl)
                    }
                }
            }
            .navigationTitle(Language.get("SelectBreedTitle", alter: "اختر السلالة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .font(Font.custom("Beiruti-Medium", size: 15))
                    .foregroundStyle(AdminSurface.secondaryText)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - Related Accessories Selection Sheet

@available(iOS 16.0, *)
private struct PPLivePetRelatedAccessoryPickerSheet: View {
    let currentItemId: String
    let selectedIDs: [String]
    let onSaveSelection: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var allAccessories: [PetAccessory] = []
    @State private var currentSelection: Set<String> = []
    @State private var searchQuery: String = ""
    @State private var isLoading: Bool = false

    private var filteredAccessories: [PetAccessory] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return allAccessories }
        return allAccessories.filter {
            $0.name.lowercased().contains(q) || ($0.nameEn?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: AdminSpacing.md) {
                    // Search Field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AdminSurface.secondaryText)

                        TextField(Language.get("SearchAccessoriesPlaceholder", alter: "بحث في مستلزمات المتجر..."), text: $searchQuery)
                            .font(Font.custom("Beiruti-Medium", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)

                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                        }
                    }
                    .padding(AdminSpacing.md)
                    .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.75))
                    .padding(.horizontal, AdminSpacing.md)
                    .padding(.top, AdminSpacing.sm)

                    if isLoading {
                        Spacer()
                        ProgressView()
                            .tint(AdminSurface.primary)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: AdminSpacing.sm) {
                                ForEach(filteredAccessories, id: \.accessoryID) { item in
                                    let isSelected = currentSelection.contains(item.accessoryID)
                                    Button {
                                        if isSelected {
                                            currentSelection.remove(item.accessoryID)
                                        } else {
                                            currentSelection.insert(item.accessoryID)
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            if let firstImage = item.imageURLsArray.first, let url = URL(string: firstImage) {
                                                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 96, height: 96)) {
                                                    AdminSurface.control
                                                }
                                                .frame(width: 48, height: 48)
                                                .clipShape(RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))
                                            } else {
                                                RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                                                    .fill(AdminSurface.control)
                                                    .frame(width: 48, height: 48)
                                                    .overlay(Image(systemName: "bag").foregroundStyle(AdminSurface.secondaryText))
                                            }

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name)
                                                    .font(Font.custom("Beiruti-Bold", size: 14))
                                                    .foregroundStyle(AdminSurface.primaryText)
                                                    .lineLimit(1)

                                                HStack(spacing: 6) {
                                                    if item.price.doubleValue > 0 {
                                                        Text("\(item.price.stringValue) QAR")
                                                            .font(Font.custom("Beiruti-Medium", size: 12))
                                                            .foregroundStyle(AdminSurface.emerald)
                                                    }
                                                    if let cat = item.category, !cat.isEmpty {
                                                        Text("• \(cat)")
                                                            .font(Font.custom("Beiruti-Regular", size: 12))
                                                            .foregroundStyle(AdminSurface.secondaryText)
                                                    }
                                                }
                                            }

                                            Spacer()

                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20))
                                                .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.4))
                                        }
                                        .padding(AdminSpacing.sm)
                                        .background(isSelected ? AdminSurface.primary.opacity(0.08) : AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                                                .stroke(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 0.5)
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, AdminSpacing.md)
                            .padding(.bottom, AdminSpacing.xl)
                        }
                    }
                }
            }
            .navigationTitle(Language.get("LinkAccessoriesTitle", alter: "ربط مستلزمات متوافقة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .font(Font.custom("Beiruti-Medium", size: 15))
                    .foregroundStyle(AdminSurface.secondaryText)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(Language.get("Done", alter: "تم")) {
                        onSaveSelection(Array(currentSelection))
                        dismiss()
                    }
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primary)
                }
            }
            .task {
                currentSelection = Set(selectedIDs)
                await loadCatalogAccessories()
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func loadCatalogAccessories() async {
        isLoading = true
        let db = Firestore.firestore()
        do {
            // Fetch non-live-pet accessories
            let snapshot = try await db.collection("petAccessories")
                .whereField("accessKindType", isNotEqualTo: 3)
                .limit(to: 60)
                .getDocuments()

            var list: [PetAccessory] = []
            for doc in snapshot.documents {
                guard doc.documentID != currentItemId else { continue }
                list.append(PetAccessory(dictionary: doc.data(), documentID: doc.documentID))
            }
            DispatchQueue.main.async {
                self.allAccessories = list
                self.isLoading = false
            }
        } catch {
            print("[PPLivePetRelatedAccessoryPickerSheet] Error loading accessories: \(error)")
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
}

// MARK: - PHPicker UIViewControllerRepresentable

private struct PPImagePickerSheet: UIViewControllerRepresentable {
    let maxSelection: Int
    let onPicked: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = maxSelection
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
        let parent: PPImagePickerSheet

        init(_ parent: PPImagePickerSheet) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard !results.isEmpty else { return }

            var images: [UIImage] = []
            let group = DispatchGroup()
            let lock = NSLock()

            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                        if let img = object as? UIImage {
                            lock.lock()
                            images.append(img)
                            lock.unlock()
                        }
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                self.parent.onPicked(images)
            }
        }
    }
}
